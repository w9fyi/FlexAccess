//
//  FlexSettings.swift
//  FlexAccess
//
//  Persists non-sensitive settings to UserDefaults and SmartLink credentials
//  to iCloud Keychain so they roam across Mac/iPad/iPhone.
//

import Foundation

enum FlexSettings {

    // MARK: UserDefaults keys

    private static let lastSerialKey     = "FlexAccess.LastSerial"
    private static let lastLocalIPKey    = "FlexAccess.LastLocalIP"
    private static let lastLocalPortKey  = "FlexAccess.LastLocalPort"
    private static let smartLinkEmailKey = "FlexAccess.SmartLinkEmail"

    // MARK: SmartLink Keychain

    private static let slService = "FlexAccess.SmartLink"
    private static let slAccount = "refreshToken"

    // MARK: Local radio

    static func saveLastLocalRadio(ip: String, port: Int) {
        UserDefaults.standard.set(ip, forKey: lastLocalIPKey)
        UserDefaults.standard.set(port, forKey: lastLocalPortKey)
    }

    static func loadLastLocalIP() -> String? {
        UserDefaults.standard.string(forKey: lastLocalIPKey)
    }

    static func loadLastLocalPort() -> Int {
        UserDefaults.standard.integer(forKey: lastLocalPortKey).nonZero ?? 4992
    }

    static func saveLastSerial(_ serial: String) {
        UserDefaults.standard.set(serial, forKey: lastSerialKey)
    }

    static func loadLastSerial() -> String? {
        UserDefaults.standard.string(forKey: lastSerialKey)
    }

    // MARK: SmartLink email (non-sensitive, display only)

    static func saveSmartLinkEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: smartLinkEmailKey)
    }

    static func loadSmartLinkEmail() -> String? {
        UserDefaults.standard.string(forKey: smartLinkEmailKey)
    }

    // MARK: SmartLink refresh_token (iCloud Keychain — roams across devices)

    static func saveSmartLinkRefreshToken(_ token: String) {
        do {
            try FlexKeychainStore.set(token, service: slService, account: slAccount, scope: .iCloud)
        } catch {
            AppFileLogger.shared.log("FlexSettings: failed to save refresh_token: \(error)")
        }
    }

    static func loadSmartLinkRefreshToken() -> String? {
        do {
            return try FlexKeychainStore.get(service: slService, account: slAccount, scope: .iCloud)
        } catch {
            AppFileLogger.shared.log("FlexSettings: failed to load refresh_token: \(error)")
            return nil
        }
    }

    static func deleteSmartLinkRefreshToken() {
        do {
            try FlexKeychainStore.delete(service: slService, account: slAccount, scope: .iCloud)
        } catch {
            AppFileLogger.shared.log("FlexSettings: failed to delete refresh_token: \(error)")
        }
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
