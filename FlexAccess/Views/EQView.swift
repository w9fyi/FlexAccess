//
//  EQView.swift
//  FlexAccess
//
//  RX and TX parametric EQ — 8-band sliders, enable toggle, flat reset.
//  EQ commands are global in SmartSDR (eq rxsc / eq txsc) but the model
//  stores them per-slice for consistency with the rest of the API.
//

import SwiftUI

struct EQView: View {
    let radio: Radio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if radio.connectionStatus != .connected {
                    Text("Connect to a radio to adjust EQ.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else if let slice = radio.activeSlice {
                    EQSectionView(radio: radio, slice: slice, type: .rx, title: "RX Equalizer")
                    EQSectionView(radio: radio, slice: slice, type: .tx, title: "TX Equalizer")
                } else {
                    Text("No active slice.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding()
        }
    }
}

// MARK: - Section (RX or TX)

private struct EQSectionView: View {
    let radio: Radio
    @Bindable var slice: Slice
    let type: FlexEQType
    let title: String

    private var isEnabled: Bool {
        type == .rx ? slice.rxEQEnabled : slice.txEQEnabled
    }

    private func bandValue(_ hz: Int) -> Int {
        (type == .rx ? slice.rxEQBands[hz] : slice.txEQBands[hz]) ?? 0
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {

                // Enable toggle + Flat button
                HStack {
                    Toggle("Enable", isOn: Binding(
                        get: { isEnabled },
                        set: { radio.setEQEnabled(type: type, sliceIndex: slice.id, enabled: $0) }
                    ))
                    .accessibilityLabel("\(title) enable")

                    Spacer()

                    Button("Flat") {
                        radio.setEQFlat(type: type, sliceIndex: slice.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isEnabled)
                    .accessibilityLabel("Reset \(title) to flat")
                }

                // Band sliders
                VStack(spacing: 8) {
                    ForEach(FlexProtocol.eqBandHz, id: \.self) { hz in
                        EQBandRow(
                            label: bandLabel(hz),
                            value: bandValue(hz),
                            enabled: isEnabled
                        ) { newValue in
                            radio.setEQBand(type: type, sliceIndex: slice.id,
                                            hz: hz, value: newValue)
                        }
                    }
                }
                .disabled(!isEnabled)
            }
            .padding(4)
        } label: {
            Text(title).font(.headline)
        }
    }

    private func bandLabel(_ hz: Int) -> String {
        hz >= 1000 ? "\(hz / 1000) kHz" : "\(hz) Hz"
    }
}

// MARK: - Band row

private struct EQBandRow: View {
    let label: String
    let value: Int
    let enabled: Bool
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 52, alignment: .trailing)
                .foregroundStyle(enabled ? .primary : .secondary)

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: -10...10, step: 1
            )
            .accessibilityLabel("\(label) EQ")
            .accessibilityValue("\(value) dB")

            Text(value == 0 ? "0 dB" : (value > 0 ? "+\(value) dB" : "\(value) dB"))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(value == 0 ? .secondary : .primary)
        }
    }
}
