import SwiftUI

/// SmartLink login + app preferences.
struct SettingsView: View {
    @Bindable var radio: Radio
    @ObservedObject var smartLinkAuth = SmartLinkAuth.shared

    @State private var email    = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var loginError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // SmartLink Auth
                GroupBox("SmartLink (Remote Access)") {
                    VStack(alignment: .leading, spacing: 10) {
                        if smartLinkAuth.isSignedIn {
                            HStack {
                                Label("Signed in as \(smartLinkAuth.email)",
                                      systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                                Button("Sign Out") { smartLinkAuth.logout() }
                                    .accessibilityLabel("Sign out of SmartLink")
                            }
                        } else {
                            Text("Sign in to connect to your radio remotely over SmartLink.")
                                .font(.callout).foregroundStyle(.secondary)

                            TextField("Email", text: $email)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("SmartLink email address")
                            #if os(macOS)
                                .textContentType(.emailAddress)
                            #endif

                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("SmartLink password")

                            if let error = loginError {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red).font(.callout)
                                    .accessibilityLabel("Login error: \(error)")
                            }

                            HStack {
                                Button(isLoggingIn ? "Signing in…" : "Sign In") {
                                    Task { await loginToSmartLink() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(email.isEmpty || password.isEmpty || isLoggingIn)
                                .accessibilityLabel("Sign in to SmartLink")
                            }
                        }
                    }
                    .padding(4)
                }

                // About
                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FlexAccess")
                            .font(.headline)
                        Text("For FlexRadio 6000 and 8000 series.")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("SmartSDR API — LAN and SmartLink.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(4)
                    .accessibilityElement(children: .combine)
                }

                // Log
                GroupBox("Connection Log") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Spacer()
                            Button("Clear") { radio.clearLog() }
                                .controlSize(.small)
                                .accessibilityLabel("Clear connection log")
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(radio.connectionLog.suffix(50), id: \.self) { line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                    .padding(4)
                    .accessibilityHidden(true)
                }
            }
            .padding()
        }
        .onAppear {
            email = smartLinkAuth.email
        }
    }

    private func loginToSmartLink() async {
        isLoggingIn = true
        loginError  = nil
        do {
            _ = try await smartLinkAuth.login(email: email, password: password)
            password = ""
        } catch {
            loginError = error.localizedDescription
        }
        isLoggingIn = false
    }
}
