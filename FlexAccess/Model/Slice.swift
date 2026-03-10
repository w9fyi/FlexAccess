//
//  Slice.swift
//  FlexAccess
//
//  @Observable model for one FlexRadio receiver slice.
//  All mutations happen on the MainActor.
//

import Foundation
import Observation

@MainActor
@Observable
final class Slice: Identifiable {
    let id: Int   // slice index (0-7)

    // VFO
    var frequencyHz: Int    = 14_225_000
    var mode: FlexMode      = .usb
    var filterLo: Int       = 200
    var filterHi: Int       = 2700

    // DSP
    var nrEnabled: Bool     = false
    var nbEnabled: Bool     = false
    var anfEnabled: Bool    = false
    var agcMode: FlexAGCMode = .med
    var agcThreshold: Int   = 65    // 0-100
    var rfGain: Int         = 0     // dB
    var audioLevel: Int     = 50    // 0-100

    // Antenna
    var rxAnt: String       = "ANT1"
    var antList: [String]   = ["ANT1", "ANT2"]

    // DAX
    var daxChannel: Int     = 0     // 0 = unassigned, 1-8 = active channel
    var daxTXEnabled: Bool  = false

    // TX
    var isTX: Bool          = false

    // EQ
    var rxEQEnabled: Bool   = false
    var txEQEnabled: Bool   = false
    var rxEQBands: [Int: Int] = Dictionary(uniqueKeysWithValues: FlexProtocol.eqBandHz.map { ($0, 0) })
    var txEQBands: [Int: Int] = Dictionary(uniqueKeysWithValues: FlexProtocol.eqBandHz.map { ($0, 0) })

    init(index: Int) {
        self.id = index
    }

    var formattedFrequency: String {
        let mhz = Double(frequencyHz) / 1_000_000.0
        return String(format: "%.6f MHz", mhz)
    }

    var accessibilityLabel: String {
        "Slice \(id): \(formattedFrequency), \(mode.label)\(isTX ? ", transmitting" : "")"
    }

    /// Apply a batch of key=value properties from a status line.
    func applyProperties(_ props: [String: String]) {
        if let f = props["rf_frequency"], let mhz = Double(f) {
            frequencyHz = Int((mhz * 1_000_000).rounded())
        }
        if let m = props["mode"], let mode = FlexMode(rawValue: m.uppercased()) { self.mode = mode }
        if let v = props["filter_lo"],  let lo = Int(v) { filterLo = lo }
        if let v = props["filter_hi"],  let hi = Int(v) { filterHi = hi }
        if let v = props["nr"]          { nrEnabled  = v == "1" }
        if let v = props["nb"]          { nbEnabled  = v == "1" }
        if let v = props["anf"]         { anfEnabled = v == "1" }
        if let v = props["agc_mode"],   let agc = FlexAGCMode(rawValue: v) { agcMode = agc }
        if let v = props["agc_threshold"], let t = Int(v) { agcThreshold = t }
        if let v = props["rfgain"],     let g = Int(v) { rfGain = g }
        if let v = props["audio_level"],let l = Int(v) { audioLevel = l }
        if let v = props["rxant"],      !v.isEmpty      { rxAnt = v }
        if let v = props["ant_list"],   !v.isEmpty {
            antList = v.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        }
        if let v = props["dax"],        let ch = Int(v) { daxChannel = ch }
        if let v = props["dax_tx"]      { daxTXEnabled = v == "1" }
        if let v = props["tx"]          { isTX = v == "1" }
    }
}
