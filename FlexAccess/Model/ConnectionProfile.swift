//
//  ConnectionProfile.swift
//  FlexAccess
//
//  Saved connection profile — label, host, port — with UserDefaults persistence.
//

import Foundation

// MARK: - ConnectionProfile

struct ConnectionProfile: Identifiable, Codable, Equatable {

    var id: UUID
    var label: String
    var host: String
    var port: Int

    init(label: String, host: String, port: Int = 4992) {
        self.id    = UUID()
        self.label = label
        self.host  = host
        self.port  = port
    }

    /// Primary display name — label if non-empty, otherwise "host:port".
    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "\(host):\(port)" : trimmed
    }

    /// Secondary line — "host:port" when label is set, empty string otherwise.
    var subtitle: String {
        label.isEmpty ? "" : "\(host):\(port)"
    }
}

// MARK: - ConnectionProfileStore

/// In-memory + UserDefaults-backed store for connection profiles.
@Observable
final class ConnectionProfileStore {

    private static let defaultsKey = "flexaccess.connectionProfiles"

    private(set) var profiles: [ConnectionProfile] = []

    init() {
        load()
    }

    // MARK: Mutations

    func add(_ profile: ConnectionProfile) {
        profiles.append(profile)
        save()
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    func delete(at offsets: IndexSet) {
        for i in offsets.sorted().reversed() {
            profiles.remove(at: i)
        }
        save()
    }

    func update(_ profile: ConnectionProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func deleteAll() {
        profiles.removeAll()
        save()
    }

    // MARK: Persistence

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
        else { return }
        profiles = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
