//
//  FlexAccessApp.swift
//  FlexAccess
//
//  App entry point. Creates the single FlexDiscovery and FlexRadioState instances,
//  installs the Option-Space PTT key monitor, and wires menu bar commands.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

let FlexSelectSectionNotification = Notification.Name("FlexAccess.SelectSection")
let FlexSelectSectionKey = "section"

// MARK: - PTT Key Monitor (macOS)

#if os(macOS)
final class PTTKeyMonitor {
    static let shared = PTTKeyMonitor()
    private init() {}

    private var radio: FlexRadioState?
    private var monitor: Any?
    private var isDown = false
    private var optionIsDown = false

    func attach(radio: FlexRadioState) {
        self.radio = radio
        installIfNeeded()
        NotificationCenter.default.addObserver(self, selector: #selector(appResigned),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        AppFileLogger.shared.log("PTTKeyMonitor: attached")
    }

    private func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged { self.optionIsDown = event.modifierFlags.contains(.option) }
            let optEffective = event.modifierFlags.contains(.option) || self.optionIsDown
            let spaceDown = (event.type == .keyDown && event.keyCode == 49)
            let spaceUp   = (event.type == .keyUp   && event.keyCode == 49)

            if optEffective && spaceDown && !self.isDown {
                self.radio?.setPTT(down: true)
                self.isDown = true
                return nil
            }
            if (spaceUp || (!optEffective && self.isDown)) && self.isDown {
                self.radio?.setPTT(down: false)
                self.isDown = false
                if spaceUp { return nil }
            }
            return event
        }
    }

    @objc private func appResigned() {
        if isDown {
            isDown = false
            Task { @MainActor in self.radio?.setPTT(down: false) }
        }
    }
}
#endif

// MARK: - App

@main
struct FlexAccessApp: App {
    @StateObject private var discovery = FlexDiscovery()
    @StateObject private var radio: FlexRadioState

    init() {
        let disc = FlexDiscovery()
        let r = FlexRadioState(discovery: disc)
        _discovery = StateObject(wrappedValue: disc)
        _radio = StateObject(wrappedValue: r)

        AppFileLogger.shared.logLaunchHeader()
        AppFileLogger.shared.log("FlexAccess launched — NR backend: \(r.noiseReductionBackend)")
        disc.start()

        #if os(macOS)
        PTTKeyMonitor.shared.attach(radio: r)
        #endif

        // Attempt silent SmartLink token refresh on launch
        Task { @MainActor in
            guard SmartLinkAuth.shared.isSignedIn else { return }
            do {
                _ = try await SmartLinkAuth.shared.refreshIfNeeded()
                AppFileLogger.shared.log("SmartLinkAuth: token refreshed on launch")
            } catch {
                AppFileLogger.shared.log("SmartLinkAuth: launch refresh failed — \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(radio: radio, discovery: discovery)
        }
        #if os(macOS)
        .commands {
            CommandMenu("Connection") {
                Button("Connect") { /* handled in ConnectionSectionView */ }
                    .keyboardShortcut("c", modifiers: [.command])
                Button("Disconnect") { radio.disconnect() }
                    .keyboardShortcut("d", modifiers: [.command])
            }
            CommandMenu("Audio") {
                Toggle("Noise Reduction", isOn: Binding(
                    get: { radio.isNoiseReductionEnabled },
                    set: { radio.setNoiseReduction(enabled: $0) }
                ))
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!radio.isNoiseReductionAvailable)
            }
            CommandMenu("Mode") {
                Button("LSB") { radio.setSliceMode(.lsb) }.keyboardShortcut("l", modifiers: [.control, .shift])
                Button("USB") { radio.setSliceMode(.usb) }.keyboardShortcut("u", modifiers: [.control, .shift])
                Button("CW")  { radio.setSliceMode(.cw)  }.keyboardShortcut("c", modifiers: [.control, .shift])
                Button("AM")  { radio.setSliceMode(.am)  }.keyboardShortcut("a", modifiers: [.control, .shift])
                Button("FM")  { radio.setSliceMode(.fm)  }.keyboardShortcut("f", modifiers: [.control, .shift])
            }
            CommandMenu("View") {
                Button("Connection") { post("connection") }.keyboardShortcut("1", modifiers: [.command])
                Button("Slice")      { post("slice")      }.keyboardShortcut("2", modifiers: [.command])
                Button("Audio")      { post("audio")      }.keyboardShortcut("3", modifiers: [.command])
                Button("Equalizer")  { post("equalizer")  }.keyboardShortcut("4", modifiers: [.command])
                Button("Logs")       { post("logs")       }.keyboardShortcut("5", modifiers: [.command])
            }
            CommandMenu("Radio") {
                Button("PTT Down (TX)") { radio.setPTT(down: true) }
                Button("PTT Up (RX)")   { radio.setPTT(down: false) }
                Divider()
                Text("Hold Option-Space for push-to-talk")
            }
        }
        #endif
    }

    #if os(macOS)
    private func post(_ section: String) {
        NotificationCenter.default.post(name: FlexSelectSectionNotification, object: nil,
                                        userInfo: [FlexSelectSectionKey: section])
    }
    #endif
}
