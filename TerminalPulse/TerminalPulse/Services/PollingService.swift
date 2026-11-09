import Foundation
import UIKit
import SwiftUI
import BackgroundTasks
import OSLog

@Observable
@MainActor
final class PollingService {
    static let shared = PollingService()
    var renderedLines: [AttributedString] = []
    private(set) var currentPayload: WatchPayload?
    // This belongs to the displayed capture, never to the current Settings values.
    // Disk cache and demo payloads are intentionally read-only.
    private(set) var currentPayloadInputContextID: String?
    var hostLabel: String { currentPayload?.host ?? "" }
    var plainOutput: String { currentPayload?.runs.map { $0.map(\.t).joined() }.joined(separator: "\n") ?? "" }
    var isRefreshing: Bool { isPolling }
    var sessionLabel = ""
    var lastUpdate: Date?
    var isConnected = false
    var errorMessage: String?
    var sessions: [SessionInfo] = []
    var windowsBySession: [String: [WindowInfoResponse]] = [:]
    var selectedTarget: String?

    private let api = APIClient()
    private var timer: Timer?
    private var lastHash = ""
    private var cachedHostname: String?
    private var lastLineWasPrompt = true // Start true so first poll doesn't notify
    private var lastPaneIDForCommandState: String?
    private var lastPaneCommand: String?
    private var demoTask: Task<Void, Never>?
    private var lastDemoWatchSend: Date = .distantPast
    private var watchNeedsSync = true // Always send first successful poll to watch
    var watchBridge: WatchBridge?
    private var currentPaneSession: String?
    private var currentPaneWindowIndex: Int?
    private var preferredWindowBaseBySession: [String: Int] = [:] // 0 or 1
    private var isPolling = false
    private var pendingPoll = false
    private var pollCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var watchInputSyncTask: Task<Void, Never>?
    private var activeBackgroundPollTask: UIBackgroundTaskIdentifier = .invalid
    private var started = false
    private var pollTask: Task<Void, Never>?
    private var lastSuccessfulPoll: Date = .distantPast
    private var connectionIdentity: WatchConnectionIdentity?
    private var watchInputContext = WatchInputContext()

    private var boundConnectionAPI: (identity: WatchConnectionIdentity, api: APIClient)?

    private func api(for connection: WatchConnectionIdentity) -> APIClient {
        if let cached = boundConnectionAPI, cached.identity == connection { return cached.api }
        let client = APIClient(serverURL: connection.serverURL, authToken: connection.authToken)
        boundConnectionAPI = (connection, client)
        return client
    }

    private var currentConnection: WatchConnectionIdentity {
        let connection = WatchConnectionIdentity(serverURL: UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787",
                                authToken: KeychainService.load(key: "authToken") ?? "")
        watchInputContext.observe(connection)
        return connection
    }

    private func isCurrentWatchContext(_ id: String?, connection: WatchConnectionIdentity) -> Bool {
        guard currentConnection == connection else { return false }
        return watchInputContext.accepts(id, connection: connection)
    }

    private var inputContextError: String {
        String(localized: "Terminal connection changed. Refresh the terminal and reopen input before sending. If this continues, update both apps.")
    }


    /// Wire background WatchConnectivity launches independently of SwiftUI appearing.
    func configureWatchBridge() {
        guard watchBridge == nil else { return }
        let bridge = WatchBridge.shared
        watchBridge = bridge
        isInBackground = UIApplication.shared.applicationState != .active
        bridge.onRefreshRequested = { [weak self] in self?.fetchForWatch() }
        bridge.onSendKeysRequested = { [weak self] text, special, paneID, inputContextID, reply in
            guard let self, let paneID, paneID != "?" else {
                reply(false, "Refresh the terminal before sending input.")
                return
            }
            Task { @MainActor in
                do {
                    let connection = self.currentConnection
                    guard self.watchInputContext.accepts(inputContextID, connection: connection) else {
                        reply(false, self.inputContextError)
                        return
                    }
                    try await self.sendInput(text: text, special: special, paneID: paneID, inputContextID: inputContextID, validatedConnection: connection)
                    reply(true, nil)
                } catch { reply(false, error.localizedDescription) }
            }
        }
        bridge.onSwitchSessionRequested = { [weak self] direction, inputContextID, reply in
            guard let self, StoreManager.shared.isProUnlocked, !DemoData.isDemo else {
                reply(false, "Connect a terminal and unlock Pro to switch windows.")
                return
            }
            Task { @MainActor in
                let (ok, error) = await self.switchSession(direction: direction, inputContextID: inputContextID)
                reply(ok, error)
            }
        }
        StoreManager.shared.onProStatusChanged = { [weak bridge] _ in bridge?.syncProStatus() }
    }

