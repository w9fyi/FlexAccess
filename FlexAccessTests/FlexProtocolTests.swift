//
//  FlexProtocolTests.swift
//  FlexAccessTests
//
//  Unit tests for FlexProtocol command string builders.
//  These are pure string-generation tests — no radio connection required.
//

import XCTest

final class FlexProtocolTests: XCTestCase {

    // MARK: RIT

    func testSetRITEnabled() {
        XCTAssertEqual(FlexProtocol.setRIT(index: 0, enabled: true),  "slice set 0 rit_on=1")
        XCTAssertEqual(FlexProtocol.setRIT(index: 0, enabled: false), "slice set 0 rit_on=0")
    }

    func testSetRITSliceIndex() {
        XCTAssertEqual(FlexProtocol.setRIT(index: 3, enabled: true), "slice set 3 rit_on=1")
    }

    func testSetRITOffsetPositive() {
        XCTAssertEqual(FlexProtocol.setRITOffset(index: 0, hz: 500), "slice set 0 rit_freq=500")
    }

    func testSetRITOffsetNegative() {
        XCTAssertEqual(FlexProtocol.setRITOffset(index: 0, hz: -250), "slice set 0 rit_freq=-250")
    }

    func testSetRITOffsetZero() {
        XCTAssertEqual(FlexProtocol.setRITOffset(index: 1, hz: 0), "slice set 1 rit_freq=0")
    }

    func testSetRITOffsetMaxPositive() {
        XCTAssertEqual(FlexProtocol.setRITOffset(index: 0, hz: 99999), "slice set 0 rit_freq=99999")
    }

    func testSetRITOffsetMaxNegative() {
        XCTAssertEqual(FlexProtocol.setRITOffset(index: 0, hz: -99999), "slice set 0 rit_freq=-99999")
    }

    // MARK: XIT

    func testSetXITEnabled() {
        XCTAssertEqual(FlexProtocol.setXIT(index: 0, enabled: true),  "slice set 0 xit_on=1")
        XCTAssertEqual(FlexProtocol.setXIT(index: 0, enabled: false), "slice set 0 xit_on=0")
    }

    func testSetXITOffsetPositive() {
        XCTAssertEqual(FlexProtocol.setXITOffset(index: 0, hz: 600), "slice set 0 xit_freq=600")
    }

    func testSetXITOffsetNegative() {
        XCTAssertEqual(FlexProtocol.setXITOffset(index: 2, hz: -100), "slice set 2 xit_freq=-100")
    }

    func testSetXITOffsetZero() {
        XCTAssertEqual(FlexProtocol.setXITOffset(index: 0, hz: 0), "slice set 0 xit_freq=0")
    }

    // MARK: Squelch

    func testSetSquelchEnabled() {
        XCTAssertEqual(FlexProtocol.setSquelch(index: 0, enabled: true),  "slice set 0 squelch=1")
        XCTAssertEqual(FlexProtocol.setSquelch(index: 0, enabled: false), "slice set 0 squelch=0")
    }

    func testSetSquelchLevelMinimum() {
        XCTAssertEqual(FlexProtocol.setSquelchLevel(index: 0, level: 0), "slice set 0 squelch_level=0")
    }

    func testSetSquelchLevelMaximum() {
        XCTAssertEqual(FlexProtocol.setSquelchLevel(index: 0, level: 100), "slice set 0 squelch_level=100")
    }

    func testSetSquelchLevelMid() {
        XCTAssertEqual(FlexProtocol.setSquelchLevel(index: 1, level: 35), "slice set 1 squelch_level=35")
    }

    // MARK: APF

    func testSetAPFEnabled() {
        XCTAssertEqual(FlexProtocol.setAPF(index: 0, enabled: true),  "slice set 0 apf_on=1")
        XCTAssertEqual(FlexProtocol.setAPF(index: 0, enabled: false), "slice set 0 apf_on=0")
    }

    func testSetAPFQFactorMinimum() {
        XCTAssertEqual(FlexProtocol.setAPFQFactor(index: 0, q: 0), "slice set 0 apf_qfactor=0")
    }

    func testSetAPFQFactorMaximum() {
        XCTAssertEqual(FlexProtocol.setAPFQFactor(index: 0, q: 33), "slice set 0 apf_qfactor=33")
    }

    func testSetAPFQFactorMid() {
        XCTAssertEqual(FlexProtocol.setAPFQFactor(index: 2, q: 16), "slice set 2 apf_qfactor=16")
    }

    func testSetAPFGainMinimum() {
        XCTAssertEqual(FlexProtocol.setAPFGain(index: 0, gain: 0), "slice set 0 apf_gain=0")
    }

    func testSetAPFGainMaximum() {
        XCTAssertEqual(FlexProtocol.setAPFGain(index: 0, gain: 100), "slice set 0 apf_gain=100")
    }

    func testSetAPFGainMid() {
        XCTAssertEqual(FlexProtocol.setAPFGain(index: 1, gain: 50), "slice set 1 apf_gain=50")
    }

    // MARK: Tuning step

    func testSetStep100Hz() {
        XCTAssertEqual(FlexProtocol.setStep(index: 0, hz: 100), "slice set 0 step=100")
    }

    func testSetStep1kHz() {
        XCTAssertEqual(FlexProtocol.setStep(index: 0, hz: 1000), "slice set 0 step=1000")
    }

    func testSetStep1Hz() {
        XCTAssertEqual(FlexProtocol.setStep(index: 0, hz: 1), "slice set 0 step=1")
    }

    func testSetStep10kHz() {
        XCTAssertEqual(FlexProtocol.setStep(index: 3, hz: 10_000), "slice set 3 step=10000")
    }

    // MARK: Step values constant

    func testStepValuesContainsStandardValues() {
        let steps = FlexProtocol.stepValues
        XCTAssertTrue(steps.contains(1))
        XCTAssertTrue(steps.contains(10))
        XCTAssertTrue(steps.contains(100))
        XCTAssertTrue(steps.contains(1_000))
        XCTAssertTrue(steps.contains(10_000))
    }

    func testStepValuesAreAscending() {
        let steps = FlexProtocol.stepValues
        XCTAssertEqual(steps, steps.sorted())
    }

    func testStepValuesAllPositive() {
        XCTAssertTrue(FlexProtocol.stepValues.allSatisfy { $0 > 0 })
    }

    // MARK: Pre-existing commands — regression guards

    func testSliceTuneFormat() {
        let cmd = FlexProtocol.sliceTune(index: 0, freqMHz: 14.225)
        XCTAssertEqual(cmd, "slice t 0 14.225000")
    }

    func testSetNREnabled() {
        XCTAssertEqual(FlexProtocol.setNR(index: 0, enabled: true),  "slice set 0 nr=1")
        XCTAssertEqual(FlexProtocol.setNR(index: 0, enabled: false), "slice set 0 nr=0")
    }

    func testSetAGCMode() {
        XCTAssertEqual(FlexProtocol.setAGC(index: 0, mode: .fast), "slice set 0 agc_mode=fast")
        XCTAssertEqual(FlexProtocol.setAGC(index: 0, mode: .off),  "slice set 0 agc_mode=off")
    }

    func testSetFilter() {
        XCTAssertEqual(FlexProtocol.setFilter(index: 0, lo: 200, hi: 2700),
                       "slice set 0 filter_lo=200 filter_hi=2700")
    }

    func testPTTDown() {
        XCTAssertEqual(FlexProtocol.pttDown(), "xmit 1")
    }

    func testPTTUp() {
        XCTAssertEqual(FlexProtocol.pttUp(), "xmit 0")
    }
}
