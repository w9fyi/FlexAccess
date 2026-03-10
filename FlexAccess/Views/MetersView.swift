//
//  MetersView.swift
//  FlexAccess
//
//  Accessible real-time meter display.
//  Meters are grouped by source: slice (RX), TX, and radio/amplifier.
//

import SwiftUI

struct MetersView: View {
    let radio: Radio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if radio.connectionStatus != .connected {
                    Text("Connect to a radio to see meters.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else if radio.meters.isEmpty {
                    Text("Waiting for meter data…")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    let rxMeters    = radio.meters.filter { $0.source.lowercased().hasPrefix("slc") }
                    let txMeters    = radio.meters.filter { $0.isTXMeter }
                    let radioMeters = radio.meters.filter { $0.isRadioMeter }

                    if !rxMeters.isEmpty {
                        MeterGroupView(title: "Receive", meters: rxMeters)
                    }
                    if !txMeters.isEmpty {
                        MeterGroupView(title: "Transmit", meters: txMeters)
                    }
                    if !radioMeters.isEmpty {
                        MeterGroupView(title: "Radio / PA", meters: radioMeters)
                    }

                    // Any meters that don't fall in the above groups
                    let known = rxMeters + txMeters + radioMeters
                    let other = radio.meters.filter { m in !known.contains(where: { $0.id == m.id }) }
                    if !other.isEmpty {
                        MeterGroupView(title: "Other", meters: other)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Group

private struct MeterGroupView: View {
    let title: String
    let meters: [RadioMeter]

    var body: some View {
        GroupBox(title) {
            VStack(spacing: 8) {
                ForEach(meters) { meter in
                    MeterRowView(meter: meter)
                }
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Row

private struct MeterRowView: View {
    @State var meter: RadioMeter   // @State to observe @Observable

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(meter.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                // S-meter label for signal meters
                if meter.isSignalMeter {
                    Text(meter.sMeterLabel)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(sMeterColor(meter.sMeterLabel))
                }
                Text(meter.formattedValue)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minWidth: 80, alignment: .trailing)
            }
            MeterBarView(value: meter.value, low: meter.low, high: meter.high)
                .frame(height: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(meter.accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func sMeterColor(_ label: String) -> Color {
        if label.contains("+") { return .red }
        if label >= "S7"       { return .orange }
        return .green
    }
}

// MARK: - Bar

private struct MeterBarView: View {
    let value: Double
    let low: Double
    let high: Double

    private var fraction: Double {
        guard high > low else { return 0 }
        return Swift.max(0, Swift.min(1, (value - low) / (high - low)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * fraction)
            }
        }
    }

    private var barColor: Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.7 { return .orange }
        return .accentColor
    }
}
