import SwiftUI

@main
struct FlexAccessApp: App {
    @State private var discovery = FlexDiscovery()
    @State private var radio: Radio?
    @State private var profileStore = ConnectionProfileStore()

    var body: some Scene {
        WindowGroup {
            if let radio {
                ContentView(radio: radio, discovery: discovery, profileStore: profileStore)
            } else {
                // Radio is created after discovery starts so @Observable works correctly
                Color.clear.onAppear {
                    discovery.start()
                    radio = Radio(discovery: discovery)
                }
            }
        }
        .windowResizability(.contentSize)
    }
}
