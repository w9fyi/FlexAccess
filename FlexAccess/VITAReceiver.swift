//
//  VITAReceiver.swift
//  FlexAccess
//
//  Listens on UDP for VITA-49 DAX audio packets from a FlexRadio.
//
//  LAN path (port 4991): float32 stereo big-endian → native mono → 48 kHz feed.
//  WAN path (publicUdpPort, typically 4993): stub — Phase 3 (Opus decode).
//
//  VITA-49 header layout (big-endian 32-bit words):
//    Word 0:  packetType[31:28] | C[27] | T[26] | TSI[25:22] | TSF[21:20]
//             | packetCount[19:16] | packetSizeWords[15:0]
//    Word 1:  stream ID  (packet types 1, 3, 4, 5)
//    Words 2–3: class ID (if C=1, 2 words)
//    Word N:  integer timestamp (if TSI ≠ 0, 1 word)
//    Words N+1–N+2: fractional timestamp (if TSF ≠ 0, 2 words)
//    Payload: float32 samples, big-endian, stereo interleaved (L, R, L, R …)
//
//  Key lessons applied from KenwoodLanAudio:
//  - close(fd) synchronously in stop() before DispatchSourceRead.cancel() fires async.
//  - Receiver stays alive across TCP reconnects; re-send dax=1 on reconnect.
//

import Foundation
import Darwin

final class VITAReceiver {

    // MARK: Callbacks — delivered on receiver's background queue

    var onLog: ((String) -> Void)?
    var onError: ((String) -> Void)?

    /// 48 kHz mono float samples ready for LanAudioPipeline.
    var onAudio48kMono: (([Float]) -> Void)?

    /// Diagnostic: called per valid audio packet with (streamID, stereo pair count).
    var onPacket: ((UInt32, Int) -> Void)?

    // MARK: Configuration

    /// If set, only VITA-49 packets matching this stream ID are processed.
    /// Updated from the radio's audio_stream status line.
    var expectedStreamID: UInt32?

    /// If non-nil, treat the VITA-49 payload as an Opus packet and decode it.
    /// Nil (default) → LAN path: payload is float32 stereo big-endian.
    var opusDecoder: OpusDecoder?

    // MARK: Private state

    private let queue = DispatchQueue(label: "VITAReceiver.udp", qos: .userInteractive)
    private var readSource: DispatchSourceRead?
    private var fd: Int32 = -1

    /// Held between packets for linear-interpolation upsample continuity.
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
        #if os(iOS)
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        #endif

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
        if bound != 0 {
            let e = errno
            Darwin.close(fd); fd = -1
            throw ReceiverError.bindFailed(
                e == EADDRINUSE
                    ? "UDP port \(port) already in use — is another SmartSDR client running?"
                    : "bind() failed: \(String(cString: strerror(e)))"
            )
        }

        let flags = fcntl(fd, F_GETFL)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            Darwin.close(self.fd)
            self.fd = -1
        }
        readSource = source
        source.resume()
        onLog?("VITAReceiver: listening on UDP \(port)")
    }

    // MARK: Stop

    func stop() {
        readSource?.cancel()
        readSource = nil
        // Synchronous close before the async cancel handler fires — releases the port immediately.
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        upsampleCarry = nil
    }

    // MARK: Private — UDP drain

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = buf.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress, raw.count, 0)
            }
            if n < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN { break }
                onError?("VITAReceiver recv: \(String(cString: strerror(errno)))")
                break
            }
            if n == 0 { break }
            buf.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                handlePacket(base, count: n)
            }
        }
    }

    // MARK: Private — VITA-49 parser

    private func handlePacket(_ bytes: UnsafePointer<UInt8>, count: Int) {
        guard count >= 8 else { return }

        // Word 0 — big-endian
        let w0          = be32(bytes, at: 0)
        let packetType  = UInt8((w0 >> 28) & 0x0F)
        let classIDPres = (w0 >> 27) & 1 == 1
        let trailerPres = (w0 >> 26) & 1 == 1
        let tsi         = UInt8((w0 >> 22) & 0x03)
        let tsf         = UInt8((w0 >> 20) & 0x03)
        let pktWords    = Int(w0 & 0xFFFF)

        // Accept IF data (type 1) or Extension data (type 3) — both carry stream ID.
        guard packetType == 1 || packetType == 3 else { return }

        // Word 1 — stream ID
        let streamID = be32(bytes, at: 4)
        if let exp = expectedStreamID, streamID != exp { return }

        // Calculate header byte length
        var hdrWords = 2                    // word 0 + word 1 (stream ID)
        if classIDPres { hdrWords += 2 }    // class ID = 2 words
        if tsi != 0    { hdrWords += 1 }    // integer timestamp = 1 word
        if tsf != 0    { hdrWords += 2 }    // fractional timestamp = 2 words
        let hdrBytes     = hdrWords * 4
        let trailerBytes = trailerPres ? 4 : 0

        // Use packet-size-in-words from header if present, else use actual received length.
        let totalBytes = pktWords > 0 ? pktWords * 4 : count
        guard totalBytes <= count else { return }

        let payloadBytes = totalBytes - hdrBytes - trailerBytes
        guard payloadBytes >= 8 else { return }   // need at least 1 stereo float32 pair

        let payload = bytes.advanced(by: hdrBytes)

        if let decoder = opusDecoder {
            // WAN path: payload is one Opus frame (variable-length binary).
            // OpusDecoder returns 480 float32 samples at 48 kHz.
            onPacket?(streamID, 1)  // 1 frame = 480 samples
            if let decoded = decoder.decode(bytes: payload, count: payloadBytes) {
                onAudio48kMono?(decoded)
            }
        } else {
            // LAN path: payload is float32 stereo interleaved big-endian (L₀ R₀ L₁ R₁ …)
            let pairCount = payloadBytes / 8    // each pair = L(4 bytes) + R(4 bytes)
            onPacket?(streamID, pairCount)

            var mono = [Float](repeating: 0, count: pairCount)
            for i in 0..<pairCount {
                let l = beFloat(payload, at: i * 8)
                let r = beFloat(payload, at: i * 8 + 4)
                mono[i] = (l + r) * 0.5
            }

            // Heuristic sample rate detection:
            //   ≤ 160 stereo pairs/packet → radio sending at 24 kHz → upsample 2× to 48 kHz
            //   > 160 stereo pairs/packet → radio sending at 48 kHz → pass straight through
            let out: [Float] = pairCount <= 160 ? upsample2x(mono) : mono
            if !out.isEmpty { onAudio48kMono?(out) }
        }
    }

    // MARK: Private — helpers

    @inline(__always)
    private func be32(_ b: UnsafePointer<UInt8>, at offset: Int) -> UInt32 {
        let p = b + offset
        return (UInt32(p[0]) << 24) | (UInt32(p[1]) << 16) | (UInt32(p[2]) << 8) | UInt32(p[3])
    }

    @inline(__always)
    private func beFloat(_ b: UnsafePointer<UInt8>, at offset: Int) -> Float {
        Float(bitPattern: be32(b, at: offset))
    }

    /// Linear 2× interpolation upsample. Produces exactly 2×count output samples.
    /// A carry sample is held between calls so inter-packet boundaries are smooth.
    private func upsample2x(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var out = [Float]()
        out.reserveCapacity(samples.count * 2)
        var prev = upsampleCarry ?? samples[0]
        for s in samples {
            out.append((prev + s) * 0.5)   // interpolated midpoint
            out.append(s)                   // original sample
            prev = s
        }
        upsampleCarry = samples.last
        return out
    }
}
