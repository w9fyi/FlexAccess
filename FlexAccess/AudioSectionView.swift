//
//  AudioSectionView.swift
//  FlexAccess
//
//  DAX receive audio controls, output device selection, and software noise reduction.
//

import SwiftUI

struct AudioSectionView: View {
    @ObservedObject var radio: FlexRadioState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Audio")
                    .font(.title2)

                daxSection
                Divider()
                micSection
                Divider()
                nrSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    // MARK: DAX Receive Audio

    private var daxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAX Receive Audio")
                .font(.headline)

            HStack(spacing: 12) {
                Text(radio.isDAXRunning ? "Running" : "Stopped")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(radio.isDAXRunning ? .green : .secondary)
                    .accessibilityLabel("DAX audio \(radio.isDAXRunning ? "running" : "stopped")")

                if radio.isOpusPath {
                    Text("(Opus / WAN)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if radio.isDAXRunning {
                    Text("(PCM float32 / LAN)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(radio.isDAXRunning ? "Stop" : "Start") {
                    if radio.isDAXRunning { radio.stopDAXAudio() } else { radio.startDAXAudio() }
                }
                .disabled(radio.connectionStatus.lowercased() != "connected")
                .accessibilityLabel(radio.isDAXRunning ? "Stop DAX audio" : "Start DAX audio")
                .accessibilityHint("Toggles DAX receive audio from the radio")
            }

            HStack(spacing: 12) {
                Text("Packets: \(radio.audioPacketCount)")
                    .font(.system(.body, design: .monospaced))
                if let t = radio.lanAudioLastPacketAt {
                    Text("Last: \(t.formatted(date: .omitted, time: .standard))")
                        .font(.system(.body, design: .monospaced))
                }
            }

            if let err = radio.lanAudioError {
                Text("Audio Error: \(err)")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Audio error: \(err)")
            }

            #if os(macOS)
            HStack(spacing: 12) {
                Picker("Output", selection: $radio.selectedLanAudioOutputUID) {
                    Text("System Default").tag("")
                    ForEach(radio.audioOutputDevices) { dev in
                        Text(dev.displayName).tag(dev.uid)
                    }
                }
                .frame(minWidth: 320)
                .accessibilityLabel("Audio output device")
                .onChange(of: radio.selectedLanAudioOutputUID) { _, _ in
                    radio.applyLanAudioOutputSelection()
                }

                Button("Refresh") { radio.refreshAudioDevices() }
                    .accessibilityHint("Re-scans for audio output devices")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Volume:")
                    Slider(value: $radio.lanAudioOutputGain, in: 0.1...4.0)
                        .frame(width: 240)
                        .accessibilityLabel("Audio output volume")
                        .accessibilityValue(String(format: "%.2f", radio.lanAudioOutputGain))
                    Text(String(format: "%.2f", radio.lanAudioOutputGain))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 48, alignment: .trailing)
                }
                Text("1.0 = unity gain  •  4.0 = maximum boost")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }

    // MARK: DAX Transmit Audio (Mic)

    private var micSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAX Transmit Audio (Mic)")
                .font(.headline)

            Toggle("Send mic audio with PTT", isOn: $radio.isMicTXEnabled)
                .accessibilityLabel("Send microphone audio when transmitting")
                .accessibilityHint("When enabled, holds PTT down to start mic capture and PTT up to stop")

            #if os(macOS)
            HStack(spacing: 12) {
                Picker("Mic Input", selection: $radio.selectedLanAudioInputUID) {
                    Text("System Default").tag("")
                    ForEach(radio.audioInputDevices) { dev in
                        Text(dev.name).tag(dev.uid)
                    }
                }
                .frame(minWidth: 320)
                .accessibilityLabel("Microphone input device")

                Button("Refresh") { radio.refreshAudioDevices() }
                    .accessibilityHint("Re-scans for audio input devices")
            }
            #endif

            if radio.isMicTXEnabled {
                HStack(spacing: 8) {
                    Circle()
                        .fill(radio.isMicActive ? Color.red : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(radio.isMicActive ? "Transmitting mic audio" : "Idle (PTT not held)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(radio.isMicActive ? .red : .secondary)
                        .accessibilityLabel(
                            radio.isMicActive ? "Microphone active, transmitting" : "Microphone idle"
                        )
                }

                Text("Start DAX first, then hold PTT (Option-Space or button) to transmit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Audio is sent at 24 kHz mono, duplicated to stereo for the radio.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Software Noise Reduction

    private var nrSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Software Noise Reduction")
                .font(.headline)

            Toggle("Enable", isOn: Binding(
                get: { radio.isNoiseReductionEnabled },
                set: { radio.setNoiseReduction(enabled: $0) }
            ))
            .disabled(!radio.isNoiseReductionAvailable)
            .accessibilityLabel("Software noise reduction")
            .accessibilityValue(radio.isNoiseReductionEnabled ? "On" : "Off")

            Text("Shortcut: Command-Shift-N")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Noise reduction keyboard shortcut: Command Shift N")

            HStack(spacing: 12) {
                Text("Backend:")
                Picker("NR Backend", selection: $radio.selectedNoiseReductionBackend) {
                    ForEach(radio.availableNoiseReductionBackends, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(minWidth: 240)
                .accessibilityLabel("Noise reduction backend")
                .onChange(of: radio.selectedNoiseReductionBackend) { _, name in
                    radio.setNoiseReductionBackend(name)
                }
            }

            if !radio.selectedNoiseReductionBackend.hasPrefix("WDSP") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Text("Strength:")
                        Slider(value: $radio.noiseReductionStrength, in: 0...1, step: 0.05)
                            .frame(minWidth: 240)
                            .accessibilityLabel("Noise reduction strength")
                            .accessibilityValue("\(Int(radio.noiseReductionStrength * 100)) percent")
                        Text("\(Int(radio.noiseReductionStrength * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Text("Radio NR / NB / ANF are controlled in the Slice section.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Tip: Start DAX in the Audio section to receive audio from the radio. Software NR processes DAX audio before playback.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
