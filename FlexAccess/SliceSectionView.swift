//
//  SliceSectionView.swift
//  FlexAccess
//
//  Controls for the active receive slice: frequency, mode, filter, DSP, antenna, PTT.
//

import SwiftUI

struct SliceSectionView: View {
    @ObservedObject var radio: FlexRadioState

    @State private var freqMHzString: String = ""
    @State private var filterLo: Double = 200
    @State private var filterHi: Double = 2700

    private let filterLoDebounce = Debouncer(delay: 0.15)
    private let filterHiDebounce = Debouncer(delay: 0.15)
    private let rfGainDebounce   = Debouncer(delay: 0.15)
    private let audioLvlDebounce = Debouncer(delay: 0.15)
    private let agcThreshDebounce = Debouncer(delay: 0.15)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Slice \(radio.sliceIndex)")
                    .font(.title2)

                frequencySection
                Divider()
                modeSection
                Divider()
                filterSection
                Divider()
                dspSection
                Divider()
                antennaSection
                Divider()
                pttSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear { syncFromRadio() }
        .onChange(of: radio.sliceFrequencyHz) { _, _ in syncFreq() }
        .onChange(of: radio.sliceFilterLo)    { _, v in filterLo = Double(v) }
        .onChange(of: radio.sliceFilterHi)    { _, v in filterHi = Double(v) }
    }

    // MARK: Frequency

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frequency")
                .font(.headline)
            HStack(spacing: 12) {
                TextField("MHz", text: $freqMHzString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .accessibilityLabel("Frequency in megahertz")
                    .onSubmit { applyFrequency() }

                Button("Set") { applyFrequency() }

                if let hz = radio.sliceFrequencyHz {
                    Text(String(format: "%.6f MHz", Double(hz) / 1_000_000.0))
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel(String(format: "Current frequency %.6f megahertz", Double(hz) / 1_000_000.0))
                }
            }
        }
    }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach([FlexMode.lsb, .usb, .cw, .am, .fm]) { mode in
                    Button(mode.label) { radio.setSliceMode(mode) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(mode.label)
                }
            }

            Picker("Mode", selection: Binding(
                get: { radio.sliceMode },
                set: { radio.setSliceMode($0) }
            )) {
                ForEach(FlexMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("Operating mode selector")
        }
    }

    // MARK: Filter

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RX Filter")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Low Cut:")
                        .frame(width: 72, alignment: .trailing)
                    Slider(value: $filterLo, in: -6000...6000, step: 25)
                        .frame(minWidth: 200)
                        .accessibilityLabel("Filter low cut")
                        .accessibilityValue("\(Int(filterLo)) Hz")
                        .onChange(of: filterLo) { _, v in
                            filterLoDebounce.call {
                                radio.setFilter(lo: Int(v.rounded()), hi: radio.sliceFilterHi)
                            }
                        }
                    Text("\(Int(filterLo)) Hz")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text("High Cut:")
                        .frame(width: 72, alignment: .trailing)
                    Slider(value: $filterHi, in: -6000...6000, step: 25)
                        .frame(minWidth: 200)
                        .accessibilityLabel("Filter high cut")
                        .accessibilityValue("\(Int(filterHi)) Hz")
                        .onChange(of: filterHi) { _, v in
                            filterHiDebounce.call {
                                radio.setFilter(lo: radio.sliceFilterLo, hi: Int(v.rounded()))
                            }
                        }
                    Text("\(Int(filterHi)) Hz")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 72, alignment: .trailing)
                }
            }

            Text("Typical USB: Low 100 Hz, High 2800 Hz  •  CW: Low −500, High 500")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: DSP

    private var dspSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DSP")
                .font(.headline)

            HStack(spacing: 20) {
                Toggle("NR", isOn: Binding(get: { radio.sliceNREnabled },  set: { radio.setNR($0) }))
                    .accessibilityLabel("Radio noise reduction")
                Toggle("NB", isOn: Binding(get: { radio.sliceNBEnabled },  set: { radio.setNB($0) }))
                    .accessibilityLabel("Noise blanker")
                Toggle("ANF", isOn: Binding(get: { radio.sliceANFEnabled }, set: { radio.setANF($0) }))
                    .accessibilityLabel("Automatic notch filter")
            }

            // AGC mode
            HStack(spacing: 12) {
                Text("AGC:")
                Picker("AGC", selection: Binding(
                    get: { radio.sliceAGCMode },
                    set: { radio.setAGC($0) }
                )) {
                    ForEach(FlexAGCMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .frame(width: 200)
                .accessibilityLabel("AGC mode")
            }

            // AGC threshold (hidden when AGC is off)
            if radio.sliceAGCMode != .off {
                HStack(spacing: 12) {
                    Text("AGC Threshold:")
                        .frame(width: 110, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(radio.sliceAGCThreshold) },
                            set: { v in
                                let t = Int(v.rounded())
                                agcThreshDebounce.call { radio.setAGCThreshold(t) }
                            }
                        ),
                        in: 0...100, step: 1
                    )
                    .frame(minWidth: 180)
                    .accessibilityLabel("AGC threshold")
                    .accessibilityValue("\(radio.sliceAGCThreshold)")
                    Text("\(radio.sliceAGCThreshold)")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }
            }

            // RF Gain
            HStack(spacing: 12) {
                Text("RF Gain:")
                    .frame(width: 110, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { Double(radio.sliceRFGain) },
                        set: { v in
                            let g = Int(v.rounded())
                            rfGainDebounce.call { radio.setRFGain(g) }
                        }
                    ),
                    in: -100...20, step: 1
                )
                .frame(minWidth: 180)
                .accessibilityLabel("RF gain")
                .accessibilityValue("\(radio.sliceRFGain) dB")
                Text("\(radio.sliceRFGain) dB")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 56, alignment: .trailing)
            }

            // Slice audio level (radio's internal DAX audio gain)
            HStack(spacing: 12) {
                Text("Audio Level:")
                    .frame(width: 110, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { Double(radio.sliceAudioLevel) },
                        set: { v in
                            let l = Int(v.rounded())
                            audioLvlDebounce.call { radio.setAudioLevel(l) }
                        }
                    ),
                    in: 0...100, step: 1
                )
                .frame(minWidth: 180)
                .accessibilityLabel("Slice audio level")
                .accessibilityValue("\(radio.sliceAudioLevel)")
                Text("\(radio.sliceAudioLevel)")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 36, alignment: .trailing)
            }
            Text("Audio Level controls the radio's internal slice gain before DAX output.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Antenna

    private var antennaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Antenna")
                .font(.headline)

            HStack(spacing: 12) {
                Text("RX Antenna:")
                Picker("RX Antenna", selection: Binding(
                    get: { radio.sliceRxAnt },
                    set: { radio.setRxAnt($0) }
                )) {
                    ForEach(radio.sliceAntList, id: \.self) { ant in
                        Text(ant).tag(ant)
                    }
                }
                .frame(minWidth: 180)
                .accessibilityLabel("RX antenna selection")
            }
        }
    }

    // MARK: PTT

    private var pttSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PTT")
                .font(.headline)

            HStack(spacing: 12) {
                Button("PTT Down (TX)") { radio.setPTT(down: true) }
                    .accessibilityLabel("PTT down, transmit")
                Button("PTT Up (RX)")   { radio.setPTT(down: false) }
                    .accessibilityLabel("PTT up, receive")
                Text(radio.isTX ? "TX" : "RX")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(radio.isTX ? .red : .green)
                    .accessibilityLabel(radio.isTX ? "Transmitting" : "Receiving")
            }

            Text("Keyboard: hold Option-Space for push-to-talk.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private func syncFromRadio() {
        syncFreq()
        filterLo = Double(radio.sliceFilterLo)
        filterHi = Double(radio.sliceFilterHi)
    }

    private func syncFreq() {
        if let hz = radio.sliceFrequencyHz {
            freqMHzString = String(format: "%.6f", Double(hz) / 1_000_000.0)
        }
    }

    private func applyFrequency() {
        let normalized = freqMHzString.replacingOccurrences(of: ",", with: ".")
        guard let mhz = Double(normalized) else { return }
        radio.setSliceFrequency(Int((mhz * 1_000_000).rounded()))
    }
}

// MARK: - Debouncer (simple timer wrapper)

final class Debouncer {
    private var timer: Timer?
    private let delay: TimeInterval
    init(delay: TimeInterval) { self.delay = delay }
    func call(_ action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in action() }
    }
}
