import Foundation
import WatchConnectivity
import WatchKit
import SwiftUI

@Observable
@MainActor
final class PhoneBridge: NSObject, WCSessionDelegate {
    var renderedLines: [AttributedString] = []
    var sessionLabel = ""
    var lastUpdate: Date?
    var isConnected = false
    var host = ""

    private var session: WCSession?
    private var currentHash = ""
    private var refreshTimer: Timer?
    private var wasDisconnected = false
    private static let isoFormatter = ISO8601DateFormatter()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        self.session = s
        loadCache()
    }

    func requestRefresh() {
        session?.sendMessage(["action": "refresh"], replyHandler: nil, errorHandler: nil)
    }

    /// Start periodic refresh requests while the watch app is visible.
    /// Uses the iPhone's synced poll interval, with a minimum of 5 seconds.
    func startAutoRefresh() {
        stopAutoRefresh()
        let syncedInterval = UserDefaults.standard.integer(forKey: "pollInterval")
        let interval = TimeInterval(max(syncedInterval, 5))
        requestRefresh() // Immediate first request
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.requestRefresh() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Payload handling

    private func handlePayload(_ dict: [String: Any]) {
        // Sync settings from iPhone (before hash check, so settings always update)
        var settingsChanged = false
        if let syncedFontSize = dict["_watchFontSize"] as? Int, syncedFontSize > 0 {
            let current = UserDefaults.standard.integer(forKey: "watchFontSize")
            if syncedFontSize != current {
                UserDefaults.standard.set(syncedFontSize, forKey: "watchFontSize")
                settingsChanged = true
            }
        }
        if let syncedTheme = dict["_colorTheme"] as? String {
            let current = UserDefaults.standard.string(forKey: "colorTheme") ?? "default"
            if syncedTheme != current {
                UserDefaults.standard.set(syncedTheme, forKey: "colorTheme")
                TerminalColors.invalidateCache()
                settingsChanged = true
            }
        }
        if let syncedPollInterval = dict["_pollInterval"] as? Int, syncedPollInterval > 0 {
            UserDefaults.standard.set(syncedPollInterval, forKey: "pollInterval")
        }

        // Settings-only message — just re-render cached output with new settings
        if dict["_settingsOnly"] as? Bool == true {
            if settingsChanged { rerenderCached() }
            return
        }

        guard let payload = WatchPayload.from(dictionary: dict) else { return }

        // Re-render if content changed OR settings changed (even with same hash)
        guard payload.hash != currentHash || settingsChanged else { return }

        let isFirstData = currentHash.isEmpty
        currentHash = payload.hash

        let fontSize = CGFloat(UserDefaults.standard.integer(forKey: "watchFontSize").clamped(to: 7...12, default: 10))
        renderedLines = RunsRenderer.buildLines(from: payload.runs, fontSize: fontSize)
        sessionLabel = "\(payload.session):\(payload.winName)"
        host = payload.host
        lastUpdate = Self.isoFormatter.date(from: payload.ts) ?? Date()

        // Haptic: reconnection
        if wasDisconnected && !isFirstData {
            WKInterfaceDevice.current().play(.directionUp)
            wasDisconnected = false
        }
        isConnected = true

        // Haptic: check if command finished (notification payload flag)
        // Only fire if this is a live message, not a cached restore
        if let commandFinished = dict["commandFinished"] as? Bool, commandFinished {
            WKInterfaceDevice.current().play(.notification)
        }

        // Strip transient flags before caching to avoid replaying haptics on launch
        var cacheDict = dict
        cacheDict.removeValue(forKey: "commandFinished")
        saveCache(cacheDict)
    }

    /// Re-render the cached terminal output with current settings (font size, theme).
    private func rerenderCached() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = WatchPayload.from(dictionary: dict) else { return }

        let fontSize = CGFloat(UserDefaults.standard.integer(forKey: "watchFontSize").clamped(to: 7...12, default: 10))
        renderedLines = RunsRenderer.buildLines(from: payload.runs, fontSize: fontSize)
    }

    // MARK: - Cache

    private static let cacheKey = "terminalpulse_cache"

    private func saveCache(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        handlePayload(dict)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if !session.isReachable {
                self.wasDisconnected = true
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handlePayload(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handlePayload(applicationContext)
        }
    }
}
