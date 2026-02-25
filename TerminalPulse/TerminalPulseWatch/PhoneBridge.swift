import Foundation
import WatchConnectivity
import WatchKit
import SwiftUI

@Observable
@MainActor
final class PhoneBridge: NSObject, WCSessionDelegate {
    enum SendStatus: Equatable {
        case idle
        case sending
        case sent(String)
        case error(String)
    }

    var renderedLines: [AttributedString] = []
    var sessionLabel = ""
    var lastUpdate: Date?
    var isConnected = false
    var host = ""
    var currentPaneId: String?
    var sendStatus: SendStatus = .idle
    var isProUnlocked = false
    var sessionTransitionToken = 0
    var sessionTransitionDirection = 1

    private var session: WCSession?
    private var currentHash = ""
    private var latestSequence = 0
    private var latestSequenceEpoch: String?
    private var latestSequenceTimestamp: TimeInterval = 0
    private var wasDisconnected = false
    private var statusClearTask: Task<Void, Never>?
    private var lastAutoRefreshRequestAt: Date = .distantPast
    private let autoRefreshDebounce: TimeInterval = 1.0
    private var deferredPayload: WatchPayload?
    private var needsDeferredRerender = false
    private var isLuminanceReduced = false
    private var isInBackground = false
    private var refreshPulseTimer: Timer?
    private var lastPayloadAt: Date = .distantPast
    private var consecutiveUnchangedPayloads = 0
    private var consecutiveRefreshFailures = 0
    private var lastQueuedRefreshRequestAt: Date = .distantPast
    private var lastQueuedSwitchRequestAt: Date = .distantPast
    private let minQueuedSwitchGap: TimeInterval = 0.35
    private var pendingSessionSwitchDirection: Int?
    private var pendingSessionSwitchResetTask: Task<Void, Never>?
    private var lastSwitchRequestAt: Date = .distantPast
    private var lastSessionIdentity = ""
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
        sendRefreshRequest(automatic: false, reason: "manual")
    }

    func requestRefreshIfNeeded() {
        sendRefreshRequest(automatic: true, reason: "event")
    }

    func setLuminanceReduced(_ reduced: Bool) {
        guard isLuminanceReduced != reduced else { return }
        isLuminanceReduced = reduced
        if !reduced {
            flushDeferredUpdates()
        }
        scheduleNextRefreshPulse()
    }

    func setScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isInBackground = false
            startRefreshPulseLoopIfNeeded()
            requestRefreshIfNeeded()
        case .inactive:
            isInBackground = false
            startRefreshPulseLoopIfNeeded()
        case .background:
            isInBackground = true
            stopRefreshPulseLoop()
        @unknown default:
            break
        }
    }

    func sendKeys(text: String? = nil, special: String? = nil) {
        guard isProUnlocked else {
            sendStatus = .error("Pro required")
            WKInterfaceDevice.current().play(.failure)
            clearStatusAfterDelay()
            return
        }
        guard let session else { return }

        let normalizedText: String? = {
            guard let text else { return nil }
            return text.isEmpty ? nil : text
        }()
        let normalizedSpecial: String? = {
            guard let special else { return nil }
            let trimmed = special.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        guard (normalizedText != nil) != (normalizedSpecial != nil) else {
            sendStatus = .error("Invalid key request")
            WKInterfaceDevice.current().play(.failure)
            clearStatusAfterDelay()
            return
        }

        var msg: [String: Any] = ["action": "sendKeys"]
        if let normalizedText { msg["text"] = normalizedText }
        if let normalizedSpecial { msg["special"] = normalizedSpecial }
        if let currentPaneId { msg["paneId"] = currentPaneId }

        sendStatus = .sending

        session.sendMessage(msg, replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                if reply["ok"] as? Bool == true {
                    let label = text ?? special ?? "key"
                    self.sendStatus = .sent(label)
                    WKInterfaceDevice.current().play(.click)
                } else {
                    let err = reply["error"] as? String ?? "Failed"
                    self.sendStatus = .error(err)
                    WKInterfaceDevice.current().play(.failure)
                }
                self.clearStatusAfterDelay()
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.sendStatus = .error(error.localizedDescription)
                WKInterfaceDevice.current().play(.failure)
                self.clearStatusAfterDelay()
            }
        })
    }

    func switchSession(direction rawDirection: Int) {
        guard isProUnlocked else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        guard let session else { return }

        let direction = rawDirection >= 0 ? 1 : -1
        let ts = Date().timeIntervalSince1970
        let now = Date()
        guard now.timeIntervalSince(lastSwitchRequestAt) >= 0.25 else { return }
        lastSwitchRequestAt = now
        pendingSessionSwitchResetTask?.cancel()
        pendingSessionSwitchDirection = direction

        let request: [String: Any] = [
            "action": "switchSession",
            "direction": direction,
            "ts": ts
        ]

        guard session.isReachable else {
            queueBackgroundSwitchSignal(via: session, direction: direction, ts: ts)
            sendStatus = .sent(direction > 0 ? "next" : "prev")
            WKInterfaceDevice.current().play(.click)
            clearStatusAfterDelay()
            return
        }

        session.sendMessage(
            request,
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    if reply["ok"] as? Bool == true {
                        self.isConnected = true
                        WKInterfaceDevice.current().play(.click)
                        self.schedulePendingSessionDirectionReset()
                    } else {
                        self.pendingSessionSwitchResetTask?.cancel()
                        self.pendingSessionSwitchDirection = nil
                        let err = reply["error"] as? String ?? "Failed to switch session"
                        self.sendStatus = .error(self.compactSwitchError(err))
                        WKInterfaceDevice.current().play(.failure)
                        self.clearStatusAfterDelay()
                    }
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isConnected = false
                    if session.isReachable {
                        self.pendingSessionSwitchResetTask?.cancel()
                        self.pendingSessionSwitchDirection = nil
                        self.sendStatus = .error(self.compactSwitchError(error.localizedDescription))
                        WKInterfaceDevice.current().play(.failure)
                        self.clearStatusAfterDelay()
                    } else {
                        self.queueBackgroundSwitchSignal(via: session, direction: direction, ts: ts)
                        self.sendStatus = .sent(direction > 0 ? "next" : "prev")
                        WKInterfaceDevice.current().play(.click)
                        self.clearStatusAfterDelay()
                    }
                }
            }
        )
    }

    private func compactSwitchError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("only 1 tmux window")
            || lower.contains("no additional tmux windows")
            || lower.contains("no additional tmux sessions or windows") {
            return "Only 1 tmux window"
        }
        if lower.contains("window did not change") {
            return "Window unchanged"
        }
        if lower.contains("unreachable through proxy")
            || lower.contains("status 502")
            || lower.contains("network")
            || lower.contains("timed out") {
            return "Network path issue"
        }
        return message
    }

    private func clearStatusAfterDelay() {
        statusClearTask?.cancel()
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            sendStatus = .idle
        }
    }

    private func sendRefreshRequest(automatic: Bool, reason: String) {
        guard let session else { return }

        if automatic {
            let now = Date()
            guard now.timeIntervalSince(lastAutoRefreshRequestAt) >= autoRefreshDebounce else { return }
            lastAutoRefreshRequestAt = now
        }

        let request: [String: Any] = [
            "action": "refresh",
            "reason": reason,
            "ts": Date().timeIntervalSince1970
        ]

        guard session.isReachable else {
            wasDisconnected = true
            isConnected = false
            if automatic {
                consecutiveRefreshFailures = min(consecutiveRefreshFailures + 1, 6)
            }
            queueBackgroundRefreshSignal(via: session, reason: reason)
            return
        }

        session.sendMessage(request, replyHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = true
                self.consecutiveRefreshFailures = 0
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.wasDisconnected = true
                self.isConnected = false
                if automatic {
                    self.consecutiveRefreshFailures = min(self.consecutiveRefreshFailures + 1, 6)
                }
                self.queueBackgroundRefreshSignal(via: session, reason: reason)
            }
        })
    }

    private func startRefreshPulseLoopIfNeeded() {
        guard !isInBackground else { return }
        if refreshPulseTimer == nil {
            scheduleNextRefreshPulse()
        }
    }

    private func stopRefreshPulseLoop() {
        refreshPulseTimer?.invalidate()
        refreshPulseTimer = nil
    }

    private func scheduleNextRefreshPulse() {
        guard !isInBackground else {
            stopRefreshPulseLoop()
            return
        }

        refreshPulseTimer?.invalidate()
        let age = Date().timeIntervalSince(lastPayloadAt)
        let staleTarget = refreshStalenessTarget()
        let interval = max(1.0, staleTarget - age)

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleRefreshPulse()
            }
        }
        timer.tolerance = min(interval * 0.2, 2.0)
        refreshPulseTimer = timer
    }

    private func handleRefreshPulse() {
        guard !isInBackground else { return }
        let age = Date().timeIntervalSince(lastPayloadAt)
        if age >= refreshStalenessTarget() {
            sendRefreshRequest(automatic: true, reason: "pulse")
        }
        scheduleNextRefreshPulse()
    }

    private func refreshStalenessTarget() -> TimeInterval {
        let pollInterval = TimeInterval(UserDefaults.standard.integer(forKey: "pollInterval").clamped(to: 1...120, default: 2))
        let baseActive = max(2.6, pollInterval + 0.6)
        let baseReduced = max(8.0, pollInterval * 2.5)
        let base = isLuminanceReduced ? baseReduced : baseActive

        let exponent = max(0, min(consecutiveUnchangedPayloads - 2, 3))
        var interval = base * pow(1.8, Double(exponent))
        let cap = isLuminanceReduced ? 30.0 : 15.0
        interval = min(interval, cap)

        if consecutiveRefreshFailures > 0 {
            let failureBackoff = min(60.0, 5.0 * pow(2.0, Double(min(consecutiveRefreshFailures, 3))))
            interval = max(interval, failureBackoff)
        }
        return interval
    }

    private func minQueuedRefreshGap() -> TimeInterval {
        if isInBackground {
            return 12.0
        }
        return isLuminanceReduced ? 8.0 : 2.5
    }

    private func maxOutstandingRefreshHints() -> Int {
        if isInBackground || isLuminanceReduced {
            return 1
        }
        return 3
    }

    private func queueBackgroundRefreshSignal(via session: WCSession, reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastQueuedRefreshRequestAt) >= minQueuedRefreshGap() else { return }
        lastQueuedRefreshRequestAt = now

        let hint: [String: Any] = [
            "action": "refresh",
            "reason": reason,
            "queued": true,
            "ts": now.timeIntervalSince1970
        ]
        try? session.updateApplicationContext(hint)

        let outstandingRefreshHints = session.outstandingUserInfoTransfers.filter {
            ($0.userInfo["action"] as? String) == "refresh"
        }.count
        if outstandingRefreshHints < maxOutstandingRefreshHints() {
            session.transferUserInfo(hint)
        }
    }

    private func queueBackgroundSwitchSignal(via session: WCSession, direction: Int, ts: TimeInterval) {
        let now = Date()
        guard now.timeIntervalSince(lastQueuedSwitchRequestAt) >= minQueuedSwitchGap else { return }
        lastQueuedSwitchRequestAt = now

        let hint: [String: Any] = [
            "action": "switchSession",
            "direction": direction,
            "queued": true,
            "ts": ts
        ]
        try? session.updateApplicationContext(hint)

        let hasPendingSwitchHint = session.outstandingUserInfoTransfers.contains {
            ($0.userInfo["action"] as? String) == "switchSession"
        }
        if !hasPendingSwitchHint {
            session.transferUserInfo(hint)
        }
    }


    // MARK: - Payload handling

    private func handlePayload(_ dict: [String: Any]) {
        if let ts = dict["_seqTs"] as? TimeInterval, ts < latestSequenceTimestamp {
            return
        }
        if let epoch = dict["_seqEpoch"] as? String, epoch != latestSequenceEpoch {
            latestSequenceEpoch = epoch
            latestSequence = 0
        }
        if let seq = dict["_seq"] as? Int {
            guard seq >= latestSequence else { return }
            latestSequence = seq
        }
        if let ts = dict["_seqTs"] as? TimeInterval {
            latestSequenceTimestamp = ts
        }

        // Sync settings from iPhone (before hash check, so settings always update)
        var settingsChanged = false
        if let syncedFontSize = dict["_watchFontSize"] as? Int, syncedFontSize > 0 {
            let current = UserDefaults.standard.integer(forKey: "watchFontSize")
            if syncedFontSize != current {
                UserDefaults.standard.set(syncedFontSize, forKey: "watchFontSize")
                settingsChanged = true
            }
        }
        if let proStatus = dict["_proUnlocked"] as? Bool {
            isProUnlocked = proStatus
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

        // Settings-only message — re-render cached output with new settings
        // and request a fresh capture so colors update immediately
        if dict["_settingsOnly"] as? Bool == true {
            if settingsChanged {
                currentHash = "" // Force accept next payload (dividers recalculated at new font size)
                if isLuminanceReduced {
                    needsDeferredRerender = true
                } else {
                    rerenderCached()
                }
                requestRefreshIfNeeded()
            }
            scheduleNextRefreshPulse()
            return
        }

        guard let payload = WatchPayload.from(dictionary: dict) else { return }

        // Track the current pane for send-keys targeting
        currentPaneId = payload.paneId

        let changed = payload.hash != currentHash
        lastPayloadAt = Date()
        if changed {
            consecutiveUnchangedPayloads = 0
        } else {
            consecutiveUnchangedPayloads = min(consecutiveUnchangedPayloads + 1, 20)
        }
        consecutiveRefreshFailures = 0
        scheduleNextRefreshPulse()

        // Re-render if content changed OR settings changed (even with same hash)
        guard changed || settingsChanged else { return }

        if isLuminanceReduced {
            deferredPayload = payload
            needsDeferredRerender = needsDeferredRerender || settingsChanged
        } else {
            applyPayloadToUI(payload, force: settingsChanged)
        }

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

    private func applyPayloadToUI(_ payload: WatchPayload, force: Bool = false) {
        guard force || payload.hash != currentHash else { return }

        let isFirstData = currentHash.isEmpty
        currentHash = payload.hash

        let fontSize = CGFloat(UserDefaults.standard.integer(forKey: "watchFontSize").clamped(to: 7...12, default: 10))
        renderedLines = RunsRenderer.buildLines(from: payload.runs, fontSize: fontSize)
        let newSessionIdentity = "\(payload.session):\(payload.winName)"
        if !lastSessionIdentity.isEmpty, lastSessionIdentity != newSessionIdentity {
            let direction = pendingSessionSwitchDirection ?? 1
            sessionTransitionDirection = direction >= 0 ? 1 : -1
            sessionTransitionToken += 1
        }
        sessionLabel = newSessionIdentity
        lastSessionIdentity = newSessionIdentity
        pendingSessionSwitchResetTask?.cancel()
        pendingSessionSwitchDirection = nil
        host = payload.host
        lastUpdate = Self.isoFormatter.date(from: payload.ts) ?? Date()

        // Haptic: reconnection
        if wasDisconnected && !isFirstData {
            WKInterfaceDevice.current().play(.directionUp)
            wasDisconnected = false
        }
        isConnected = true
    }

    private func flushDeferredUpdates() {
        if needsDeferredRerender {
            needsDeferredRerender = false
            currentHash = ""
            rerenderCached()
        }

        if let payload = deferredPayload {
            deferredPayload = nil
            applyPayloadToUI(payload)
        }
        scheduleNextRefreshPulse()
    }

    /// Re-render the cached terminal output with current settings (font size, theme).
    private func rerenderCached() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = WatchPayload.from(dictionary: dict) else { return }

        let fontSize = CGFloat(UserDefaults.standard.integer(forKey: "watchFontSize").clamped(to: 7...12, default: 10))
        renderedLines = RunsRenderer.buildLines(from: payload.runs, fontSize: fontSize)
        sessionLabel = "\(payload.session):\(payload.winName)"
        lastSessionIdentity = sessionLabel
    }

    private func schedulePendingSessionDirectionReset() {
        pendingSessionSwitchResetTask?.cancel()
        pendingSessionSwitchResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            pendingSessionSwitchDirection = nil
        }
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

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            // Always request fresh data when session activates
            self.requestRefreshIfNeeded()
            self.startRefreshPulseLoopIfNeeded()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                // Phone became reachable — request one refresh.
                self.requestRefreshIfNeeded()
                self.startRefreshPulseLoopIfNeeded()
                self.isConnected = true
                self.wasDisconnected = false
            } else {
                self.wasDisconnected = true
                self.isConnected = false
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
