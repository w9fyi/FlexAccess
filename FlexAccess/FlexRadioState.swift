//
//  FlexRadioState.swift
//  FlexAccess
//
//  Central @Observable state object. Wires FlexConnection callbacks into published
//  properties consumed by SwiftUI views. Mirrors RadioState.swift from Kenwood Control.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
import AudioToolbox
#endif

@MainActor
final class FlexRadioState: ObservableObject {

    // MARK: Connection

    @Published private(set) var connectionStatus: String = "Disconnected"
    @Published private(set) var lastError: String? = nil
    @Published private(set) var radioModel: String = ""
    @Published private(set) var firmwareVersion: String = ""
    @Published private(set) var isWAN: Bool = false
    @Published private(set) var connectionLog: [String] = []
    @Published private(set) var errorLog: [String] = []
    @Published private(set) var lastTXFrame: String = ""
    @Published private(set) var lastRXFrame: String = ""

    // MARK: Active slice

    @Published private(set) var sliceIndex: Int = 0
    @Published var sliceFrequencyHz: Int? = nil
    @Published var sliceMode: FlexMode = .usb
    @Published var sliceFilterLo: Int = 200
    @Published var sliceFilterHi: Int = 2700
    @Published var sliceNREnabled: Bool = false
    @Published var sliceNBEnabled: Bool = false
    @Published var sliceANFEnabled: Bool = false
    @Published var sliceAGCMode: FlexAGCMode = .med
    @Published private(set) var isTX: Bool = false

    // MARK: Equalizer

    @Published var rxEQEnabled: Bool = false
    @Published var txEQEnabled: Bool = false
    @Published var rxEQBands: [Int: Int] = {
        Dictionary(uniqueKeysWithValues: FlexProtocol.eqBandHz.map { ($0, 0) })
    }()
    @Published var txEQBands: [Int: Int] = {
        Dictionary(uniqueKeysWithValues: FlexProtocol.eqBandHz.map { ($0, 0) })
    }()

    // MARK: Audio

    @Published private(set) var isDAXRunning: Bool = false
    @Published private(set) var lanAudioError: String? = nil
    @Published private(set) var audioPacketCount: Int = 0
    @Published private(set) var lanAudioLastPacketAt: Date? = nil
    @Published private(set) var isOpusPath: Bool = false
    @Published var lanAudioOutputGain: Float = 1.0
    @Published var selectedLanAudioOutputUID: String = ""
    @Published var audioOutputDevices: [AudioDeviceInfo] = []

    // MARK: Software Noise Reduction

    @Published var isNoiseReductionEnabled: Bool = false {
        didSet { processorProxy.isEnabled = isNoiseReductionEnabled }
    }
    @Published private(set) var isNoiseReductionAvailable: Bool = false
    @Published var selectedNoiseReductionBackend: String = "RNNoise"
    @Published var noiseReductionStrength: Float = 0.85
    @Published private(set) var availableNoiseReductionBackends: [String] = []
    @Published private(set) var noiseReductionBackend: String = "Passthrough"

    // MARK: Infrastructure

    private let connection = FlexConnection()
    private let discovery: FlexDiscovery
    let smartLinkAuth = SmartLinkAuth.shared
    private let smartLinkBroker = SmartLinkBroker()

    let processorProxy: NoiseReductionProcessorProxy
    private var lanAudioPipeline: LanAudioPipeline?
    private var audioPlayer: AudioOutputPlayer?

    private var cancellables = Set<AnyCancellable>()
    private var pendingWANRadio: DiscoveredRadio? = nil

    // MARK: Init

    init(discovery: FlexDiscovery) {
        self.discovery = discovery

        // Build NR proxy — try RNNoise first, fall back to passthrough
        var backends: [String] = ["Passthrough"]
        var initialInner: any NoiseReductionProcessor = PassthroughNoiseReduction()

        if let rn = RNNoiseProcessor() {
            initialInner = rn
            backends.insert("RNNoise", at: 0)
            AppFileLogger.shared.log("FlexRadioState: RNNoise available")
        }
        if WDSPNoiseReductionProcessor(mode: .emnr) != nil {
            backends.insert("WDSP EMNR", at: backends.count - 1)
            AppFileLogger.shared.log("FlexRadioState: WDSP EMNR available")
        }
        if WDSPNoiseReductionProcessor(mode: .anr) != nil {
            backends.insert("WDSP ANR", at: backends.count - 1)
            AppFileLogger.shared.log("FlexRadioState: WDSP ANR available")
        }

        self.processorProxy = NoiseReductionProcessorProxy(inner: initialInner)
        self.availableNoiseReductionBackends = backends
        self.noiseReductionBackend = backends.first ?? "Passthrough"
        self.selectedNoiseReductionBackend = noiseReductionBackend
        self.isNoiseReductionAvailable = !(initialInner is PassthroughNoiseReduction)

        setupConnectionCallbacks()
        setupSmartLinkBroker()
        refreshAudioDevices()
        loadPersistedSettings()
    }

    // MARK: Public — connect

