//
//  QSOLog.swift
//  FlexAccess
//
//  Observable QSO log — owns the entry list, handles persistence, and
//  provides ADIF export.  Entries are kept newest-first.
//

import Foundation

@Observable
@MainActor
final class QSOLog {

    // MARK: - State

    private(set) var entries: [QSOEntry] = []

    // MARK: - UserDefaults key

    private static let storageKey = "com.w9fyi.flexaccess.qsolog"

    // MARK: - Init

    init() { load() }

    // MARK: - Mutations

    func add(_ entry: QSOEntry) {
        entries.insert(entry, at: 0)   // newest first
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Export

    /// ADIF string for all logged contacts (newest first).
    var adifText: String { QSOEntry.adifExport(entries) }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([QSOEntry].self, from: data)
        else { return }
        entries = saved
    }

    nonisolated deinit {}
}
