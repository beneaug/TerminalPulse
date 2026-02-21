import SwiftUI

struct ContentView: View {
    @State private var polling = PollingService()
    @State private var watchBridge = WatchBridge()
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if onboardingComplete {
            mainContent
        } else {
            OnboardingView(isComplete: $onboardingComplete)
        }
    }

    private var mainContent: some View {
        TabView {
            NavigationStack {
                TerminalView(polling: polling)
                    .navigationTitle("TerminalPulse")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            NavigationStack {
                SettingsView(
                    watchReachable: watchBridge.isReachable,
                    onPollIntervalChanged: { polling.restartTimer() },
                    onAppearanceChanged: {
                        polling.rerender()
                        polling.syncSettingsToWatch()
                    }
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .onAppear {
            polling.watchBridge = watchBridge
            watchBridge.onRefreshRequested = { polling.fetchNow() }
            PollingService.backgroundRefreshHandler = { polling.handleBackgroundRefresh(task: $0) }
            polling.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                polling.enterBackground()
            case .active:
                polling.enterForeground()
            default:
                break
            }
        }
    }
}
