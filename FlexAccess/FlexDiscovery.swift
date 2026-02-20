//
//  FlexDiscovery.swift
//  FlexAccess
//
//  Listens on UDP port 4992 for VITA-49 discovery broadcasts from FlexRadio 6000-series
//  radios on the local LAN. Also accepts injected entries from SmartLinkBroker for WAN
//  radios. Published [DiscoveredRadio] auto-removes stale LAN entries after 3 seconds.
//

import Foundation
import Network

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

    private var listener: NWListener?
    private var staleTimers: [String: DispatchSourceTimer] = [:]
    private let queue = DispatchQueue(label: "com.w9fyi.flexaccess.discovery", qos: .utility)
    private let staleTimeout: TimeInterval = 5.0

    // VITA-49 discovery packet identifiers
    private static let discoveryStreamID: UInt32 = 0x00000800
    private static let discoveryOUI: UInt32      = 0x001C2D
    private static let discoveryClassCode: UInt16 = 0xFFFF

    // MARK: Start / Stop

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 4992)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    AppFileLogger.shared.log("FlexDiscovery: listening on UDP 4992")
                case .failed(let err):
                    AppFileLogger.shared.log("FlexDiscovery: listener failed \(err)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener?.start(queue: queue)
        } catch {
            AppFileLogger.shared.log("FlexDiscovery: failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
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

    // MARK: UDP connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(from: conn)
    }

    private func receive(from conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            defer { conn.cancel() }
            guard let data, error == nil else { return }
            self?.parsePacket(data)
        }
    }

    // MARK: VITA-49 parsing

    private func parsePacket(_ data: Data) {
        // VITA-49 header is 7 × 4-byte words = 28 bytes minimum for discovery
        guard data.count >= 28 else { return }

        // Word 0: packet type, class indicator, TSI, TSF, count, size
        let word0 = data.readUInt32BE(at: 0)
        let packetType = (word0 >> 28) & 0xF
        // Type 4 = Extension Context (used for discovery)
        guard packetType == 4 else { return }

        // Word 1: Stream ID
        let streamID = data.readUInt32BE(at: 4)
        guard streamID == FlexDiscovery.discoveryStreamID else { return }

        // Words 2–3: Class ID (OUI + Information Class + Packet Class)
        let oui = data.readUInt32BE(at: 8) & 0x00FFFFFF
        let classCode = UInt16(data.readUInt32BE(at: 12) & 0xFFFF)
        guard oui == FlexDiscovery.discoveryOUI, classCode == FlexDiscovery.discoveryClassCode else { return }

        // Payload starts at byte 28 (7 header words × 4)
        guard data.count > 28 else { return }
        let payload = data.subdata(in: 28..<data.count)
        guard let text = String(data: payload, encoding: .utf8) else { return }

        parseDiscoveryPayload(text)
    }

    private func parseDiscoveryPayload(_ text: String) {
        var kv: [String: String] = [:]
        for token in text.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                kv[String(parts[0])] = String(parts[1]).replacingOccurrences(of: "_", with: " ")
            }
        }

        guard let serial = kv["serial"], !serial.isEmpty,
              let ip = kv["ip"], !ip.isEmpty else { return }

        let radio = DiscoveredRadio(
            id: serial,
            model: kv["model"] ?? "FlexRadio",
            callsign: kv["callsign"] ?? "",
            ip: ip,
            port: Int(kv["port"] ?? "4992") ?? 4992,
            version: kv["version"] ?? "",
            source: .local,
            publicIp: ip,
            publicTlsPort: Int(kv["publicTlsPort"] ?? "4994") ?? 4994,
            publicUdpPort: Int(kv["publicUdpPort"] ?? "4993") ?? 4993,
            wanConnected: kv["wanConnected"] == "1"
        )

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
        let t = DispatchSource.makeTimerSource(queue: queue)
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
}

// MARK: - Data helpers

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            let val = ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            return val.bigEndian
        }
    }
}
