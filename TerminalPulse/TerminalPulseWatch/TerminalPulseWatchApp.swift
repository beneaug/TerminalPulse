import SwiftUI

@main
struct TerminalPulseWatchApp: App {
    @State private var bridge = PhoneBridge()

    var body: some Scene {
        WindowGroup {
            WatchTerminalView(bridge: bridge)
        }
    }
}
