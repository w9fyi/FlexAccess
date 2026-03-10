import SwiftUI

/// VFO, mode, filters, DSP and TX controls for one slice.
struct SliceView: View {
    let radio: Radio
    @Bindable var slice: Slice

    @State private var freqString: String = ""
    @State private var isEditingFreq = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Frequency
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
                    // Band up/down
                    Stepper("", onIncrement: { stepFrequency(by: 1000) },
                               onDecrement: { stepFrequency(by: -1000) })
                        .labelsHidden()
                        .accessibilityLabel("Tune frequency by 1 kHz")
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
                // Preset filter buttons
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

            // DSP toggles
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

    private func commitFrequency() {
        isEditingFreq = false
        guard let mhz = Double(freqString) else { return }
        let hz = Int((mhz * 1_000_000).rounded())
        radio.tune(sliceIndex: slice.id, hz: hz)
    }

    private func stepFrequency(by delta: Int) {
        let current = slice.frequencyHz
        radio.tune(sliceIndex: slice.id, hz: current + delta)
    }
}
