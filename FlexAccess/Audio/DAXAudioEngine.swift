//
//  DAXAudioEngine.swift
//  FlexAccess
//
//  Manages the DAX RX/TX audio pipeline:
//    - NRPipeline      — noise reduction (swappable backend)
//    - AudioOutputPlayer — CoreAudio HAL output
//    - MicCapture      — TX mic → VITA-49 UDP
//
//  Radio owns the single VITAReceiver and feeds decoded audio here via feedAudio(_:).
//  One instance lives in Radio; Radio calls startAudio()/stop() around DAX sessions.
//

import Foundation
#if os(macOS)
import CoreAudio
#endif

final class DAXAudioEngine {

    // MARK: Diagnostics

    private(set) var audioPacketCount: Int = 0
    private(set) var lastPacketAt: Date? = nil

    // MARK: Stream IDs (for Radio.swift to send stream remove commands)

    private(set) var rxStreamIDHex: String? = nil
    private(set) var txStreamIDHex: String? = nil

    // MARK: Private components

    private var audioPlayer:  AudioOutputPlayer?
    private var nrPipeline:   NRPipeline?
    private var micCapture:   MicCapture?
    private var nrProxy:      NoiseReductionProcessorProxy?

    private var feedBatchCount = 0

    // MARK: Start

    func startAudio(outputUID: String,
                    nrBackend: String,
                    nrEnabled: Bool) throws {
        stopAudio()

        // Build NR proxy
        let inner = makeNRProcessor(backend: nrBackend)
        inner.isEnabled = nrEnabled
        let proxy = NoiseReductionProcessorProxy(inner: inner)
        nrProxy   = proxy

        let pipeline = NRPipeline(processor: proxy)
        nrPipeline   = pipeline

        // Build audio player
        let player = AudioOutputPlayer(sampleRate: 48_000)
        player.onLog   = { msg in AppFileLogger.shared.log("AudioOutputPlayer: \(msg)") }
        player.onError = { msg in AppFileLogger.shared.log("AudioOutputPlayer ERROR: \(msg)") }

        #if os(macOS)
        let devID: AudioDeviceID? = outputUID.isEmpty
            ? AudioDeviceManager.defaultOutputDeviceID()
            : AudioDeviceManager.deviceID(forUID: outputUID)
        try player.start(outputDeviceID: devID)
        #else
        try player.start()
        #endif
        audioPlayer = player

        AppFileLogger.shared.log("DAXAudioEngine: audio started")
    }

    /// Feed 48 kHz mono samples from the VITA receiver into the NR pipeline → audio player.
    /// Called on the VITAReceiver background thread.
    func feedAudio(_ samples: [Float]) {
        feedBatchCount += 1
        if feedBatchCount >= 100 {
            let n = feedBatchCount; feedBatchCount = 0
            Task { @MainActor [weak self] in
                self?.audioPacketCount += n
                self?.lastPacketAt = Date()
            }
        }
        guard let pipeline = nrPipeline, let player = audioPlayer else { return }
        pipeline.process(samples) { processed in player.enqueue48kMono(processed) }
    }

    // MARK: Stop

    func stop() {
        stopAudio()
        rxStreamIDHex = nil
        txStreamIDHex = nil
        audioPacketCount = 0
        lastPacketAt = nil
        AppFileLogger.shared.log("DAXAudioEngine: stopped")
    }

    func stopAudio() {
        micCapture?.stop();  micCapture  = nil
        audioPlayer?.stop();  audioPlayer  = nil
        nrPipeline?.reset();  nrPipeline   = nil
        nrProxy     = nil
        feedBatchCount = 0
    }

    // MARK: Stream ID updates (called from Radio when radio responds to stream create)

    func setExpectedStreamID(_ sid: UInt32) {
        rxStreamIDHex = String(format: "0x%08X", sid)
        AppFileLogger.shared.log("DAXAudioEngine: RX stream ID → \(rxStreamIDHex!)")
    }

    func setTxStreamID(_ sid: UInt32) {
        txStreamIDHex = String(format: "0x%08X", sid)
        AppFileLogger.shared.log("DAXAudioEngine: TX stream ID → \(txStreamIDHex!)")
    }

    // MARK: NR controls

    func setNREnabled(_ enabled: Bool) {
        nrProxy?.isEnabled = enabled
    }

    func setNRBackend(_ backend: String) {
        let inner = makeNRProcessor(backend: backend)
        inner.isEnabled = nrProxy?.isEnabled ?? false
        nrProxy?.inner = inner
        AppFileLogger.shared.log("DAXAudioEngine: NR backend → \(backend)")
    }

    // MARK: Mic TX

    func startMicCapture(radioIP: String, isWAN: Bool, wanUDPPort: Int, inputUID: String) {
        stopMicCapture()
        let port: UInt16 = isWAN ? UInt16(wanUDPPort) : 4991
        let txSID: UInt32 = txStreamIDHex.flatMap { UInt32($0.dropFirst(2), radix: 16) } ?? 0x00000001
        let capture = MicCapture()
        capture.onLog   = { msg in AppFileLogger.shared.log("MicCapture: \(msg)") }
        capture.onError = { msg in AppFileLogger.shared.log("MicCapture ERROR: \(msg)") }
        do {
            #if os(macOS)
            let devID: UInt32? = inputUID.isEmpty
                ? AudioDeviceManager.defaultInputDeviceID()
                : AudioDeviceManager.deviceID(forUID: inputUID)
            try capture.start(radioIP: radioIP, port: port, streamID: txSID, inputDeviceID: devID)
            #else
            try capture.start(radioIP: radioIP, port: port, streamID: txSID)
            #endif
            micCapture = capture
        } catch {
            AppFileLogger.shared.log("DAXAudioEngine: mic capture start failed: \(error)")
        }
    }

    func stopMicCapture() {
        micCapture?.stop()
        micCapture = nil
    }

    // MARK: Output device switch (mid-session)

    func switchOutputDevice(uid: String) {
        guard let player = audioPlayer else { return }
        #if os(macOS)
        let devID: AudioDeviceID? = uid.isEmpty
            ? AudioDeviceManager.defaultOutputDeviceID()
            : AudioDeviceManager.deviceID(forUID: uid)
        player.stop()
        try? player.start(outputDeviceID: devID)
        #endif
    }

    // MARK: Private

    private func makeNRProcessor(backend: String) -> any NoiseReductionProcessor {
        switch backend {
        case "RNNoise":   return RNNoiseProcessor()    ?? PassthroughNoiseReduction()
        case "WDSP EMNR": return WDSPNoiseReductionProcessor(mode: .emnr) ?? PassthroughNoiseReduction()
        case "WDSP ANR":  return WDSPNoiseReductionProcessor(mode: .anr)  ?? PassthroughNoiseReduction()
        default:          return PassthroughNoiseReduction()
        }
    }
}
