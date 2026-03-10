//
//  MIDIMapping.swift
//  FlexAccess
//
//  Pure-Swift MIDI mapping model — no CoreMIDI dependency.
//  A MIDIMapping binds a MIDITrigger (channel + CC or note number)
//  to a MIDIAction (radio command).
//

import Foundation

// MARK: - Trigger

enum MIDITrigger: Codable, Equatable, Hashable {
    case cc(channel: Int, cc: Int)
    case note(channel: Int, note: Int)

    /// True if this trigger matches the given channel and CC/note number.
    func matches(channel: Int, ccOrNote: Int) -> Bool {
        switch self {
        case .cc(let ch, let n):   return ch == channel && n == ccOrNote
        case .note(let ch, let n): return ch == channel && n == ccOrNote
        }
    }

    var displayName: String {
        switch self {
        case .cc(let ch, let n):   return "Ch\(ch) CC\(n)"
        case .note(let ch, let n): return "Ch\(ch) Note\(n)"
        }
    }
}

// MARK: - Action

enum MIDIAction: Codable, Equatable, Hashable {
    case tuneUp(hz: Int)
    case tuneDown(hz: Int)
    case pttToggle
    case cwMacro(index: Int)
    case setMode(FlexMode)
    case nrToggle
    case bandUp
    case bandDown
    case memoryTune(id: Int)

    var displayName: String {
        switch self {
        case .tuneUp(let hz):     return "Tune +\(stepLabel(hz))"
        case .tuneDown(let hz):   return "Tune −\(stepLabel(hz))"
        case .pttToggle:          return "PTT Toggle"
        case .cwMacro(let i):     return "CW Macro \(i + 1)"
        case .setMode(let m):     return "Mode → \(m.label)"
        case .nrToggle:           return "NR Toggle"
        case .bandUp:             return "Band Up"
        case .bandDown:           return "Band Down"
        case .memoryTune(let id): return "Memory \(id)"
        }
    }

    private func stepLabel(_ hz: Int) -> String {
        hz >= 1_000 ? "\(hz / 1_000)kHz" : "\(hz)Hz"
    }
}

// MARK: - Mapping

struct MIDIMapping: Codable, Equatable, Identifiable {
    let id: UUID
    var trigger: MIDITrigger
    var action:  MIDIAction
    var label:   String   // user-editable description

    init(trigger: MIDITrigger, action: MIDIAction, label: String = "") {
        self.id      = UUID()
        self.trigger = trigger
        self.action  = action
        self.label   = label.isEmpty ? action.displayName : label
    }

    // MARK: - Lookup

    /// Return the first mapping whose trigger matches, or nil.
    static func lookup(trigger: MIDITrigger, in mappings: [MIDIMapping]) -> MIDIMapping? {
        mappings.first { $0.trigger == trigger }
    }

    // MARK: - Defaults

    /// Sensible defaults for a generic MIDI controller (e.g. Lynovations CTR2 or any knob box).
    /// Channel 1; CC 1=encoder clockwise, CC 2=encoder counter-clockwise,
    /// notes 36–40 = buttons 1–5.
    static let defaults: [MIDIMapping] = [
        MIDIMapping(trigger: .cc(channel: 1, cc: 1),   action: .tuneUp(hz: 100),    label: "Encoder CW → Tune +100 Hz"),
        MIDIMapping(trigger: .cc(channel: 1, cc: 2),   action: .tuneDown(hz: 100),  label: "Encoder CCW → Tune −100 Hz"),
        MIDIMapping(trigger: .note(channel: 1, note: 36), action: .pttToggle,        label: "Button 1 → PTT"),
        MIDIMapping(trigger: .note(channel: 1, note: 37), action: .cwMacro(index: 0),label: "Button 2 → CW Macro 1"),
        MIDIMapping(trigger: .note(channel: 1, note: 38), action: .cwMacro(index: 1),label: "Button 3 → CW Macro 2"),
        MIDIMapping(trigger: .note(channel: 1, note: 39), action: .bandUp,           label: "Button 4 → Band Up"),
        MIDIMapping(trigger: .note(channel: 1, note: 40), action: .bandDown,         label: "Button 5 → Band Down"),
        MIDIMapping(trigger: .cc(channel: 1, cc: 3),   action: .tuneUp(hz: 1_000),  label: "Fast Encoder CW → +1 kHz"),
        MIDIMapping(trigger: .cc(channel: 1, cc: 4),   action: .tuneDown(hz: 1_000),label: "Fast Encoder CCW → −1 kHz"),
        MIDIMapping(trigger: .note(channel: 1, note: 41), action: .nrToggle,         label: "Button 6 → NR Toggle"),
    ]
}
