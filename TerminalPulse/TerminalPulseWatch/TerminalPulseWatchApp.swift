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
        .backgroundTask(.watchConnectivity) {
            await bridge.receiveBackgroundContent()
        }
        .onChange(of: scenePhase) { _, phase in
            bridge.setScenePhase(phase)
        }
    }
}
