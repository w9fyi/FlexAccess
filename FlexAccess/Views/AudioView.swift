import SwiftUI
#if os(macOS)
import CoreAudio
#endif

/// DAX audio controls — start/stop, NR, device selection.
struct AudioView: View {
    @Bindable var radio: Radio

    @State private var outputDevices: [AudioDeviceInfo] = []
    @State private var inputDevices:  [AudioDeviceInfo] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // DAX Start / Stop
                GroupBox("DAX Audio") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(radio.isDAXRunning ? "Running" : "Stopped")
                                    .foregroundStyle(radio.isDAXRunning ? .green : .secondary)
                                    .font(.callout.bold())
                                if let at = radio.daxEngine.lastPacketAt {
                                    Text("Last packet: \(at.formatted(.relative(presentation: .named)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Packets: \(radio.daxEngine.audioPacketCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            Spacer()
                            Button(radio.isDAXRunning ? "Stop DAX" : "Start DAX") {
                                if radio.isDAXRunning { radio.stopDAX() }
                                else if let slice = radio.activeSlice { radio.startDAX(forSlice: slice.id) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(radio.connectionStatus != .connected)
                            .accessibilityLabel(radio.isDAXRunning ? "Stop DAX audio" : "Start DAX audio")
                        }

                        // Output device
                        #if os(macOS)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output Device").font(.caption).foregroundStyle(.secondary)
                            Picker("Output Device", selection: Binding(
                                get: { radio.audioOutputUID },
                                set: { radio.audioOutputUID = $0; radio.daxEngine.switchOutputDevice(uid: $0) }
                            )) {
                                Text("System Default").tag("")
                                ForEach(outputDevices) { dev in
                                    Text(dev.displayName).tag(dev.uid)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("Audio output device")
                        }

                        // Input device (mic TX)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mic Input Device").font(.caption).foregroundStyle(.secondary)
                            Picker("Mic Input", selection: Binding(
                                get: { radio.audioInputUID },
                                set: { radio.audioInputUID = $0 }
                            )) {
                                Text("System Default").tag("")
                                ForEach(inputDevices) { dev in
                                    Text(dev.displayName).tag(dev.uid)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("Microphone input device")
                        }
                        #endif
                    }
                }

                // Noise Reduction
                GroupBox("Noise Reduction") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable Noise Reduction", isOn: Binding(
                            get: { radio.isNREnabled },
                            set: { radio.isNREnabled = $0 }
                        ))
                        .accessibilityLabel("Software noise reduction on/off")

                        if radio.isNREnabled {
                            Picker("Backend", selection: Binding(
                                get: { radio.nrBackend },
                                set: { radio.nrBackend = $0 }
                            )) {
                                ForEach(radio.availableNRBackends, id: \.self) { backend in
                                    Text(backend).tag(backend)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Noise reduction algorithm")
                        }
                    }
                    .padding(4)
                }

                // DAX stream IDs (diagnostic)
                if radio.isDAXRunning {
                    GroupBox("Stream IDs") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let rxID = radio.daxEngine.rxStreamIDHex {
                                Text("RX: \(rxID)").font(.system(.caption, design: .monospaced))
                            }
                            if let txID = radio.daxEngine.txStreamIDHex {
                                Text("TX: \(txID)").font(.system(.caption, design: .monospaced))
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            .padding()
        }
        .onAppear { refreshDevices() }
    }

    private func refreshDevices() {
        #if os(macOS)
        outputDevices = AudioDeviceManager.outputDevices()
        inputDevices  = AudioDeviceManager.inputDevices()
        #endif
    }
}
