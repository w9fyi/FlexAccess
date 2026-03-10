//
//  SlicePropertiesTests.swift
//  FlexAccessTests
//
//  Unit tests for Slice.applyProperties — verifies that every status-line
//  key/value pair is correctly parsed and applied to slice model state.
//

import XCTest


@MainActor
final class SlicePropertiesTests: XCTestCase {

    // MARK: RIT

    func testApplyRITEnabled() {
        let slice = Slice(index: 0)
        slice.applyProperties(["rit_on": "1"])
        XCTAssertTrue(slice.ritEnabled)
    }

    func testApplyRITDisabled() {
        let slice = Slice(index: 0)
        slice.ritEnabled = true
        slice.applyProperties(["rit_on": "0"])
        XCTAssertFalse(slice.ritEnabled)
    }

    func testApplyRITOffsetPositive() {
        let slice = Slice(index: 0)
        slice.applyProperties(["rit_freq": "500"])
        XCTAssertEqual(slice.ritOffsetHz, 500)
    }

    func testApplyRITOffsetNegative() {
        let slice = Slice(index: 0)
        slice.applyProperties(["rit_freq": "-250"])
        XCTAssertEqual(slice.ritOffsetHz, -250)
    }

    func testApplyRITOffsetZero() {
        let slice = Slice(index: 0)
        slice.ritOffsetHz = 500
        slice.applyProperties(["rit_freq": "0"])
        XCTAssertEqual(slice.ritOffsetHz, 0)
    }

    func testApplyRITBothKeysAtOnce() {
        let slice = Slice(index: 0)
        slice.applyProperties(["rit_on": "1", "rit_freq": "750"])
        XCTAssertTrue(slice.ritEnabled)
        XCTAssertEqual(slice.ritOffsetHz, 750)
    }

    // MARK: XIT

    func testApplyXITEnabled() {
        let slice = Slice(index: 0)
        slice.applyProperties(["xit_on": "1"])
        XCTAssertTrue(slice.xitEnabled)
    }

    func testApplyXITDisabled() {
        let slice = Slice(index: 0)
        slice.xitEnabled = true
        slice.applyProperties(["xit_on": "0"])
        XCTAssertFalse(slice.xitEnabled)
    }

    func testApplyXITOffsetPositive() {
        let slice = Slice(index: 0)
        slice.applyProperties(["xit_freq": "300"])
        XCTAssertEqual(slice.xitOffsetHz, 300)
    }

    func testApplyXITOffsetNegative() {
        let slice = Slice(index: 0)
        slice.applyProperties(["xit_freq": "-100"])
        XCTAssertEqual(slice.xitOffsetHz, -100)
    }

    // MARK: Squelch

    func testApplySquelchEnabled() {
        let slice = Slice(index: 0)
        slice.applyProperties(["squelch": "1"])
        XCTAssertTrue(slice.squelchEnabled)
    }

    func testApplySquelchDisabled() {
        let slice = Slice(index: 0)
        slice.squelchEnabled = true
        slice.applyProperties(["squelch": "0"])
        XCTAssertFalse(slice.squelchEnabled)
    }

    func testApplySquelchLevel() {
        let slice = Slice(index: 0)
        slice.applyProperties(["squelch_level": "42"])
        XCTAssertEqual(slice.squelchLevel, 42)
    }

    func testApplySquelchLevelZero() {
        let slice = Slice(index: 0)
        slice.applyProperties(["squelch_level": "0"])
        XCTAssertEqual(slice.squelchLevel, 0)
    }

    func testApplySquelchLevelMax() {
        let slice = Slice(index: 0)
        slice.applyProperties(["squelch_level": "100"])
        XCTAssertEqual(slice.squelchLevel, 100)
    }

    // MARK: APF

    func testApplyAPFEnabled() {
        let slice = Slice(index: 0)
        slice.applyProperties(["apf_on": "1"])
        XCTAssertTrue(slice.apfEnabled)
    }

    func testApplyAPFDisabled() {
        let slice = Slice(index: 0)
        slice.apfEnabled = true
        slice.applyProperties(["apf_on": "0"])
        XCTAssertFalse(slice.apfEnabled)
    }

    func testApplyAPFQFactor() {
        let slice = Slice(index: 0)
        slice.applyProperties(["apf_qfactor": "16"])
        XCTAssertEqual(slice.apfQFactor, 16)
    }

    func testApplyAPFQFactorMin() {
        let slice = Slice(index: 0)
        slice.applyProperties(["apf_qfactor": "0"])
        XCTAssertEqual(slice.apfQFactor, 0)
    }

    func testApplyAPFQFactorMax() {
        let slice = Slice(index: 0)
        slice.applyProperties(["apf_qfactor": "33"])
        XCTAssertEqual(slice.apfQFactor, 33)
    }

