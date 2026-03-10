//
//  RadioMeterTests.swift
//  FlexAccessTests
//
//  Unit tests for RadioMeter model and FlexProtocol.parseMeters().
//

import XCTest

@MainActor
final class RadioMeterTests: XCTestCase {

    // MARK: FlexProtocol.parseMeters

    func testParseMetersEmpty() {
        XCTAssertTrue(FlexProtocol.parseMeters(from: [:]).isEmpty)
    }

    func testParseMetersSingleMeter() {
        let props: [String: String] = [
            "1.nam": "SIGNAL", "1.src": "slc-0",
            "1.unit": "dBm",  "1.low": "-150", "1.high": "20", "1.fps": "20"
        ]
        let meters = FlexProtocol.parseMeters(from: props)
        XCTAssertEqual(meters.count, 1)
        let m = meters[0]
        XCTAssertEqual(m.id,     1)
        XCTAssertEqual(m.name,   "SIGNAL")
        XCTAssertEqual(m.source, "slc-0")
        XCTAssertEqual(m.unit,   "dBm")
        XCTAssertEqual(m.low,    -150)
        XCTAssertEqual(m.high,   20)
        XCTAssertEqual(m.fps,    20)
    }

    func testParseMetersMultipleMeters() {
        let props: [String: String] = [
            "1.nam": "SIGNAL", "1.src": "slc-0", "1.unit": "dBm",
            "1.low": "-150",   "1.high": "20",   "1.fps": "20",
            "2.nam": "RFPWR",  "2.src": "tx",    "2.unit": "W",
            "2.low": "0",      "2.high": "200",  "2.fps": "50",
            "3.nam": "SWR",    "3.src": "tx",    "3.unit": "SWR",
            "3.low": "1",      "3.high": "10",   "3.fps": "10"
        ]
        let meters = FlexProtocol.parseMeters(from: props)
        XCTAssertEqual(meters.count, 3)
        XCTAssertEqual(meters[0].id,   1);  XCTAssertEqual(meters[0].name, "SIGNAL")
        XCTAssertEqual(meters[1].id,   2);  XCTAssertEqual(meters[1].name, "RFPWR")
        XCTAssertEqual(meters[2].id,   3);  XCTAssertEqual(meters[2].name, "SWR")
    }

    func testParseMetersOrderedByID() {
        // Properties arrive in arbitrary order from dict — result must be sorted by ID
        let props: [String: String] = [
            "3.nam": "SWR",   "3.src": "tx",    "3.unit": "SWR", "3.low": "1", "3.high": "10", "3.fps": "10",
            "1.nam": "SIGNAL","1.src": "slc-0", "1.unit": "dBm", "1.low": "-150", "1.high": "20", "1.fps": "20"
        ]
        let meters = FlexProtocol.parseMeters(from: props)
        XCTAssertEqual(meters.count, 2)
        XCTAssertEqual(meters[0].id, 1)
        XCTAssertEqual(meters[1].id, 3)
    }

    func testParseMetersIgnoresNonNumericPrefix() {
        let props: [String: String] = [
            "model": "FLEX-8400",
            "1.nam": "SIGNAL", "1.src": "slc-0", "1.unit": "dBm",
            "1.low": "-150",   "1.high": "20",   "1.fps": "20"
        ]
        let meters = FlexProtocol.parseMeters(from: props)
        XCTAssertEqual(meters.count, 1)
        XCTAssertEqual(meters[0].name, "SIGNAL")
    }

    func testParseMetersSkipsMeterWithoutName() {
        let props: [String: String] = [
            "1.src": "slc-0", "1.unit": "dBm",          // no 1.nam
            "2.nam": "RFPWR", "2.src": "tx", "2.unit": "W",
            "2.low": "0",     "2.high": "200",  "2.fps": "50"
        ]
        let meters = FlexProtocol.parseMeters(from: props)
        XCTAssertEqual(meters.count, 1)
        XCTAssertEqual(meters[0].name, "RFPWR")
    }

    func testParseMetersDefaultsForMissingOptionalFields() {
        let props: [String: String] = ["5.nam": "TEMP"]
        let meters = FlexProtocol.parseMeters(from: props)
        XCTAssertEqual(meters.count, 1)
        XCTAssertEqual(meters[0].id,     5)
        XCTAssertEqual(meters[0].name,   "TEMP")
        XCTAssertEqual(meters[0].source, "")
        XCTAssertEqual(meters[0].unit,   "")
        XCTAssertEqual(meters[0].fps,    0)
    }

    // MARK: RadioMeter.formattedValue

    func testFormattedValueDBm() {
        let m = makeMeter(unit: "dBm");  m.value = -73.5
        XCTAssertEqual(m.formattedValue, "-73.5 dBm")
    }

