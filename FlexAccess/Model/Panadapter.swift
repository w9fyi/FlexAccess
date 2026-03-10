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

    func applyProperties(_ props: [String: String]) {
        if let v = props["center"],    let mhz = Double(v) { centerMHz    = mhz }
        if let v = props["bandwidth"], let mhz = Double(v) { bandwidthMHz = mhz }
        if let v = props["rxant"],     !v.isEmpty           { antenna      = v   }
        if let v = props["auto_black"]                      { autoBlackLevel = v == "1" }
        if let v = props["black_level"], let l = Int(v)     { blackLevel   = l }
        if let v = props["color_gain"],  let g = Int(v)     { colorGain    = g }
    }
}
