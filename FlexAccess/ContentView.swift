//
//  ContentView.swift
//  FlexAccess
//
//  Top-level NavigationSplitView. Sidebar lists sections; detail shows the selected view.
//  Adapts automatically to macOS window, iPad split view, and iPhone stack.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var radio: FlexRadioState
    @ObservedObject var discovery: FlexDiscovery

    enum Section: String, Hashable {
        case connection, slice, audio, equalizer, logs
    }

    @AppStorage("FlexAccess.SelectedSection") private var selectedSectionRaw: String = Section.connection.rawValue
    @State private var selectedSection: Section = .connection

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Text("Connection").tag(Section.connection)
                Text("Slice").tag(Section.slice)
                Text("Audio").tag(Section.audio)
                Text("Equalizer").tag(Section.equalizer)
                Text("Logs").tag(Section.logs)
            }
            .navigationTitle("FlexAccess")
        } detail: {
            switch selectedSection {
            case .connection: ConnectionSectionView(radio: radio, discovery: discovery)
            case .slice:      SliceSectionView(radio: radio)
            case .audio:      AudioSectionView(radio: radio)
            case .equalizer:  EqualizerSectionView(radio: radio)
            case .logs:       LogsSectionView(radio: radio)
            }
        }
        .controlSize(.large)
        .onChange(of: selectedSection) { _, newValue in
            selectedSectionRaw = newValue.rawValue
        }
        .onAppear {
            if let sec = Section(rawValue: selectedSectionRaw) { selectedSection = sec }
        }
        .onReceive(NotificationCenter.default.publisher(for: FlexSelectSectionNotification)) { note in
            if let raw = note.userInfo?[FlexSelectSectionKey] as? String,
               let sec = Section(rawValue: raw) {
                selectedSection = sec
            }
        }
    }
}
