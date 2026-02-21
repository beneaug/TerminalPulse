import SwiftUI
import BackgroundTasks

@main
struct TerminalPulseApp: App {
    init() {
        // Register sensible defaults so raw UserDefaults.integer reads match @AppStorage defaults
        UserDefaults.standard.register(defaults: [
            "pollInterval": 2,
            "fontSize": 11,
            "watchFontSize": 10,
            "colorTheme": "default"
        ])

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: PollingService.bgRefreshID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            PollingService.backgroundRefreshHandler?(refreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    Self.migrateTokenToKeychain()
                    if UserDefaults.standard.bool(forKey: "onboardingComplete") {
                        NotificationService.requestPermission()
                    }
                }
        }
    }

    /// One-time migration: move authToken from UserDefaults to Keychain.
    private static func migrateTokenToKeychain() {
        let defaults = UserDefaults.standard
        if let legacyToken = defaults.string(forKey: "authToken"), !legacyToken.isEmpty {
            _ = KeychainService.save(key: "authToken", value: legacyToken)
            defaults.removeObject(forKey: "authToken")
        }
    }
}
