import SwiftUI

/// VFO, mode, filters, DSP and TX controls for one slice.
struct SliceView: View {
    let radio: Radio
    @Bindable var slice: Slice

    @State private var freqString: String = ""
    @State private var isEditingFreq = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Frequency + tuning step
            VStack(alignment: .leading, spacing: 4) {
                Text("Frequency").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("MHz", text: $freqString, onCommit: commitFrequency)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title2, design: .monospaced))
                        .frame(maxWidth: 200)
                        .accessibilityLabel("Frequency in megahertz")
                        .accessibilityValue(slice.formattedFrequency)
                        .onAppear { freqString = String(format: "%.6f", Double(slice.frequencyHz) / 1_000_000) }
                        .onChange(of: slice.frequencyHz) { _, new in
                            if !isEditingFreq {
                                freqString = String(format: "%.6f", Double(new) / 1_000_000)
                            }
                        }
                    Stepper("", onIncrement: { stepFrequency(by:  slice.stepHz) },
                               onDecrement: { stepFrequency(by: -slice.stepHz) })
                        .labelsHidden()
                        .accessibilityLabel("Tune frequency by \(stepLabel(slice.stepHz))")
                }
                // Tuning step picker
                HStack(spacing: 4) {
                    Text("Step:").font(.caption).foregroundStyle(.secondary)
                    ForEach(FlexProtocol.stepValues, id: \.self) { step in
                        Button(stepLabel(step)) {
                            radio.setStep(sliceIndex: slice.id, hz: step)
                        }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .tint(slice.stepHz == step ? Color.accentColor : nil)
                        .accessibilityLabel("Tuning step \(stepLabel(step))")
                        .accessibilityAddTraits(slice.stepHz == step ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }

            // Mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Mode").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(FlexMode.allCases) { mode in
                        Button(mode.label) {
                            radio.setMode(sliceIndex: slice.id, mode: mode)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(slice.mode == mode ? Color.accentColor : nil)
                        .accessibilityLabel("Mode \(mode.label)")
                        .accessibilityAddTraits(slice.mode == mode ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }

            // Filters
            VStack(alignment: .leading, spacing: 4) {
                Text("Filter").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Lo:").font(.caption)
                    TextField("Lo", value: Binding(
                        get: { slice.filterLo },
                        set: { radio.setFilter(sliceIndex: slice.id, lo: $0, hi: slice.filterHi) }
                    ), formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                        .accessibilityLabel("Filter low edge in hertz")
                    Text("Hi:").font(.caption)
                    TextField("Hi", value: Binding(
                        get: { slice.filterHi },
                        set: { radio.setFilter(sliceIndex: slice.id, lo: slice.filterLo, hi: $0) }
                    ), formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                        .accessibilityLabel("Filter high edge in hertz")
                    Text("Hz").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(filterPresets, id: \.0) { label, lo, hi in
                        Button(label) { radio.setFilter(sliceIndex: slice.id, lo: lo, hi: hi) }
                            .buttonStyle(.bordered).controlSize(.mini)
                            .accessibilityLabel("Filter \(label)")
                    }
                }
            }

            // AGC
            VStack(alignment: .leading, spacing: 4) {
                Text("AGC").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(FlexAGCMode.allCases) { mode in
                        Button(mode.label) {
                            radio.setAGC(sliceIndex: slice.id, mode: mode)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(slice.agcMode == mode ? Color.accentColor : nil)
                        .accessibilityLabel("AGC \(mode.label)")
                        .accessibilityAddTraits(slice.agcMode == mode ? [.isButton, .isSelected] : .isButton)
                    }
                    Spacer()
                    Text("Threshold:").font(.caption)
                    Slider(value: Binding(
                        get: { Double(slice.agcThreshold) },
                        set: { radio.setAGCThreshold(sliceIndex: slice.id, level: Int($0)) }
                    ), in: 0...100, step: 1)
                        .frame(width: 100)
                        .accessibilityLabel("AGC threshold \(slice.agcThreshold)")
                }
            }

            // RF Gain / Audio Level
            VStack(alignment: .leading, spacing: 4) {
                Text("Levels").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RF Gain: \(slice.rfGain) dB").font(.caption)
                        Slider(value: Binding(
                            get: { Double(slice.rfGain) },
                            set: { radio.setRFGain(sliceIndex: slice.id, db: Int($0)) }
                        ), in: -100...0, step: 1)
                            .frame(width: 120)
                            .accessibilityLabel("RF gain \(slice.rfGain) dB")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio: \(slice.audioLevel)").font(.caption)
                        Slider(value: Binding(
                            get: { Double(slice.audioLevel) },
                            set: { radio.setAudioLevel(sliceIndex: slice.id, level: Int($0)) }
                        ), in: 0...100, step: 1)
                            .frame(width: 120)
                            .accessibilityLabel("Audio level \(slice.audioLevel)")
                    }
                }
            }

            // DSP toggles (NR / NB / ANF)
            HStack(spacing: 16) {
                Toggle("NR", isOn: Binding(get: { slice.nrEnabled },
                                           set: { radio.setNR(sliceIndex: slice.id, enabled: $0) }))
                    .accessibilityLabel("Noise Reduction")
                Toggle("NB", isOn: Binding(get: { slice.nbEnabled },
                                           set: { radio.setNB(sliceIndex: slice.id, enabled: $0) }))
                    .accessibilityLabel("Noise Blanker")
                Toggle("ANF", isOn: Binding(get: { slice.anfEnabled },
                                            set: { radio.setANF(sliceIndex: slice.id, enabled: $0) }))
                    .accessibilityLabel("Automatic Notch Filter")
            }
            .toggleStyle(.button)

            // APF — only shown for CW modes
            if slice.mode == .cw || slice.mode == .cwl {
                VStack(alignment: .leading, spacing: 4) {
                    Text("APF").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Toggle("APF", isOn: Binding(
                            get: { slice.apfEnabled },
                            set: { radio.setAPF(sliceIndex: slice.id, enabled: $0) }))
                            .toggleStyle(.button).controlSize(.small)
                            .accessibilityLabel("Audio Peak Filter")
                        if slice.apfEnabled {
                            Text("Q:").font(.caption)
                            Slider(value: Binding(
                                get: { Double(slice.apfQFactor) },
                                set: { radio.setAPFQFactor(sliceIndex: slice.id, q: Int($0)) }
                            ), in: 0...33, step: 1)
                                .frame(width: 80)
                                .accessibilityLabel("APF Q factor \(slice.apfQFactor)")
                            Text("Gain:").font(.caption)
                            Slider(value: Binding(
                                get: { Double(slice.apfGain) },
                                set: { radio.setAPFGain(sliceIndex: slice.id, gain: Int($0)) }
                            ), in: 0...100, step: 1)
                                .frame(width: 80)
                                .accessibilityLabel("APF gain \(slice.apfGain)")
                        }
                    }
                }
            }

            // RIT / XIT
            VStack(alignment: .leading, spacing: 4) {
                Text("RIT / XIT").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    // RIT
                    HStack(spacing: 4) {
                        Toggle("RIT", isOn: Binding(
                            get: { slice.ritEnabled },
                            set: { radio.setRIT(sliceIndex: slice.id, enabled: $0) }))
                            .toggleStyle(.button).controlSize(.small)
                            .accessibilityLabel("Receiver Incremental Tuning")
                        Stepper("", onIncrement: { radio.setRITOffset(sliceIndex: slice.id, hz: slice.ritOffsetHz + 10) },
                                   onDecrement: { radio.setRITOffset(sliceIndex: slice.id, hz: slice.ritOffsetHz - 10) })
                            .labelsHidden()
                            .disabled(!slice.ritEnabled)
                            .accessibilityLabel("RIT offset adjust")
                        Text(offsetLabel(slice.ritOffsetHz))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minWidth: 64, alignment: .trailing)
                            .accessibilityLabel("RIT offset \(slice.ritOffsetHz) hertz")
                        if slice.ritOffsetHz != 0 {
                            Button("Clear") { radio.setRITOffset(sliceIndex: slice.id, hz: 0) }
                                .buttonStyle(.bordered).controlSize(.mini)
                                .accessibilityLabel("Clear RIT offset")
                        }
                    }
                    // XIT
                    HStack(spacing: 4) {
                        Toggle("XIT", isOn: Binding(
                            get: { slice.xitEnabled },
                            set: { radio.setXIT(sliceIndex: slice.id, enabled: $0) }))
                            .toggleStyle(.button).controlSize(.small)
                            .accessibilityLabel("Transmitter Incremental Tuning")
                        Stepper("", onIncrement: { radio.setXITOffset(sliceIndex: slice.id, hz: slice.xitOffsetHz + 10) },
                                   onDecrement: { radio.setXITOffset(sliceIndex: slice.id, hz: slice.xitOffsetHz - 10) })
                            .labelsHidden()
                            .disabled(!slice.xitEnabled)
                            .accessibilityLabel("XIT offset adjust")
                        Text(offsetLabel(slice.xitOffsetHz))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minWidth: 64, alignment: .trailing)
                            .accessibilityLabel("XIT offset \(slice.xitOffsetHz) hertz")
                        if slice.xitOffsetHz != 0 {
                            Button("Clear") { radio.setXITOffset(sliceIndex: slice.id, hz: 0) }
                                .buttonStyle(.bordered).controlSize(.mini)
                                .accessibilityLabel("Clear XIT offset")
                        }
                    }
                }
            }

            // Squelch — FM/NFM only
            if slice.mode == .fm || slice.mode == .nfm {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Squelch").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Toggle("SQL", isOn: Binding(
                            get: { slice.squelchEnabled },
                            set: { radio.setSquelch(sliceIndex: slice.id, enabled: $0) }))
                            .toggleStyle(.button).controlSize(.small)
                            .accessibilityLabel("Squelch enable")
                        Slider(value: Binding(
                            get: { Double(slice.squelchLevel) },
                            set: { radio.setSquelchLevel(sliceIndex: slice.id, level: Int($0)) }
                        ), in: 0...100, step: 1)
                            .frame(width: 120)
                            .accessibilityLabel("Squelch level \(slice.squelchLevel) percent")
                        Text("\(slice.squelchLevel)%").font(.caption)
                            .accessibilityHidden(true)
                    }
                }
            }

            // Antenna
            VStack(alignment: .leading, spacing: 4) {
                Text("Antenna").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(slice.antList, id: \.self) { ant in
                        Button(ant) { radio.setRxAnt(sliceIndex: slice.id, ant: ant) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(slice.rxAnt == ant ? Color.accentColor : nil)
                            .accessibilityLabel("Antenna \(ant)")
                            .accessibilityAddTraits(slice.rxAnt == ant ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }

            // PTT
            Button(action: { radio.setPTT(down: !radio.isTX) }) {
                Label(radio.isTX ? "TX — Press to Unkey" : "PTT",
                      systemImage: radio.isTX ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(radio.isTX ? .red : Color.accentColor)
            .accessibilityLabel(radio.isTX ? "Transmitting — activate to stop" : "Push to talk")
            .accessibilityAddTraits(radio.isTX ? [.isButton, .isSelected] : .isButton)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Private

    private var filterPresets: [(String, Int, Int)] {
        switch slice.mode {
        case .usb, .lsb: return [("2.7k", 200, 2700), ("2.4k", 300, 2400), ("1.8k", 400, 1800)]
        case .cw, .cwl:  return [("500", -250, 250), ("250", -125, 125), ("100", -50, 50)]
        case .am, .sam:  return [("6k", -3000, 3000), ("5k", -2500, 2500), ("3k", -1500, 1500)]
        case .fm, .nfm:  return [("12k", -6000, 6000), ("8k", -4000, 4000), ("5k", -2500, 2500)]
        default:          return [("2.7k", 200, 2700), ("2.4k", 300, 2400)]
        }
    }

    private func stepLabel(_ hz: Int) -> String {
        if hz >= 1_000 { return "\(hz / 1_000)k" }
        return "\(hz)Hz"
    }

    private func offsetLabel(_ hz: Int) -> String {
        hz == 0 ? "0 Hz" : (hz > 0 ? "+\(hz) Hz" : "\(hz) Hz")
    }

    private func commitFrequency() {
        isEditingFreq = false
        guard let mhz = Double(freqString) else { return }
        let hz = Int((mhz * 1_000_000).rounded())
        radio.tune(sliceIndex: slice.id, hz: hz)
    }

    private func stepFrequency(by delta: Int) {
        radio.tune(sliceIndex: slice.id, hz: slice.frequencyHz + delta)
    }
}
