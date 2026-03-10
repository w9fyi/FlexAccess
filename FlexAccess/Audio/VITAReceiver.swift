//
//  VITAReceiver.swift
//  FlexAccess
//
//  Receives VITA-49 DAX audio packets over UDP.
//
//  LAN path  (port 4991): float32 stereo big-endian.
//  WAN path  (publicUdpPort): Opus-encoded, decoded by OpusDecoder.
//
//  Sample rate:
//    Set `expectedSampleRate` from the radio's audio_stream status (dax_rate or
//    sample_rate key). Defaults to 24 kHz (most DAX channels). At 24 kHz the
//    receiver upsamples 2× to 48 kHz for the audio pipeline. At 48 kHz,
//    samples are passed straight through.
//
//  Uses a blocking recv() loop on a dedicated Thread — more reliable than
//  DispatchSourceRead on macOS 15 with SO_REUSEPORT.
//

import Foundation
import Darwin

final class VITAReceiver {

    // MARK: Callbacks (called on receiver background thread)

    var onLog:          ((String) -> Void)?
    var onError:        ((String) -> Void)?
    var onAudio48kMono: (([Float]) -> Void)?
    var onPacket:       ((UInt32, Int) -> Void)?

    // MARK: Configuration

    /// Filter packets by stream ID. Updated from audio_stream status.
    var expectedStreamID: UInt32?

    /// Actual DAX sample rate from radio status (24000 or 48000). Default 24000.
    var expectedSampleRate: Int = 24_000

    /// WAN path: Opus decoder. Nil = LAN float32 path.
    var opusDecoder: OpusDecoder?

    // MARK: Private

    private var fd: Int32 = -1
    private var receiveThread: Thread?
    private var upsampleCarry: Float?

    // MARK: Errors

    enum ReceiverError: LocalizedError {
        case socketFailed(String)
        case bindFailed(String)
        var errorDescription: String? {
            switch self {
            case .socketFailed(let s), .bindFailed(let s): return s
            }
        }
    }

    // MARK: Start

    func start(port: UInt16 = 4991) throws {
        stop()
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw ReceiverError.socketFailed("socket() failed: \(String(cString: strerror(errno)))")
        }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        var sin = sockaddr_in()
        sin.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port   = port.bigEndian
        sin.sin_addr   = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bound: Int32 = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let e = errno; Darwin.close(fd); fd = -1
            throw ReceiverError.bindFailed(
                e == EADDRINUSE
                    ? "UDP port \(port) in use — is another SmartSDR client running?"
                    : "bind() failed: \(String(cString: strerror(e)))"
            )
        }

        let capturedFd = fd
        weak var weakSelf = self
        let t = Thread {
            var buf = [UInt8](repeating: 0, count: 8192)
            var rawPktCount = 0
            while true {
                let n = buf.withUnsafeMutableBytes { raw in recv(capturedFd, raw.baseAddress!, raw.count, 0) }
                if n > 0 {
                    rawPktCount += 1
                    if rawPktCount <= 5 {
                        let h = buf.count >= 4 ? String(format: "%02X %02X %02X %02X", buf[0],buf[1],buf[2],buf[3]) : "?"
                        let s = buf.count >= 8 ? String(format: "0x%02X%02X%02X%02X", buf[4],buf[5],buf[6],buf[7]) : "?"
                        weakSelf?.onLog?("VITAReceiver pkt #\(rawPktCount) len=\(n) hdr=[\(h)] sid=\(s)")
                    }
                    buf.withUnsafeBytes { raw in
                        guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                        weakSelf?.handlePacket(base, count: n)
                    }
                } else if n == 0 {
                    continue
                } else {
                    let err = errno
                    if err == EINTR { continue }
                    weakSelf?.onError?("VITAReceiver recv error \(err): \(String(cString: strerror(err)))")
                    break
                }
            }
            weakSelf?.onLog?("VITAReceiver: thread exited")
        }
        t.name = "com.w9fyi.flexaccess.vita"
        t.qualityOfService = .userInteractive
        t.start()
        receiveThread = t
        onLog?("VITAReceiver: listening on UDP \(port)")
    }

    // MARK: Stop

    func stop() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        receiveThread = nil
        upsampleCarry = nil
    }

    // MARK: Private — VITA-49 parser

    private func handlePacket(_ bytes: UnsafePointer<UInt8>, count: Int) {
        guard count >= 8 else { return }
        let w0         = be32(bytes, at: 0)
        let packetType = UInt8((w0 >> 28) & 0x0F)
        let classID    = (w0 >> 27) & 1 == 1
        let tsi        = UInt8((w0 >> 22) & 0x03)
        let tsf        = UInt8((w0 >> 20) & 0x03)
        let pktWords   = Int(w0 & 0xFFFF)

        guard packetType == 1 || packetType == 3 else { return }

        let streamID = be32(bytes, at: 4)
        if let exp = expectedStreamID, streamID != exp { return }

        var hdrWords = 2
        if classID  { hdrWords += 2 }
        if tsi != 0 { hdrWords += 1 }
        if tsf != 0 { hdrWords += 2 }
        let hdrBytes     = hdrWords * 4
        let trailerBytes = (w0 >> 26) & 1 == 1 ? 4 : 0
        let totalBytes   = pktWords > 0 ? pktWords * 4 : count
        guard totalBytes <= count, totalBytes > hdrBytes + trailerBytes else { return }

        let payloadBytes = totalBytes - hdrBytes - trailerBytes
        guard payloadBytes >= 8 else { return }
        let payload = bytes.advanced(by: hdrBytes)

        if let decoder = opusDecoder {
            onPacket?(streamID, 1)
            if let decoded = decoder.decode(bytes: payload, count: payloadBytes) {
                onAudio48kMono?(decoded)
            }
        } else {
            // LAN: float32 stereo big-endian → mono
            let pairCount = payloadBytes / 8
            onPacket?(streamID, pairCount)
            var mono = [Float](repeating: 0, count: pairCount)
            for i in 0..<pairCount {
                let l = beFloat(payload, at: i * 8)
                let r = beFloat(payload, at: i * 8 + 4)
                mono[i] = (l + r) * 0.5
            }
            // Upsample if radio is sending at 24 kHz
            let out = expectedSampleRate <= 24_000 ? upsample2x(mono) : mono
            if !out.isEmpty { onAudio48kMono?(out) }
        }
    }

    @inline(__always)
    private func be32(_ b: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        let p = b + offset
        return (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
    }

    @inline(__always)
    private func beFloat(_ b: UnsafePointer<UInt8>, at offset: Int) -> Float {
        Float(bitPattern: be32(b, at: offset))
    }

    private func upsample2x(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var out = [Float](); out.reserveCapacity(samples.count * 2)
        var prev = upsampleCarry ?? samples[0]
        for s in samples {
            out.append((prev + s) * 0.5)
            out.append(s)
            prev = s
        }
        upsampleCarry = samples.last
        return out
    }
}
