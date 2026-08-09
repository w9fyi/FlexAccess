//
//  OpusDecoderTests.swift
//  FlexAccessTests
//
//  Tests for AudioToolbox-backed Opus decoder setup and error handling.
//

import XCTest

final class OpusDecoderTests: XCTestCase {

    private func makeDecoderOrSkip(file: StaticString = #filePath, line: UInt = #line) throws -> OpusDecoder {
        guard let decoder = OpusDecoder() else {
            throw XCTSkip("AudioToolbox Opus decoder is not available on this test platform", file: file, line: line)
        }
        return decoder
    }

    func testInitCreatesDecoderWhenOpusConverterIsAvailable() throws {
        _ = try makeDecoderOrSkip()
    }

    func testDecodeReturnsNilForEmptyPacket() throws {
        let decoder = try makeDecoderOrSkip()
        var packet: [UInt8] = [0]

        let decoded = packet.withUnsafeBufferPointer { buffer in
            decoder.decode(bytes: buffer.baseAddress!, count: 0)
        }

        XCTAssertNil(decoded)
    }

    func testDecodeReturnsNilForInvalidPacket() throws {
        let decoder = try makeDecoderOrSkip()
        // TOC 0x83 = code 3 (arbitrary frame count follows); count byte 0xFF
        // declares 63 frames, far more than 4 bytes can hold — a genuinely
        // malformed packet, unlike a short packet with garbage payload bits
        // (which is syntactically valid Opus and decodes to noise, not nil).
        let packet: [UInt8] = [0x83, 0xFF, 0x00, 0x00]

        let decoded = packet.withUnsafeBufferPointer { buffer in
            decoder.decode(bytes: buffer.baseAddress!, count: buffer.count)
        }

        XCTAssertNil(decoded)
    }
}
