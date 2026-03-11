import SwiftUI

/// Radio discovery list + connection controls.
struct RadioListView: View {
    @Bindable var radio: Radio
    @ObservedObject var discovery: FlexDiscovery
    let profileStore: ConnectionProfileStore

    @State private var showDirectConnect = false
    @State private var directHost = ""
    @State private var directPort = "4992"
    @State private var profileLabel = ""
    @State private var showSaveConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Connection status / disconnect button
                if radio.connectionStatus != .disconnected {
                    HStack {
                        Label(radio.connectionStatus == .connected ? "Connected" : "Connecting…",
                              systemImage: radio.connectionStatus == .connected ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(radio.connectionStatus == .connected ? .green : .yellow)
                        Spacer()
                        if radio.connectionStatus == .connected {
                            // Per-slice tabs when connected
                            if !radio.slices.isEmpty {
                                Picker("Active Slice", selection: Binding(
                                    get: { radio.activeSliceIndex },
                                    set: { radio.activeSliceIndex = $0 }
                                )) {
                                    ForEach(radio.slices) { slice in
                                        Text("Slice \(slice.id)").tag(slice.id)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 200)
                                .accessibilityLabel("Active slice selector")
                            }
                        }
                        Button("Disconnect") { radio.disconnect() }
                            .accessibilityLabel("Disconnect from radio")
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    if let slice = radio.activeSlice {
                        SliceView(radio: radio, slice: slice)
                            .padding(.horizontal)
                    }

                    // Bandscope — shown when at least one panadapter is active
                    if let pan = radio.panadapters.first {
                        let sliceMHz = Double(radio.activeSlice?.frequencyHz ?? 0) / 1_000_000
                        BandscopeView(pan: pan, radio: radio, sliceFreqMHz: sliceMHz)
                            .padding(.horizontal)
                    }

                    // Log (last 8 lines)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(radio.connectionLog.suffix(8), id: \.self) { line in
                            Text(line).font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                } else {
                    // Discovered radios
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Discovered Radios").font(.headline)
                            Spacer()
                            Button(action: { discovery.stop(); discovery.start() }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh radio list")
                        }

                        if discovery.radios.isEmpty {
                            Text("Scanning for radios on your network…")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .accessibilityLabel("Scanning for radios")
                        } else {
                            ForEach(discovery.radios) { discovered in
                                RadioRowView(radio: discovered) {
                                    radio.connect(to: discovered)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    // Saved profiles
                    if !profileStore.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved Profiles").font(.headline)
                            ForEach(profileStore.profiles) { profile in
                                ProfileRowView(profile: profile) {
                                    radio.connect(host: profile.host, port: profile.port)
                                } onDelete: {
                                    profileStore.delete(id: profile.id)
                                }
                            }
                        }
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Direct connect
                    VStack(alignment: .leading, spacing: 8) {
                        Button(showDirectConnect ? "Hide Direct Connect" : "Direct Connect…") {
                            showDirectConnect.toggle()
                        }
                        .accessibilityLabel(showDirectConnect ? "Hide direct connect form" : "Show direct connect form")

                        if showDirectConnect {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("IP Address", text: $directHost)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 200)
                                        .accessibilityLabel("Radio IP address")
                                    TextField("Port", text: $directPort)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 80)
                                        .accessibilityLabel("Port number")
                                    Button("Connect") {
                                        if let port = Int(directPort), !directHost.isEmpty {
                                            radio.connect(host: directHost, port: port)
                                        }
                                    }
                                    .disabled(directHost.isEmpty)
                                    .accessibilityLabel("Connect to \(directHost)")
                                }

                                // Save profile row
                                HStack {
                                    TextField("Label (optional)", text: $profileLabel)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 200)
                                        .accessibilityLabel("Profile label, optional")
                                    Button("Save Profile") {
                                        guard !directHost.isEmpty, let port = Int(directPort) else { return }
                                        profileStore.add(ConnectionProfile(label: profileLabel,
                                                                           host: directHost,
                                                                           port: port))
                                        profileLabel = ""
                                        showSaveConfirm = true
                                    }
                                    .disabled(directHost.isEmpty)
                                    .accessibilityLabel("Save connection profile for \(directHost)")
                                    if showSaveConfirm {
                                        Label("Saved", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                            .transition(.opacity)
                                            .onAppear {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                    showSaveConfirm = false
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    // Error display
                    if let error = radio.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Error: \(error)")
                    }
                }
            }
            .padding()
        }
    }
}

private struct RadioRowView: View {
    let radio: DiscoveredRadio
    let onConnect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(radio.displayName).font(.callout.bold())
                Text("\(radio.source.rawValue.capitalized) — \(radio.ip):\(radio.port) — v\(radio.version)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect", action: onConnect)
                .accessibilityLabel("Connect to \(radio.displayName)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(radio.displayName), \(radio.source.rawValue), \(radio.ip)")
        .accessibilityHint("Activate to connect")
        .accessibilityAddTraits(.isButton)
        .contentShape(Rectangle())
        .onTapGesture(perform: onConnect)
    }
}

private struct ProfileRowView: View {
    let profile: ConnectionProfile
    let onConnect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.callout.bold())
                if !profile.subtitle.isEmpty {
                    Text(profile.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Connect", action: onConnect)
                .accessibilityLabel("Connect to \(profile.displayName)")
            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete profile \(profile.displayName)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.subtitle.isEmpty
                            ? profile.displayName
                            : "\(profile.displayName), \(profile.subtitle)")
        .accessibilityHint("Activate to connect")
        .accessibilityAddTraits(.isButton)
        .contentShape(Rectangle())
        .onTapGesture(perform: onConnect)
    }
}
