//
//  QSOEntry.swift
//  FlexAccess
//
//  A single logged contact.  Serialises to/from JSON and exports ADIF lines.
//

import Foundation

struct QSOEntry: Identifiable, Codable, Equatable {

    let id:          UUID
    var callsign:    String
    var frequencyHz: Int
    var mode:        FlexMode
    var sentRST:     String
    var rcvdRST:     String
    var notes:       String
    var date:        Date

    init(callsign: String, frequencyHz: Int, mode: FlexMode,
         sentRST: String = "59", rcvdRST: String = "59",
         notes: String = "", date: Date = Date()) {
        self.id          = UUID()
        self.callsign    = callsign.uppercased()
        self.frequencyHz = frequencyHz
        self.mode        = mode
        self.sentRST     = sentRST
        self.rcvdRST     = rcvdRST
        self.notes       = notes
        self.date        = date
    }

    // MARK: - Derived

    /// Amateur-band label based on frequency, or "?" if unrecognised.
    var band: String {
        let mhz = Double(frequencyHz) / 1_000_000
        switch mhz {
        case 1.8..<2.0:       return "160m"
        case 3.5..<4.0:       return "80m"
        case 5.3305..<5.4065: return "60m"
        case 7.0..<7.3:       return "40m"
        case 10.1..<10.15:    return "30m"
        case 14.0..<14.35:    return "20m"
        case 18.068..<18.168: return "17m"
        case 21.0..<21.45:    return "15m"
        case 24.89..<24.99:   return "12m"
        case 28.0..<29.7:     return "10m"
        case 50.0..<54.0:     return "6m"
        case 144.0..<148.0:   return "2m"
        case 222.0..<225.0:   return "1.25m"
        case 420.0..<450.0:   return "70cm"
        default:              return "?"
        }
    }

    // MARK: - ADIF

    /// Single ADIF record line ending with <EOR>.
    var adifLine: String {
        var fields: [String] = []

        func field(_ tag: String, _ value: String) {
            fields.append("<\(tag):\(value.count)>\(value)")
        }

        field("CALL",     callsign)
        field("BAND",     band)
        field("MODE",     mode.rawValue.uppercased())
        field("FREQ",     String(format: "%.6f", Double(frequencyHz) / 1_000_000))
        field("RST_SENT", sentRST)
        field("RST_RCVD", rcvdRST)
        field("QSO_DATE", Self.adifDate(date))
        field("TIME_ON",  Self.adifTime(date))
        if !notes.isEmpty { field("COMMENT", notes) }

        return fields.joined(separator: " ") + " <EOR>"
    }

    /// Full ADIF file string from an array of entries.
    static func adifExport(_ entries: [QSOEntry]) -> String {
        let header = "ADIF export from FlexAccess\n<EOH>\n\n"
        let records = entries.map { $0.adifLine }.joined(separator: "\n")
        return header + records
    }

    // MARK: - Private date helpers

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private static func adifDate(_ date: Date) -> String {
        let c = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func adifTime(_ date: Date) -> String {
        let c = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
