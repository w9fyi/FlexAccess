//
//  FlexProtocolParserTests.swift
//  FlexAccessTests
//
//  Unit tests for FlexProtocol.parseStatusLine — verifies correct routing and
//  key/value extraction for every status line kind the radio sends.
//

import XCTest


final class FlexProtocolParserTests: XCTestCase {

    // MARK: Helpers

    private func parse(_ line: String) -> FlexStatusMessage {
        FlexProtocol.parseStatusLine(line)
    }

    private func assertSlice(_ msg: FlexStatusMessage, index expectedIndex: Int,
                              file: StaticString = #file, line: UInt = #line) {
        if case .slice(let idx) = msg.kind {
            XCTAssertEqual(idx, expectedIndex, file: file, line: line)
        } else {
            XCTFail("Expected .slice(\(expectedIndex)), got \(msg.kind)", file: file, line: line)
        }
    }

    // MARK: Slice kind routing

    func testParseSliceZero() {
        let msg = parse("slice 0 rf_frequency=14.225000 mode=USB")
        assertSlice(msg, index: 0)
    }

    func testParseSliceNonZeroIndex() {
        let msg = parse("slice 3 rf_frequency=7.200000")
        assertSlice(msg, index: 3)
    }

    // MARK: RIT properties in slice status line

