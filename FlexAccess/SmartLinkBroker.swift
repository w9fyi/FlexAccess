//
//  SmartLinkBroker.swift
//  FlexAccess
//
//  Maintains a TLS connection to smartlink.flexradio.com:443 after SmartLink login.
//  Registers the app, receives the list of online radios, and brokers the WAN
//  connection request (returning a wanHandle nonce for wan validate).
//

import Foundation
import Network

@MainActor
final class SmartLinkBroker: ObservableObject {

    @Published private(set) var isConnected = false

    // Callback — fires when the broker delivers a wanHandle ready for FlexConnection.sendWANValidation
    var onWANHandleReady: ((String, DiscoveredRadio) -> Void)?
    // Callback — fires when the radio list updates
    var onRadioListUpdate: (([DiscoveredRadio]) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.w9fyi.flexaccess.smartlink", qos: .userInitiated)
    private var receiveBuffer = Data()
    private var pendingSerial: String = ""
    private var pendingRadio: DiscoveredRadio?

    private static let host = "smartlink.flexradio.com"
    private static let port: UInt16 = 443

    // MARK: Connect to broker

    func connect(idToken: String) {
        disconnect()
        AppFileLogger.shared.log("SmartLinkBroker: connecting to \(Self.host):\(Self.port)")

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, done in
            done(true)  // Accept all certs
        }, queue)
        let params = NWParameters(tls: tlsOptions, tcp: .init())
        guard let nwPort = NWEndpoint.Port(rawValue: Self.port) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(Self.host), port: nwPort)

        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                AppFileLogger.shared.log("SmartLinkBroker: TLS connected")
                Task { @MainActor in
                    self.receiveLoop(conn: conn)
                    self.register(idToken: idToken, conn: conn)
                    self.isConnected = true
                }
            case .failed(let err):
                AppFileLogger.shared.log("SmartLinkBroker: failed — \(err)")
                Task { @MainActor in self.isConnected = false }
            case .cancelled:
                Task { @MainActor in self.isConnected = false }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        isConnected = false
    }

    // MARK: Request WAN connection to a radio

    func requestConnect(to radio: DiscoveredRadio) {
        pendingSerial = radio.id
        pendingRadio = radio
        // SmartLink server message format (matches K3TZR ApiPackage)
        send("application connect serial=\(radio.id) hole_punch_port=0")
        AppFileLogger.shared.log("SmartLinkBroker: requesting connect to \(radio.id)")
    }

    // MARK: Private — registration

    private func register(idToken: String, conn: NWConnection) {
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        send("application register name=FlexAccess platform=\(platform) token=\(idToken)")
    }

    // MARK: Private — receive loop

    private func receiveLoop(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === conn else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if error != nil || isComplete { return }
            self.receiveLoop(conn: conn)
        }
    }

    private func processBuffer() {
        while let range = receiveBuffer.range(of: Data([0x0A])) {
            let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<range.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                Task { @MainActor in self.handleLine(line) }
            }
        }
    }

    private func handleLine(_ line: String) {
        AppFileLogger.shared.log("SmartLinkBroker RX: \(line)")

        // Radio list: "radio list serial=... model=... ip=... ..."
        if line.hasPrefix("radio list") {
            parseRadioList(line)
            return
        }

        // Connection ready: "radio connect_ready handle=<wanHandle>"
        if line.hasPrefix("radio connect_ready") {
            let kv = parseKV(line)
            if let handle = kv["handle"], let radio = pendingRadio {
                AppFileLogger.shared.log("SmartLinkBroker: WAN handle ready for \(radio.id)")
                onWANHandleReady?(handle, radio)
            }
            return
        }
    }

    // MARK: Private — radio list parser

    private func parseRadioList(_ line: String) {
        // Each radio is a space-separated key=value sequence after "radio list"
        // Multiple radios may arrive in separate "radio list" messages
        let kv = parseKV(line)
        guard let serial = kv["serial"], !serial.isEmpty,
              let ip = kv["ip"], !ip.isEmpty else { return }

        var radio = DiscoveredRadio(
            id: serial,
            model: kv["model"] ?? "FlexRadio",
            callsign: kv["callsign"] ?? "",
            ip: ip,
            port: Int(kv["port"] ?? "4992") ?? 4992,
            version: kv["version"] ?? "",
            source: .smartlink
        )
        radio.publicIp = ip
        radio.publicTlsPort = Int(kv["publicTlsPort"] ?? "4994") ?? 4994
        radio.publicUdpPort = Int(kv["publicUdpPort"] ?? "4993") ?? 4993
        radio.wanConnected = true

        AppFileLogger.shared.log("SmartLinkBroker: radio \(radio.displayName) in list")
        onRadioListUpdate?([radio])
    }

    private func parseKV(_ line: String) -> [String: String] {
        var kv: [String: String] = [:]
        for token in line.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                kv[String(parts[0])] = String(parts[1])
            }
        }
        return kv
    }

    private func send(_ text: String) {
        guard let conn = connection else { return }
        let data = (text + "\n").data(using: .utf8)!
        conn.send(content: data, completion: .contentProcessed { error in
            if let error {
                AppFileLogger.shared.log("SmartLinkBroker TX error: \(error)")
            }
        })
        AppFileLogger.shared.log("SmartLinkBroker TX: \(text.hasPrefix("application register") ? "application register ... token=<redacted>" : text)")
    }
}
