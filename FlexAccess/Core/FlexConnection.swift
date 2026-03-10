//
//  FlexConnection.swift
//  FlexAccess
//
//  TCP state machine for the SmartSDR API (port 4992 LAN / port 4994 TLS WAN).
//  Protocol lines:
//    V<version>        — firmware version (first line after connect)
//    H<handle>        — client handle (second line; signals fully connected)
//    R<seq>|<result>|[message]  — response to a command
//    S<handle>|<body> — unsolicited status update
//    M<body>          — meter data
//

import Foundation
import Network

enum FlexConnectionStatus: String {
    case disconnected = "Disconnected"
    case connecting   = "Connecting"
    case connected    = "Connected"
}

final class FlexConnection {

    var onStatusChange: ((FlexConnectionStatus) -> Void)?
    var onStatusLine:   ((String) -> Void)?
    var onMeterLine:    ((String) -> Void)?
    var onLog:          ((String) -> Void)?
    var onError:        ((String) -> Void)?

    private(set) var status: FlexConnectionStatus = .disconnected
    private(set) var clientHandle: String = ""
    private(set) var firmwareVersion: String = ""

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.w9fyi.flexaccess.tcp", qos: .userInitiated)
    private var receiveBuffer = Data()
    private var seqNumber = 1
    private var pendingResponses: [Int: (String, String) -> Void] = [:]
    private var connectTimeoutTimer: DispatchSourceTimer?
    private var keepaliveTimer: DispatchSourceTimer?
    private(set) var isWAN = false
    private var currentHost = ""

    // MARK: Connect

    func connect(to radio: DiscoveredRadio) {
        teardown()
        isWAN = (radio.source == .smartlink)
        currentHost = isWAN ? radio.publicIp : radio.ip
        let port = isWAN ? radio.publicTlsPort : radio.port
        seqNumber = 1
        pendingResponses.removeAll()

        status = .connecting
        DispatchQueue.main.async { self.onStatusChange?(.connecting) }
        onLog?("Connecting to \(currentHost):\(port) [\(isWAN ? "WAN/TLS" : "LAN")]")

        let params: NWParameters
        if isWAN {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, done in
                done(true)
            }, queue)
            params = NWParameters(tls: tlsOptions, tcp: .init())
        } else {
            params = .tcp
        }

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            DispatchQueue.main.async { self.onError?("Invalid port \(port)") }
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(currentHost), port: nwPort)
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self, self.connection === conn else { return }
            self.handleStateChange(state, conn: conn)
        }
        conn.start(queue: queue)
        startConnectTimeout()
    }

    func sendWANValidation(wanHandle: String) {
        sendRaw("wan validate handle=\(wanHandle)")
    }

    // MARK: Disconnect

    func disconnect() {
        teardown()
        status = .disconnected
        DispatchQueue.main.async {
            self.onStatusChange?(.disconnected)
            self.onLog?("Disconnected")
        }
    }

    // MARK: Send

    @discardableResult
    func send(_ command: String, response: ((String, String) -> Void)? = nil) -> Int {
        let seq = seqNumber
        seqNumber += 1
        if let response { pendingResponses[seq] = response }
        let redacted = command.hasPrefix("wan validate") ? "wan validate handle=<redacted>" : command
        DispatchQueue.main.async { self.onLog?("TX: C\(seq)|\(redacted)") }
        sendRaw("C\(seq)|\(command)")
        return seq
    }

    // MARK: Private — teardown

    private func teardown() {
        stopConnectTimeout()
        stopKeepalive()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        clientHandle = ""
        firmwareVersion = ""
    }

    // MARK: Private — state machine

    private func handleStateChange(_ state: NWConnection.State, conn: NWConnection) {
        switch state {
        case .ready:
            stopConnectTimeout()
            DispatchQueue.main.async { self.onLog?("TCP ready — awaiting V/H handshake") }
            receiveLoop(conn: conn)
            startKeepalive()
        case .failed(let error):
            stopConnectTimeout()
            DispatchQueue.main.async { self.onError?("Connection failed: \(error.localizedDescription)") }
            disconnect()
        case .waiting(let error):
            DispatchQueue.main.async { self.onError?("Waiting: \(error.localizedDescription)") }
        case .cancelled:
            break
        default:
            break
        }
    }

    // MARK: Private — receive loop

    private func receiveLoop(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, self.connection === conn else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if let error {
                DispatchQueue.main.async { self.onError?("Receive error: \(error.localizedDescription)") }
                self.disconnect()
                return
            }
            if isComplete { self.disconnect(); return }
            self.receiveLoop(conn: conn)
        }
    }

    private func processBuffer() {
        while let range = receiveBuffer.range(of: Data([0x0A])) {
            let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<range.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                handleLine(line)
            }
        }
    }

    private func handleLine(_ line: String) {
        DispatchQueue.main.async { self.onLog?("RX: \(line)") }

        if line.hasPrefix("V") {
            firmwareVersion = String(line.dropFirst())
            return
        }
        if line.hasPrefix("H") {
            clientHandle = String(line.dropFirst())
            status = .connected
            DispatchQueue.main.async {
                self.onStatusChange?(.connected)
                self.onLog?("Connected — handle=\(self.clientHandle) v=\(self.firmwareVersion)")
            }
            return
        }
        if line.hasPrefix("R") {
            let parts = line.dropFirst().split(separator: "|", maxSplits: 2)
            if parts.count >= 2, let seq = Int(parts[0]) {
                let result  = String(parts[1])
                let message = parts.count > 2 ? String(parts[2]) : ""
                if let handler = pendingResponses.removeValue(forKey: seq) {
                    DispatchQueue.main.async { handler(result, message) }
                }
            }
            return
        }
        if line.hasPrefix("S") {
            let payload = line.dropFirst()
            if let barIdx = payload.firstIndex(of: "|") {
                let body = String(payload[payload.index(after: barIdx)...])
                DispatchQueue.main.async { self.onStatusLine?(body) }
            }
            return
        }
        if line.hasPrefix("M") {
            let body = String(line.dropFirst())
            DispatchQueue.main.async { self.onMeterLine?(body) }
            return
        }
    }

    // MARK: Private — raw send

    private func sendRaw(_ text: String) {
        guard let conn = connection, status != .disconnected else { return }
        let data = (text + "\n").data(using: .utf8)!
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onError?("Send failed: \(error.localizedDescription)") }
            }
        })
    }

    // MARK: Private — timers

    private func startConnectTimeout() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 15)
        t.setEventHandler { [weak self] in
            guard let self, self.status == .connecting else { return }
            DispatchQueue.main.async { self.onError?("Connection timed out — \(self.currentHost) unreachable") }
            self.disconnect()
        }
        t.resume()
        connectTimeoutTimer = t
    }
    private func stopConnectTimeout() { connectTimeoutTimer?.cancel(); connectTimeoutTimer = nil }

    private func startKeepalive() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 25, repeating: 25)
        t.setEventHandler { [weak self] in self?.send("ping") }
        t.resume()
        keepaliveTimer = t
    }
    private func stopKeepalive() { keepaliveTimer?.cancel(); keepaliveTimer = nil }
}
