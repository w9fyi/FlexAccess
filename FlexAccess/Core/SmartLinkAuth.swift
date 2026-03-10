//
//  SmartLinkAuth.swift
//  FlexAccess
//
//  Auth0 ROPC login for FlexRadio SmartLink (frtest.auth0.com).
//  id_token kept in memory; refresh_token stored in iCloud Keychain.
//

import Foundation
#if os(iOS)
import UIKit
#endif

enum SmartLinkAuthError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case missingToken(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidResponse:          return "Invalid response from SmartLink auth server"
        case .httpError(let c, let m):  return "Auth error \(c): \(m)"
        case .missingToken(let k):      return "Auth response missing field: \(k)"
        case .noRefreshToken:           return "No saved SmartLink credentials — please sign in"
        }
    }
}

@MainActor
final class SmartLinkAuth: ObservableObject {
    static let shared = SmartLinkAuth()

    @Published private(set) var isSignedIn = false
    @Published private(set) var email: String = ""

    private(set) var idToken: String = ""

    private let auth0Domain = "https://frtest.auth0.com"
    private let clientID    = "4Y9fEIIsVYyQo5u6jr7yBWc4lV5ugC2m"

    private init() {
        email     = FlexSettings.loadSmartLinkEmail() ?? ""
        isSignedIn = FlexSettings.loadSmartLinkRefreshToken() != nil
    }

    func login(email: String, password: String) async throws -> String {
        let token = try await fetchToken(email: email, password: password)
        self.email = email
        self.idToken = token.idToken
        FlexSettings.saveSmartLinkEmail(email)
        FlexSettings.saveSmartLinkRefreshToken(token.refreshToken)
        isSignedIn = true
        AppFileLogger.shared.log("SmartLinkAuth: signed in as \(email)")
        return token.idToken
    }

    func refreshIfNeeded() async throws -> String {
        guard let refreshToken = FlexSettings.loadSmartLinkRefreshToken() else {
            throw SmartLinkAuthError.noRefreshToken
        }
        let newToken = try await fetchRefreshedToken(using: refreshToken)
        self.idToken = newToken
        AppFileLogger.shared.log("SmartLinkAuth: token refreshed")
        return newToken
    }

    func logout() {
        FlexSettings.deleteSmartLinkRefreshToken()
        FlexSettings.saveSmartLinkEmail("")
        idToken = ""; email = ""; isSignedIn = false
        AppFileLogger.shared.log("SmartLinkAuth: signed out")
    }

    func ensureValidToken() async throws -> String {
        if !idToken.isEmpty { return idToken }
        return try await refreshIfNeeded()
    }

    // MARK: Private

    private struct TokenResponse { let idToken: String; let refreshToken: String }

    private func fetchToken(email: String, password: String) async throws -> TokenResponse {
        let url = URL(string: "\(auth0Domain)/oauth/ro")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id":  clientID,
            "connection": "Username-Password-Authentication",
            "device":     deviceName(),
            "grant_type": "password",
            "username":   email,
            "password":   password,
            "scope":      "openid offline_access email given_name family_name picture"
        ]
        req.httpBody = try JSONEncoder().encode(body)
        return try await performTokenRequest(req)
    }

    private func fetchRefreshedToken(using refreshToken: String) async throws -> String {
        let url = URL(string: "\(auth0Domain)/delegation")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id":     clientID,
            "grant_type":    "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "refresh_token": refreshToken,
            "scope":         "openid"
        ]
        req.httpBody = try JSONEncoder().encode(body)
        return try await performTokenRequest(req).idToken
    }

    private func performTokenRequest(_ req: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw SmartLinkAuthError.httpError(http.statusCode, msg)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw SmartLinkAuthError.missingToken("id_token")
        }
        let rt = (json["refresh_token"] as? String) ?? FlexSettings.loadSmartLinkRefreshToken() ?? ""
        return TokenResponse(idToken: idToken, refreshToken: rt)
    }

    private func deviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }
}
