//
//  FlexKeychainStore.swift
//  FlexAccess
//

import Foundation
import Security

enum KeychainScope { case local, iCloud }

enum FlexKeychainStore {

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        var errorDescription: String? {
            if case .unexpectedStatus(let s) = self { return "Keychain error: \(s)" }
            return nil
        }
    }

    static func set(_ value: String, service: String, account: String, scope: KeychainScope) throws {
        let data = value.data(using: .utf8)!
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if scope == .iCloud { query[kSecAttrSynchronizable] = kCFBooleanTrue }
        SecItemDelete(query as CFDictionary)
        query[kSecValueData] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func get(service: String, account: String, scope: KeychainScope) throws -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if scope == .iCloud { query[kSecAttrSynchronizable] = kCFBooleanTrue }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String, scope: KeychainScope) throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if scope == .iCloud { query[kSecAttrSynchronizable] = kCFBooleanTrue }
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
