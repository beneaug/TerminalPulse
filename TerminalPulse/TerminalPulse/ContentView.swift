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
                    .navigationTitle("tmuxonwatch")
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
                    },
                    onDemoLoaded: {
                        polling.startDemoAnimation()
                    }
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .onAppear {
            polling.watchBridge = watchBridge
            watchBridge.onRefreshRequested = { polling.fetchForWatch() }
            watchBridge.onSendKeysRequested = { text, special, paneId, reply in
                let target = paneId ?? polling.selectedTarget
                Task {
                    do {
                        _ = try await APIClient().sendKeys(text: text, special: special, target: target)
                        reply(true, nil)
                        polling.fetchNow()
                    } catch {
                        reply(false, error.localizedDescription)
                    }
                }
            }
            StoreManager.shared.onProStatusChanged = { _ in
                watchBridge.syncProStatus()
            }
            PollingService.backgroundRefreshHandler = { polling.handleBackgroundRefresh(task: $0) }
            polling.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                polling.enterBackground()
            case .active:
                polling.enterForeground()
            @unknown default:
                break
            }
        }
    }
}