    func connect(to radio: DiscoveredRadio) {
        lastError = nil
        radioModel = radio.model
        isWAN = (radio.source == .smartlink)
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
                    appendError(error.localizedDescription)
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

    // MARK: Public — disconnect

    func disconnect() {
        smartLinkBroker.disconnect()
        connection.disconnect()
        stopDAXAudio()
    }

    // MARK: Public — send command

    @discardableResult
    func send(_ command: String) -> Int {
        connection.send(command)
    }

    // MARK: Public — slice control

    func setSliceFrequency(_ hz: Int) {
        sliceFrequencyHz = hz
        let mhz = Double(hz) / 1_000_000.0
        send(FlexProtocol.sliceTune(index: sliceIndex, freqMHz: mhz))
    }

    func setSliceMode(_ mode: FlexMode) {
        sliceMode = mode
        send(FlexProtocol.setMode(index: sliceIndex, mode: mode))
    }

    func setFilter(lo: Int, hi: Int) {
        sliceFilterLo = lo
        sliceFilterHi = hi
        send(FlexProtocol.setFilter(index: sliceIndex, lo: lo, hi: hi))
    }

    func setNR(_ enabled: Bool) {
        sliceNREnabled = enabled
        send(FlexProtocol.setNR(index: sliceIndex, enabled: enabled))
    }

    func setNB(_ enabled: Bool) {
        sliceNBEnabled = enabled
        send(FlexProtocol.setNB(index: sliceIndex, enabled: enabled))
    }

    func setANF(_ enabled: Bool) {
        sliceANFEnabled = enabled
        send(FlexProtocol.setANF(index: sliceIndex, enabled: enabled))
    }

    func setAGC(_ mode: FlexAGCMode) {
        sliceAGCMode = mode
        send(FlexProtocol.setAGC(index: sliceIndex, mode: mode))
    }

    func setPTT(down: Bool) {
        send(down ? FlexProtocol.pttDown() : FlexProtocol.pttUp())
        isTX = down
        if down { announceAccessibility("Transmitting") } else { announceAccessibility("Receiving") }
    }

    // MARK: Public — equalizer

    func setEQBand(type: FlexEQType, hz: Int, value: Int) {
        if type == .rx { rxEQBands[hz] = value } else { txEQBands[hz] = value }
        send(FlexProtocol.eqBand(type: type, hz: hz, value: value))
    }

    func setEQEnabled(type: FlexEQType, enabled: Bool) {
        if type == .rx { rxEQEnabled = enabled } else { txEQEnabled = enabled }
        send(FlexProtocol.eqMode(type: type, enabled: enabled))
    }

    func eqFlat(type: FlexEQType) {
        let zeroBands = Dictionary(uniqueKeysWithValues: FlexProtocol.eqBandHz.map { ($0, 0) })
        if type == .rx { rxEQBands = zeroBands } else { txEQBands = zeroBands }
        send(FlexProtocol.eqFlat(type: type))
    }

    // MARK: Public — NR backend

    func setNoiseReductionBackend(_ name: String) {
        selectedNoiseReductionBackend = name
        noiseReductionBackend = name
        UserDefaults.standard.set(name, forKey: "FlexAccess.NRBackend")
        let newProcessor: any NoiseReductionProcessor
        switch name {
        case "RNNoise":    newProcessor = RNNoiseProcessor()    ?? PassthroughNoiseReduction()
        case "WDSP EMNR":  newProcessor = WDSPNoiseReductionProcessor(mode: .emnr) ?? PassthroughNoiseReduction()
        case "WDSP ANR":   newProcessor = WDSPNoiseReductionProcessor(mode: .anr)  ?? PassthroughNoiseReduction()
        default:           newProcessor = PassthroughNoiseReduction()
        }
        newProcessor.isEnabled = isNoiseReductionEnabled
        processorProxy.inner = newProcessor
        AppFileLogger.shared.log("FlexRadioState: NR backend → \(name)")
    }

    func setNoiseReduction(enabled: Bool) {
        isNoiseReductionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "FlexAccess.NREnabled")
    }

    // MARK: Public — audio

    func refreshAudioDevices() {
        #if os(macOS)
        audioOutputDevices = AudioDeviceManager.outputDevices()
        #endif
    }

    func applyLanAudioOutputSelection() {
        #if os(macOS)
        guard let player = audioPlayer else { return }
        let deviceID: AudioDeviceID?
        if selectedLanAudioOutputUID.isEmpty {
            deviceID = AudioDeviceManager.defaultOutputDeviceID()
        } else {
            deviceID = AudioDeviceManager.deviceID(forUID: selectedLanAudioOutputUID)
        }
        // Player must be restarted to switch device — stop + restart
        if isDAXRunning {
            player.stop()
            try? player.start(outputDeviceID: deviceID)
        }
        #endif
    }

    // MARK: Public — logs

    func clearConnectionLog() { connectionLog.removeAll() }

    // MARK: Private — setup callbacks

