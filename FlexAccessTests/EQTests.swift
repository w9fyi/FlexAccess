//
//  EQTests.swift
//  FlexAccessTests
//
//  Unit tests for FlexProtocol EQ command builders and parseEQBands().
//

import XCTest

final class EQTests: XCTestCase {

    // MARK: eqMode

    func testEQModeRXEnable()  { XCTAssertEqual(FlexProtocol.eqMode(type: .rx, enabled: true),  "eq rxsc mode=1") }
    func testEQModeRXDisable() { XCTAssertEqual(FlexProtocol.eqMode(type: .rx, enabled: false), "eq rxsc mode=0") }
    func testEQModeTXEnable()  { XCTAssertEqual(FlexProtocol.eqMode(type: .tx, enabled: true),  "eq txsc mode=1") }
    func testEQModeTXDisable() { XCTAssertEqual(FlexProtocol.eqMode(type: .tx, enabled: false), "eq txsc mode=0") }

    // MARK: eqBand

    func testEQBandRX63Hz() {
        XCTAssertEqual(FlexProtocol.eqBand(type: .rx, hz: 63, value: 5), "eq rxsc 63Hz=5")
    }

    func testEQBandRX8kHz() {
        XCTAssertEqual(FlexProtocol.eqBand(type: .rx, hz: 8000, value: -3), "eq rxsc 8000Hz=-3")
    }

    func testEQBandTXNegativeValue() {
        XCTAssertEqual(FlexProtocol.eqBand(type: .tx, hz: 500, value: -7), "eq txsc 500Hz=-7")
    }

    func testEQBandZeroValue() {
        XCTAssertEqual(FlexProtocol.eqBand(type: .rx, hz: 1000, value: 0), "eq rxsc 1000Hz=0")
    }

    func testEQBandMaxPositiveValue() {
        XCTAssertEqual(FlexProtocol.eqBand(type: .rx, hz: 250, value: 10), "eq rxsc 250Hz=10")
    }

    func testEQBandAllStandardFrequenciesFormatCorrectly() {
        for hz in FlexProtocol.eqBandHz {
            let cmd = FlexProtocol.eqBand(type: .rx, hz: hz, value: 0)
            XCTAssertTrue(cmd.contains("\(hz)Hz="), "Band \(hz)Hz not correctly formatted in: \(cmd)")
        }
    }

    // MARK: eqFlat

    func testEQFlatRXStartsWithCorrectPrefix() {
        XCTAssertTrue(FlexProtocol.eqFlat(type: .rx).hasPrefix("eq rxsc "))
    }

    func testEQFlatTXStartsWithCorrectPrefix() {
        XCTAssertTrue(FlexProtocol.eqFlat(type: .tx).hasPrefix("eq txsc "))
    }

    func testEQFlatRXContainsAllBandsAtZero() {
        let cmd = FlexProtocol.eqFlat(type: .rx)
        for hz in FlexProtocol.eqBandHz {
            XCTAssertTrue(cmd.contains("\(hz)Hz=0"), "eqFlat(rx) missing \(hz)Hz=0 in: \(cmd)")
        }
    }

    func testEQFlatTXContainsAllBandsAtZero() {
        let cmd = FlexProtocol.eqFlat(type: .tx)
        for hz in FlexProtocol.eqBandHz {
            XCTAssertTrue(cmd.contains("\(hz)Hz=0"), "eqFlat(tx) missing \(hz)Hz=0 in: \(cmd)")
        }
    }

    // MARK: eqBandHz constant

    func testEQBandHzCount() {
        XCTAssertEqual(FlexProtocol.eqBandHz.count, 8)
    }

    func testEQBandHzContainsStandardBands() {
        let bands = FlexProtocol.eqBandHz
        for hz in [63, 125, 250, 500, 1000, 2000, 4000, 8000] {
            XCTAssertTrue(bands.contains(hz), "eqBandHz missing \(hz)")
        }
    }

    func testEQBandHzAscending() {
        XCTAssertEqual(FlexProtocol.eqBandHz, FlexProtocol.eqBandHz.sorted())
    }

    // MARK: parseEQBands

    func testParseEQBandsAllBands() {
        let props: [String: String] = [
            "63hz": "3",  "125hz": "-2", "250hz": "0",
            "500hz": "5", "1000hz": "-3","2000hz": "1",
            "4000hz": "7","8000hz": "-5"
        ]
        let bands = FlexProtocol.parseEQBands(from: props)
        XCTAssertEqual(bands[63],   3)
        XCTAssertEqual(bands[125], -2)
        XCTAssertEqual(bands[250],  0)
        XCTAssertEqual(bands[500],  5)
        XCTAssertEqual(bands[1000],-3)
        XCTAssertEqual(bands[2000], 1)
        XCTAssertEqual(bands[4000], 7)
        XCTAssertEqual(bands[8000],-5)
    }

    func testParseEQBandsPartial() {
        let props: [String: String] = ["63hz": "3", "500hz": "-2"]
        let bands = FlexProtocol.parseEQBands(from: props)
        XCTAssertEqual(bands[63],   3)
        XCTAssertEqual(bands[500], -2)
        XCTAssertNil(bands[125])
        XCTAssertNil(bands[1000])
    }

    func testParseEQBandsEmpty() {
        XCTAssertTrue(FlexProtocol.parseEQBands(from: [:]).isEmpty)
    }

    func testParseEQBandsIgnoresNonEQKeys() {
        let props: [String: String] = ["mode": "1", "63hz": "5", "model": "FLEX-8400"]
        let bands = FlexProtocol.parseEQBands(from: props)
        XCTAssertEqual(bands.count, 1)
        XCTAssertEqual(bands[63], 5)
    }

    func testParseEQBandsZeroValue() {
        let props: [String: String] = ["1000hz": "0"]
        let bands = FlexProtocol.parseEQBands(from: props)
        XCTAssertEqual(bands[1000], 0)
    }
}
