//
//  EqualizerSectionView.swift
//  FlexAccess
//
//  RX and TX equalizer — 8 bands each, −10 to +10 dB, sent to radio in real time.
//  Commands use capital-Hz format (63Hz=) but status arrives lowercase (63hz=).
//

import SwiftUI

struct EqualizerSectionView: View {
    @ObservedObject var radio: FlexRadioState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Equalizer")
                    .font(.title2)

                eqSection(type: .rx, title: "RX Equalizer",
                          enabled: $radio.rxEQEnabled,
                          bands: $radio.rxEQBands)

                Divider()

                eqSection(type: .tx, title: "TX Equalizer",
                          enabled: $radio.txEQEnabled,
                          bands: $radio.txEQBands)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    // MARK: EQ section (shared for RX and TX)

    private func eqSection(
        type: FlexEQType,
        title: String,
        enabled: Binding<Bool>,
        bands: Binding<[Int: Int]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.headline)

                Toggle("Enable", isOn: Binding(
                    get: { enabled.wrappedValue },
                    set: { radio.setEQEnabled(type: type, enabled: $0) }
                ))
                .accessibilityLabel("\(title) enabled")

                Button("Flat") { radio.eqFlat(type: type) }
                    .accessibilityHint("Resets all \(title) bands to 0 dB")
            }

            ForEach(FlexProtocol.eqBandHz, id: \.self) { hz in
                bandRow(type: type, hz: hz, bands: bands)
            }
        }
    }

    // MARK: Band row

    private func bandRow(type: FlexEQType, hz: Int, bands: Binding<[Int: Int]>) -> some View {
        let label = hz >= 1000 ? "\(hz / 1000) kHz" : "\(hz) Hz"
        let value = bands.wrappedValue[hz] ?? 0

        return HStack(spacing: 12) {
            Text(label)
                .frame(width: 60, alignment: .trailing)
                .font(.system(.body, design: .monospaced))
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { Double(bands.wrappedValue[hz] ?? 0) },
                    set: { newVal in
                        let clamped = Swift.max(-10, Swift.min(10, Int(newVal.rounded())))
                        radio.setEQBand(type: type, hz: hz, value: clamped)
                    }
                ),
                in: -10...10,
                step: 1
            )
            .frame(minWidth: 200)
            .accessibilityLabel("\(label) band")
            .accessibilityValue("\(value) dB")

            Text("\(value > 0 ? "+" : "")\(value) dB")
                .frame(width: 56, alignment: .trailing)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(value == 0 ? .secondary : (value > 0 ? .primary : .primary))
                .accessibilityHidden(true)
        }
    }
}
