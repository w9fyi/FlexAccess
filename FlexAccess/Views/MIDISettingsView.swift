//
//  MIDISettingsView.swift
//  FlexAccess
//
//  MIDI mapping editor — shows current mappings, lets user edit trigger
//  and action for each, and provides a "Learn" button to capture the
//  next incoming MIDI event as the trigger.
//

import SwiftUI

struct MIDISettingsView: View {
    let radio: Radio

    private var engine: MIDIEngine { radio.midiEngine }

    @State private var learningID:  UUID?   = nil   // mapping being "learned"
    @State private var editingID:   UUID?   = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Engine on/off
            HStack {
                Toggle("Enable MIDI", isOn: Binding(
                    get: { engine.isActive },
                    set: { $0 ? engine.start() : engine.stop() }
                ))
                .accessibilityLabel("Enable MIDI controller input")
                Spacer()
                if engine.isActive {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Active").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !engine.lastEventDesc.isEmpty {
                Text("Last event: \(engine.lastEventDesc)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Last MIDI event: \(engine.lastEventDesc)")
            }

            Divider()

            Text("Mappings").font(.headline)

            // Mapping table
            ForEach(Bindable(engine).mappings) { $mapping in
                MappingRow(
                    mapping: $mapping,
                    isLearning: learningID == mapping.id,
                    onLearn: { startLearn(id: mapping.id) }
                )
            }

            HStack {
                Button("Reset to Defaults") {
                    engine.mappings = MIDIMapping.defaults
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset MIDI mappings to defaults")
                Spacer()
            }
        }
        .padding()
        // When learning, capture the next MIDI event to update the trigger
        .onChange(of: engine.lastEventDesc) { _, desc in
            handleLearnEvent(desc)
        }
    }

    // MARK: - Learn mode

    private func startLearn(id: UUID) {
        learningID = id
    }

    private func handleLearnEvent(_ desc: String) {
        guard let id = learningID else { return }
        // Parse "CC ch1 #7 val64" or "Note On ch1 note60 vel100"
        let trigger: MIDITrigger?
        if desc.hasPrefix("CC") {
            trigger = parseCCDesc(desc)
        } else if desc.hasPrefix("Note On") {
            trigger = parseNoteDesc(desc)
        } else {
            return
        }
        if let t = trigger,
           let idx = engine.mappings.firstIndex(where: { $0.id == id }) {
            engine.mappings[idx].trigger = t
        }
        learningID = nil
    }

    private func parseCCDesc(_ desc: String) -> MIDITrigger? {
        // "CC ch1 #7 val64"
        let parts = desc.split(separator: " ")
        guard parts.count >= 3,
              let ch = Int(parts[1].dropFirst(2)),
              let cc = Int(parts[2].dropFirst(1)) else { return nil }
        return .cc(channel: ch, cc: cc)
    }

    private func parseNoteDesc(_ desc: String) -> MIDITrigger? {
        // "Note On ch1 note60 vel100"
        let parts = desc.split(separator: " ")
        guard parts.count >= 4,
              let ch   = Int(parts[2].dropFirst(2)),
              let note = Int(parts[3].dropFirst(4)) else { return nil }
        return .note(channel: ch, note: note)
    }
}

// MARK: - Mapping row

private struct MappingRow: View {
    @Binding var mapping:  MIDIMapping
    let isLearning: Bool
    let onLearn:    () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Trigger pill
            Button(action: onLearn) {
                Text(isLearning ? "Waiting…" : mapping.trigger.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(isLearning ? Color.orange.opacity(0.3) : Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(minWidth: 90)
            .accessibilityLabel(isLearning
                ? "Waiting for MIDI input — press a control"
                : "Trigger: \(mapping.trigger.displayName). Activate to learn new trigger.")
            .accessibilityAddTraits(.isButton)

            // Action picker
            Picker("", selection: $mapping.action) {
                Text("Tune +100 Hz").tag(MIDIAction.tuneUp(hz: 100))
                Text("Tune +1 kHz").tag(MIDIAction.tuneUp(hz: 1_000))
                Text("Tune −100 Hz").tag(MIDIAction.tuneDown(hz: 100))
                Text("Tune −1 kHz").tag(MIDIAction.tuneDown(hz: 1_000))
                Text("PTT Toggle").tag(MIDIAction.pttToggle)
                Text("CW Macro 1").tag(MIDIAction.cwMacro(index: 0))
                Text("CW Macro 2").tag(MIDIAction.cwMacro(index: 1))
                Text("CW Macro 3").tag(MIDIAction.cwMacro(index: 2))
                Text("Mode USB").tag(MIDIAction.setMode(.usb))
                Text("Mode LSB").tag(MIDIAction.setMode(.lsb))
                Text("Mode CW").tag(MIDIAction.setMode(.cw))
                Text("Mode FM").tag(MIDIAction.setMode(.fm))
                Text("Mode DIGU").tag(MIDIAction.setMode(.digu))
                Text("NR Toggle").tag(MIDIAction.nrToggle)
                Text("Band Up").tag(MIDIAction.bandUp)
                Text("Band Down").tag(MIDIAction.bandDown)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel("Action: \(mapping.action.displayName)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MIDI mapping: \(mapping.trigger.displayName) → \(mapping.action.displayName)")
    }
}
