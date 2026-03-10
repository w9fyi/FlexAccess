//
//  CWProtocolTests.swift
//  FlexAccessTests
//
//  Unit tests for FlexProtocol CW command builders.
//

import XCTest

final class CWProtocolTests: XCTestCase {

    // MARK: cwSend

    func testCWSendSimpleText() {
        XCTAssertEqual(FlexProtocol.cwSend("CQ DE AI5OS"), "cw send CQ DE AI5OS")
    }

    func testCWSendSingleChar() {
        XCTAssertEqual(FlexProtocol.cwSend("K"), "cw send K")
    }

    func testCWSendProsign() {
        XCTAssertEqual(FlexProtocol.cwSend("73 TU"), "cw send 73 TU")
    }

    // MARK: cwAbort

    func testCWAbort() {
        XCTAssertEqual(FlexProtocol.cwAbort(), "cw abort")
    }

    // MARK: cwSpeed

    func testCWSpeedTypical() {
        XCTAssertEqual(FlexProtocol.cwSpeed(20), "cw keyer_speed 20")
    }

    func testCWSpeedMinimum() {
        XCTAssertEqual(FlexProtocol.cwSpeed(FlexProtocol.cwSpeedRange.lowerBound),
                       "cw keyer_speed 5")
    }

    func testCWSpeedMaximum() {
        XCTAssertEqual(FlexProtocol.cwSpeed(FlexProtocol.cwSpeedRange.upperBound),
                       "cw keyer_speed 60")
    }

    // MARK: cwSidetoneLevel

    func testCWSidetoneLevelMid() {
        XCTAssertEqual(FlexProtocol.cwSidetoneLevel(50), "cw sidetone_level 50")
    }

    func testCWSidetoneLevelZero() {
        XCTAssertEqual(FlexProtocol.cwSidetoneLevel(0), "cw sidetone_level 0")
    }

    func testCWSidetoneLevelMax() {
        XCTAssertEqual(FlexProtocol.cwSidetoneLevel(100), "cw sidetone_level 100")
    }

    // MARK: cwSidetoneFrequency

    func testCWSidetoneFrequency700Hz() {
        XCTAssertEqual(FlexProtocol.cwSidetoneFrequency(700), "cw sidetone_frequency 700")
    }

    func testCWSidetoneFrequency400Hz() {
        XCTAssertEqual(FlexProtocol.cwSidetoneFrequency(400), "cw sidetone_frequency 400")
    }

    func testCWSidetoneFrequency1000Hz() {
        XCTAssertEqual(FlexProtocol.cwSidetoneFrequency(1000), "cw sidetone_frequency 1000")
    }

    // MARK: Range constants

    func testCWSpeedRange() {
        XCTAssertEqual(FlexProtocol.cwSpeedRange, 5...60)
    }

    func testCWSidetoneRange() {
        XCTAssertEqual(FlexProtocol.cwSidetoneRange, 0...100)
    }

    func testCWPitchRange() {
        XCTAssertEqual(FlexProtocol.cwPitchRange, 300...1000)
    }
}
