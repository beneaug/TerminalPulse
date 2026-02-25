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
                guard StoreManager.shared.isProUnlocked else {
                    reply(false, "Pro required")
                    return
                }
                let normalizedPaneId = paneId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let paneTarget: String? = {
                    guard let normalizedPaneId, !normalizedPaneId.isEmpty, normalizedPaneId != "?" else {
                        return nil
                    }
                    return normalizedPaneId
                }()
                let target = paneTarget ?? polling.selectedTarget
                Task {
                    do {
                        _ = try await APIClient().sendKeys(text: text, special: special, target: target)
                        reply(true, nil)
                        polling.scheduleWatchInputFollowUp()
                    } catch {
                        reply(false, error.localizedDescription)
                    }
                }
            }
            watchBridge.onSwitchSessionRequested = { direction, reply in
                guard StoreManager.shared.isProUnlocked else {
                    reply(false, "Pro required")
                    return
                }
                Task { @MainActor in
                    let (ok, error) = await polling.switchSession(direction: direction)
                    reply(ok, error)
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
            case .background:
                polling.enterBackground()
            case .inactive:
                break
            case .active:
                polling.enterForeground()
            @unknown default:
                break
            }
        }
    }
}
