//
//  FlexMicCapture.swift
//  FlexAccess
//
//  Captures microphone audio and transmits it to a FlexRadio as VITA-49 IF data
//  packets over UDP.  Used for DAX TX (transmit audio from the computer to the radio).
//
//  LAN path (port 4991): float32 stereo big-endian VITA-49 at 24 kHz, 480 samples/frame
//  (20 ms).  The mono mic signal is duplicated to both L and R channels as the radio
//  expects stereo interleaved samples.
//
//  WAN path: same VITA-49 format sent to the radio's public UDP port (typically 4993).
//  The WAN path currently sends the same float32 format; a future enhancement could
//  add Opus encoding here if the radio requires it for WAN mic audio.
//
//  Threading
//  ---------
//  AVAudioEngine's tap callback runs on a real-time audio thread.  All sample conversion
//  and frame buffering happen on that thread.  Completed 480-sample frames are dispatched
//  to a dedicated serial queue (`sendQueue`) where the VITA-49 packet is built and
//  the UDP `sendto()` call is made, keeping the audio thread free of system calls.
//
//  Lifecycle
//  ---------
//  Call start(radioIP:port:streamID:) when PTT goes down.
//  Call stop() when PTT goes up.
//  A single instance per session is fine; start/stop may be called repeatedly.
//

import Foundation
import AVFoundation
import Darwin
#if os(macOS)
import CoreAudio
import AudioToolbox
#endif

final class FlexMicCapture {

    // MARK: - Error type

    enum MicError: LocalizedError {
        case socketFailed(String)
        case formatError(String)
        case engineError(String)

        var errorDescription: String? {
            switch self {
            case .socketFailed(let s), .formatError(let s), .engineError(let s): return s
            }
        }
    }

    // MARK: - Callbacks

    var onLog: ((String) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Private state

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?

    private var fd: Int32 = -1
    private var destAddr: sockaddr_in?

    private var frameBuffer: [Float] = []
    private var sampleCount: UInt64 = 0
    private var pktSeq: UInt8 = 0
    private var currentStreamID: UInt32 = 0x00000001

    // Serial queue for UDP sends — keeps audio thread free of syscalls.
    private let sendQueue = DispatchQueue(label: "FlexMicCapture.send", qos: .userInitiated)

    private let targetRate: Double = 24_000
    private let frameSamples: Int = 480   // 20 ms at 24 kHz

    // MARK: - Start

    /// Begin mic capture and VITA-49 UDP transmission to the radio.
    /// - Parameters:
    ///   - radioIP: IP address of the FlexRadio (IPv4 string).
    ///   - port: UDP port to send to (4991 on LAN, publicUdpPort on WAN).
    ///   - streamID: VITA-49 stream ID the radio expects for DAX TX audio.
    ///   - inputDeviceID: macOS CoreAudio device ID for the mic input (UInt32). Nil = system default.
    ///     Ignored on iOS — use AVAudioSession to select the input there.
    func start(radioIP: String, port: UInt16 = 4991, streamID: UInt32,
               inputDeviceID: UInt32? = nil) throws {
        stop()

        currentStreamID = streamID
        frameBuffer.removeAll(keepingCapacity: true)
        sampleCount = 0
        pktSeq = 0

        // --- UDP send socket (send-only; no bind required) ---
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw MicError.socketFailed("socket() failed: \(String(cString: strerror(errno)))")
        }

        var sin = sockaddr_in()
        sin.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port   = port.bigEndian
        guard inet_pton(AF_INET, radioIP, &sin.sin_addr) == 1 else {
            Darwin.close(fd); fd = -1
            throw MicError.socketFailed("Invalid radio IP address: \(radioIP)")
        }
        destAddr = sin

        // --- AVAudioSession (iOS only) ---
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        // --- AVAudioEngine ---
        let e = AVAudioEngine()
        let inputNode = e.inputNode

        // On macOS, select the CoreAudio input device before querying the hardware format.
        // Must be done after accessing inputNode (which instantiates the AUHAL unit).
        // AudioDeviceID is a typealias for UInt32, so no cast is needed.
        #if os(macOS)
        if let devID = inputDeviceID {
            var selectedID = devID
            AudioUnitSetProperty(
                inputNode.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &selectedID,
                UInt32(MemoryLayout<UInt32>.size)
            )
        }
        #endif

        let hwFormat  = inputNode.outputFormat(forBus: 0)

        guard let outFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   targetRate,
            channels:     1,
            interleaved:  false
        ) else {
            Darwin.close(fd); fd = -1
            throw MicError.formatError("Cannot create 24 kHz mono AVAudioFormat")
        }

        guard let conv = AVAudioConverter(from: hwFormat, to: outFmt) else {
            Darwin.close(fd); fd = -1
            throw MicError.formatError(
                "Cannot create AVAudioConverter \(Int(hwFormat.sampleRate)) Hz → 24 kHz"
            )
        }
        converter = conv

        // Request ~20 ms tap buffers at the hardware rate.
        let tapFrames = AVAudioFrameCount(hwFormat.sampleRate * 0.02)
        inputNode.installTap(onBus: 0, bufferSize: tapFrames, format: hwFormat) { [weak self] buf, _ in
            self?.handleTap(buf)
        }

