//
//  MicCapture.swift
//  FlexAccess
//
//  Captures mic audio and sends it to the radio as VITA-49 DAX TX packets over UDP.
//  24 kHz mono float32, 480 samples/frame (20 ms). Duplicated L+R in payload.
//

import Foundation
import AVFoundation
import Darwin
#if os(macOS)
import CoreAudio
import AudioToolbox
#endif

final class MicCapture {

    enum MicError: LocalizedError {
        case socketFailed(String), formatError(String), engineError(String)
        var errorDescription: String? {
            switch self {
            case .socketFailed(let s), .formatError(let s), .engineError(let s): return s
            }
        }
    }

    var onLog:   ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var fd: Int32 = -1
    private var destAddr: sockaddr_in?
    private var frameBuffer: [Float] = []
    private var sampleCount: UInt64 = 0
    private var pktSeq: UInt8 = 0
    private var streamID: UInt32 = 0x00000001
    private let sendQueue = DispatchQueue(label: "com.w9fyi.flexaccess.mic.send", qos: .userInitiated)
    private let targetRate: Double = 24_000
    private let frameSamples = 480

    func start(radioIP: String, port: UInt16 = 4991, streamID: UInt32,
               inputDeviceID: UInt32? = nil) throws {
        stop()
        self.streamID = streamID
        frameBuffer.removeAll(keepingCapacity: true)
        sampleCount = 0; pktSeq = 0

        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw MicError.socketFailed("socket() failed: \(String(cString: strerror(errno)))") }

        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = port.bigEndian
        guard inet_pton(AF_INET, radioIP, &sin.sin_addr) == 1 else {
            Darwin.close(fd); fd = -1
            throw MicError.socketFailed("Invalid radio IP: \(radioIP)")
        }
        destAddr = sin

        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        let e = AVAudioEngine()
        let inputNode = e.inputNode

        #if os(macOS)
        if let devID = inputDeviceID {
            var id = devID
            AudioUnitSetProperty(inputNode.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<UInt32>.size))
        }
        #endif

        let hwFmt = inputNode.outputFormat(forBus: 0)
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: targetRate,
                                         channels: 1, interleaved: false) else {
            Darwin.close(fd); fd = -1
            throw MicError.formatError("Cannot create 24 kHz mono format")
        }
        guard let conv = AVAudioConverter(from: hwFmt, to: outFmt) else {
            Darwin.close(fd); fd = -1
            throw MicError.formatError("Cannot create AVAudioConverter \(Int(hwFmt.sampleRate)) Hz → 24 kHz")
        }
        converter = conv

        let tapFrames = AVAudioFrameCount(hwFmt.sampleRate * 0.02)
        inputNode.installTap(onBus: 0, bufferSize: tapFrames, format: hwFmt) { [weak self] buf, _ in
            self?.handleTap(buf)
        }

        do { try e.start() } catch {
            inputNode.removeTap(onBus: 0)
            Darwin.close(fd); fd = -1; converter = nil
            throw MicError.engineError("AVAudioEngine.start: \(error.localizedDescription)")
        }
        engine = e
        onLog?("MicCapture: started → \(radioIP):\(port) stream=0x\(String(streamID, radix: 16, uppercase: true)) hw=\(Int(hwFmt.sampleRate)) Hz")
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil; converter = nil; frameBuffer.removeAll()
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        destAddr = nil
    }

    private func handleTap(_ hwBuf: AVAudioPCMBuffer) {
        guard let conv = converter else { return }
        let ratio    = targetRate / hwBuf.format.sampleRate
        let capacity = AVAudioFrameCount(Double(hwBuf.frameLength) * ratio) + 8
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: conv.outputFormat, frameCapacity: capacity) else { return }
        var inputConsumed = false
        var convErr: NSError?
        conv.convert(to: outBuf, error: &convErr) { _, outStatus in
            if inputConsumed { outStatus.pointee = .noDataNow; return nil }
            inputConsumed = true; outStatus.pointee = .haveData; return hwBuf
        }
        if let e = convErr { onError?("Mic converter: \(e.localizedDescription)"); return }
        guard let ch = outBuf.floatChannelData?[0] else { return }
        let n = Int(outBuf.frameLength)
        for i in 0..<n {
            frameBuffer.append(ch[i])
            if frameBuffer.count >= frameSamples {
                let frame = Array(frameBuffer.prefix(frameSamples))
                frameBuffer.removeFirst(frameSamples)
                let pkt   = buildPacket(frame)
                let dest  = destAddr; let sock = fd
                sampleCount += UInt64(frameSamples); pktSeq &+= 1
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
                }
            }
        }
    }

    private func buildPacket(_ mono: [Float]) -> [UInt8] {
        let hdr = 5; let payload = mono.count * 2; let total = hdr + payload
        var pkt = [UInt8](repeating: 0, count: total * 4)
        let w0: UInt32 = (0x1 << 28) | (1 << 22) | (3 << 20)
                       | (UInt32(pktSeq & 0xF) << 16) | UInt32(total)
        writeBE32(&pkt, at: 0,  v: w0)
        writeBE32(&pkt, at: 4,  v: streamID)
        writeBE32(&pkt, at: 8,  v: UInt32(Date().timeIntervalSince1970))
        writeBE32(&pkt, at: 12, v: UInt32(sampleCount >> 32))
        writeBE32(&pkt, at: 16, v: UInt32(sampleCount & 0xFFFF_FFFF))
        var off = hdr * 4
        for s in mono {
            let bits = s.bitPattern
            writeBE32(&pkt, at: off, v: bits); writeBE32(&pkt, at: off + 4, v: bits)
            off += 8
        }
        return pkt
    }

    @inline(__always)
    private func writeBE32(_ buf: inout [UInt8], at offset: Int, v: UInt32) {
        buf[offset] = UInt8((v >> 24) & 0xFF); buf[offset+1] = UInt8((v >> 16) & 0xFF)
        buf[offset+2] = UInt8((v >> 8) & 0xFF); buf[offset+3] = UInt8(v & 0xFF)
    }
}
