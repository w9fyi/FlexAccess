//
//  MIDIEngine.swift
//  FlexAccess
//
//  CoreMIDI input listener.  Receives MIDI events from any connected source,
//  matches them against a mapping table, and fires the mapped radio action.
//
//  Architecture:
//    - MIDIEngine owns the CoreMIDI client and input port.
//    - Radio creates a MIDIEngine, passes its mapping list, and wires
//      onAction to dispatch radio commands.
//    - The engine can be started/stopped independently of the radio connection.
//

import Foundation
import CoreMIDI

@Observable
@MainActor
final class MIDIEngine {

    // MARK: - Public state

    var isActive:      Bool   = false
    var lastEventDesc: String = ""   // human-readable last event (for UI/debug)

    var mappings: [MIDIMapping] = MIDIMapping.defaults

    /// Called on MainActor when a mapped action fires.
    var onAction: ((MIDIAction) -> Void)?

    // MARK: - CoreMIDI internals

    private var client:    MIDIClientRef    = 0
    private var inputPort: MIDIPortRef      = 0

    // MARK: - Start / Stop

    func start() {
        guard !isActive else { return }

        var status = MIDIClientCreateWithBlock(
            "FlexAccess" as CFString, &client
        ) { [weak self] notification in
            // MIDI setup changed (sources added/removed) — handle on main actor
            Task { @MainActor [weak self] in
                self?.setupInputPort()
            }
        }
        guard status == noErr else {
            lastEventDesc = "MIDI client error \(status)"
            return
        }

        status = MIDIInputPortCreateWithProtocol(
            client, "FlexAccess Input" as CFString,
            MIDIProtocolID._1_0, &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            // Callback fires on a CoreMIDI thread — hop to main actor
            let events = Self.extractEvents(eventList)
            Task { @MainActor [weak self] in
                self?.handle(events: events)
            }
        }
        guard status == noErr else {
            lastEventDesc = "MIDI port error \(status)"
            return
        }

        isActive = true
        setupInputPort()
    }

    func stop() {
        guard isActive else { return }
        if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
        if client    != 0 { MIDIClientDispose(client);  client    = 0 }
        isActive = false
    }

    // MARK: - Source wiring

    private func setupInputPort() {
        guard inputPort != 0 else { return }
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, src, nil)
        }
    }

    // MARK: - Event extraction (nonisolated — called from CoreMIDI thread)

    private nonisolated static func extractEvents(
        _ eventList: UnsafePointer<MIDIEventList>
    ) -> [(type: UInt8, channel: Int, data1: Int, data2: Int)] {

        var results: [(UInt8, Int, Int, Int)] = []
        let numPackets = Int(eventList.pointee.numPackets)
        guard numPackets > 0 else { return results }

        // MIDIEventList C layout: protocol(UInt32, 4 bytes) + numPackets(UInt32, 4 bytes)
        // then MIDIEventPacket[] starts at offset 8.
        var packetPtr = (UnsafeMutableRawPointer(mutating: UnsafeRawPointer(eventList)) + 8)
            .assumingMemoryBound(to: MIDIEventPacket.self)

        for _ in 0..<numPackets {
            let wordCount = Int(packetPtr.pointee.wordCount)
            // Access words tuple as contiguous UInt32 buffer via raw bytes
            withUnsafeBytes(of: packetPtr.pointee.words) { raw in
                let wordBuffer = raw.bindMemory(to: UInt32.self)
                for w in 0..<Swift.min(wordCount, wordBuffer.count) {
                    let word = wordBuffer[w]
                    let msgType = UInt8((word >> 28) & 0x0F)
                    // Only handle UMP type 2 (MIDI 1.0 channel voice)
                    guard msgType == 0x02 else { continue }
                    let status  = UInt8((word >> 16) & 0xFF)
                    let data1   = Int((word >> 8) & 0x7F)
                    let data2   = Int(word & 0x7F)
                    let kind    = status & 0xF0
                    let channel = Int(status & 0x0F) + 1   // 1-based
                    results.append((kind, channel, data1, data2))
                }
            }
            packetPtr = MIDIEventPacketNext(packetPtr)
        }
        return results
    }

    // MARK: - Dispatch

    private func handle(events: [(type: UInt8, channel: Int, data1: Int, data2: Int)]) {
        for event in events {
            let trigger: MIDITrigger
            switch event.type {
            case 0x90 where event.data2 > 0:   // note on
                trigger = .note(channel: event.channel, note: event.data1)
                lastEventDesc = "Note On ch\(event.channel) note\(event.data1) vel\(event.data2)"
            case 0xB0:   // CC
                trigger = .cc(channel: event.channel, cc: event.data1)
                lastEventDesc = "CC ch\(event.channel) #\(event.data1) val\(event.data2)"
            default:
                continue
            }
            if let mapping = MIDIMapping.lookup(trigger: trigger, in: mappings) {
                onAction?(mapping.action)
            }
        }
    }

    nonisolated deinit {}
}
