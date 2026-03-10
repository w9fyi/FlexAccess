//
//  FlexSettings.swift
//  FlexAccess
//

import Foundation

enum FlexSettings {

    private static let lastSerialKey     = "FA2.LastSerial"
    private static let lastLocalIPKey    = "FA2.LastLocalIP"
    private static let lastLocalPortKey  = "FA2.LastLocalPort"
    private static let smartLinkEmailKey = "FA2.SmartLinkEmail"
    private static let nrBackendKey      = "FA2.NRBackend"
    private static let nrEnabledKey      = "FA2.NREnabled"
    private static let audioOutputUIDKey = "FA2.AudioOutputUID"
    private static let audioInputUIDKey  = "FA2.AudioInputUID"

    private static let slService = "FlexAccess.SmartLink"
    private static let slAccount = "refreshToken"

    // MARK: Last connected radio

    static func saveLastSerial(_ serial: String) { UserDefaults.standard.set(serial, forKey: lastSerialKey) }
    static func loadLastSerial() -> String? { UserDefaults.standard.string(forKey: lastSerialKey) }

    static func saveLastLocalRadio(ip: String, port: Int) {
        UserDefaults.standard.set(ip,   forKey: lastLocalIPKey)
        UserDefaults.standard.set(port, forKey: lastLocalPortKey)
    }
    static func loadLastLocalIP() -> String? { UserDefaults.standard.string(forKey: lastLocalIPKey) }
    static func loadLastLocalPort() -> Int {
        let v = UserDefaults.standard.integer(forKey: lastLocalPortKey)
        return v == 0 ? 4992 : v
    }

    // MARK: SmartLink

    static func saveSmartLinkEmail(_ e: String) { UserDefaults.standard.set(e, forKey: smartLinkEmailKey) }
    static func loadSmartLinkEmail() -> String? { UserDefaults.standard.string(forKey: smartLinkEmailKey) }

    static func saveSmartLinkRefreshToken(_ token: String) {
        do { try FlexKeychainStore.set(token, service: slService, account: slAccount, scope: .iCloud) }
        catch { AppFileLogger.shared.log("FlexSettings: save refreshToken failed: \(error)") }
    }
    static func loadSmartLinkRefreshToken() -> String? {
        do { return try FlexKeychainStore.get(service: slService, account: slAccount, scope: .iCloud) }
        catch { AppFileLogger.shared.log("FlexSettings: load refreshToken failed: \(error)"); return nil }
    }
    static func deleteSmartLinkRefreshToken() {
        do { try FlexKeychainStore.delete(service: slService, account: slAccount, scope: .iCloud) }
        catch { AppFileLogger.shared.log("FlexSettings: delete refreshToken failed: \(error)") }
    }

    // MARK: Audio

    static func saveAudioOutputUID(_ uid: String) { UserDefaults.standard.set(uid, forKey: audioOutputUIDKey) }
    static func loadAudioOutputUID() -> String { UserDefaults.standard.string(forKey: audioOutputUIDKey) ?? "" }
    static func saveAudioInputUID(_ uid: String) { UserDefaults.standard.set(uid, forKey: audioInputUIDKey) }
    static func loadAudioInputUID() -> String { UserDefaults.standard.string(forKey: audioInputUIDKey) ?? "" }

    // MARK: Noise reduction

    static func saveNRBackend(_ name: String) { UserDefaults.standard.set(name, forKey: nrBackendKey) }
    static func loadNRBackend() -> String? { UserDefaults.standard.string(forKey: nrBackendKey) }
    static func saveNREnabled(_ v: Bool) { UserDefaults.standard.set(v, forKey: nrEnabledKey) }
    static func loadNREnabled() -> Bool { UserDefaults.standard.bool(forKey: nrEnabledKey) }
}