        do {
            try e.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            Darwin.close(fd); fd = -1
            converter = nil
            throw MicError.engineError("AVAudioEngine.start failed: \(error.localizedDescription)")
        }

        engine = e
        onLog?(
            "FlexMicCapture: started → \(radioIP):\(port) "
            + "stream=0x\(String(streamID, radix: 16, uppercase: true)) "
            + "hw=\(Int(hwFormat.sampleRate)) Hz"
        )
    }

    // MARK: - Stop

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        frameBuffer.removeAll()
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        destAddr = nil
    }

    // MARK: - Audio tap handler (real-time thread)

    private func handleTap(_ hwBuf: AVAudioPCMBuffer) {
        guard let conv = converter else { return }

        // Allocate an output buffer sized conservatively for the resampled frames.
        let ratio = targetRate / hwBuf.format.sampleRate
        let capacity = AVAudioFrameCount(Double(hwBuf.frameLength) * ratio) + 8
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: conv.outputFormat,
                                             frameCapacity: capacity) else { return }

        var inputConsumed = false
        var convError: NSError?
        conv.convert(to: outBuf, error: &convError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return hwBuf
        }

        if let err = convError {
            onError?("Mic converter: \(err.localizedDescription)")
            return
        }

        guard let channelData = outBuf.floatChannelData?[0] else { return }
        let n = Int(outBuf.frameLength)

        // Accumulate into fixed 480-sample frames; dispatch each complete frame.
        for i in 0..<n {
            frameBuffer.append(channelData[i])
            if frameBuffer.count >= frameSamples {
                let frame = Array(frameBuffer.prefix(frameSamples))
                frameBuffer.removeFirst(frameSamples)
                let pkt = buildPacket(frame)
                let dest = destAddr
                let sock = fd
                let seq  = sampleCount
                sampleCount += UInt64(frameSamples)
                pktSeq &+= 1
                sendQueue.async {
                    guard sock >= 0, var d = dest else { return }
                    _ = pkt.withUnsafeBytes { raw in
                        withUnsafeMutablePointer(to: &d) { ptr in
                            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                sendto(sock, raw.baseAddress!, raw.count, 0, sa,
                                       socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                    _ = seq   // suppress unused warning
                }
            }
        }
    }

    // MARK: - VITA-49 packet builder

    /// Build one VITA-49 IF-data packet containing `mono.count` stereo float32 pairs.
    ///
    /// Header layout (C=0, no class ID):
    ///   Word 0:  type=1, C=0, T=0, TSI=1, TSF=3, pktCount(mod16), totalWords
    ///   Word 1:  stream ID
    ///   Word 2:  integer timestamp (seconds since Unix epoch, 32-bit)
    ///   Word 3:  fractional timestamp high word (0 — sample count fits in 32 bits)
    ///   Word 4:  fractional timestamp low word  (cumulative sample count)
    ///   Payload: float32 stereo big-endian  (L₀ R₀ L₁ R₁ … L₄₇₉ R₄₇₉)
    private func buildPacket(_ mono: [Float]) -> [UInt8] {
        let hdrWords     = 5
        let payloadWords = mono.count * 2   // duplicate mono→stereo
        let totalWords   = hdrWords + payloadWords

        var pkt = [UInt8](repeating: 0, count: totalWords * 4)

        // Word 0
        let w0: UInt32 = (0x1  << 28)                    // packet type 1: IF data with stream ID
                       | (0    << 27)                    // C=0: no class ID
                       | (1    << 22)                    // TSI=1: integer timestamp (seconds)
                       | (3    << 20)                    // TSF=3: fractional = sample count
                       | (UInt32(pktSeq & 0xF) << 16)   // packet count (mod 16)
                       | UInt32(totalWords)               // total packet size in 32-bit words
        writeBE32(&pkt, at: 0,  value: w0)

        // Word 1: stream ID
        writeBE32(&pkt, at: 4,  value: currentStreamID)

        // Word 2: integer timestamp (seconds)
        writeBE32(&pkt, at: 8,  value: UInt32(Date().timeIntervalSince1970))

        // Words 3–4: 64-bit fractional timestamp (sample count)
        writeBE32(&pkt, at: 12, value: UInt32(sampleCount >> 32))
        writeBE32(&pkt, at: 16, value: UInt32(sampleCount & 0xFFFF_FFFF))

        // Payload: mono duplicated to stereo, big-endian float32
        var offset = hdrWords * 4
        for s in mono {
            let bits = s.bitPattern
            writeBE32(&pkt, at: offset,     value: bits)  // L
            writeBE32(&pkt, at: offset + 4, value: bits)  // R (same as L)
            offset += 8
        }

        return pkt
    }

    // MARK: - Helpers

    @inline(__always)
    private func writeBE32(_ buf: inout [UInt8], at offset: Int, value: UInt32) {
        buf[offset]     = UInt8((value >> 24) & 0xFF)
        buf[offset + 1] = UInt8((value >> 16) & 0xFF)
        buf[offset + 2] = UInt8((value >>  8) & 0xFF)
        buf[offset + 3] = UInt8( value        & 0xFF)
    }
}
