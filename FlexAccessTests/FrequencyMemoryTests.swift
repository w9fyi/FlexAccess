//
//  FrequencyMemoryTests.swift
//  FlexAccessTests
//
//  Tests for FrequencyMemory model and default memory bank.
//

import XCTest

final class FrequencyMemoryTests: XCTestCase {

    // MARK: - Basic model

    func testInitSetsAllFields() {
        let m = FrequencyMemory(id: 1, label: "20m Phone", frequencyHz: 14_225_000, mode: .usb, notes: "")
        XCTAssertEqual(m.id,          1)
        XCTAssertEqual(m.label,       "20m Phone")
        XCTAssertEqual(m.frequencyHz, 14_225_000)
        XCTAssertEqual(m.mode,        .usb)
    }

    func testFormattedFrequencyMHz() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 14_225_000, mode: .usb)
        XCTAssertEqual(m.formattedFrequency, "14.225 MHz")
    }

    func testFormattedFrequencyKHz() {
        // 146.52 MHz (2m simplex)
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 146_520_000, mode: .fm)
        XCTAssertEqual(m.formattedFrequency, "146.520 MHz")
    }

    func testBand80m() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 3_900_000, mode: .lsb)
        XCTAssertEqual(m.band, "80m")
    }

    func testBand40m() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 7_200_000, mode: .lsb)
        XCTAssertEqual(m.band, "40m")
    }

    func testBand20m() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 14_225_000, mode: .usb)
        XCTAssertEqual(m.band, "20m")
    }

    func testBand15m() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 21_300_000, mode: .usb)
        XCTAssertEqual(m.band, "15m")
    }

    func testBand10m() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 28_400_000, mode: .usb)
        XCTAssertEqual(m.band, "10m")
    }

    func testBand2m() {
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 146_520_000, mode: .fm)
        XCTAssertEqual(m.band, "2m")
    }

    func testBandUnknown() {
        // 27 MHz — not a standard ham band
        let m = FrequencyMemory(id: 0, label: "", frequencyHz: 27_000_000, mode: .am)
        XCTAssertEqual(m.band, "?")
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = FrequencyMemory(id: 42, label: "Test", frequencyHz: 7_074_000, mode: .digu, notes: "FT8")
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(FrequencyMemory.self, from: data)
        XCTAssertEqual(decoded.id,          original.id)
        XCTAssertEqual(decoded.label,       original.label)
        XCTAssertEqual(decoded.frequencyHz, original.frequencyHz)
        XCTAssertEqual(decoded.mode,        original.mode)
        XCTAssertEqual(decoded.notes,       original.notes)
    }

    // MARK: - Default bank

    func testDefaultMemoriesIsNotEmpty() {
        XCTAssertFalse(FrequencyMemory.defaults.isEmpty)
    }

    func testDefaultMemoriesHaveUniqueIDs() {
        let ids = FrequencyMemory.defaults.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate IDs in defaults")
    }

    func testDefaultMemoriesInclude20mPhone() {
        let has20mPhone = FrequencyMemory.defaults.contains {
            $0.frequencyHz >= 14_000_000 && $0.frequencyHz < 14_350_000 && $0.mode == .usb
        }
        XCTAssertTrue(has20mPhone, "Defaults should include a 20m USB frequency")
    }

    func testDefaultMemoriesInclude40mCW() {
        let has40mCW = FrequencyMemory.defaults.contains {
            $0.frequencyHz >= 7_000_000 && $0.frequencyHz < 7_300_000 &&
            ($0.mode == .cw || $0.mode == .cwl)
        }
        XCTAssertTrue(has40mCW, "Defaults should include a 40m CW frequency")
    }

    func testDefaultMemoriesIncludeFT8Frequency() {
        // 20m FT8 = 14.074 MHz, mode DIGU
        let hasFT8 = FrequencyMemory.defaults.contains {
            $0.frequencyHz == 14_074_000
        }
        XCTAssertTrue(hasFT8, "Defaults should include 20m FT8 (14.074 MHz)")
    }

    func testDefaultMemoriesLabelsAreNonEmpty() {
        for m in FrequencyMemory.defaults {
            XCTAssertFalse(m.label.isEmpty, "Memory id=\(m.id) has empty label")
        }
    }

    func testDefaultMemoriesAllHaveValidBand() {
        for m in FrequencyMemory.defaults {
            XCTAssertNotEqual(m.band, "?", "Memory '\(m.label)' at \(m.formattedFrequency) has unknown band")
        }
    }
}
