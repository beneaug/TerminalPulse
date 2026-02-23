import SwiftUI

@main
struct TerminalPulseWatchApp: App {
    @State private var bridge = PhoneBridge()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchTerminalView(bridge: bridge)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                bridge.requestRefresh()
            }
        }
    }
}