    private func setupConnectionCallbacks() {
        connection.onStatusChange = { [weak self] status in
            guard let self else { return }
            connectionStatus = status.rawValue
            switch status {
            case .connected:
                appendLog("Connected — \(isWAN ? "SmartLink/WAN" : "Local LAN")")
                sendInitialSubscriptions()
                announceAccessibility("Connected to radio")
            case .disconnected:
                appendLog("Disconnected")
                stopDAXAudio()
                isTX = false
                announceAccessibility("Disconnected from radio")
            case .connecting:
                appendLog("Connecting…")
            }
        }

        connection.onStatusLine = { [weak self] body in
            self?.handleStatusLine(body)
        }

        connection.onLog = { [weak self] msg in
            guard let self else { return }
            if msg.hasPrefix("TX:") { lastTXFrame = msg }
            if msg.hasPrefix("RX:") { lastRXFrame = msg }
            appendLog(msg)
        }

        connection.onError = { [weak self] msg in
            self?.lastError = msg
            self?.appendError(msg)
            self?.announceAccessibility("Error: \(msg)")
        }
    }

    private func setupSmartLinkBroker() {
        smartLinkBroker.onWANHandleReady = { [weak self] handle, radio in
            guard let self else { return }
            Task { @MainActor in
                // WAN handle received — now open the direct TLS connection to the radio
                self.connection.connect(to: radio)
                // After TCP is established, send WAN validation
                // Small delay to allow V/H lines to be received first
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.connection.sendWANValidation(wanHandle: handle)
            }
        }

        smartLinkBroker.onRadioListUpdate = { [weak self] radios in
            guard let self else { return }
            for radio in radios {
                self.discovery.injectSmartLinkRadio(radio)
            }
        }
    }

    // MARK: Private — subscriptions

    private func sendInitialSubscriptions() {
        send(FlexProtocol.subRadio())
        send(FlexProtocol.subSliceAll())
        send(FlexProtocol.subMeterList())
        // Query EQ state
        send("eq rxsc info")
        send("eq txsc info")
    }

    // MARK: Private — status line handler

    private func handleStatusLine(_ body: String) {
        let msg = FlexProtocol.parseStatusLine(body)
        switch msg.kind {
        case .slice(let idx):
            if idx == sliceIndex { applySliceProps(msg.properties) }
        case .eq(let type):
            applyEQProps(msg.properties, type: type)
        case .radio:
            applyRadioProps(msg.properties)
        case .audioStream:
            break // Phase 2
        default:
            break
        }
    }

    private func applySliceProps(_ props: [String: String]) {
        if let f = props["rf_frequency"], let mhz = Double(f) {
            sliceFrequencyHz = Int((mhz * 1_000_000).rounded())
        }
        if let m = props["mode"], let mode = FlexMode(rawValue: m.uppercased()) {
            sliceMode = mode
        }
        if let v = props["filter_lo"], let lo = Int(v) { sliceFilterLo = lo }
        if let v = props["filter_hi"], let hi = Int(v) { sliceFilterHi = hi }
        if let v = props["nr"]  { sliceNREnabled  = v == "1" }
        if let v = props["nb"]  { sliceNBEnabled  = v == "1" }
        if let v = props["anf"] { sliceANFEnabled = v == "1" }
        if let v = props["agc_mode"], let agc = FlexAGCMode(rawValue: v) { sliceAGCMode = agc }
        if let v = props["tx"] { isTX = v == "1" }
    }

    private func applyEQProps(_ props: [String: String], type: FlexEQType) {
        let enabled = props["mode"] == "1"
        let bands = FlexProtocol.parseEQBands(from: props)
        if type == .rx {
            rxEQEnabled = enabled
            for (hz, val) in bands { rxEQBands[hz] = val }
        } else {
            txEQEnabled = enabled
            for (hz, val) in bands { txEQBands[hz] = val }
        }
    }

    private func applyRadioProps(_ props: [String: String]) {
        if let m = props["model"] { radioModel = m }
    }

    // MARK: Private — DAX audio (Phase 2 stub)

    private func stopDAXAudio() {
        isDAXRunning = false
        audioPlayer?.stop()
        lanAudioPipeline = nil
    }

    // MARK: Private — log helpers

    private func appendLog(_ msg: String) {
        let entry = "[\(timestamp())] \(msg)"
        connectionLog.append(entry)
        if connectionLog.count > 200 { connectionLog.removeFirst() }
        AppFileLogger.shared.log(msg)
    }

    private func appendError(_ msg: String) {
        let entry = "[\(timestamp())] \(msg)"
        errorLog.append(entry)
        if errorLog.count > 100 { errorLog.removeFirst() }
        AppFileLogger.shared.log("ERROR: \(msg)")
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: Private — accessibility

    private func announceAccessibility(_ message: String) {
        #if os(macOS)
        NSAccessibility.post(element: NSApp, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        #else
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    // MARK: Private — persisted settings

    private func loadPersistedSettings() {
        if let backend = UserDefaults.standard.string(forKey: "FlexAccess.NRBackend"),
           availableNoiseReductionBackends.contains(backend) {
            setNoiseReductionBackend(backend)
        }
        isNoiseReductionEnabled = UserDefaults.standard.bool(forKey: "FlexAccess.NREnabled")
        processorProxy.isEnabled = isNoiseReductionEnabled
    }
}
