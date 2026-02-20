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

    // MARK: Mic TX

    /// When true, PTT down/up automatically starts/stops microphone capture.
    @Published var isMicTXEnabled: Bool = false
    /// True while mic audio is actively being captured and sent to the radio.
    @Published private(set) var isMicActive: Bool = false
    @Published var lanAudioOutputGain: Float = 1.0 {
        didSet { audioPlayer?.gain = lanAudioOutputGain }
    }
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
    private var vitaReceiver: VITAReceiver?
    private var lanAudioPipeline: LanAudioPipeline?
    private var audioPlayer: AudioOutputPlayer?

    private var cancellables = Set<AnyCancellable>()
    private var pendingWANRadio: DiscoveredRadio? = nil
    private var pendingWANHandle: String? = nil

    private var micCapture: FlexMicCapture?
    private var txDAXStreamID: UInt32 = 0x00000001  // updated from radio's dax_tx stream status
    private var currentRadioIP: String = ""         // set on connect; used for mic UDP target

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
        stopDAXAudio(sendCommand: false)   // connection is closing — don't send TCP commands
    }

    // MARK: Public — DAX audio

    func startDAXAudio() {
        guard connectionStatus.lowercased() == "connected" else { return }
        stopDAXAudio(sendCommand: true)

        let pipeline = LanAudioPipeline(processor: processorProxy)
        let player   = AudioOutputPlayer(sampleRate: 48_000)
        player.gain  = lanAudioOutputGain
        player.onLog   = { [weak self] msg in Task { @MainActor in self?.appendLog(msg) } }
        player.onError = { [weak self] msg in Task { @MainActor in self?.lanAudioError = msg } }

        let receiver = VITAReceiver()
        receiver.onLog   = { [weak self] msg in Task { @MainActor in self?.appendLog(msg) } }
        receiver.onError = { [weak self] msg in Task { @MainActor in
            self?.lanAudioError = msg
            self?.appendError("DAX: \(msg)")
        }}
        receiver.onPacket = { [weak self] _, _ in Task { @MainActor in
            guard let self else { return }
            self.audioPacketCount += 1
            self.lanAudioLastPacketAt = Date()
            if !self.isDAXRunning { self.isDAXRunning = true }
        }}
        receiver.onAudio48kMono = { [weak pipeline, weak player] samples in
            guard let pipeline, let player else { return }
            pipeline.process48kMono(samples) { processed in
                player.enqueue48kMono(processed)
            }
        }

        // Start audio output
        #if os(macOS)
        do {
            let deviceID: AudioDeviceID? = selectedLanAudioOutputUID.isEmpty
                ? AudioDeviceManager.defaultOutputDeviceID()
                : AudioDeviceManager.deviceID(forUID: selectedLanAudioOutputUID)
            try player.start(outputDeviceID: deviceID)
        } catch {
            lanAudioError = error.localizedDescription
            appendError("Audio player: \(error.localizedDescription)")
            return
        }
        #endif

        // Bind UDP receiver
        let udpPort: UInt16 = isWAN ? UInt16(pendingWANRadio?.publicUdpPort ?? 4993) : 4991
        do {
            try receiver.start(port: udpPort)
        } catch {
            player.stop()
            lanAudioError = error.localizedDescription
            appendError("VITAReceiver: \(error.localizedDescription)")
            return
        }

        // WAN path: attach Opus decoder so VITAReceiver decodes Opus payload instead of float32.
        if isWAN {
            if let decoder = OpusDecoder() {
                receiver.opusDecoder = decoder
                isOpusPath = true
            } else {
                appendLog("Warning: Opus decoder unavailable — WAN audio may be silent")
                isOpusPath = false
            }
        } else {
            isOpusPath = false
        }

        vitaReceiver    = receiver
        lanAudioPipeline = pipeline
        audioPlayer      = player
        lanAudioError    = nil

        // Enable DAX RX channel 1 and DAX TX on the active slice.
        // DAX TX must be enabled so the radio will accept our VITA-49 mic packets.
        send(FlexProtocol.setDAX(index: sliceIndex, channel: 1))
        send(FlexProtocol.setDAXTX(index: sliceIndex, enabled: true))
        appendLog("DAX audio started on UDP \(udpPort)")
    }

    func stopDAXAudio() { stopDAXAudio(sendCommand: true) }

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
        if down {
            announceAccessibility("Transmitting")
            if isMicTXEnabled { startMicCapture() }
        } else {
            announceAccessibility("Receiving")
            if isMicActive { stopMicCapture() }
        }
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
                if isWAN, let wanHandle = pendingWANHandle {
                    // WAN: send wan validate first, then subscriptions after a short delay
                    // so the radio has time to process the validation before receiving API commands.
                    pendingWANHandle = nil
                    connection.sendWANValidation(wanHandle: wanHandle)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        self.sendInitialSubscriptions()
                    }
                } else {
                    sendInitialSubscriptions()
                }
                announceAccessibility("Connected to radio")
            case .disconnected:
                appendLog("Disconnected")
                stopDAXAudio(sendCommand: false)
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
                // Store the WAN handle. setupConnectionCallbacks will send wan validate
                // immediately when the H line arrives (before subscriptions).
                self.pendingWANHandle = handle
                self.connection.connect(to: radio)
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
        // WAN requires registering our UDP endpoint so the radio knows where to send audio.
        if isWAN {
            send(FlexProtocol.clientUDPRegister(handle: connection.clientHandle))
            send(FlexProtocol.clientIP())
        }
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
            applyAudioStreamProps(msg.properties)
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

    // MARK: Private — DAX audio

    private func applyAudioStreamProps(_ props: [String: String]) {
        // Extract stream ID from the synthetic "_streamid" key injected in parseStatusLine.
        if let hexStr = props["_streamid"],
           let streamID = UInt32(hexStr.dropFirst(2), radix: 16) {
            let isDaxTX = props["type"] == "dax_tx" || props["dax_tx"] == "1"
            if isDaxTX {
                // Store the TX stream ID so FlexMicCapture uses the correct VITA-49 stream ID.
                txDAXStreamID = streamID
                AppFileLogger.shared.log("DAX TX stream ID: \(hexStr)")
            } else {
                vitaReceiver?.expectedStreamID = streamID
                AppFileLogger.shared.log("VITAReceiver: filtering on stream ID \(hexStr)")
            }
        }
        if props["in_use"] == "1" { isDAXRunning = true }
        if props["in_use"] == "0" { isDAXRunning = false }
    }

    private func stopDAXAudio(sendCommand: Bool) {
        if sendCommand && isDAXRunning {
            send(FlexProtocol.setDAX(index: sliceIndex, channel: 0))
            send(FlexProtocol.setDAXTX(index: sliceIndex, enabled: false))
        }
        stopMicCapture()
        vitaReceiver?.stop()
        vitaReceiver = nil
        audioPlayer?.stop()
        audioPlayer = nil
        lanAudioPipeline = nil
        audioPacketCount = 0
        isDAXRunning = false
        isOpusPath = false
    }

    // MARK: Private — mic TX

    private func startMicCapture() {
        guard isDAXRunning, !currentRadioIP.isEmpty else {
            appendLog("Mic TX: DAX must be running before PTT to send mic audio")
            return
        }
        stopMicCapture()

        let udpPort: UInt16 = isWAN ? UInt16(pendingWANRadio?.publicUdpPort ?? 4993) : 4991
        let capture = FlexMicCapture()
        capture.onLog   = { [weak self] msg in Task { @MainActor in self?.appendLog(msg) } }
        capture.onError = { [weak self] msg in Task { @MainActor in self?.appendError("Mic: \(msg)") } }
        do {
            try capture.start(radioIP: currentRadioIP, port: udpPort, streamID: txDAXStreamID)
            micCapture = capture
            isMicActive = true
        } catch {
            appendError("Mic capture failed: \(error.localizedDescription)")
        }
    }

    private func stopMicCapture() {
        micCapture?.stop()
        micCapture = nil
        isMicActive = false
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