    // Adaptive polling state
    private var consecutiveUnchanged = 0
    private var consecutiveErrors = 0
    private var isInBackground = false
    private var powerStateObserver: NSObjectProtocol?

    static let bgRefreshID = "com.augustbenedikt.TerminalPulse.refresh"
    private static let allowedTargetScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:.-%")
    private static let preferredWindowBaseDefaultsKey = "preferredWindowBaseBySession"
    private static let shellLikeCommands: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ash", "ksh", "csh", "tcsh",
        "nu", "elvish", "xonsh", "pwsh"
    ]
    private let logger = Logger(subsystem: "com.augustbenedikt.TerminalPulse", category: "PollingService")
    private static let terminalFontMetrics = UIFontMetrics(forTextStyle: .body)

    private var renderedFontSize: CGFloat {
        let base = CGFloat(UserDefaults.standard.integer(forKey: "fontSize").clamped(to: 8...16, default: 11))
        let traits = UITraitCollection(preferredContentSizeCategory: UIApplication.shared.preferredContentSizeCategory)
        return Self.terminalFontMetrics.scaledValue(for: base, compatibleWith: traits)
    }

    var pollInterval: TimeInterval {
        Double(UserDefaults.standard.integer(forKey: "pollInterval").clamped(to: 1...120, default: 2))
    }

    /// Computed effective interval with idle/error backoff and Low Power Mode awareness.
    private var effectiveInterval: TimeInterval {
        RefreshPolicy.phoneInterval(base: pollInterval, unchanged: consecutiveUnchanged,
                                    errors: consecutiveErrors, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    func start() {
        guard !started else { return }
        configureWatchBridge()
        started = true
        isInBackground = UIApplication.shared.applicationState != .active
        loadPreferredWindowBases()
        if DemoData.isDemo {
            startDemoAnimation()
        } else if let cached = CaptureCache.load() {
            applyPayload(cached)
            // Don't send cache to watch here — let the first poll send fresh data.
            // The watch shows its own cache on launch; sending stale iPhone cache
            // would just reset the hash and cause the first real poll to be skipped.
        }
        observePowerState()
        startTimer()
    }

    func stop() {
        pollTask?.cancel()
        pendingPoll = false
        stopDemoAnimation()
        timer?.invalidate()
        timer = nil
        watchInputSyncTask?.cancel()
        watchInputSyncTask = nil
        endBackgroundPollTaskIfNeeded()
        started = false
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
            self.powerStateObserver = nil
        }
    }

    func fetchNow() {
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        requestPoll()
    }

    func sendInput(text: String? = nil, special: String? = nil, paneID: String, inputContextID: String?, validatedConnection: WatchConnectionIdentity? = nil) async throws {
        guard StoreManager.shared.isProUnlocked, !DemoData.isDemo else {
            throw APIError.badStatus(403, "Connect a terminal and unlock Pro to send input.")
        }
        guard paneID.hasPrefix("%"), paneID.dropFirst().allSatisfy(\.isNumber), paneID.count > 1 else {
            throw APIError.badStatus(400, "Choose a connected pane first.")
        }
        let connection = validatedConnection ?? currentConnection
        guard isCurrentWatchContext(inputContextID, connection: connection) else {
            throw APIError.badStatus(409, inputContextError)
        }
        let boundAPI = api(for: connection)
        _ = try await boundAPI.sendKeys(text: text, special: special, target: paneID)
        scheduleWatchInputFollowUp()
    }

    /// Watch requested a refresh — force-send result even if hash unchanged.
    func fetchForWatch() {
        if DemoData.isDemo, let payload = currentPayload {
            watchBridge?.send(payload: payload.checked(at: Date()))
            return
        }
        let connection = currentConnection
        if Date().timeIntervalSince(lastSuccessfulPoll) < min(pollInterval, 1),
           connectionIdentity == connection, let payload = currentPayload {
            watchBridge?.send(payload: payload.checked(at: lastSuccessfulPoll), inputContextID: currentPayloadInputContextID)
            return
        }
        watchNeedsSync = true
        // Preserve quiet/error backoff across watch heartbeats. The explicit
        // request still captures immediately; changed output resets the backoff.
        requestPoll()
    }

    func fetchAndWait() async {
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        await requestPollAndWait()
    }

    /// Coalesce bursty watch key events into a single near-immediate follow-up poll.
    func scheduleWatchInputFollowUp() {
        watchInputSyncTask?.cancel()
        watchInputSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            watchNeedsSync = true
            consecutiveUnchanged = 0
            consecutiveErrors = 0
            requestPoll()
        }
    }

    /// Call when the app moves to background — stop timer entirely to save battery.
    func enterBackground() {
        isInBackground = true
        timer?.invalidate()
        timer = nil
        watchInputSyncTask?.cancel()
        watchInputSyncTask = nil
        stopDemoAnimation()
        scheduleBackgroundRefresh()
    }

    /// Call when the app returns to foreground.
    func enterForeground() {
        isInBackground = false
        endBackgroundPollTaskIfNeeded()
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        watchNeedsSync = true // Watch may have stale data while we were in background
        if DemoData.isDemo {
            startDemoAnimation()
        }
        startTimer() // Restart at base interval
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called by BGTaskScheduler when the app is woken for a refresh.
    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        configureWatchBridge()
        guard UserDefaults.standard.bool(forKey: "onboardingComplete"), !DemoData.isDemo else {
            task.setTaskCompleted(success: true)
            return
        }
        isInBackground = UIApplication.shared.applicationState != .active
        scheduleBackgroundRefresh()
        var completed = false
        let work = Task { @MainActor in
            await requestPollAndWait()
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: isConnected && !Task.isCancelled)
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard !completed else { return }
                completed = true
                work.cancel()
                self?.pollTask?.cancel()
                self?.pendingPoll = false
                task.setTaskCompleted(success: false)
            }
        }
    }

    private func startTimer() {
        guard !isInBackground, !DemoData.isDemo else { return }
        timer?.invalidate()
        let interval = effectiveInterval
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.requestPoll() }
        }
        t.tolerance = interval * 0.1 // Let iOS coalesce timer wakes
        timer = t
        requestPoll()
    }

    func restartTimer() {
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        startTimer()
    }

    /// Restart the timer if the effective interval has changed significantly.
    private func rescheduleIfNeeded() {
        guard started, !isInBackground, !DemoData.isDemo else { return }
        let newInterval = effectiveInterval
        self.timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.requestPoll() }
        }
        t.tolerance = newInterval * 0.1
        self.timer = t
    }

    /// Re-render the terminal output (e.g. after font size or theme change).
    func rerender() {
        if let cached = currentPayload {
            applyPayload(cached, inputContextID: currentPayloadInputContextID)
        }
    }

    /// Push current settings to the watch immediately so it re-renders.
    func syncSettingsToWatch() {
        watchBridge?.syncSettings()
    }

    func refreshSessions() {
        let server = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        Task {
            if let resp = try? await api.fetchSessions() {
                guard server == (UserDefaults.standard.string(forKey: "serverURL") ?? "") else { return }
                sessions = resp.sessions
                await refreshWindows(for: resp.sessions, server: server)
            }
        }
    }

    private func refreshWindows(for sessions: [SessionInfo], server: String) async {
        var refreshed: [String: [WindowInfoResponse]] = [:]
        for session in sessions {
            guard server == (UserDefaults.standard.string(forKey: "serverURL") ?? "") else { return }
            if let resp = try? await api.fetchWindows(session: session.name) {
                refreshed[session.name] = resp.windows
            }
        }
        guard server == (UserDefaults.standard.string(forKey: "serverURL") ?? "") else { return }
        windowsBySession = refreshed
    }

    func selectTarget(_ target: String?) {
        selectedTarget = sanitizedTarget(target)
        lastHash = "" // Force re-render on switch
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        if isPolling { pendingPoll = true }
        fetchNow()
    }

    /// Swipe switch behavior: prefer tmux windows, fall back to sessions when needed.
    func switchSession(direction rawDirection: Int, inputContextID: String?) async -> (Bool, String?) {
        guard StoreManager.shared.isProUnlocked, !DemoData.isDemo else {
            return (false, "Connect a terminal and unlock Pro to switch windows.")
        }
        let connection = currentConnection
        guard watchInputContext.accepts(inputContextID, connection: connection) else { return (false, inputContextError) }
        let boundAPI = api(for: connection)
        let direction = rawDirection >= 0 ? 1 : -1
        do {
            // Always refresh on explicit switch so we do not rely on stale counts.
            let refreshed = try await boundAPI.fetchSessions().sessions
            guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
            sessions = refreshed
        } catch {
            if sessions.isEmpty {
                return (false, error.localizedDescription)
            }
            logger.notice("Using cached sessions after refresh failure: \(error.localizedDescription, privacy: .public)")
        }

        guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
        let available = sessions.map(\.name)
        guard !available.isEmpty else { return (false, "No tmux sessions found") }

        // Prefer the live pane session over selectedTarget so swipes advance relative
        // to what is currently visible on the watch.
        let activeSession = currentPaneSession ?? Self.sessionName(fromTarget: selectedTarget) ?? selectedTarget
        let sessionName = activeSession ?? available[0]
        let sessionInfo = sessions.first(where: { $0.name == sessionName }) ?? sessions.first
        let sessionWindowCount = max(sessionInfo?.windows ?? 1, 1)

        // Always try a window switch first. This keeps swipe behavior consistent even
        // when multiple tmux sessions exist.
        let windowResult = await switchWindowInSession(
            sessionName: sessionName,
            direction: direction,
            sessionWindowCount: sessionWindowCount,
            connection: connection,
            inputContextID: inputContextID,
            boundAPI: boundAPI
        )
        if windowResult.0 {
            return windowResult
        }

        guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
        // If the current session has only one window, fall back to switching sessions.
        guard available.count > 1, isOnlyOneWindowError(windowResult.1) else {
            return windowResult
        }

        let nextTarget: String
        if let activeSession, let currentIndex = available.firstIndex(of: activeSession) {
            let wrapped = (currentIndex + direction + available.count) % available.count
            nextTarget = available[wrapped]
        } else {
            nextTarget = direction > 0 ? available[0] : available[available.count - 1]
        }

        selectedTarget = nextTarget
        await forceSwitchPoll()
        guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }

        if !isConnected {
            return (false, errorMessage ?? "Unable to refresh capture")
        }
        if let currentPaneSession, currentPaneSession != nextTarget {
            return (false, "Session did not change")
        }
        return (true, nil)
    }

    private func switchWindowInSession(
        sessionName: String,
        direction: Int,
        sessionWindowCount: Int,
        connection: WatchConnectionIdentity,
        inputContextID: String?,
        boundAPI: APIClient
    ) async -> (Bool, String?) {
        do {
            let previousWindow = currentPaneWindowIndex
            guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
            let response = try await boundAPI.switchWindow(direction: direction, target: sessionName)
            guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
            if let pane = response.pane {
                currentPaneSession = pane.session
                currentPaneWindowIndex = pane.winIndex
                // Keep capture scoped to the session so follow-up polls track the active window.
                selectedTarget = pane.session
            } else {
                selectedTarget = sessionName
            }

            await forceSwitchPoll()
            guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }

            if !isConnected {
                return (false, errorMessage ?? "Unable to refresh capture")
            }
            if let previousWindow, currentPaneWindowIndex == previousWindow {
                return (false, "Window did not change")
            }
            return (true, nil)
        } catch let apiError as APIError where apiError.statusCode == 404 {
            logger.notice("Server missing /switch-window endpoint; using connection-bound capture probing")
            guard sessionWindowCount > 1 else {
                return (false, "Only 1 tmux window")
            }
            return await legacySwitchWindowByTargetProbe(
                sessionName: sessionName, direction: direction, windowCount: sessionWindowCount,
                connection: connection, inputContextID: inputContextID, boundAPI: boundAPI
            )
        } catch {
            return (false, userFacingSwitchError(error.localizedDescription))
        }
    }

    private func isOnlyOneWindowError(_ message: String?) -> Bool {
        guard let message else { return false }
        let lower = message.lowercased()
        return lower.contains("only 1 tmux window")
            || lower.contains("no additional tmux windows")
            || lower.contains("no additional tmux sessions or windows")
            || lower.contains("no tmux sessions or windows")
    }

    private func userFacingSwitchError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("no additional tmux windows")
            || lower.contains("no additional tmux sessions or windows")
            || lower.contains("no tmux sessions or windows") {
            return "Only 1 tmux window"
        }
        if lower.contains("can't find window") {
            return "tmux window not found"
        }
        if lower.contains("status 400") && lower.contains("direction must be non-zero") {
            return "Invalid swipe direction"
        }
        return message
    }

    private func forceSwitchPoll() async {
        lastHash = ""
        watchNeedsSync = true
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        if isPolling { pendingPoll = true }
        await requestPollAndWait()
    }

    private func wrapped(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let mod = value % count
        return mod >= 0 ? mod : mod + count
    }

    private static func windowIndex(fromTarget target: String?) -> Int? {
        guard let target, let separator = target.lastIndex(of: ":") else { return nil }
        let suffix = target[target.index(after: separator)...]
        return Int(suffix)
    }

    private static func sessionName(fromTarget target: String?) -> String? {
        guard let target else { return nil }
        guard let separator = target.firstIndex(of: ":") else { return target }
        return String(target[..<separator])
    }

    private func legacySwitchWindowByTargetProbe(
        sessionName: String,
        direction: Int,
        windowCount: Int,
        connection: WatchConnectionIdentity,
        inputContextID: String?,
        boundAPI: APIClient
    ) async -> (Bool, String?) {
        guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
        var previousWindow = currentPaneWindowIndex
        if previousWindow == nil {
            do {
                let capture = try await boundAPI.fetchCapture(target: sessionName)
                guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
                previousWindow = capture.pane?.winIndex
            } catch {
                return (false, userFacingSwitchError(error.localizedDescription))
            }
        }
        var lastObservedError: String?
        let candidates = windowCandidates(
            current: previousWindow ?? Self.windowIndex(fromTarget: selectedTarget),
            count: windowCount, direction: direction,
            preferredBase: preferredWindowBaseBySession[sessionName]
        )
        for candidateIndex in candidates {
            guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
            let candidateTarget = "\(sessionName):\(candidateIndex)"
            do {
                // Read-only probes use immutable credentials and never change the
                // global target until a matching result is validated on this phone.
                let capture = try await boundAPI.fetchCapture(target: candidateTarget)
                guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
                guard capture.pane?.session == sessionName, let observedWindow = capture.pane?.winIndex else { continue }
                if let previousWindow {
                    guard observedWindow != previousWindow else { continue }
                } else if observedWindow != candidateIndex {
                    continue
                }
                selectedTarget = candidateTarget
                if observedWindow == 0 || previousWindow == 0 {
                    preferredWindowBaseBySession[sessionName] = 0
                } else if observedWindow == windowCount || previousWindow == windowCount {
                    preferredWindowBaseBySession[sessionName] = 1
                }
                persistPreferredWindowBases()
                await forceSwitchPoll()
                guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
                return isConnected ? (true, nil) : (false, errorMessage ?? "Unable to refresh capture")
            } catch {
                guard isCurrentWatchContext(inputContextID, connection: connection) else { return (false, inputContextError) }
                lastObservedError = userFacingSwitchError(error.localizedDescription)
                let message = error.localizedDescription.lowercased()
                if message.contains("proxy") || message.contains("timed out") || message.contains("not connected") || message.contains("network") {
                    break
                }
            }
        }
        return (false, lastObservedError ?? "Window did not change")
    }

    private func windowCandidates(current: Int?, count: Int, direction: Int, preferredBase: Int?) -> [Int] {
        guard count > 1 else { return [] }
        let direction = direction >= 0 ? 1 : -1
        var result: [Int] = []

        func append(_ value: Int?) {
            guard let value else { return }
            guard !result.contains(value) else { return }
            if let current, value == current { return }
            result.append(value)
        }

        if let current {
            let zeroBased = wrapped(current + direction, count: count)
            let oneBased = wrapped((current - 1) + direction, count: count) + 1

            // Try both common tmux index bases first (remembering what worked before).
            // If unknown, bias toward 1-based for positive indexes to avoid invalid :0 probes
            // on common base-index-1 or sparse-window setups.
            let preferOneBased: Bool
            if let preferredBase {
                preferOneBased = preferredBase == 1
            } else if current == 0 {
                preferOneBased = false
            } else if current == count {
                preferOneBased = true
            } else {
                preferOneBased = true
            }

            if preferOneBased {
                append(oneBased)
                append(zeroBased)
            } else {
                append(zeroBased)
                append(oneBased)
            }

            // Then probe nearby indexes to handle sparse/non-standard layouts.
            for step in 1..<count {
                append(current + direction * step)
            }
        } else {
            for idx in 1...count { append(idx) }
            for idx in 0..<count { append(idx) }
        }

        return result
    }

    private func loadPreferredWindowBases() {
        guard let data = UserDefaults.standard.data(forKey: Self.preferredWindowBaseDefaultsKey),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            preferredWindowBaseBySession = [:]
            return
        }
        preferredWindowBaseBySession = map
    }

    private func persistPreferredWindowBases() {
        guard let data = try? JSONEncoder().encode(preferredWindowBaseBySession) else { return }
        UserDefaults.standard.set(data, forKey: Self.preferredWindowBaseDefaultsKey)
    }

    private func requestPoll() {
        guard !DemoData.isDemo else { return }
        if isPolling { return }

        isPolling = true
        timer?.invalidate()
        timer = nil
        pollTask = Task { @MainActor in
            while true {
                self.pendingPoll = false
                self.beginBackgroundPollTaskIfNeeded()
                await self.poll()
                self.endBackgroundPollTaskIfNeeded()
                guard self.pendingPoll, !Task.isCancelled else { break }
            }
            self.isPolling = false
            self.resumePollWaiters()
            self.pollTask = nil
            self.rescheduleIfNeeded()
        }
    }

    private func requestPollAndWait() async {
        guard !DemoData.isDemo else { return }
        await withCheckedContinuation { continuation in
            pollCompletionWaiters.append(continuation)
            requestPoll()
        }
    }

    private func resumePollWaiters() {
        guard !pollCompletionWaiters.isEmpty else { return }
        let waiters = pollCompletionWaiters
        pollCompletionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func beginBackgroundPollTaskIfNeeded() {
        guard isInBackground else { return }
        guard activeBackgroundPollTask == .invalid else { return }

        let app = UIApplication.shared
        activeBackgroundPollTask = app.beginBackgroundTask(withName: "WatchRefreshPoll") { [weak self] in
            guard let self else { return }
            self.pollTask?.cancel()
            self.pendingPoll = false
            if self.activeBackgroundPollTask != .invalid {
                app.endBackgroundTask(self.activeBackgroundPollTask)
                self.activeBackgroundPollTask = .invalid
            }
        }
    }

    private func endBackgroundPollTaskIfNeeded() {
        guard activeBackgroundPollTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(activeBackgroundPollTask)
        activeBackgroundPollTask = .invalid
    }

    private func poll() async {
        do {
            let connection = currentConnection
            let boundAPI = api(for: connection)
            if connectionIdentity != connection {
                connectionIdentity = connection
                cachedHostname = nil
                lastHash = ""
                lastPaneIDForCommandState = nil
                lastPaneCommand = nil
                lastLineWasPrompt = true
                sessions = []
                windowsBySession = [:]
            }
            let target = sanitizedTarget(selectedTarget)
            if target != selectedTarget {
                selectedTarget = target
            }
            let capture = try await boundAPI.fetchCapture(target: target)
            try Task.checkCancellation()
            guard target == sanitizedTarget(selectedTarget), connection == currentConnection, !DemoData.isDemo else {
                pendingPoll = !DemoData.isDemo
                return
            }
            currentPaneSession = capture.pane?.session
            currentPaneWindowIndex = capture.pane?.winIndex
            isConnected = true
            errorMessage = nil
            consecutiveErrors = 0
            // Fetch hostname once per server; refresh session inventory on demand.
            if cachedHostname == nil {
                cachedHostname = (try? await boundAPI.fetchHealth())?.hostname
                refreshSessions()
            }
            try Task.checkCancellation()
            guard target == sanitizedTarget(selectedTarget), connection == currentConnection else {
                pendingPoll = true
                return
            }
            let inputContextID = watchInputContext.establish(for: connection)
            let host = cachedHostname ?? "unknown"

            let sourcePayload = WatchPayload.from(capture: capture, host: host).checked(at: Date())
            let changed = sourcePayload.renderIdentity != lastHash || CaptureDisplayPolicy.requiresReplacement(
                acceptedIdentity: sourcePayload.renderIdentity,
                displayedIdentity: currentPayload?.renderIdentity,
                acceptedContextID: inputContextID,
                displayedContextID: currentPayloadInputContextID
            )
            let needsWatchSync = watchNeedsSync
            lastHash = sourcePayload.renderIdentity
            lastUpdate = Date()
            lastSuccessfulPoll = Date()

            // Track command state on every successful sample, including unchanged
            // terminal text and pane switches. Never notify merely for changing panes.
            let samePane = lastPaneIDForCommandState == capture.pane?.paneId
            let currentIsPrompt = NotificationService.isPromptLine(lastNonEmptyLine(from: capture.parsedLines))
            let promptFinished = samePane && !lastLineWasPrompt && currentIsPrompt
            lastLineWasPrompt = currentIsPrompt
            let commandTransition = detectCommandFinishedByPaneCommand(capture.pane)
            let commandFinished = (promptFinished || commandTransition)
                && UserDefaults.standard.bool(forKey: "notificationsEnabled")

            if commandFinished, let pane = capture.pane {
                NotificationService.notifyCommandFinished(session: pane.session, windowIndex: pane.winIndex,
                    window: pane.winName, outputLines: capture.parsedLines.map { $0.map(\.t).joined() })
            }

            // Track consecutive unchanged polls for idle backoff
            if changed {
                consecutiveUnchanged = 0
            } else {
                consecutiveUnchanged += 1
            }

            // Skip re-render if nothing changed on iPhone side
            guard changed else {
                // Displayed identity and authority already match this accepted
                // capture. Renewed authority or demo/cache exits take applyPayload
                // below so a stale pane can never acquire fresh input authority.
                if needsWatchSync || commandFinished {
                    watchNeedsSync = false
                    let payload = compactPayload(sourcePayload)
                    watchBridge?.send(payload: payload, commandFinished: commandFinished, inputContextID: inputContextID)
                }
                return
            }

            watchNeedsSync = false
            let payload = compactPayload(sourcePayload)
            applyPayload(payload, inputContextID: inputContextID)

            // Save cache off the main thread to avoid disk I/O during scrolling
            CaptureCache.save(payload)

            watchBridge?.send(payload: payload, commandFinished: commandFinished, inputContextID: inputContextID)

        } catch {
            guard !Task.isCancelled else { return }
            isConnected = false
            errorMessage = error.localizedDescription
            consecutiveErrors += 1
            rescheduleIfNeeded()
        }
    }

    private func applyPayload(_ payload: WatchPayload, inputContextID: String? = nil) {
        currentPayload = payload
        currentPayloadInputContextID = inputContextID
        renderedLines = RunsRenderer.buildLines(from: payload.runs, fontSize: renderedFontSize)
        sessionLabel = "\(payload.session):\(payload.winName)"
        // Restore timestamp from payload if we don't have a live one yet
        if lastUpdate == nil {
            lastUpdate = TerminalTimestamp.date(from: payload.ts)
        }
    }

    private func lastNonEmptyLine(from lines: [[TerminalRun]]) -> String {
        for line in lines.reversed() {
            let text = line.map(\.t).joined()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    private func detectCommandFinishedByPaneCommand(_ pane: PaneInfo?) -> Bool {
        guard let pane else {
            lastPaneIDForCommandState = nil
            lastPaneCommand = nil
            return false
        }

        let paneID = pane.paneId
        let currentCommand = pane.paneCurrentCommand?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        defer {
            lastPaneIDForCommandState = paneID
            lastPaneCommand = currentCommand
        }

        guard lastPaneIDForCommandState == paneID,
              let previous = lastPaneCommand,
              let current = currentCommand else {
            return false
        }

        return !Self.isShellLikeCommand(previous) && Self.isShellLikeCommand(current)
    }

    private static func isShellLikeCommand(_ rawCommand: String) -> Bool {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let firstToken = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let commandName = URL(fileURLWithPath: firstToken).lastPathComponent.lowercased()
        return shellLikeCommands.contains(commandName)
    }

    private func sanitizedTarget(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "?" else { return nil }
        let isValid = trimmed.unicodeScalars.allSatisfy { Self.allowedTargetScalars.contains($0) }
        return isValid ? trimmed : nil
    }

    private static let maxPayloadLines = 120
    private static let maxPayloadRunsPerLine = 180
    private static let maxPayloadCharsPerLine = 512

    /// Bound payload size to keep rendering/cache/WatchConnectivity stable while
    /// preserving the newest terminal output. Older lines are dropped silently.
    private func compactPayload(_ payload: WatchPayload) -> WatchPayload {
        var compactRuns: [[TerminalRun]] = []
        let sourceLines = payload.runs.suffix(Self.maxPayloadLines)
        compactRuns.reserveCapacity(sourceLines.count)

        for line in sourceLines {
            var remainingChars = Self.maxPayloadCharsPerLine
            var compactLine: [TerminalRun] = []
            compactLine.reserveCapacity(min(line.count, Self.maxPayloadRunsPerLine))

            for run in line.prefix(Self.maxPayloadRunsPerLine) {
                if remainingChars <= 0 {
                    break
                }
                if run.t.isEmpty {
                    continue
                }
                if run.t.count <= remainingChars {
                    compactLine.append(run)
                    remainingChars -= run.t.count
                } else {
                    let clipped = String(run.t.prefix(remainingChars))
                    compactLine.append(
                        TerminalRun(t: clipped, fg: run.fg, bg: run.bg, b: run.b, d: run.d, i: run.i, u: run.u)
                    )
                    remainingChars = 0
                }
            }

            compactRuns.append(compactLine)
        }

        return WatchPayload(
            host: payload.host,
            ts: payload.ts,
            session: payload.session,
            winIndex: payload.winIndex,
            winName: payload.winName,
            paneId: payload.paneId,
            hash: payload.hash,
            runs: compactRuns
        )
    }

    // MARK: - Power State

    private func observePowerState() {
        guard powerStateObserver == nil else { return }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rescheduleIfNeeded()
            }
        }
    }

    // MARK: - Demo Animation

    func startDemoAnimation() {
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pendingPoll = false
        stopDemoAnimation()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoSnapshot") {
            applyPayload(DemoData.payload)
            lastUpdate = Date()
            watchBridge?.send(payload: DemoData.payload)
            return
        }
        #endif
        demoTask = Task { await runDemoLoop() }
    }

    func stopDemoAnimation() {
        demoTask?.cancel()
        demoTask = nil
    }

    private func runDemoLoop() async {
        while !Task.isCancelled {
            let allLines = DemoData.payload.runs
            renderedLines = []
            sessionLabel = "dev:build"
            lastUpdate = Date()
            lastDemoWatchSend = .distantPast

            for lineIndex in 0..<allLines.count {
                guard !Task.isCancelled else { return }

                let line = allLines[lineIndex]

                if Self.isTypedCommand(line) {
                    // Pause before typing a command
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    await typeCommand(line, at: lineIndex, allLines: allLines)
                } else {
                    try? await Task.sleep(for: .seconds(Self.delayFor(line)))
                    guard !Task.isCancelled else { return }
                    renderDemoFrame(Array(allLines.prefix(lineIndex + 1)))
                }
            }

            // Send final frame to watch
            let payload = DemoData.payload
            CaptureCache.save(payload)
            watchBridge?.send(payload: payload)

            // Hold the completed terminal for a few seconds
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }

            // Clear and restart
            renderedLines = []
            try? await Task.sleep(for: .seconds(0.4))
        }
    }

    /// Type a command line character-by-character (e.g., "$ swift build")
    private func typeCommand(_ line: [TerminalRun], at lineIndex: Int, allLines: [[TerminalRun]]) async {
        guard line.count >= 3 else {
            renderDemoFrame(Array(allLines.prefix(lineIndex + 1)))
            return
        }

        let promptRuns = Array(line.prefix(2)) // ["$", " "]
        let commandRun = line[2]
        let commandText = commandRun.t
        let preceding = Array(allLines.prefix(lineIndex))

        // Show just the prompt
        renderDemoFrame(preceding + [promptRuns])
        try? await Task.sleep(for: .seconds(0.12))

        // Type each character
        for charIndex in 1...commandText.count {
            guard !Task.isCancelled else { return }
            let partial = String(commandText.prefix(charIndex))
            let partialRun = TerminalRun(t: partial, fg: commandRun.fg, bg: commandRun.bg, b: commandRun.b)
            renderDemoFrame(preceding + [promptRuns + [partialRun]])
            try? await Task.sleep(for: .seconds(0.06))
        }
    }

    private func renderDemoFrame(_ runs: [[TerminalRun]]) {
        renderedLines = RunsRenderer.buildLines(from: runs, fontSize: renderedFontSize)
        lastUpdate = Date()

        // Stream to watch, throttled to ~2 updates/sec
        let now = Date()
        if now.timeIntervalSince(lastDemoWatchSend) >= 0.5 {
            lastDemoWatchSend = now
            let payload = WatchPayload(
                host: "macbook",
                ts: ISO8601DateFormatter().string(from: now),
                session: "dev", winIndex: 0, winName: "build", paneId: "%0",
                hash: "demo-\(UUID().uuidString)",
                runs: runs
            )
            currentPayload = payload
            currentPayloadInputContextID = nil
            watchBridge?.send(payload: payload)
        }
    }

    /// A "typed command" line has exactly 3 runs: bold "$", space, command text.
    private static func isTypedCommand(_ line: [TerminalRun]) -> Bool {
        guard line.count == 3 else { return false }
        return line[0].b == true && line[0].t.trimmingCharacters(in: .whitespaces) == "$"
    }

    private static func delayFor(_ line: [TerminalRun]) -> TimeInterval {
        if line.isEmpty { return 0.04 }
        if line.first?.bg != nil { return 0.03 } // Header row with background (htop-style)
        return 0.08
    }
}
