//
//  MemoryView.swift
//  FlexAccess
//
//  Frequency memory browser — grouped by band, tap to tune active slice.
//  VoiceOver-first: each row announces frequency and mode, with a "Tune"
//  custom action so VO users don't need to navigate to a separate button.
//

import SwiftUI

struct MemoryView: View {
    @Bindable var radio: Radio

    /// All memories, optionally merged with user-saved extras (future extension).
    @State private var memories: [FrequencyMemory] = FrequencyMemory.defaults
    @State private var showAddSheet = false
    @State private var searchText  = ""

    private var filtered: [FrequencyMemory] {
        guard !searchText.isEmpty else { return memories }
        let q = searchText.lowercased()
        return memories.filter {
            $0.label.lowercased().contains(q) ||
            $0.band.lowercased().contains(q)  ||
            $0.notes.lowercased().contains(q)
        }
    }

    private var byBand: [(band: String, items: [FrequencyMemory])] {
        let order = ["160m","80m","60m","40m","30m","20m","17m","15m","12m","10m","6m","2m","1.25m","70cm","?"]
        let groups = Dictionary(grouping: filtered) { $0.band }
        return order.compactMap { band -> (String, [FrequencyMemory])? in
            guard let items = groups[band], !items.isEmpty else { return nil }
            return (band, items.sorted { $0.frequencyHz < $1.frequencyHz })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search memories…", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search memories")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)

            if radio.connectionStatus != .connected {
                Spacer()
                Text("Connect to a radio to tune memories.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(byBand, id: \.band) { group in
                        Section(group.band) {
                            ForEach(group.items) { memory in
                                MemoryRow(memory: memory, radio: radio)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Row

private struct MemoryRow: View {
    let memory: FrequencyMemory
    let radio:  Radio

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.label)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(memory.formattedFrequency)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(memory.mode.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !memory.notes.isEmpty {
                        Text(memory.notes)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button("Tune") { tune() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHidden(true)   // exposed via custom action below
        }
        .contentShape(Rectangle())
        .onTapGesture { tune() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Tune") { tune() }
    }

    private var accessibilityLabel: String {
        var parts = [memory.label, memory.formattedFrequency, memory.mode.label]
        if !memory.notes.isEmpty { parts.append(memory.notes) }
        return parts.joined(separator: ", ")
    }

    private func tune() {
        guard let slice = radio.activeSlice else { return }
        radio.tune(sliceIndex: slice.id, hz: memory.frequencyHz)
        radio.setMode(sliceIndex: slice.id, mode: memory.mode)
    }
}
