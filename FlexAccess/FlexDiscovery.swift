//
//  FlexDiscovery.swift
//  FlexAccess
//
//  Listens on UDP port 4992 for VITA-49 discovery broadcasts from FlexRadio 6000-series
//  radios on the local LAN. Also accepts injected entries from SmartLinkBroker for WAN
//  radios. Published [DiscoveredRadio] auto-removes stale LAN entries after 5 seconds.
//
//  BSD sockets are used instead of NWListener because:
//    1. SO_REUSEPORT is required so multiple processes (e.g. SmartSDR for Mac) can all
//       bind to UDP 4992 and receive the same broadcast — NWListener's
//       allowLocalEndpointReuse only sets SO_REUSEADDR, not SO_REUSEPORT.
//    2. SO_BROADCAST must be set to receive subnet-directed broadcast packets.
//
//  Packet format (VITA-49 Extension Context, per SmartSDR API):
//    Word 0:   type=5 (Extension Context), C=1 (class ID present), TSI/TSF flags, size
//    Word 1:   stream ID = 0x00000800
//    Words 2-3: class ID (OUI=0x001C2D, PCC=0xFFFF)
//    Word N:   integer timestamp (if TSI != 0)
//    Words N+1-N+2: fractional timestamp (if TSF != 0)
//    Payload:  space-separated key=value pairs (ASCII)
//

import Foundation
import Darwin

// MARK: - Radio packet source

enum PacketSource: String {
    case local      // LAN UDP broadcast
    case smartlink  // WAN via SmartLink broker
    case direct     // Manually entered IP
}

// MARK: - Discovered radio

struct DiscoveredRadio: Identifiable, Equatable {
    let id: String          // serial number
    var model: String
    var callsign: String
    var ip: String
    var port: Int
    var version: String
    var source: PacketSource

    // WAN fields (SmartLink)
    var publicIp: String = ""
    var publicTlsPort: Int = 4994
    var publicUdpPort: Int = 4993
    var wanConnected: Bool = false

    var displayName: String {
        callsign.isEmpty ? "\(model) (\(ip))" : "\(callsign) — \(model)"
    }

    static func == (lhs: DiscoveredRadio, rhs: DiscoveredRadio) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - FlexDiscovery

@MainActor
final class FlexDiscovery: ObservableObject {
    @Published private(set) var radios: [DiscoveredRadio] = []

    private var fd: Int32 = -1
    private var receiveThread: Thread?
    private var staleTimers: [String: DispatchSourceTimer] = [:]
    private let staleQueue = DispatchQueue(label: "com.w9fyi.flexaccess.discovery.stale", qos: .utility)
    private let staleTimeout: TimeInterval = 5.0

    // MARK: Start / Stop

    func start() {
        guard fd < 0 else { return }

        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            AppFileLogger.shared.log("FlexDiscovery: socket() failed: \(String(cString: strerror(errno)))")
            return
        }

        // Allow multiple processes to share UDP 4992 (SmartSDR for Mac, MacLogger, etc.).
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Required to receive subnet-directed broadcast packets.
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var sin = sockaddr_in()
        sin.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port   = UInt16(4992).bigEndian
        sin.sin_addr   = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bound: Int32 = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            AppFileLogger.shared.log("FlexDiscovery: bind() failed: \(String(cString: strerror(errno)))")
            Darwin.close(fd); fd = -1
            return
        }

