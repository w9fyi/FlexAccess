//
//  QSOLogTests.swift
//  FlexAccessTests
//
//  Tests for QSOEntry model and ADIF export.
//

import XCTest

final class QSOLogTests: XCTestCase {

    // MARK: - QSOEntry basics

    private func makeEntry(
        callsign: String  = "W1AW",
        freqHz:   Int     = 14_225_000,
        mode:     FlexMode = .usb,
        sentRST:  String  = "59",
        rcvdRST:  String  = "59",
        notes:    String  = "",
        date:     Date    = .distantPast
    ) -> QSOEntry {
        QSOEntry(callsign: callsign, frequencyHz: freqHz,
                 mode: mode, sentRST: sentRST, rcvdRST: rcvdRST,
                 notes: notes, date: date)
    }

    func testInitSetsCallsign() {
        XCTAssertEqual(makeEntry(callsign: "AI5OS").callsign, "AI5OS")
    }

    func testInitSetsFrequency() {
        XCTAssertEqual(makeEntry(freqHz: 7_074_000).frequencyHz, 7_074_000)
    }

    func testInitSetsMode() {
        XCTAssertEqual(makeEntry(mode: .cw).mode, .cw)
    }

    func testInitSetsSentAndRcvd() {
        let e = makeEntry(sentRST: "5NN", rcvdRST: "5NN")
        XCTAssertEqual(e.sentRST, "5NN")
        XCTAssertEqual(e.rcvdRST, "5NN")
    }

    func testIDIsNonZero() {
        XCTAssertNotEqual(makeEntry().id, UUID())
    }

    func testTwoEntriesHaveDifferentIDs() {
        XCTAssertNotEqual(makeEntry().id, makeEntry().id)
    }

    // MARK: - Band from frequency

    func testBand20m() { XCTAssertEqual(makeEntry(freqHz: 14_225_000).band, "20m") }
    func testBand40m() { XCTAssertEqual(makeEntry(freqHz: 7_200_000).band,  "40m") }
    func testBand80m() { XCTAssertEqual(makeEntry(freqHz: 3_850_000).band,  "80m") }
    func testBand15m() { XCTAssertEqual(makeEntry(freqHz: 21_200_000).band, "15m") }
    func testBand10m() { XCTAssertEqual(makeEntry(freqHz: 28_500_000).band, "10m") }
    func testBand2m()  { XCTAssertEqual(makeEntry(freqHz: 144_200_000).band,"2m")  }

    // MARK: - ADIF field generation

    func testADIFContainsCall() {
        let adif = makeEntry(callsign: "K5TMW").adifLine
        XCTAssertTrue(adif.contains("<CALL:5>K5TMW"), "ADIF: \(adif)")
    }

    func testADIFContainsBand() {
        let adif = makeEntry(freqHz: 14_225_000).adifLine
        XCTAssertTrue(adif.contains("<BAND:3>20m"), "ADIF: \(adif)")
    }

    func testADIFContainsMode() {
        let adif = makeEntry(mode: .usb).adifLine
        XCTAssertTrue(adif.contains("<MODE:3>USB"), "ADIF: \(adif)")
    }

    func testADIFContainsCWMode() {
        let adif = makeEntry(mode: .cw).adifLine
        XCTAssertTrue(adif.contains("<MODE:2>CW"), "ADIF: \(adif)")
    }

    func testADIFContainsRSTSent() {
        let adif = makeEntry(sentRST: "59").adifLine
        XCTAssertTrue(adif.contains("<RST_SENT:2>59"), "ADIF: \(adif)")
    }

    func testADIFContainsRSTRcvd() {
        let adif = makeEntry(rcvdRST: "57").adifLine
        XCTAssertTrue(adif.contains("<RST_RCVD:2>57"), "ADIF: \(adif)")
    }

    func testADIFContainsFrequencyInMHz() {
        // 14.225 MHz → "14.225000"
        let adif = makeEntry(freqHz: 14_225_000).adifLine
        XCTAssertTrue(adif.contains("<FREQ:"), "ADIF missing FREQ: \(adif)")
        XCTAssertTrue(adif.contains("14.225"), "ADIF FREQ wrong: \(adif)")
    }

    func testADIFEndsWithEOR() {
        XCTAssertTrue(makeEntry().adifLine.hasSuffix("<EOR>"))
    }

    func testADIFDateFormat() {
        // ADIF date = YYYYMMDD
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2026, month: 3, day: 10, hour: 0, minute: 0)
        let date = cal.date(from: components)!
        let adif = makeEntry(date: date).adifLine
        XCTAssertTrue(adif.contains("<QSO_DATE:8>20260310"), "ADIF date wrong: \(adif)")
    }

    func testADIFTimeFormat() {
        // ADIF time = HHMMSS UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2026, month: 3, day: 10, hour: 14, minute: 23, second: 5)
        let date = cal.date(from: components)!
        let adif = makeEntry(date: date).adifLine
        XCTAssertTrue(adif.contains("<TIME_ON:6>142305"), "ADIF time wrong: \(adif)")
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = makeEntry(callsign: "N5ZZ", freqHz: 7_074_000, mode: .digu,
                                 sentRST: "599", rcvdRST: "599", notes: "FT8")
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QSOEntry.self, from: data)
        XCTAssertEqual(decoded.callsign,     original.callsign)
        XCTAssertEqual(decoded.frequencyHz,  original.frequencyHz)
        XCTAssertEqual(decoded.mode,         original.mode)
        XCTAssertEqual(decoded.sentRST,      original.sentRST)
        XCTAssertEqual(decoded.rcvdRST,      original.rcvdRST)
        XCTAssertEqual(decoded.notes,        original.notes)
        XCTAssertEqual(decoded.id,           original.id)
    }

    // MARK: - ADIF file export

    func testADIFExportHeader() {
        let entries = [makeEntry(callsign: "W1AW"), makeEntry(callsign: "K0RQ")]
        let adif = QSOEntry.adifExport(entries)
        XCTAssertTrue(adif.hasPrefix("ADIF export"), "Header missing: \(adif.prefix(40))")
        XCTAssertTrue(adif.contains("<EOH>"), "EOH marker missing")
    }

    func testADIFExportContainsAllEntries() {
        let entries = [makeEntry(callsign: "W1AW"), makeEntry(callsign: "K0RQ")]
        let adif = QSOEntry.adifExport(entries)
        XCTAssertTrue(adif.contains("W1AW"))
        XCTAssertTrue(adif.contains("K0RQ"))
    }

    func testADIFExportEmptyProducesHeaderOnly() {
        let adif = QSOEntry.adifExport([])
        XCTAssertTrue(adif.contains("<EOH>"))
        XCTAssertFalse(adif.contains("<EOR>"))
    }
}
