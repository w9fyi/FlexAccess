//
//  MorseDecodeTests.swift
//  FlexAccessTests
//
//  Unit tests for MorseTable — encode, decode, and round-trip.
//

import XCTest

final class MorseDecodeTests: XCTestCase {

    // MARK: Decode — letters

    func testDecodeA() { XCTAssertEqual(MorseTable.decode(".-"),    "A") }
    func testDecodeB() { XCTAssertEqual(MorseTable.decode("-..."),  "B") }
    func testDecodeC() { XCTAssertEqual(MorseTable.decode("-.-."),  "C") }
    func testDecodeD() { XCTAssertEqual(MorseTable.decode("-.."),   "D") }
    func testDecodeE() { XCTAssertEqual(MorseTable.decode("."),     "E") }
    func testDecodeF() { XCTAssertEqual(MorseTable.decode("..-."),  "F") }
    func testDecodeG() { XCTAssertEqual(MorseTable.decode("--."),   "G") }
    func testDecodeH() { XCTAssertEqual(MorseTable.decode("...."),  "H") }
    func testDecodeI() { XCTAssertEqual(MorseTable.decode(".."),    "I") }
    func testDecodeJ() { XCTAssertEqual(MorseTable.decode(".---"),  "J") }
    func testDecodeK() { XCTAssertEqual(MorseTable.decode("-.-"),   "K") }
    func testDecodeL() { XCTAssertEqual(MorseTable.decode(".-.."),  "L") }
    func testDecodeM() { XCTAssertEqual(MorseTable.decode("--"),    "M") }
    func testDecodeN() { XCTAssertEqual(MorseTable.decode("-."),    "N") }
    func testDecodeO() { XCTAssertEqual(MorseTable.decode("---"),   "O") }
    func testDecodeP() { XCTAssertEqual(MorseTable.decode(".--."),  "P") }
    func testDecodeQ() { XCTAssertEqual(MorseTable.decode("--.-"),  "Q") }
    func testDecodeR() { XCTAssertEqual(MorseTable.decode(".-."),   "R") }
    func testDecodeS() { XCTAssertEqual(MorseTable.decode("..."),   "S") }
    func testDecodeT() { XCTAssertEqual(MorseTable.decode("-"),     "T") }
    func testDecodeU() { XCTAssertEqual(MorseTable.decode("..-"),   "U") }
    func testDecodeV() { XCTAssertEqual(MorseTable.decode("...-"),  "V") }
    func testDecodeW() { XCTAssertEqual(MorseTable.decode(".--"),   "W") }
    func testDecodeX() { XCTAssertEqual(MorseTable.decode("-..-"),  "X") }
    func testDecodeY() { XCTAssertEqual(MorseTable.decode("-.--"),  "Y") }
    func testDecodeZ() { XCTAssertEqual(MorseTable.decode("--.."),  "Z") }

    // MARK: Decode — numbers

    func testDecode0() { XCTAssertEqual(MorseTable.decode("-----"), "0") }
    func testDecode1() { XCTAssertEqual(MorseTable.decode(".----"), "1") }
    func testDecode2() { XCTAssertEqual(MorseTable.decode("..---"), "2") }
    func testDecode3() { XCTAssertEqual(MorseTable.decode("...--"), "3") }
    func testDecode4() { XCTAssertEqual(MorseTable.decode("....-"), "4") }
    func testDecode5() { XCTAssertEqual(MorseTable.decode("....."), "5") }
    func testDecode6() { XCTAssertEqual(MorseTable.decode("-...."), "6") }
    func testDecode7() { XCTAssertEqual(MorseTable.decode("--..."), "7") }
    func testDecode8() { XCTAssertEqual(MorseTable.decode("---.."), "8") }
    func testDecode9() { XCTAssertEqual(MorseTable.decode("----."), "9") }

    // MARK: Decode — punctuation

    func testDecodePeriod()       { XCTAssertEqual(MorseTable.decode(".-.-.-"), ".") }
    func testDecodeComma()        { XCTAssertEqual(MorseTable.decode("--..--"), ",") }
    func testDecodeQuestion()     { XCTAssertEqual(MorseTable.decode("..--.."), "?") }
    func testDecodeSlash()        { XCTAssertEqual(MorseTable.decode("-..-."),  "/") }
    func testDecodeEquals()       { XCTAssertEqual(MorseTable.decode("-...-"),  "=") }

    // MARK: Decode — unknown / empty

    func testDecodeUnknownReturnsNil() {
        XCTAssertNil(MorseTable.decode("......"))  // not a standard character
    }

    func testDecodeEmptyReturnsNil() {
        XCTAssertNil(MorseTable.decode(""))
    }

    // MARK: Encode — uppercase

    func testEncodeA()    { XCTAssertEqual(MorseTable.encode("A"), ".-") }
    func testEncodeS()    { XCTAssertEqual(MorseTable.encode("S"), "...") }
    func testEncodeO()    { XCTAssertEqual(MorseTable.encode("O"), "---") }
    func testEncodeZero() { XCTAssertEqual(MorseTable.encode("0"), "-----") }
    func testEncodeNine() { XCTAssertEqual(MorseTable.encode("9"), "----.") }

    // MARK: Encode — lowercase normalised

    func testEncodeLowercaseA() { XCTAssertEqual(MorseTable.encode("a"), ".-") }
    func testEncodeLowercaseZ() { XCTAssertEqual(MorseTable.encode("z"), "--..") }

    // MARK: Encode — unknown

    func testEncodeUnknownReturnsNil() {
        XCTAssertNil(MorseTable.encode("#"))   // # is not a Morse character
    }

    // MARK: Round-trip

    func testRoundTripAllLetters() {
        for c: Character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            guard let code = MorseTable.encode(c) else {
                XCTFail("No code for \(c)"); continue
            }
            XCTAssertEqual(MorseTable.decode(code), c, "Round-trip failed for \(c)")
        }
    }

    func testRoundTripAllDigits() {
        for c: Character in "0123456789" {
            guard let code = MorseTable.encode(c) else {
                XCTFail("No code for \(c)"); continue
            }
            XCTAssertEqual(MorseTable.decode(code), c, "Round-trip failed for \(c)")
        }
    }

    // MARK: Table coverage

    func testAllCodesAreUnique() {
        let codes = Array(MorseTable.codeToChar.keys)
        XCTAssertEqual(codes.count, Set(codes).count, "Duplicate codes in table")
    }

    func testTableHas26Letters() {
        let letters = MorseTable.codeToChar.values.filter { $0.isLetter }
        XCTAssertEqual(letters.count, 26)
    }

    func testTableHas10Digits() {
        let digits = MorseTable.codeToChar.values.filter { $0.isNumber }
        XCTAssertEqual(digits.count, 10)
    }
}
