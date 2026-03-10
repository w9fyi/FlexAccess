//
//  BandscopeView.swift
//  FlexAccess
//
//  Canvas-based panadapter spectrum display.
//  VoiceOver-first: the Canvas is invisible to a11y by default; we add an
//  accessibilityLabel with center/bandwidth, accessibilityChildren for the
//  top signal peaks, and adjustable actions to shift center frequency.
//

import SwiftUI

struct BandscopeView: View {
    @Bindable var pan: Panadapter
    let radio: Radio
    let sliceFreqMHz: Double

    // Bandwidth step ladder (MHz)
    private static let bwSteps: [Double] = [
        0.025, 0.050, 0.100, 0.200, 0.400, 0.800, 1.600, 3.200
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // MARK: Controls row
            HStack {
                Text("Bandscope").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()

                // Bandwidth control
                HStack(spacing: 4) {
                    Text("BW:").font(.caption).foregroundStyle(.secondary)
                    Button { narrowBW() } label: { Image(systemName: "minus") }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel("Narrow bandwidth")
                    Text(bwLabel)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minWidth: 56, alignment: .center)
                        .accessibilityHidden(true)
                    Button { widenBW() } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel("Widen bandwidth")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bandwidth \(bwLabel)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAdjustableAction { dir in
                    dir == .increment ? widenBW() : narrowBW()
                }

                // Center frequency control
                HStack(spacing: 4) {
                    Button { shiftCenter(-0.005) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel("Shift center down 5 kHz")
                    Text(String(format: "%.3f", pan.centerMHz))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minWidth: 56, alignment: .center)
                        .accessibilityHidden(true)
                    Button { shiftCenter(+0.005) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.bordered).controlSize(.mini)
                        .accessibilityLabel("Shift center up 5 kHz")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Center \(String(format: "%.3f MHz", pan.centerMHz))")
                .accessibilityAddTraits(.isButton)
                .accessibilityAdjustableAction { dir in
                    shiftCenter(dir == .increment ? +0.005 : -0.005)
                }
            }

            // MARK: Spectrum canvas
            ZStack(alignment: .bottom) {
                Canvas { ctx, size in
                    // Background
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(.black))
                    // Grid lines every 10 dB
                    drawGrid(ctx: ctx, size: size)
                    // Spectrum line
                    drawSpectrum(ctx: ctx, size: size)
                    // Slice frequency marker
                    drawSliceMarker(ctx: ctx, size: size)
                }
                .frame(height: 130)
                // VoiceOver: label + children for top peaks + adjustable tuning
                .accessibilityElement(children: .contain)
                .accessibilityLabel(canvasLabel)
                .accessibilityChildren {
                    ForEach(Array(pan.peakBins(count: 5).enumerated()), id: \.offset) { idx, peak in
                        Text(peakLabel(peak, rank: idx + 1))
                            .accessibilityLabel(peakLabel(peak, rank: idx + 1))
                    }
                    // Always include the slice frequency level if available
                    if let sliceLevel = pan.levelAtFrequency(sliceFreqMHz) {
                        Text(String(format: "Slice at %.3f MHz: %.0f dBm",
                                    sliceFreqMHz, sliceLevel))
                    }
                }
                .accessibilityAdjustableAction { dir in
                    shiftCenter(dir == .increment ? +0.005 : -0.005)
                }

                // Frequency axis labels (overlay, VoiceOver hidden)
                HStack {
                    Text(String(format: "%.3f", pan.centerMHz - pan.bandwidthMHz / 2))
                    Spacer()
                    Text(String(format: "%.3f", pan.centerMHz))
                    Spacer()
                    Text(String(format: "%.3f", pan.centerMHz + pan.bandwidthMHz / 2))
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.bottom, 3)
                .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Drawing

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let minDB = pan.displayMinDBm
        let maxDB = pan.displayMaxDBm
        let range = maxDB - minDB
        stride(from: minDB, through: maxDB, by: 10).forEach { db in
            let y = size.height * CGFloat(1 - (db - minDB) / range)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
        }
    }

    private func drawSpectrum(ctx: GraphicsContext, size: CGSize) {
        let data = pan.fftData
        guard data.count > 1 else { return }
        let minDB = pan.displayMinDBm
        let maxDB = pan.displayMaxDBm
        let dbRange = maxDB - minDB

        var path = Path()
        // Start at bottom-left corner for fill
        path.move(to: CGPoint(x: 0, y: size.height))

        for (i, db) in data.enumerated() {
            let x = CGFloat(i) / CGFloat(data.count - 1) * size.width
            let norm = CGFloat((Swift.max(minDB, Swift.min(maxDB, db)) - minDB) / dbRange)
            let y = size.height * (1 - norm)
            if i == 0 { path.addLine(to: CGPoint(x: x, y: y)) }
            else       { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        // Close at bottom-right for fill
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()

        ctx.fill(path, with: .color(Color.green.opacity(0.25)))

        // Stroke just the top line
        var linePath = Path()
        for (i, db) in data.enumerated() {
            let x = CGFloat(i) / CGFloat(data.count - 1) * size.width
            let norm = CGFloat((Swift.max(minDB, Swift.min(maxDB, db)) - minDB) / dbRange)
            let y = size.height * (1 - norm)
            if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
            else       { linePath.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.stroke(linePath, with: .color(.green), lineWidth: 1.5)
    }

    private func drawSliceMarker(ctx: GraphicsContext, size: CGSize) {
        guard pan.bandwidthMHz > 0 else { return }
        let half = pan.bandwidthMHz / 2
        let loMHz = pan.centerMHz - half
        let hiMHz = pan.centerMHz + half
        guard sliceFreqMHz >= loMHz, sliceFreqMHz <= hiMHz else { return }
        let x = CGFloat((sliceFreqMHz - loMHz) / pan.bandwidthMHz) * size.width
        var p = Path()
        p.move(to: CGPoint(x: x, y: 0))
        p.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(p, with: .color(.yellow.opacity(0.9)), lineWidth: 1.5)
    }

    // MARK: - Helpers

    private var bwLabel: String {
        let khz = pan.bandwidthMHz * 1_000
        return khz < 1_000
            ? String(format: "%.0f kHz", khz)
            : String(format: "%.1f MHz", pan.bandwidthMHz)
    }

    private var canvasLabel: String {
        let khz = Int(pan.bandwidthMHz * 1_000)
        let peaks = pan.peakBins(count: 3)
        let peakDesc = peaks.isEmpty
            ? "no data"
            : peaks.map { String(format: "%.3f MHz %.0f dBm", $0.freqMHz, $0.levelDBm) }
                   .joined(separator: ", ")
        return "Bandscope: \(String(format: "%.3f", pan.centerMHz)) MHz center, \(khz) kHz wide. Top signals: \(peakDesc)."
    }

    private func peakLabel(_ peak: (freqMHz: Double, levelDBm: Float), rank: Int) -> String {
        String(format: "Signal %d: %.3f MHz, %.0f dBm", rank, peak.freqMHz, peak.levelDBm)
    }

    private func narrowBW() {
        let steps = Self.bwSteps
        let idx = steps.firstIndex { $0 >= pan.bandwidthMHz } ?? steps.endIndex - 1
        let newBW = steps[Swift.max(0, idx - 1)]
        pan.bandwidthMHz = newBW
        radio.send(FlexProtocol.panadapterSetBandwidth(id: pan.id, bwMHz: newBW))
    }

    private func widenBW() {
        let steps = Self.bwSteps
        let idx = steps.lastIndex { $0 <= pan.bandwidthMHz } ?? 0
        let newBW = steps[Swift.min(steps.endIndex - 1, idx + 1)]
        pan.bandwidthMHz = newBW
        radio.send(FlexProtocol.panadapterSetBandwidth(id: pan.id, bwMHz: newBW))
    }

    private func shiftCenter(_ deltaMHz: Double) {
        pan.centerMHz += deltaMHz
        radio.send(FlexProtocol.panadapterSetCenter(id: pan.id, freqMHz: pan.centerMHz))
    }
}
