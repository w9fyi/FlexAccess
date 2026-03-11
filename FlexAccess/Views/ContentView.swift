import SwiftUI

struct ContentView: View {
    @Bindable var radio: Radio
    let discovery: FlexDiscovery
    let profileStore: ConnectionProfileStore

    @State private var selectedTab: Tab = .radio

    enum Tab: String, CaseIterable {
        case radio   = "Radio"
        case audio   = "Audio"
        case cw      = "CW"
        case memory  = "Memory"
        case log     = "Log"
        case meters  = "Meters"
        case eq      = "EQ"
        case settings = "Settings"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if radio.connectionStatus == .connected {
                    Text(radio.radioModel.isEmpty ? "FlexRadio" : radio.radioModel)
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusText)
            .accessibilityAddTraits(.updatesFrequently)

            Divider()

            // Tab content
            switch selectedTab {
            case .radio:
                RadioListView(radio: radio, discovery: discovery, profileStore: profileStore)
            case .audio:
                AudioView(radio: radio)
            case .cw:
                CWKeyerView(radio: radio)
            case .memory:
                MemoryView(radio: radio)
            case .log:
                LogView(radio: radio)
            case .meters:
                MetersView(radio: radio)
            case .eq:
                EQView(radio: radio)
            case .settings:
                SettingsView(radio: radio)
            }

            Divider()

            // Tab bar
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 2) {
                            Image(systemName: iconName(for: tab))
                                .font(.title3)
                            Text(tab.rawValue)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
                }
            }
            .background(.bar)
        }
        .frame(minWidth: 480, minHeight: 600)
    }

    private var statusColor: Color {
        switch radio.connectionStatus {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch radio.connectionStatus {
        case .connected:    return "Connected\(radio.firmwareVersion.isEmpty ? "" : " — v\(radio.firmwareVersion)")"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Disconnected"
        }
    }

    private func iconName(for tab: Tab) -> String {
        switch tab {
        case .radio:    return "dot.radiowaves.left.and.right"
        case .audio:    return "speaker.wave.2"
        case .cw:       return "key.horizontal"
        case .memory:   return "star"
        case .log:      return "list.bullet.clipboard"
        case .meters:   return "gauge.with.needle"
        case .eq:       return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}
