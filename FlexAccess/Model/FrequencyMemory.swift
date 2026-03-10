//
//  FrequencyMemory.swift
//  FlexAccess
//
//  A stored frequency/mode preset.  Persisted as JSON in UserDefaults.
//

import Foundation

struct FrequencyMemory: Identifiable, Codable, Equatable {

    let id:          Int
    var label:       String
    var frequencyHz: Int
    var mode:        FlexMode
    var notes:       String

    init(id: Int, label: String, frequencyHz: Int, mode: FlexMode, notes: String = "") {
        self.id          = id
        self.label       = label
        self.frequencyHz = frequencyHz
        self.mode        = mode
        self.notes       = notes
    }

    // MARK: - Derived

    var formattedFrequency: String {
        String(format: "%.3f MHz", Double(frequencyHz) / 1_000_000)
    }

    /// Amateur-band label based on frequency, or "?" if not a recognised band.
    var band: String {
        let mhz = Double(frequencyHz) / 1_000_000
        switch mhz {
        case 1.8..<2.0:    return "160m"
        case 3.5..<4.0:    return "80m"
        case 5.3305..<5.4065: return "60m"
        case 7.0..<7.3:    return "40m"
        case 10.1..<10.15: return "30m"
        case 14.0..<14.35: return "20m"
        case 18.068..<18.168: return "17m"
        case 21.0..<21.45: return "15m"
        case 24.89..<24.99: return "12m"
        case 28.0..<29.7:  return "10m"
        case 50.0..<54.0:  return "6m"
        case 144.0..<148.0: return "2m"
        case 222.0..<225.0: return "1.25m"
        case 420.0..<450.0: return "70cm"
        default:           return "?"
        }
    }

    // MARK: - Defaults

    /// Pre-loaded common operating frequencies for AI5OS / HF + VHF bands.
    static let defaults: [FrequencyMemory] = [
        // 80m
        FrequencyMemory(id: 10, label: "80m Phone",   frequencyHz: 3_900_000, mode: .lsb),
        FrequencyMemory(id: 11, label: "80m CW",      frequencyHz: 3_550_000, mode: .cw),
        FrequencyMemory(id: 12, label: "80m FT8",     frequencyHz: 3_573_000, mode: .digu,  notes: "FT8"),
        // 40m
        FrequencyMemory(id: 20, label: "40m Phone",   frequencyHz: 7_200_000, mode: .lsb),
        FrequencyMemory(id: 21, label: "40m CW",      frequencyHz: 7_030_000, mode: .cw),
        FrequencyMemory(id: 22, label: "40m FT8",     frequencyHz: 7_074_000, mode: .digu,  notes: "FT8"),
        // 30m
        FrequencyMemory(id: 30, label: "30m CW",      frequencyHz: 10_106_000, mode: .cw),
        FrequencyMemory(id: 31, label: "30m FT8",     frequencyHz: 10_136_000, mode: .digu, notes: "FT8"),
        // 20m
        FrequencyMemory(id: 40, label: "20m Phone",   frequencyHz: 14_225_000, mode: .usb),
        FrequencyMemory(id: 41, label: "20m CW",      frequencyHz: 14_025_000, mode: .cw),
        FrequencyMemory(id: 42, label: "20m FT8",     frequencyHz: 14_074_000, mode: .digu, notes: "FT8"),
        FrequencyMemory(id: 43, label: "20m RTTY",    frequencyHz: 14_080_000, mode: .digu, notes: "RTTY"),
        // 17m
        FrequencyMemory(id: 50, label: "17m Phone",   frequencyHz: 18_130_000, mode: .usb),
        FrequencyMemory(id: 51, label: "17m FT8",     frequencyHz: 18_100_000, mode: .digu, notes: "FT8"),
        // 15m
        FrequencyMemory(id: 60, label: "15m Phone",   frequencyHz: 21_300_000, mode: .usb),
        FrequencyMemory(id: 61, label: "15m CW",      frequencyHz: 21_025_000, mode: .cw),
        FrequencyMemory(id: 62, label: "15m FT8",     frequencyHz: 21_074_000, mode: .digu, notes: "FT8"),
        // 10m
        FrequencyMemory(id: 70, label: "10m Phone",   frequencyHz: 28_400_000, mode: .usb),
        FrequencyMemory(id: 71, label: "10m CW",      frequencyHz: 28_025_000, mode: .cw),
        FrequencyMemory(id: 72, label: "10m FT8",     frequencyHz: 28_074_000, mode: .digu, notes: "FT8"),
        // 6m
        FrequencyMemory(id: 80, label: "6m Phone",    frequencyHz: 50_125_000, mode: .usb),
        FrequencyMemory(id: 81, label: "6m FT8",      frequencyHz: 50_313_000, mode: .digu, notes: "FT8"),
        // 2m
        FrequencyMemory(id: 90, label: "2m SSB",      frequencyHz: 144_200_000, mode: .usb),
        FrequencyMemory(id: 91, label: "2m Simplex",  frequencyHz: 146_520_000, mode: .fm),
    ]
}
