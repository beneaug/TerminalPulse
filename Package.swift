// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TmuxOnWatchCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TmuxCore", targets: ["TmuxCore"])],
    targets: [
        .target(name: "TmuxCore", path: "TerminalPulse",
                exclude: ["Products.storekit", "TerminalPulse.xcodeproj", "TerminalPulseWatch",
                          "Shared/DemoData.swift", "Shared/RunsRenderer.swift", "Shared/StoreManager.swift", "Shared/TerminalColors.swift",
                          "TerminalPulse/Assets.xcassets", "TerminalPulse/ContentView.swift", "TerminalPulse/Info.plist",
                          "TerminalPulse/LanguageManager.swift", "TerminalPulse/Localizable.xcstrings", "TerminalPulse/OnboardingView.swift",
                          "TerminalPulse/PrivacyInfo.xcprivacy", "TerminalPulse/SettingsView.swift", "TerminalPulse/TerminalPulse.entitlements",
                          "TerminalPulse/TerminalPulseApp.swift", "TerminalPulse/TerminalView.swift",
                          "TerminalPulse/Services/CaptureCache.swift", "TerminalPulse/Services/NotificationService.swift",
                          "TerminalPulse/Services/PollingService.swift", "TerminalPulse/Services/WatchBridge.swift"],
                sources: ["Shared/Models.swift", "Shared/WatchDisplayPolicy.swift", "TerminalPulse/Services/APIClient.swift", "TerminalPulse/Services/KeychainService.swift"]),
        .testTarget(name: "TmuxCoreTests", dependencies: ["TmuxCore"], path: "Tests/TmuxCoreTests")
    ]
)
