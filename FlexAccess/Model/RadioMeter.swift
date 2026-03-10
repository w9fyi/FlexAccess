//
//  RadioMeter.swift
//  FlexAccess
//
//  @Observable model for one radio meter channel.
//  Definitions arrive via TCP status lines; real-time values via VITA-49 UDP.
//

import Foundation
import Observation

@MainActor
@Observable
final class RadioMeter: Identifiable {

    let id: Int           // meter number in SmartSDR API (1, 2, 3 …)
    var name: String      // e.g. "SIGNAL", "RFPWR", "SWR"
    var source: String    // e.g. "slc-0", "tx", "amp"
    var unit: String      // e.g. "dBm", "W", "SWR", "%", "C", "V", "A"
    var low: Double       // minimum expected value (from radio)
    var high: Double      // maximum expected value (from radio)
    var fps: Int          // target update rate in frames per second
    var value: Double = 0 // current live value (updated from VITA-49)

    init(id: Int, name: String, source: String, unit: String,
         low: Double, high: Double, fps: Int) {
        self.id = id;  self.name = name;  self.source = source
        self.unit = unit;  self.low = low;  self.high = high;  self.fps = fps
    }

    init(definition: FlexProtocol.MeterDefinition) {
        id = definition.id;  name = definition.name;  source = definition.source
        unit = definition.unit;  low = definition.low;  high = definition.high
        fps = definition.fps
    }

    // MARK: Formatted display

    var formattedValue: String {
        switch unit.lowercased() {
        case "dbm":  return String(format: "%.1f dBm", value)
        case "w":    return String(format: "%.1f W",   value)
        case "v":    return String(format: "%.2f V",   value)
        case "c":    return String(format: "%.0f °C",  value)
        case "a":    return String(format: "%.2f A",   value)
        case "swr":  return String(format: "%.1f:1",   value)
        case "%":    return String(format: "%.0f%%",   value)
        case "db":   return String(format: "%.1f dB",  value)
        default:     return String(format: "%.1f",     value)
        }
    }

    var displayName: String {
        switch name.uppercased() {
        case "SIGNAL":          return "Signal"
        case "RFPWR":           return "TX Power"
        case "REFPWR":          return "Reflected"
        case "SWR":             return "SWR"
        case "ALC":             return "ALC"
        case "MICPWR":          return "Mic Level"
        case "COMPRSN":         return "Compression"
        case "TEMP":            return "PA Temp"
        case "+13.8V", "PAVCC": return "PA Voltage"
        case "PA_CUR":          return "PA Current"
        default:                return name
        }
    }

    var accessibilityLabel: String { "\(displayName): \(formattedValue)" }

    // MARK: S-meter label (for SIGNAL / dBm meters)

    /// Converts dBm to amateur radio S-unit label.
    /// S9 = –73 dBm; each S-unit = 6 dB below that.
    var sMeterLabel: String {
        let s9dBm = -73.0
        if value >= s9dBm {
            let over = Int((value - s9dBm).rounded())
            return over == 0 ? "S9" : "S9+\(over)dB"
        } else {
            let sLevel = max(1, Int(((value - s9dBm) / 6.0).rounded()) + 9)
            return "S\(sLevel)"
        }
    }

    // MARK: Convenience

    var isSignalMeter: Bool { name.uppercased() == "SIGNAL" }
    var isTXMeter:     Bool { source.lowercased() == "tx" }
    var isRadioMeter:  Bool { source.lowercased() == "amp" || source.lowercased() == "radio" }
}