    func testParseSliceRITOn() {
        let msg = parse("slice 0 rit_on=1")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["rit_on"], "1")
    }

    func testParseSliceRITOff() {
        let msg = parse("slice 0 rit_on=0")
        XCTAssertEqual(msg.properties["rit_on"], "0")
    }

    func testParseSliceRITFreqPositive() {
        let msg = parse("slice 0 rit_freq=500")
        XCTAssertEqual(msg.properties["rit_freq"], "500")
    }

    func testParseSliceRITFreqNegative() {
        let msg = parse("slice 0 rit_freq=-250")
        XCTAssertEqual(msg.properties["rit_freq"], "-250")
    }

    func testParseSliceRITBothKeys() {
        let msg = parse("slice 0 rit_on=1 rit_freq=750")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["rit_on"],   "1")
        XCTAssertEqual(msg.properties["rit_freq"], "750")
    }

    // MARK: XIT properties

    func testParseSliceXITOn() {
        let msg = parse("slice 1 xit_on=1 xit_freq=300")
        assertSlice(msg, index: 1)
        XCTAssertEqual(msg.properties["xit_on"],   "1")
        XCTAssertEqual(msg.properties["xit_freq"], "300")
    }

    func testParseSliceXITFreqNegative() {
        let msg = parse("slice 0 xit_freq=-100")
        XCTAssertEqual(msg.properties["xit_freq"], "-100")
    }

    // MARK: Squelch properties

    func testParseSliceSquelchOn() {
        let msg = parse("slice 0 squelch=1 squelch_level=35")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["squelch"],       "1")
        XCTAssertEqual(msg.properties["squelch_level"], "35")
    }

    func testParseSliceSquelchOff() {
        let msg = parse("slice 0 squelch=0")
        XCTAssertEqual(msg.properties["squelch"], "0")
    }

    // MARK: APF properties

    func testParseSliceAPFAllKeys() {
        let msg = parse("slice 0 apf_on=1 apf_qfactor=20 apf_gain=80")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["apf_on"],      "1")
        XCTAssertEqual(msg.properties["apf_qfactor"], "20")
        XCTAssertEqual(msg.properties["apf_gain"],    "80")
    }

    func testParseSliceAPFOff() {
        let msg = parse("slice 0 apf_on=0")
        XCTAssertEqual(msg.properties["apf_on"], "0")
    }

    // MARK: Step property

    func testParseSliceStep100() {
        let msg = parse("slice 0 step=100")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["step"], "100")
    }

    func testParseSliceStep1000() {
        let msg = parse("slice 0 step=1000")
        XCTAssertEqual(msg.properties["step"], "1000")
    }

    // MARK: Pre-existing status lines — regression guards

    func testParseSliceFrequencyAndMode() {
        let msg = parse("slice 0 rf_frequency=14.225000 mode=USB filter_lo=200 filter_hi=2700")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["rf_frequency"], "14.225000")
        XCTAssertEqual(msg.properties["mode"],         "USB")
        XCTAssertEqual(msg.properties["filter_lo"],    "200")
        XCTAssertEqual(msg.properties["filter_hi"],    "2700")
    }

    func testParseSliceNRNBANF() {
        let msg = parse("slice 0 nr=1 nb=0 anf=1")
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["nr"],  "1")
        XCTAssertEqual(msg.properties["nb"],  "0")
        XCTAssertEqual(msg.properties["anf"], "1")
    }

    func testParseSliceAGC() {
        let msg = parse("slice 0 agc_mode=fast agc_threshold=80")
        XCTAssertEqual(msg.properties["agc_mode"],      "fast")
        XCTAssertEqual(msg.properties["agc_threshold"], "80")
    }

    // MARK: Radio status line

    func testParseRadio() {
        let msg = parse("radio model=FLEX-8400")
        if case .radio = msg.kind {
            XCTAssertEqual(msg.properties["model"], "FLEX-8400")
        } else {
            XCTFail("Expected .radio, got \(msg.kind)")
        }
    }

    // MARK: Panadapter status line

    func testParsePanadapter() {
        let msg = parse("panadapter 0x40000000 center=14.225 bandwidth=0.200")
        if case .panadapter(let id) = msg.kind {
            XCTAssertEqual(id, "0x40000000")
            XCTAssertEqual(msg.properties["center"],    "14.225")
            XCTAssertEqual(msg.properties["bandwidth"], "0.200")
        } else {
            XCTFail("Expected .panadapter, got \(msg.kind)")
        }
    }

    func testParsePanAlias() {
        let msg = parse("pan 0x40000000 center=7.2")
        if case .panadapter(let id) = msg.kind {
            XCTAssertEqual(id, "0x40000000")
        } else {
            XCTFail("Expected .panadapter for 'pan' alias")
        }
    }

    // MARK: Waterfall status line

    func testParseWaterfall() {
        let msg = parse("waterfall 0x42000000 auto_black=1")
        if case .waterfall(let id) = msg.kind {
            XCTAssertEqual(id, "0x42000000")
            XCTAssertEqual(msg.properties["auto_black"], "1")
        } else {
            XCTFail("Expected .waterfall, got \(msg.kind)")
        }
    }

    // MARK: Audio stream status line

    func testParseAudioStreamWithStreamID() {
        let msg = parse("audio_stream 0x10000001 in_use=1 dax_channel=1")
        if case .audioStream = msg.kind {
            XCTAssertEqual(msg.properties["_streamid"],   "0x10000001")
            XCTAssertEqual(msg.properties["in_use"],      "1")
            XCTAssertEqual(msg.properties["dax_channel"], "1")
        } else {
            XCTFail("Expected .audioStream, got \(msg.kind)")
        }
    }

    // MARK: Slice list

    func testParseSliceList() {
        let msg = parse("slice_list 0 1 2")
        if case .sliceList = msg.kind {
            XCTAssertEqual(msg.properties["_raw"], "0 1 2")
        } else {
            XCTFail("Expected .sliceList, got \(msg.kind)")
        }
    }

    // MARK: EQ status line

    func testParseEQRX() {
        let msg = parse("eq rxsc mode=1 63Hz=0 125Hz=3")
        if case .eq(let type) = msg.kind {
            XCTAssertEqual(type, .rx)
            XCTAssertEqual(msg.properties["mode"],  "1")
            XCTAssertEqual(msg.properties["63hz"],  "0")
            XCTAssertEqual(msg.properties["125hz"], "3")
        } else {
            XCTFail("Expected .eq, got \(msg.kind)")
        }
    }

    func testParseEQTX() {
        let msg = parse("eq txsc mode=0")
        if case .eq(let type) = msg.kind {
            XCTAssertEqual(type, .tx)
        } else {
            XCTFail("Expected .eq(tx), got \(msg.kind)")
        }
    }

    // MARK: Meter status line

    func testParseMeter() {
        let msg = parse("meter 1.src=slc-0 1.num=1")
        if case .meter = msg.kind { } else {
            XCTFail("Expected .meter, got \(msg.kind)")
        }
    }

    // MARK: Unknown / empty

    func testParseEmptyString() {
        let msg = parse("")
        if case .unknown = msg.kind { } else {
            XCTFail("Expected .unknown for empty string")
        }
    }

    func testParseUnknownKeyword() {
        let msg = parse("xyzzy foo=bar")
        if case .unknown = msg.kind { } else {
            XCTFail("Expected .unknown for unrecognised keyword")
        }
    }

    // MARK: Key normalisation — keys must be lowercased

    func testKeyNormalisationToLowercase() {
        let msg = parse("slice 0 RF_Frequency=14.225000")
        // The parser lowercases all keys
        XCTAssertNotNil(msg.properties["rf_frequency"])
    }

    // MARK: Combined full status line

    func testParseSliceFullStatusLine() {
        let line = "slice 0 rf_frequency=14.225000 mode=USB filter_lo=200 filter_hi=2700 " +
                   "nr=1 nb=0 anf=0 agc_mode=med agc_threshold=65 rfgain=0 audio_level=50 " +
                   "rxant=ANT1 dax=0 tx=0 rit_on=0 rit_freq=0 xit_on=0 xit_freq=0 " +
                   "squelch=0 squelch_level=20 apf_on=0 apf_qfactor=0 apf_gain=0 step=100"
        let msg = parse(line)
        assertSlice(msg, index: 0)
        XCTAssertEqual(msg.properties["rf_frequency"],  "14.225000")
        XCTAssertEqual(msg.properties["mode"],          "USB")
        XCTAssertEqual(msg.properties["rit_on"],        "0")
        XCTAssertEqual(msg.properties["rit_freq"],      "0")
        XCTAssertEqual(msg.properties["xit_on"],        "0")
        XCTAssertEqual(msg.properties["xit_freq"],      "0")
        XCTAssertEqual(msg.properties["squelch"],       "0")
        XCTAssertEqual(msg.properties["squelch_level"], "20")
        XCTAssertEqual(msg.properties["apf_on"],        "0")
        XCTAssertEqual(msg.properties["apf_qfactor"],   "0")
        XCTAssertEqual(msg.properties["apf_gain"],      "0")
        XCTAssertEqual(msg.properties["step"],          "100")
    }
}
