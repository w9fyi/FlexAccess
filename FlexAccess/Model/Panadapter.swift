//
//  Panadapter.swift
//  FlexAccess
//
//  @Observable model for one FlexRadio panadapter/waterfall.
//

import Foundation
import Observation

@MainActor
@Observable
final class Panadapter: Identifiable {
    let id: String   // hex pan ID from radio, e.g. "0x40000000"

    var centerMHz: Double   = 14.225
    var bandwidthMHz: Double = 0.200
    var antenna: String     = "ANT1"

    // FFT display data — updated by FFTReceiver (256 buckets typical)
    var fftData: [Float]    = []

    // Waterfall gradient control
    var autoBlackLevel: Bool = true
    var blackLevel: Int      = 0
    var colorGain: Int       = 50

    init(id: String) {
        self.id = id
    }

    // MARK: - Signal analysis

    /// Frequency (MHz) at the center of bin `i`.
    func freqMHz(forBin i: Int) -> Double {
        guard !fftData.isEmpty else { return centerMHz }
        let fraction = (Double(i) + 0.5) / Double(fftData.count) - 0.5
        return centerMHz + fraction * bandwidthMHz
    }

    /// Top `count` peaks sorted by level descending.
    func peakBins(count n: Int = 5) -> [(freqMHz: Double, levelDBm: Float)] {
        guard !fftData.isEmpty else { return [] }
        return fftData.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(n)
            .map { (offset, level) in (freqMHz: freqMHz(forBin: offset), levelDBm: level) }
    }

    /// Nearest-bin dBm at `freq` MHz, or nil if outside the current range.
    func levelAtFrequency(_ freq: Double) -> Float? {
        guard !fftData.isEmpty, bandwidthMHz > 0 else { return nil }
        let half = bandwidthMHz / 2.0
        guard freq >= centerMHz - half, freq <= centerMHz + half else { return nil }
        let binF = (freq - (centerMHz - half)) / bandwidthMHz * Double(fftData.count) - 0.5
        let i = Swift.max(0, Swift.min(fftData.count - 1, Int(binF.rounded())))
        return fftData[i]
    }

    // MARK: - Display range

    var displayMinDBm: Float { -140.0 }
    var displayMaxDBm: Float {  -10.0 }

    // MARK: - Properties

    func applyProperties(_ props: [String: String]) {
        if let v = props["center"],    let mhz = Double(v) { centerMHz    = mhz }
        if let v = props["bandwidth"], let mhz = Double(v) { bandwidthMHz = mhz }
        if let v = props["rxant"],     !v.isEmpty           { antenna      = v   }
        if let v = props["auto_black"]                      { autoBlackLevel = v == "1" }
        if let v = props["black_level"], let l = Int(v)     { blackLevel   = l }
        if let v = props["color_gain"],  let g = Int(v)     { colorGain    = g }
    }
}
