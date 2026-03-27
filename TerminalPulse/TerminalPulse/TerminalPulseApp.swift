import SwiftUI
import BackgroundTasks
import UIKit
import UserNotifications

@main
struct TerminalPulseApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var notificationAppDelegate

    init() {
        // Register sensible defaults so raw UserDefaults.integer reads match @AppStorage defaults
        UserDefaults.standard.register(defaults: [
            "pollInterval": 2,
            "fontSize": 11,
            "watchFontSize": 10,
            "colorTheme": "default",
            "notificationsEnabled": true,
            "remotePushEnabled": false
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
                    NotificationService.configureAtLaunch()
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

final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.handleAPNsDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationService.handleAPNsRegistrationFailure(error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
