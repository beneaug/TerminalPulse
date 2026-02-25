import SwiftUI

@main
struct TerminalPulseWatchApp: App {
    @State private var bridge = PhoneBridge()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchTerminalView(bridge: bridge)
                .onAppear {
                    bridge.setScenePhase(scenePhase)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            bridge.setScenePhase(phase)
        }
    }
}
