//
//  MIDIMappingTests.swift
//  FlexAccessTests
//
//  Tests for MIDIMapping model — action matching, Codable round-trip,
//  default mappings, and the CC-to-action lookup logic.
//  (No CoreMIDI needed — all pure-Swift mapping logic.)
//

import XCTest

final class MIDIMappingTests: XCTestCase {

    // MARK: - MIDITrigger matching

    func testCCTriggerMatchesExact() {
        let trigger = MIDITrigger.cc(channel: 1, cc: 7)
        XCTAssertTrue(trigger.matches(channel: 1, ccOrNote: 7))
    }

    func testCCTriggerDoesNotMatchWrongCC() {
        let trigger = MIDITrigger.cc(channel: 1, cc: 7)
        XCTAssertFalse(trigger.matches(channel: 1, ccOrNote: 8))
    }

    func testCCTriggerDoesNotMatchWrongChannel() {
        let trigger = MIDITrigger.cc(channel: 1, cc: 7)
        XCTAssertFalse(trigger.matches(channel: 2, ccOrNote: 7))
    }

    func testNoteTriggerMatchesExact() {
        let trigger = MIDITrigger.note(channel: 1, note: 60)
        XCTAssertTrue(trigger.matches(channel: 1, ccOrNote: 60))
    }

    func testNoteTriggerDoesNotMatchCC() {
        let trigger = MIDITrigger.cc(channel: 1, cc: 60)
        let noteTrigger = MIDITrigger.note(channel: 1, note: 60)
        // Same number, different kind — not directly testable via matches(),
        // but triggers should be non-equal
        XCTAssertNotEqual(trigger, noteTrigger)
    }

    // MARK: - MIDIAction display names

    func testTuneUpDisplayName() {
        XCTAssertFalse(MIDIAction.tuneUp(hz: 100).displayName.isEmpty)
    }

    func testTuneDownDisplayName() {
        XCTAssertFalse(MIDIAction.tuneDown(hz: 100).displayName.isEmpty)
    }

    func testPTTDisplayName() {
        XCTAssertFalse(MIDIAction.pttToggle.displayName.isEmpty)
    }

    func testCWMacroDisplayName() {
        XCTAssertFalse(MIDIAction.cwMacro(index: 0).displayName.isEmpty)
    }

    func testSetModeDisplayName() {
        XCTAssertFalse(MIDIAction.setMode(.cw).displayName.isEmpty)
    }

    func testNRToggleDisplayName() {
        XCTAssertFalse(MIDIAction.nrToggle.displayName.isEmpty)
    }

    func testBandUpDisplayName() {
        XCTAssertFalse(MIDIAction.bandUp.displayName.isEmpty)
    }

    func testBandDownDisplayName() {
        XCTAssertFalse(MIDIAction.bandDown.displayName.isEmpty)
    }

    // MARK: - MIDIMapping Codable round-trip

    func testCodableRoundTripCC() throws {
        let m = MIDIMapping(trigger: .cc(channel: 1, cc: 7), action: .tuneUp(hz: 500))
        let data    = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(MIDIMapping.self, from: data)
        XCTAssertEqual(decoded.trigger, m.trigger)
        XCTAssertEqual(decoded.action,  m.action)
    }

    func testCodableRoundTripNote() throws {
        let m = MIDIMapping(trigger: .note(channel: 1, note: 60), action: .pttToggle)
        let data    = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(MIDIMapping.self, from: data)
        XCTAssertEqual(decoded.trigger, m.trigger)
        XCTAssertEqual(decoded.action,  m.action)
    }

    func testCodableRoundTripSetMode() throws {
        let m = MIDIMapping(trigger: .cc(channel: 1, cc: 20), action: .setMode(.usb))
        let data    = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(MIDIMapping.self, from: data)
        XCTAssertEqual(decoded.action, m.action)
    }

    func testCodableRoundTripCWMacro() throws {
        let m = MIDIMapping(trigger: .note(channel: 1, note: 36), action: .cwMacro(index: 2))
        let data    = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(MIDIMapping.self, from: data)
        XCTAssertEqual(decoded.action, m.action)
    }

    // MARK: - Default mappings

    func testDefaultMappingsIsNotEmpty() {
        XCTAssertFalse(MIDIMapping.defaults.isEmpty)
    }

    func testDefaultMappingsIncludeTuneUp() {
        let hasTuneUp = MIDIMapping.defaults.contains {
            if case .tuneUp = $0.action { return true }
            return false
        }
        XCTAssertTrue(hasTuneUp, "Default mappings should include a tuneUp action")
    }

    func testDefaultMappingsIncludeTuneDown() {
        let hasTuneDown = MIDIMapping.defaults.contains {
            if case .tuneDown = $0.action { return true }
            return false
        }
        XCTAssertTrue(hasTuneDown, "Default mappings should include a tuneDown action")
    }

    func testDefaultMappingsIncludePTT() {
        let hasPTT = MIDIMapping.defaults.contains {
            if case .pttToggle = $0.action { return true }
            return false
        }
        XCTAssertTrue(hasPTT, "Default mappings should include pttToggle")
    }

    func testDefaultMappingsHaveUniqueTriggersPerType() {
        // All CC triggers should have distinct (channel, cc) pairs
        let ccTriggers = MIDIMapping.defaults.compactMap { m -> (Int, Int)? in
            if case .cc(let ch, let cc) = m.trigger { return (ch, cc) }
            return nil
        }
        XCTAssertEqual(ccTriggers.count, Set(ccTriggers.map { "\($0.0):\($0.1)" }).count,
                       "Duplicate CC triggers in defaults")
    }

    // MARK: - Lookup helper

    func testLookupFindsMatchingMapping() {
        let mappings = [
            MIDIMapping(trigger: .cc(channel: 1, cc: 7),  action: .tuneUp(hz: 500)),
            MIDIMapping(trigger: .cc(channel: 1, cc: 11), action: .tuneDown(hz: 500)),
        ]
        let found = MIDIMapping.lookup(trigger: .cc(channel: 1, cc: 7), in: mappings)
        XCTAssertNotNil(found)
        if case .tuneUp(let hz) = found?.action { XCTAssertEqual(hz, 500) }
        else { XCTFail("Wrong action") }
    }

    func testLookupReturnsNilForNoMatch() {
        let mappings = [MIDIMapping(trigger: .cc(channel: 1, cc: 7), action: .pttToggle)]
        XCTAssertNil(MIDIMapping.lookup(trigger: .cc(channel: 1, cc: 99), in: mappings))
    }

    func testLookupReturnsFirstMatch() {
        let mappings = [
            MIDIMapping(trigger: .cc(channel: 1, cc: 7), action: .tuneUp(hz: 100)),
            MIDIMapping(trigger: .cc(channel: 1, cc: 7), action: .tuneUp(hz: 500)),
        ]
        let found = MIDIMapping.lookup(trigger: .cc(channel: 1, cc: 7), in: mappings)
        if case .tuneUp(let hz) = found?.action { XCTAssertEqual(hz, 100) }
        else { XCTFail("Should return first match") }
    }
}
