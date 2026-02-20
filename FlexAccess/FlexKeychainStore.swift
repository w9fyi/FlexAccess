//
//  FlexKeychainStore.swift
//  FlexAccess
//
//  Keychain CRUD with two modes:
//    .local  — device-only (kSecAttrSynchronizable: false)
//    .iCloud — syncs via iCloud Keychain across Mac/iPad/iPhone (kSecAttrSynchronizable: true)
//             Used for SmartLink refresh_token so users sign in once on any device.
//

import Foundation
import Security

enum FlexKeychainError: LocalizedError {
    case unexpectedData
    case secError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:          return "Unexpected keychain data format"
        case .secError(let s):         return "Keychain error \(s): \(SecCopyErrorMessageString(s, nil) as String? ?? "unknown")"
        }
    }
}

enum FlexKeychainScope {
    case local   // kSecAttrSynchronizable: false
    case iCloud  // kSecAttrSynchronizable: true — roams across devices
}

enum FlexKeychainStore {

    // MARK: Write

    static func set(_ value: String, service: String, account: String, scope: FlexKeychainScope) throws {
        guard let data = value.data(using: .utf8) else { throw FlexKeychainError.unexpectedData }
        let sync = (scope == .iCloud) ? kCFBooleanTrue! : kCFBooleanFalse!

        // Try update first
        let query: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          account,
            kSecAttrSynchronizable as String:   sync,
            kSecUseDataProtectionKeychain as String: true
        ]
        let update: [String: Any] = [
            kSecValueData as String:            data,
            kSecAttrAccessible as String:       kSecAttrAccessibleAfterFirstUnlock
        ]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FlexKeychainError.secError(status) }
    }

    // MARK: Read

    static func get(service: String, account: String, scope: FlexKeychainScope) throws -> String? {
        let sync = (scope == .iCloud) ? kCFBooleanTrue! : kCFBooleanFalse!
        let query: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          account,
            kSecAttrSynchronizable as String:   sync,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String:           true,
            kSecMatchLimit as String:           kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw FlexKeychainError.secError(status) }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw FlexKeychainError.unexpectedData
        }
        return string
    }

    // MARK: Delete

    static func delete(service: String, account: String, scope: FlexKeychainScope) throws {
        let sync = (scope == .iCloud) ? kCFBooleanTrue! : kCFBooleanFalse!
        let query: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          account,
            kSecAttrSynchronizable as String:   sync,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FlexKeychainError.secError(status)
        }
    }
}