        // Use a blocking recv() loop on a dedicated Thread.
        // This is more reliable than DispatchSourceRead + kqueue for UDP broadcast
        // when multiple processes share the same port with SO_REUSEPORT.
        let capturedFd = fd
        let t = Thread {
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = buf.withUnsafeMutableBytes { raw in
                    recv(capturedFd, raw.baseAddress!, raw.count, 0)
                }
                if n > 0 {
                    let slice = Array(buf.prefix(n))
                    DispatchQueue.main.async { [weak self] in
                        self?.parsePacket(slice, count: n)
                    }
                } else if n == 0 {
                    continue  // empty UDP datagram — keep receiving
                } else {
                    let err = errno
                    if err == EINTR { continue }   // interrupted by signal — retry
                    AppFileLogger.shared.log("FlexDiscovery: recv error \(err): \(String(cString: strerror(err)))")
                    break   // EBADF (fd closed in stop()) or other fatal error
                }
            }
            AppFileLogger.shared.log("FlexDiscovery: recv thread exited")
        }
        t.name = "com.w9fyi.flexaccess.discovery"
        t.qualityOfService = .utility
        t.start()
        receiveThread = t

        AppFileLogger.shared.log("FlexDiscovery: listening on UDP 4992")
    }

    func stop() {
        // Closing fd causes the blocking recv() to return immediately, exiting the thread.
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        receiveThread = nil
        staleTimers.values.forEach { $0.cancel() }
        staleTimers.removeAll()
        AppFileLogger.shared.log("FlexDiscovery: stopped")
    }

    // MARK: SmartLink injection

    func injectSmartLinkRadio(_ radio: DiscoveredRadio) {
        upsert(radio, stale: false)
    }

    func removeSmartLinkRadio(serial: String) {
        Task { @MainActor in
            radios.removeAll { $0.id == serial && $0.source == .smartlink }
        }
    }

    // MARK: VITA-49 parsing

    private func parsePacket(_ buf: [UInt8], count: Int) {
        // Minimum: word0 + streamID + classID (2 words) = 16 bytes
        guard count >= 16 else { return }

        // Word 0 — big-endian
        let w0          = be32(buf, at: 0)
        let packetType  = (w0 >> 28) & 0xF
        let classIDPres = (w0 >> 27) & 1 == 1
        let tsi         = UInt8((w0 >> 22) & 0x3)
        let tsf         = UInt8((w0 >> 20) & 0x3)

        // FlexRadio discovery packet types vary by firmware version:
        //   Type 3 (Extension Data)    — firmware ≤ 1.4.x
        //   Type 4 (IF Context)        — some intermediate firmware
        //   Type 5 (Extension Context) — firmware 2.x+
        guard packetType == 5 || packetType == 4 || packetType == 3 else { return }

        // Word 1 — stream ID must be 0x00000800 for discovery
        let streamID = be32(buf, at: 4)
        guard streamID == 0x00000800 else { return }

        // Validate OUI when class ID is present (words 2-3)
        if classIDPres && count >= 16 {
            let oui = be32(buf, at: 8) & 0x00FFFFFF
            guard oui == 0x001C2D else { return }   // FlexRadio Systems
        }

        // Compute header length dynamically from flags — same logic as VITAReceiver.
        var hdrWords = 2                    // word0 + streamID
        if classIDPres { hdrWords += 2 }    // class ID = 2 words
        if tsi != 0    { hdrWords += 1 }    // integer timestamp
        if tsf != 0    { hdrWords += 2 }    // fractional timestamp
        let hdrBytes = hdrWords * 4

        guard count > hdrBytes else { return }

        let payloadData = Data(buf[hdrBytes..<count])
        guard let text = String(data: payloadData, encoding: .utf8) else { return }

        parseDiscoveryPayload(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseDiscoveryPayload(_ text: String) {
        guard !text.isEmpty else { return }

        // Keys are lowercased for case-insensitive matching.
        var kv: [String: String] = [:]
        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                kv[String(parts[0]).lowercased()] = String(parts[1])
            }
        }

        guard let serial = kv["serial"], !serial.isEmpty,
              let ip     = kv["ip"],     !ip.isEmpty else {
            AppFileLogger.shared.log("FlexDiscovery: payload missing serial/ip — \(text.prefix(120))")
            return
        }

        let radio = DiscoveredRadio(
            id:       serial,
            model:    kv["model"]    ?? kv["radio_type"] ?? "FlexRadio",
            callsign: kv["callsign"] ?? kv["nickname"]   ?? "",
            ip:       ip,
            port:     Int(kv["port"]    ?? "4992") ?? 4992,
            version:  kv["version"] ?? "",
            source:   .local,
            publicIp:      kv["publicip"]      ?? ip,
            publicTlsPort: Int(kv["publictlsport"] ?? "4994") ?? 4994,
            publicUdpPort: Int(kv["publicudpport"] ?? "4993") ?? 4993,
            wanConnected:  kv["wanconnected"] == "1"
        )

        AppFileLogger.shared.log("FlexDiscovery: parsed \(radio.displayName) @ \(ip)")
        upsert(radio, stale: true)
    }

    // MARK: Upsert + stale timer

    private func upsert(_ radio: DiscoveredRadio, stale: Bool) {
        Task { @MainActor in
            if let idx = radios.firstIndex(where: { $0.id == radio.id }) {
                radios[idx] = radio
            } else {
                radios.append(radio)
                AppFileLogger.shared.log("FlexDiscovery: found \(radio.displayName) [\(radio.source.rawValue)]")
            }
            if stale { resetStaleTimer(for: radio.id) }
        }
    }

    private func resetStaleTimer(for serial: String) {
        staleTimers[serial]?.cancel()
        let t = DispatchSource.makeTimerSource(queue: staleQueue)
        t.schedule(deadline: .now() + staleTimeout)
        t.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.radios.removeAll { $0.id == serial && $0.source == .local }
                self?.staleTimers.removeValue(forKey: serial)
                AppFileLogger.shared.log("FlexDiscovery: removed stale radio \(serial)")
            }
        }
        t.resume()
        staleTimers[serial] = t
    }

    // MARK: Helpers

    @inline(__always)
    private func be32(_ b: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(b[offset]) << 24) | (UInt32(b[offset+1]) << 16)
            | (UInt32(b[offset+2]) << 8) | UInt32(b[offset+3])
    }
}
