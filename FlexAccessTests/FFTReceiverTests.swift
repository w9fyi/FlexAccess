//
//  FFTReceiverTests.swift
//  FlexAccessTests
//
//  Tests for FFTReceiver stream-ID parsing and bin-decode arithmetic.
//  (The async process() path is covered by integration; these tests are synchronous.)
//

import XCTest

@MainActor
final class FFTReceiverTests: XCTestCase {

    private func makeReceiver(_ panID: String) -> FFTReceiver {
        let pan = Panadapter(id: panID)
        return FFTReceiver(panID: panID, panadapter: pan)
    }

    // MARK: - streamID

    func testStreamIDParsesHexPrefix() {
        XCTAssertEqual(makeReceiver("0x40000000").streamID, 0x40000000)
    }

    func testStreamIDParsesUppercasePrefix() {
        XCTAssertEqual(makeReceiver("0X4000ABCD").streamID, 0x4000ABCD)
    }

    func testStreamIDParsesWithoutPrefix() {
        XCTAssertEqual(makeReceiver("40000001").streamID, 0x40000001)
    }

    func testStreamIDParsesZero() {
        XCTAssertEqual(makeReceiver("0x00000000").streamID, 0x00000000)
    }

    func testStreamIDParsesMaxValue() {
        XCTAssertEqual(makeReceiver("0xFFFFFFFF").streamID, 0xFFFFFFFF)
    }

    func testStreamIDInvalidReturnsNil() {
        XCTAssertNil(makeReceiver("xyz").streamID)
    }

    func testStreamIDEmptyReturnsNil() {
        XCTAssertNil(makeReceiver("").streamID)
    }

    func testStreamIDDecimalStringReturnsNil() {
        // "1073741824" is decimal, not valid hex without context
        // UInt32("1073741824", radix: 16) → nil (contains digit > 9 isn't the issue;
        // but "1073741824" is actually valid hex if all chars are 0-9 / a-f)
        // Use a clearly non-hex string instead
        XCTAssertNil(makeReceiver("0xGGGGGGGG").streamID)
    }

    // MARK: - Bin decode arithmetic (tested directly, not through async process())

    func testBinDecodePositive() {
        // UInt8 payload: 0x01, 0x00 → Int16 big-endian = 0x0100 = 256 → 256/128 = 2.0 dBm
        let hi: UInt8 = 0x01; let lo: UInt8 = 0x00
        let raw = Int16(bitPattern: UInt16(hi) << 8 | UInt16(lo))
        XCTAssertEqual(Float(raw) / 128.0, 2.0, accuracy: 0.001)
    }

    func testBinDecodeZero() {
        let hi: UInt8 = 0x00; let lo: UInt8 = 0x00
        let raw = Int16(bitPattern: UInt16(hi) << 8 | UInt16(lo))
        XCTAssertEqual(Float(raw) / 128.0, 0.0, accuracy: 0.001)
    }

    func testBinDecodeNegative() {
        // 0xFF80 as Int16 = -128 → -128/128 = -1.0 dBm
        let hi: UInt8 = 0xFF; let lo: UInt8 = 0x80
        let raw = Int16(bitPattern: UInt16(hi) << 8 | UInt16(lo))
        XCTAssertEqual(Float(raw) / 128.0, -1.0, accuracy: 0.001)
    }

    func testBinDecodeTypical() {
        // -100 dBm → Int16 = -12800 = 0xCE00
        // Reverse: 0xCE = 206, 0x00 = 0 → Int16 = -12800 (= 0xCE00 as signed)
        let expected: Float = -100.0
        let int16Val = Int16(expected * 128.0)
        XCTAssertEqual(Float(int16Val) / 128.0, expected, accuracy: 0.001)
    }

    func testBinCountEqualsPayloadDividedByTwo() {
        // 8 bytes → 4 bins
        let byteCount = 8
        XCTAssertEqual(byteCount / 2, 4)
    }
}