    func testApplyAPFGain() {
        let slice = Slice(index: 0)
        slice.applyProperties(["apf_gain": "75"])
        XCTAssertEqual(slice.apfGain, 75)
    }

    func testApplyAPFAllKeys() {
        let slice = Slice(index: 0)
        slice.applyProperties(["apf_on": "1", "apf_qfactor": "20", "apf_gain": "80"])
        XCTAssertTrue(slice.apfEnabled)
        XCTAssertEqual(slice.apfQFactor, 20)
        XCTAssertEqual(slice.apfGain, 80)
    }

    // MARK: Tuning step

    func testApplyStep100Hz() {
        let slice = Slice(index: 0)
        slice.applyProperties(["step": "100"])
        XCTAssertEqual(slice.stepHz, 100)
    }

    func testApplyStep1kHz() {
        let slice = Slice(index: 0)
        slice.applyProperties(["step": "1000"])
        XCTAssertEqual(slice.stepHz, 1000)
    }

    func testApplyStep1Hz() {
        let slice = Slice(index: 0)
        slice.applyProperties(["step": "1"])
        XCTAssertEqual(slice.stepHz, 1)
    }

    // MARK: Pre-existing properties — regression guards

    func testApplyFrequency() {
        let slice = Slice(index: 0)
        slice.applyProperties(["rf_frequency": "14.225000"])
        XCTAssertEqual(slice.frequencyHz, 14_225_000)
    }

    func testApplyMode() {
        let slice = Slice(index: 0)
        slice.applyProperties(["mode": "CW"])
        XCTAssertEqual(slice.mode, .cw)
    }

    func testApplyModeUppercaseNormalization() {
        let slice = Slice(index: 0)
        slice.applyProperties(["mode": "usb"])
        XCTAssertEqual(slice.mode, .usb)
    }

    func testApplyFilterEdges() {
        let slice = Slice(index: 0)
        slice.applyProperties(["filter_lo": "-250", "filter_hi": "250"])
        XCTAssertEqual(slice.filterLo, -250)
        XCTAssertEqual(slice.filterHi,  250)
    }

    func testApplyNREnabled() {
        let slice = Slice(index: 0)
        slice.applyProperties(["nr": "1"])
        XCTAssertTrue(slice.nrEnabled)
    }

    func testApplyAGCMode() {
        let slice = Slice(index: 0)
        slice.applyProperties(["agc_mode": "fast"])
        XCTAssertEqual(slice.agcMode, .fast)
    }

    func testApplyAGCThreshold() {
        let slice = Slice(index: 0)
        slice.applyProperties(["agc_threshold": "80"])
        XCTAssertEqual(slice.agcThreshold, 80)
    }

    func testApplyRFGain() {
        let slice = Slice(index: 0)
        slice.applyProperties(["rfgain": "-30"])
        XCTAssertEqual(slice.rfGain, -30)
    }

    func testApplyAudioLevel() {
        let slice = Slice(index: 0)
        slice.applyProperties(["audio_level": "75"])
        XCTAssertEqual(slice.audioLevel, 75)
    }

    func testUnknownKeyIsIgnored() {
        let slice = Slice(index: 0)
        let before = slice.frequencyHz
        slice.applyProperties(["totally_unknown_key": "99"])
        XCTAssertEqual(slice.frequencyHz, before)
    }

    func testEmptyPropertiesChangesNothing() {
        let slice = Slice(index: 0)
        let beforeFreq = slice.frequencyHz
        let beforeMode = slice.mode
        slice.applyProperties([:])
        XCTAssertEqual(slice.frequencyHz, beforeFreq)
        XCTAssertEqual(slice.mode, beforeMode)
    }

    // MARK: Default values

    func testDefaultRITState() {
        let slice = Slice(index: 0)
        XCTAssertFalse(slice.ritEnabled)
        XCTAssertEqual(slice.ritOffsetHz, 0)
    }

    func testDefaultXITState() {
        let slice = Slice(index: 0)
        XCTAssertFalse(slice.xitEnabled)
        XCTAssertEqual(slice.xitOffsetHz, 0)
    }

    func testDefaultSquelchState() {
        let slice = Slice(index: 0)
        XCTAssertFalse(slice.squelchEnabled)
        XCTAssertEqual(slice.squelchLevel, 20)
    }

    func testDefaultAPFState() {
        let slice = Slice(index: 0)
        XCTAssertFalse(slice.apfEnabled)
        XCTAssertEqual(slice.apfQFactor, 0)
        XCTAssertEqual(slice.apfGain, 0)
    }

    func testDefaultStepHz() {
        let slice = Slice(index: 0)
        XCTAssertEqual(slice.stepHz, 100)
    }
}