    func testFormattedValueWatts() {
        let m = makeMeter(unit: "W");  m.value = 100.0
        XCTAssertEqual(m.formattedValue, "100.0 W")
    }

    func testFormattedValueDegC() {
        let m = makeMeter(unit: "C");  m.value = 42.0
        XCTAssertEqual(m.formattedValue, "42 °C")
    }

    func testFormattedValueSWR() {
        let m = makeMeter(unit: "SWR");  m.value = 1.5
        XCTAssertEqual(m.formattedValue, "1.5:1")
    }

    func testFormattedValuePercent() {
        let m = makeMeter(unit: "%");  m.value = 75.0
        XCTAssertEqual(m.formattedValue, "75%")
    }

    func testFormattedValueDB() {
        let m = makeMeter(unit: "dB");  m.value = 3.5
        XCTAssertEqual(m.formattedValue, "3.5 dB")
    }

    func testFormattedValueVolts() {
        let m = makeMeter(unit: "V");  m.value = 13.8
        XCTAssertEqual(m.formattedValue, "13.80 V")
    }

    func testFormattedValueAmps() {
        let m = makeMeter(unit: "A");  m.value = 2.5
        XCTAssertEqual(m.formattedValue, "2.50 A")
    }

    func testFormattedValueUnknownUnit() {
        let m = makeMeter(unit: "XYZ");  m.value = 42.0
        XCTAssertEqual(m.formattedValue, "42.0")
    }

    // MARK: RadioMeter.sMeterLabel

    func testSMeterLabelS9() {
        let m = makeMeter(unit: "dBm");  m.value = -73.0
        XCTAssertEqual(m.sMeterLabel, "S9")
    }

    func testSMeterLabelS8() {
        let m = makeMeter(unit: "dBm");  m.value = -79.0
        XCTAssertEqual(m.sMeterLabel, "S8")
    }

    func testSMeterLabelS5() {
        let m = makeMeter(unit: "dBm");  m.value = -97.0
        XCTAssertEqual(m.sMeterLabel, "S5")
    }

    func testSMeterLabelS1() {
        let m = makeMeter(unit: "dBm");  m.value = -121.0
        XCTAssertEqual(m.sMeterLabel, "S1")
    }

    func testSMeterLabelBelowS1ClampsToS1() {
        let m = makeMeter(unit: "dBm");  m.value = -140.0
        XCTAssertEqual(m.sMeterLabel, "S1")
    }

    func testSMeterLabelS9Plus10() {
        let m = makeMeter(unit: "dBm");  m.value = -63.0
        XCTAssertEqual(m.sMeterLabel, "S9+10dB")
    }

    func testSMeterLabelS9Plus40() {
        let m = makeMeter(unit: "dBm");  m.value = -33.0
        XCTAssertEqual(m.sMeterLabel, "S9+40dB")
    }

    // MARK: RadioMeter.displayName

    func testDisplayNameSignal()   { XCTAssertEqual(makeMeter(name: "SIGNAL").displayName,  "Signal") }
    func testDisplayNameRFPWR()    { XCTAssertEqual(makeMeter(name: "RFPWR").displayName,   "TX Power") }
    func testDisplayNameREFPWR()   { XCTAssertEqual(makeMeter(name: "REFPWR").displayName,  "Reflected") }
    func testDisplayNameSWR()      { XCTAssertEqual(makeMeter(name: "SWR").displayName,     "SWR") }
    func testDisplayNameALC()      { XCTAssertEqual(makeMeter(name: "ALC").displayName,     "ALC") }
    func testDisplayNameMICPWR()   { XCTAssertEqual(makeMeter(name: "MICPWR").displayName,  "Mic Level") }
    func testDisplayNameCOMPRSN()  { XCTAssertEqual(makeMeter(name: "COMPRSN").displayName, "Compression") }
    func testDisplayNameTEMP()     { XCTAssertEqual(makeMeter(name: "TEMP").displayName,    "PA Temp") }
    func testDisplayNameUnknown()  { XCTAssertEqual(makeMeter(name: "FOOBAR").displayName,  "FOOBAR") }

    // MARK: Value update

    func testValueDefaultsToZero() {
        XCTAssertEqual(makeMeter().value, 0.0)
    }

    func testValueUpdate() {
        let m = makeMeter();  m.value = -85.5
        XCTAssertEqual(m.value, -85.5)
    }

    // MARK: Helpers

    private func makeMeter(id: Int = 1, name: String = "SIGNAL",
                            source: String = "slc-0", unit: String = "dBm",
                            low: Double = -150, high: Double = 20, fps: Int = 20) -> RadioMeter {
        RadioMeter(id: id, name: name, source: source, unit: unit, low: low, high: high, fps: fps)
    }
}
