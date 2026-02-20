//
//  ConnectionSectionView.swift
//  FlexAccess
//
//  Shows discovered LAN radios and SmartLink (WAN) radios in separate tabs.
//  Tap a radio to connect. Manual IP entry fallback. Shows connection status and errors.
//

import SwiftUI

struct ConnectionSectionView: View {
    @ObservedObject var radio: FlexRadioState
    @ObservedObject var discovery: FlexDiscovery

    @State private var manualHost: String = FlexSettings.loadLastLocalIP() ?? ""
    @State private var manualPort: String = String(FlexSettings.loadLastLocalPort())
    @State private var connectionTab: Int = 0  // 0=Local, 1=SmartLink

    @State private var smartLinkEmail: String = FlexSettings.loadSmartLinkEmail() ?? ""
    @State private var smartLinkPassword: String = ""
    @State private var smartLinkError: String? = nil
    @State private var smartLinkSigningIn: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connection")
                    .font(.title2)

                Picker("Connection Type", selection: $connectionTab) {
                    Text("Local").tag(0)
                    Text("SmartLink").tag(1)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Connection type: Local or SmartLink")

                if connectionTab == 0 {
                    localSection
                } else {
                    smartLinkSection
                }

                Divider()
                statusSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    // MARK: Local tab

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovered Radios")
                .font(.headline)

            if discovery.radios.filter({ $0.source == .local || $0.source == .direct }).isEmpty {
                Text("Scanning for FlexRadio on LAN…")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ForEach(discovery.radios.filter { $0.source == .local || $0.source == .direct }) { r in
                    radioRow(r)
                }
            }

            Divider()

            Text("Manual Entry")
                .font(.headline)

            HStack(spacing: 12) {
                Text("Host/IP:")
                TextField("192.168.1.x", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                    .accessibilityLabel("Radio IP address")

                Text("Port:")
                TextField("4992", text: $manualPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .accessibilityLabel("TCP port")
            }

            Button("Connect to Manual IP") {
                let port = Int(manualPort) ?? 4992
                radio.connect(host: manualHost, port: port)
            }
            .accessibilityHint("Connects directly to the entered IP and port")
        }
    }

    // MARK: SmartLink tab

    private var smartLinkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if radio.smartLinkAuth.isSignedIn {
                signedInView
            } else {
                signInForm
            }

            if !discovery.radios.filter({ $0.source == .smartlink }).isEmpty {
                Divider()
                Text("SmartLink Radios")
                    .font(.headline)
                ForEach(discovery.radios.filter { $0.source == .smartlink }) { r in
                    radioRow(r)
                }
            }
        }
    }

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Signed in as \(radio.smartLinkAuth.email)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Sign Out") {
                radio.smartLinkAuth.logout()
                discovery.radios.filter { $0.source == .smartlink }.forEach {
                    discovery.removeSmartLinkRadio(serial: $0.id)
                }
            }
            .accessibilityHint("Signs out of SmartLink and removes remote radios")
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to your FlexRadio Community account to access your radio remotely.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Email:")
                TextField("you@example.com", text: $smartLinkEmail)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                    .accessibilityLabel("SmartLink email address")
            }

            HStack(spacing: 12) {
                Text("Password:")
                SecureField("Password", text: $smartLinkPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                    .accessibilityLabel("SmartLink password")
            }

            if let err = smartLinkError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .accessibilityLabel("SmartLink error: \(err)")
            }

            Button(smartLinkSigningIn ? "Signing in…" : "Sign In") {
                Task { await signInToSmartLink() }
            }
            .disabled(smartLinkSigningIn || smartLinkEmail.isEmpty || smartLinkPassword.isEmpty)
            .accessibilityHint("Signs in to SmartLink and loads your remote radios")
        }
    }

    // MARK: Radio row

    private func radioRow(_ r: DiscoveredRadio) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.displayName)
                    .font(.body)
                Text("\(r.ip)  v\(r.version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect") { radio.connect(to: r) }
                .accessibilityLabel("Connect to \(r.displayName)")
        }
        .padding(.vertical, 4)
    }

    // MARK: Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Status: \(radio.connectionStatus)")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Button("Disconnect") { radio.disconnect() }
                    .disabled(radio.connectionStatus == "Disconnected")
            }

            if let err = radio.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Connection error: \(err)")
            }
        }
    }

    // MARK: SmartLink sign-in

    private func signInToSmartLink() async {
        smartLinkError = nil
        smartLinkSigningIn = true
        defer { smartLinkSigningIn = false }
        do {
            _ = try await radio.smartLinkAuth.login(email: smartLinkEmail, password: smartLinkPassword)
            smartLinkPassword = ""
        } catch {
            smartLinkError = error.localizedDescription
        }
    }
}
