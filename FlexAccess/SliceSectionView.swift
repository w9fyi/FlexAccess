//
//  SliceSectionView.swift
//  FlexAccess
//
//  Controls for the active receive slice: frequency, mode, filter, DSP toggles, PTT.
//

import SwiftUI

struct SliceSectionView: View {
    @ObservedObject var radio: FlexRadioState

    @State private var freqMHzString: String = ""
    @State private var filterLoString: String = ""
    @State private var filterHiString: String = ""
    private let filterLoDebounce = Debouncer(delay: 0.25)
    private let filterHiDebounce = Debouncer(delay: 0.25)

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
                pttSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .onAppear { syncFromRadio() }
        .onChange(of: radio.sliceFrequencyHz) { _, _ in syncFreq() }
        .onChange(of: radio.sliceFilterLo)    { _, _ in filterLoString = String(radio.sliceFilterLo) }
        .onChange(of: radio.sliceFilterHi)    { _, _ in filterHiString = String(radio.sliceFilterHi) }
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
                    Button(mode.label) {
                        radio.setSliceMode(mode)
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("RX Filter")
                .font(.headline)

            HStack(spacing: 12) {
                Text("Low Cut:")
                TextField("Hz", text: $filterLoString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .accessibilityLabel("Filter low cut in hertz")
                    .onSubmit { applyFilter() }

                Text("High Cut:")
                TextField("Hz", text: $filterHiString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .accessibilityLabel("Filter high cut in hertz")
                    .onSubmit { applyFilter() }

                Button("Set Filter") { applyFilter() }
            }

            Text("Typical SSB: Low=200, High=2700  |  CW: Low=300, High=700")
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
        filterLoString = String(radio.sliceFilterLo)
        filterHiString = String(radio.sliceFilterHi)
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

    private func applyFilter() {
        let lo = Int(filterLoString) ?? radio.sliceFilterLo
        let hi = Int(filterHiString) ?? radio.sliceFilterHi
        radio.setFilter(lo: lo, hi: hi)
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
