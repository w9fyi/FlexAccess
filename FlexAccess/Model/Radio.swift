//
//  Radio.swift
//  FlexAccess
//
//  Central @Observable model for a connected FlexRadio.
//  Owns the TCP connection, slice/panadapter state, and DAX audio engine.
//  Replaces the old single-slice FlexRadioState monolith.
//

import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Observable
final class Radio {

    // MARK: Connection state

    private(set) var connectionStatus: FlexConnectionStatus = .disconnected
    private(set) var connectedRadio: DiscoveredRadio?
    private(set) var firmwareVersion: String = ""
    private(set) var radioModel: String = ""
    private(set) var connectionLog: [String] = []
    private(set) var lastError: String? = nil
    private(set) var isWAN: Bool = false

    // MARK: Slices (multi-slice — FLEX-6x00/8x00 support up to 8)

    private(set) var slices: [Slice] = []
    var activeSliceIndex: Int = 0

    var activeSlice: Slice? { slices.first { $0.id == activeSliceIndex } }

    // MARK: Panadapters

    private(set) var panadapters: [Panadapter] = []

    // MARK: TX

    private(set) var isTX: Bool = false
    private(set) var txAntenna: String = "ANT1"

    // MARK: Audio (DAX engine handles per-slice audio)

    let daxEngine: DAXAudioEngine
    private(set) var isDAXRunning: Bool = false

    // MARK: NR

    var isNREnabled: Bool = false {
        didSet {
            daxEngine.setNREnabled(isNREnabled)
            FlexSettings.saveNREnabled(isNREnabled)
        }
    }
    var nrBackend: String = "Passthrough" {
        didSet {
            daxEngine.setNRBackend(nrBackend)
            FlexSettings.saveNRBackend(nrBackend)
        }
    }
    private(set) var availableNRBackends: [String] = ["Passthrough"]

    // MARK: Audio device selection

    var audioOutputUID: String = "" {
        didSet { FlexSettings.saveAudioOutputUID(audioOutputUID) }
    }
    var audioInputUID: String = "" {
        didSet { FlexSettings.saveAudioInputUID(audioInputUID) }
    }

    // MARK: Infrastructure

    private let connection = FlexConnection()
    let discovery: FlexDiscovery
    let smartLinkAuth = SmartLinkAuth.shared
    private let smartLinkBroker = SmartLinkBroker()

    private var pendingWANRadio: DiscoveredRadio?
    private var pendingWANHandle: String?
    private var currentRadioIP: String = ""

    // MARK: Init

    init(discovery: FlexDiscovery) {
        self.discovery = discovery
        self.daxEngine = DAXAudioEngine()

        // Build NR backend list
        var backends: [String] = []
        if RNNoiseProcessor() != nil          { backends.append("RNNoise") }
        if WDSPNoiseReductionProcessor(mode: .emnr) != nil { backends.append("WDSP EMNR") }
        if WDSPNoiseReductionProcessor(mode: .anr)  != nil { backends.append("WDSP ANR") }
        backends.append("Passthrough")
        availableNRBackends = backends

        // Restore persisted settings
        audioOutputUID = FlexSettings.loadAudioOutputUID()
        audioInputUID  = FlexSettings.loadAudioInputUID()
        isNREnabled    = FlexSettings.loadNREnabled()
        if let backend = FlexSettings.loadNRBackend(), backends.contains(backend) {
            nrBackend = backend
        } else {
            nrBackend = backends[0]
        }

        setupConnectionCallbacks()
        setupSmartLinkBroker()
    }

    // MARK: Connect / Disconnect

    func connect(to radio: DiscoveredRadio) {
        lastError = nil
        connectedRadio = radio
        radioModel = radio.model
        isWAN = (radio.source == .smartlink)
        currentRadioIP = isWAN ? radio.publicIp : radio.ip
        FlexSettings.saveLastSerial(radio.id)
        if radio.source == .local { FlexSettings.saveLastLocalRadio(ip: radio.ip, port: radio.port) }
        appendLog("Connecting to \(radio.displayName) [\(radio.source.rawValue)]")

        if isWAN {
            pendingWANRadio = radio
            Task {
                do {
                    let token = try await smartLinkAuth.ensureValidToken()
                    smartLinkBroker.connect(idToken: token)
                    smartLinkBroker.requestConnect(to: radio)
                } catch {
                    lastError = error.localizedDescription
                    appendLog("SmartLink error: \(error.localizedDescription)")
                }
            }
        } else {
            connection.connect(to: radio)
        }
    }

    func connect(host: String, port: Int) {
        let radio = DiscoveredRadio(id: "direct", model: "FlexRadio", callsign: "",
                                   ip: host, port: port, version: "", source: .direct)
        connect(to: radio)
    }

