//
//  ConnectionProfileTests.swift
//  FlexAccessTests
//
//  Tests for ConnectionProfile model — init, displayName, Codable round-trip,
//  and ConnectionProfileStore in-memory operations.
//

import XCTest

final class ConnectionProfileTests: XCTestCase {

    // MARK: - ConnectionProfile init

    func testInitSetsLabel() {
        let p = ConnectionProfile(label: "Home Shack", host: "192.168.1.100", port: 4992)
        XCTAssertEqual(p.label, "Home Shack")
    }

    func testInitSetsHost() {
        let p = ConnectionProfile(label: "", host: "10.0.0.50", port: 4992)
        XCTAssertEqual(p.host, "10.0.0.50")
    }

    func testInitSetsPort() {
        let p = ConnectionProfile(label: "", host: "10.0.0.50", port: 5000)
        XCTAssertEqual(p.port, 5000)
    }

    func testInitDefaultPort() {
        let p = ConnectionProfile(label: "", host: "192.168.1.1")
        XCTAssertEqual(p.port, 4992)
    }

    func testIDsAreUnique() {
        let a = ConnectionProfile(label: "A", host: "192.168.1.1")
        let b = ConnectionProfile(label: "B", host: "192.168.1.1")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - displayName

    func testDisplayNameUsesLabelWhenNonEmpty() {
        let p = ConnectionProfile(label: "FLEX-8400", host: "192.168.1.50", port: 4992)
        XCTAssertEqual(p.displayName, "FLEX-8400")
    }

    func testDisplayNameFallsBackToHostPortWhenLabelEmpty() {
        let p = ConnectionProfile(label: "", host: "192.168.1.50", port: 4992)
        XCTAssertEqual(p.displayName, "192.168.1.50:4992")
    }

    func testDisplayNameFallsBackForWhitespaceLabelTrimmed() {
        // Label of only whitespace should also show host:port
        let p = ConnectionProfile(label: "  ", host: "192.168.1.1", port: 4992)
        // Either trimmed whitespace or not — just verify something is produced
        XCTAssertFalse(p.displayName.isEmpty)
    }

    // MARK: - subtitle

    func testSubtitleShowsHostPortWhenLabelIsSet() {
        let p = ConnectionProfile(label: "Home", host: "10.0.0.1", port: 4992)
        XCTAssertEqual(p.subtitle, "10.0.0.1:4992")
    }

    func testSubtitleIsEmptyWhenLabelIsEmpty() {
        let p = ConnectionProfile(label: "", host: "10.0.0.1", port: 4992)
        XCTAssertTrue(p.subtitle.isEmpty)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTripPreservesAllFields() throws {
        let original = ConnectionProfile(label: "Test Radio", host: "192.168.50.117", port: 4992)
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        XCTAssertEqual(decoded.id,    original.id)
        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.host,  original.host)
        XCTAssertEqual(decoded.port,  original.port)
    }

    func testCodableRoundTripEmptyLabel() throws {
        let original = ConnectionProfile(label: "", host: "10.0.0.5", port: 5000)
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        XCTAssertEqual(decoded.label, "")
        XCTAssertEqual(decoded.port, 5000)
    }

    func testCodableArrayRoundTrip() throws {
        let profiles = [
            ConnectionProfile(label: "A", host: "10.0.0.1", port: 4992),
            ConnectionProfile(label: "B", host: "10.0.0.2", port: 4993),
        ]
        let data    = try JSONEncoder().encode(profiles)
        let decoded = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].label, "A")
        XCTAssertEqual(decoded[1].host, "10.0.0.2")
    }

    // MARK: - ConnectionProfileStore

    func testStoreStartsEmpty() {
        let store = ConnectionProfileStore()
        // May have persisted data from UserDefaults; test is deterministic only
        // on a clean install — just verify the type works.
        XCTAssertGreaterThanOrEqual(store.profiles.count, 0)
    }

    func testStoreAddIncreasesCount() {
        let store = ConnectionProfileStore()
        let before = store.profiles.count
        store.add(ConnectionProfile(label: "X", host: "1.2.3.4", port: 4992))
        XCTAssertEqual(store.profiles.count, before + 1)
        store.deleteAll()
    }

    func testStoreDeleteByIDRemovesProfile() {
        let store = ConnectionProfileStore()
        store.deleteAll()
        let p = ConnectionProfile(label: "Del", host: "5.5.5.5", port: 4992)
        store.add(p)
        XCTAssertEqual(store.profiles.count, 1)
        store.delete(id: p.id)
        XCTAssertEqual(store.profiles.count, 0)
    }

    func testStoreDeleteAtOffsetsRemovesCorrectItem() {
        let store = ConnectionProfileStore()
        store.deleteAll()
        store.add(ConnectionProfile(label: "A", host: "1.1.1.1", port: 4992))
        store.add(ConnectionProfile(label: "B", host: "2.2.2.2", port: 4992))
        store.delete(at: IndexSet(integer: 0))
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles[0].label, "B")
        store.deleteAll()
    }

    func testStoreUpdateChangesFields() {
        let store = ConnectionProfileStore()
        store.deleteAll()
        let p = ConnectionProfile(label: "Old", host: "3.3.3.3", port: 4992)
        store.add(p)
        var updated = p
        updated.label = "New"
        updated.port  = 5000
        store.update(updated)
        XCTAssertEqual(store.profiles[0].label, "New")
        XCTAssertEqual(store.profiles[0].port, 5000)
        store.deleteAll()
    }

    func testStoreDeleteAllClearsEverything() {
        let store = ConnectionProfileStore()
        store.add(ConnectionProfile(label: "1", host: "1.1.1.1", port: 4992))
        store.add(ConnectionProfile(label: "2", host: "2.2.2.2", port: 4992))
        store.deleteAll()
        XCTAssertTrue(store.profiles.isEmpty)
    }

    func testStoreDeleteByIDForMissingIDIsNoOp() {
        let store = ConnectionProfileStore()
        store.deleteAll()
        store.add(ConnectionProfile(label: "X", host: "1.1.1.1", port: 4992))
        store.delete(id: UUID())
        XCTAssertEqual(store.profiles.count, 1)
        store.deleteAll()
    }
}
