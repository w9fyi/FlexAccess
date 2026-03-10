//
//  LogView.swift
//  FlexAccess
//
//  QSO log — shows logged contacts, add new entry, export ADIF.
//  VoiceOver-first: rows use accessibilityLabel with all key fields,
//  and the Add sheet uses labeled fields throughout.
//

import SwiftUI

struct LogView: View {
    @Bindable var radio: Radio
    @State private var log = QSOLog()

    @State private var showAddSheet  = false
    @State private var showExport    = false
    @State private var exportText    = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar row
            HStack {
                Text("\(log.entries.count) contact\(log.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showExport = true } label: {
                    Label("Export ADIF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(log.entries.isEmpty)
                .accessibilityLabel("Export log as ADIF")

                Button { showAddSheet = true } label: {
                    Label("Log QSO", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Log a new QSO")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if log.entries.isEmpty {
                Spacer()
                Text("No contacts logged yet.")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(log.entries) { entry in
                        LogRow(entry: entry)
                    }
                    .onDelete { offsets in log.delete(at: offsets) }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddQSOSheet(radio: radio, log: log)
        }
        .sheet(isPresented: $showExport) {
            ADIFExportSheet(adif: log.adifText)
        }
    }
}

// MARK: - Log row

private struct LogRow: View {
    let entry: QSOEntry

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.timeZone  = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.callsign)
                    .font(.body.bold())
                Spacer()
                Text(Self.displayFormatter.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(entry.band)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.mode.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("S:\(entry.sentRST) R:\(entry.rcvdRST)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [entry.callsign, entry.band, entry.mode.label,
                     "sent \(entry.sentRST)", "received \(entry.rcvdRST)"]
        if !entry.notes.isEmpty { parts.append(entry.notes) }
        parts.append(Self.displayFormatter.string(from: entry.date) + " UTC")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Add QSO sheet

private struct AddQSOSheet: View {
    let radio: Radio
    let log:   QSOLog
    @Environment(\.dismiss) private var dismiss

    @State private var callsign = ""
    @State private var sentRST  = "59"
    @State private var rcvdRST  = "59"
    @State private var notes    = ""

    // Pre-fill from active slice
    private var sliceFreq: Int   { radio.activeSlice?.frequencyHz ?? 14_225_000 }
    private var sliceMode: FlexMode { radio.activeSlice?.mode ?? .usb }

    private var isValid: Bool { !callsign.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    LabeledContent("Callsign") {
                        TextField("Required", text: $callsign)
                            .textInputAutocapitalization(.characters)
                            .accessibilityLabel("Callsign")
                    }
                    LabeledContent("RST Sent") {
                        TextField("59", text: $sentRST)
                            .accessibilityLabel("RST sent")
                    }
                    LabeledContent("RST Rcvd") {
                        TextField("59", text: $rcvdRST)
                            .accessibilityLabel("RST received")
                    }
                }

                Section("Radio (from active slice)") {
                    LabeledContent("Frequency") {
                        Text(String(format: "%.3f MHz", Double(sliceFreq) / 1_000_000))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Mode") {
                        Text(sliceMode.label).foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityLabel("Notes")
                }
            }
            .navigationTitle("Log QSO")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 400)
    }

    private func save() {
        let entry = QSOEntry(
            callsign:    callsign.uppercased().trimmingCharacters(in: .whitespaces),
            frequencyHz: sliceFreq,
            mode:        sliceMode,
            sentRST:     sentRST,
            rcvdRST:     rcvdRST,
            notes:       notes
        )
        log.add(entry)
        dismiss()
    }
}

// MARK: - ADIF export sheet

private struct ADIFExportSheet: View {
    let adif: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(adif)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("ADIF Export")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    ShareLink(item: adif, subject: Text("FlexAccess Log"),
                              message: Text("QSO log exported from FlexAccess"))
                        .accessibilityLabel("Share ADIF log")
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