    func disconnect() {
        smartLinkBroker.disconnect()
        connection.disconnect()
        stopDAX(sendCommand: false)
    }

    // MARK: PTT

    func setPTT(down: Bool) {
        connection.send(down ? FlexProtocol.pttDown() : FlexProtocol.pttUp())
        isTX = down
        if down {
            announce("Transmitting")
            if isDAXRunning { daxEngine.startMicCapture(radioIP: currentRadioIP, isWAN: isWAN,
                                                         wanUDPPort: pendingWANRadio?.publicUdpPort ?? 4993,
                                                         inputUID: audioInputUID) }
        } else {
            announce("Receiving")
            daxEngine.stopMicCapture()
        }
    }

    // MARK: Slice commands

    func tune(sliceIndex: Int, hz: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.frequencyHz = hz
        connection.send(FlexProtocol.sliceTune(index: sliceIndex, freqMHz: Double(hz) / 1_000_000))
    }

    func setMode(sliceIndex: Int, mode: FlexMode) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.mode = mode
        connection.send(FlexProtocol.setMode(index: sliceIndex, mode: mode))
    }

    func setFilter(sliceIndex: Int, lo: Int, hi: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.filterLo = lo; slice.filterHi = hi
        connection.send(FlexProtocol.setFilter(index: sliceIndex, lo: lo, hi: hi))
    }

    func setNR(sliceIndex: Int, enabled: Bool) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.nrEnabled = enabled
        connection.send(FlexProtocol.setNR(index: sliceIndex, enabled: enabled))
    }

    func setNB(sliceIndex: Int, enabled: Bool) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.nbEnabled = enabled
        connection.send(FlexProtocol.setNB(index: sliceIndex, enabled: enabled))
    }

    func setANF(sliceIndex: Int, enabled: Bool) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.anfEnabled = enabled
        connection.send(FlexProtocol.setANF(index: sliceIndex, enabled: enabled))
    }

    func setAGC(sliceIndex: Int, mode: FlexAGCMode) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.agcMode = mode
        connection.send(FlexProtocol.setAGC(index: sliceIndex, mode: mode))
    }

    func setAGCThreshold(sliceIndex: Int, level: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.agcThreshold = level
        connection.send(FlexProtocol.setAGCThreshold(index: sliceIndex, level: level))
    }

    func setRFGain(sliceIndex: Int, db: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.rfGain = db
        connection.send(FlexProtocol.setRFGain(index: sliceIndex, db: db))
    }

    func setAudioLevel(sliceIndex: Int, level: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.audioLevel = level
        connection.send(FlexProtocol.setAudioLevel(index: sliceIndex, level: level))
    }

    func setRxAnt(sliceIndex: Int, ant: String) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        slice.rxAnt = ant
        connection.send(FlexProtocol.setRxAnt(index: sliceIndex, ant: ant))
    }

    func setTxAnt(_ ant: String) {
        txAntenna = ant
        connection.send(FlexProtocol.setTxAnt(ant: ant))
    }

    // MARK: EQ commands

    func setEQBand(type: FlexEQType, sliceIndex: Int, hz: Int, value: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        if type == .rx { slice.rxEQBands[hz] = value } else { slice.txEQBands[hz] = value }
        connection.send(FlexProtocol.eqBand(type: type, hz: hz, value: value))
    }

    func setEQEnabled(type: FlexEQType, sliceIndex: Int, enabled: Bool) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        if type == .rx { slice.rxEQEnabled = enabled } else { slice.txEQEnabled = enabled }
        connection.send(FlexProtocol.eqMode(type: type, enabled: enabled))
    }

    // MARK: DAX audio

    func startDAX(forSlice sliceIndex: Int) {
        guard connectionStatus == .connected else { return }
        let daxChannel = resolvedDaxChannel(for: sliceIndex)
        let udpPort: UInt16 = isWAN ? UInt16(pendingWANRadio?.publicUdpPort ?? 4993) : 4991
        appendLog("DAX: starting channel \(daxChannel) for slice \(sliceIndex)")

        // New-style stream create (firmware 3.x+)
        connection.send(FlexProtocol.streamCreateDAXRX(daxChannel: daxChannel, port: udpPort)) { [weak self] result, message in
            guard let self, !result.hasPrefix("5") else { return }
            let raw = message.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
            guard !raw.isEmpty else { return }
            let hex = raw.hasPrefix("0x") ? raw : "0x\(raw)"
            if let sid = UInt32(hex.dropFirst(2), radix: 16) {
                self.daxEngine.setExpectedStreamID(sid)
                self.appendLog("DAX RX stream: \(hex)")
            }
        }
        connection.send(FlexProtocol.streamCreateDAXTX()) { [weak self] result, message in
            guard let self, !result.hasPrefix("5") else { return }
            let raw = message.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
            guard !raw.isEmpty else { return }
            let hex = raw.hasPrefix("0x") ? raw : "0x\(raw)"
            if let sid = UInt32(hex.dropFirst(2), radix: 16) {
                self.daxEngine.setTxStreamID(sid)
                self.appendLog("DAX TX stream: \(hex)")
            }
        }
        // Old-style fallback (firmware 1.x/2.x)
        connection.send(FlexProtocol.setDAX(index: sliceIndex, channel: daxChannel))

        do {
            try daxEngine.start(udpPort: udpPort, isWAN: isWAN,
                                outputUID: audioOutputUID,
                                nrBackend: nrBackend, nrEnabled: isNREnabled)
            isDAXRunning = true
        } catch {
            lastError = error.localizedDescription
            appendLog("DAX start error: \(error.localizedDescription)")
        }
    }

    func stopDAX() { stopDAX(sendCommand: true) }

    // MARK: Panadapter commands

    func createPanadapter(forSlice sliceIndex: Int) {
        guard let slice = slices.first(where: { $0.id == sliceIndex }) else { return }
        let freqMHz = Double(slice.frequencyHz) / 1_000_000
        connection.send(FlexProtocol.panadapterCreate(freqMHz: freqMHz, ant: slice.rxAnt)) { [weak self] result, message in
            guard let self, !result.hasPrefix("5") else { return }
            let panID = message.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
            guard !panID.isEmpty else { return }
            let pan = Panadapter(id: panID)
            pan.centerMHz = freqMHz
            self.panadapters.append(pan)
            self.appendLog("Panadapter created: \(panID)")
        }
    }

    // MARK: Raw send

    @discardableResult
    func send(_ command: String) -> Int { connection.send(command) }

    // MARK: Log

    func clearLog() { connectionLog.removeAll() }

    // MARK: Private — subscriptions

    private func sendInitialSubscriptions() {
        connection.send(FlexProtocol.clientProgram("FlexAccess"))
        let udpPort: UInt16 = isWAN ? UInt16(pendingWANRadio?.publicUdpPort ?? 4993) : 4991
        connection.send(FlexProtocol.clientUDPPort(udpPort))
        if isWAN { connection.send(FlexProtocol.clientIP()) }
        connection.send(FlexProtocol.subRadio())
        connection.send(FlexProtocol.subSliceAll())
        connection.send(FlexProtocol.subMeterList())
        connection.send(FlexProtocol.subPanadapter())
        connection.send(FlexProtocol.subAudioStream())
        connection.send(FlexProtocol.sliceList()) { [weak self] result, message in
            guard let self, !result.hasPrefix("5") else { return }
            let clean = message.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
            let indices = clean.split(separator: " ").compactMap { Int($0) }
            AppFileLogger.shared.log("Active slice indices: \(indices)")
            if indices.isEmpty {
                self.appendLog("No active slices — creating slice on 14.225 MHz USB")
                self.connection.send(FlexProtocol.sliceCreate(freqMHz: 14.225)) { [weak self] res, msg in
                    guard let self, !res.hasPrefix("5") else { return }
                    let raw = msg.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
                    if let idx = Int(raw) { self.ensureSlice(index: idx) }
                }
            } else {
                for idx in indices { self.ensureSlice(index: idx) }
                if let first = indices.first { self.activeSliceIndex = first }
            }
        }
        connection.send("eq rxsc info")
        connection.send("eq txsc info")
    }

    // MARK: Private — status handling

    private func handleStatusLine(_ body: String) {
        let msg = FlexProtocol.parseStatusLine(body)
        switch msg.kind {
        case .slice(let idx):
            ensureSlice(index: idx)
            slices.first(where: { $0.id == idx })?.applyProperties(msg.properties)
            if let tx = msg.properties["tx"] { if tx == "1" { isTX = true } else if tx == "0" { isTX = false } }
        case .sliceList:
            let raw    = msg.properties["_raw"] ?? ""
            let indices = raw.split(separator: " ").compactMap { Int($0) }
            for idx in indices { ensureSlice(index: idx) }
            // Remove slices that are no longer reported
            slices = slices.filter { indices.contains($0.id) }
            if let first = indices.first, !slices.contains(where: { $0.id == activeSliceIndex }) {
                activeSliceIndex = first
            }
        case .eq(let type):
            let enabled = msg.properties["mode"] == "1"
            let bands   = FlexProtocol.parseEQBands(from: msg.properties)
            if let slice = activeSlice {
                if type == .rx {
                    slice.rxEQEnabled = enabled
                    for (hz, val) in bands { slice.rxEQBands[hz] = val }
                } else {
                    slice.txEQEnabled = enabled
                    for (hz, val) in bands { slice.txEQBands[hz] = val }
                }
            }
        case .radio:
            if let m = msg.properties["model"] { radioModel = m }
        case .audioStream:
            if let hexStr = msg.properties["_streamid"],
               let sid = UInt32(hexStr.dropFirst(2), radix: 16) {
                let isDaxTX = msg.properties["type"] == "dax_tx" || msg.properties["dax_tx"] == "1"
                if isDaxTX { daxEngine.setTxStreamID(sid) }
                else       { daxEngine.setExpectedStreamID(sid) }
            }
            if msg.properties["in_use"] == "1" { isDAXRunning = true }
            if msg.properties["in_use"] == "0" { isDAXRunning = false }
        case .panadapter(let panID):
            guard !panID.isEmpty else { return }
            if let pan = panadapters.first(where: { $0.id == panID }) {
                pan.applyProperties(msg.properties)
            } else {
                let pan = Panadapter(id: panID)
                pan.applyProperties(msg.properties)
                panadapters.append(pan)
            }
        case .waterfall(let wfID):
            AppFileLogger.shared.log("Waterfall status: \(wfID) — \(msg.properties)")
        case .meter:
            break   // meters handled separately if needed
        case .unknown:
            AppFileLogger.shared.log("Radio: unhandled status — \(body.prefix(120))")
        }
    }

    // MARK: Private — slice management

    private func ensureSlice(index: Int) {
        if !slices.contains(where: { $0.id == index }) {
            slices.append(Slice(index: index))
            slices.sort { $0.id < $1.id }
            appendLog("Slice \(index) added")
        }
    }

    private func resolvedDaxChannel(for sliceIndex: Int) -> Int {
        // Use existing assignment if any, else assign channel = sliceIndex+1 (1-8)
        if let slice = slices.first(where: { $0.id == sliceIndex }), slice.daxChannel > 0 {
            return slice.daxChannel
        }
        return (sliceIndex % 8) + 1
    }

    // MARK: Private — DAX stop

    private func stopDAX(sendCommand: Bool) {
        if sendCommand && isDAXRunning {
            if let rxHex = daxEngine.rxStreamIDHex { connection.send(FlexProtocol.streamRemove(streamID: rxHex)) }
            if let txHex = daxEngine.txStreamIDHex { connection.send(FlexProtocol.streamRemove(streamID: txHex)) }
            if let slice = activeSlice { connection.send(FlexProtocol.setDAX(index: slice.id, channel: 0)) }
        }
        daxEngine.stop()
        isDAXRunning = false
    }

    // MARK: Private — connection callbacks

    private func setupConnectionCallbacks() {
        connection.onStatusChange = { [weak self] status in
            guard let self else { return }
            connectionStatus = status
            switch status {
            case .connected:
                appendLog("Connected — \(isWAN ? "SmartLink/WAN" : "LAN")")
                if isWAN, let handle = pendingWANHandle {
                    pendingWANHandle = nil
                    connection.sendWANValidation(wanHandle: handle)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        self.sendInitialSubscriptions()
                    }
                } else {
                    sendInitialSubscriptions()
                }
                announce("Connected to radio")
            case .disconnected:
                appendLog("Disconnected")
                slices.removeAll()
                panadapters.removeAll()
                isTX = false
                stopDAX(sendCommand: false)
                announce("Disconnected from radio")
            case .connecting:
                appendLog("Connecting…")
            }
        }
        connection.onStatusLine = { [weak self] body in self?.handleStatusLine(body) }
        connection.onLog   = { [weak self] msg in self?.appendLog(msg) }
        connection.onError = { [weak self] msg in
            self?.lastError = msg
            self?.appendLog("Error: \(msg)")
            self?.announce("Error: \(msg)")
        }
    }

    private func setupSmartLinkBroker() {
        smartLinkBroker.onWANHandleReady = { [weak self] handle, radio in
            guard let self else { return }
            Task { @MainActor in
                self.pendingWANHandle = handle
                self.connection.connect(to: radio)
            }
        }
        smartLinkBroker.onRadioListUpdate = { [weak self] radios in
            guard let self else { return }
            for radio in radios { self.discovery.injectSmartLinkRadio(radio) }
        }
    }

    // MARK: Private — helpers

    private func appendLog(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        connectionLog.append("[\(f.string(from: Date()))] \(msg)")
        if connectionLog.count > 300 { connectionLog.removeFirst() }
        AppFileLogger.shared.log(msg)
    }

    private func announce(_ message: String) {
        #if os(macOS)
        NSAccessibility.post(element: NSApp,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        #else
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}
