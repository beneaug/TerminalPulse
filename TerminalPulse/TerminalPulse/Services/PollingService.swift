import Foundation
import UIKit
import SwiftUI
import BackgroundTasks

@Observable
@MainActor
final class PollingService {
    var renderedLines: [AttributedString] = []
    var sessionLabel = ""
    var lastUpdate: Date?
    var isConnected = false
    var errorMessage: String?
    var sessions: [SessionInfo] = []
    var selectedTarget: String?

    private let api = APIClient()
    private var timer: Timer?
    private var lastHash = ""
    private var cachedHostname: String?
    private var lastLineWasPrompt = true // Start true so first poll doesn't notify
    private var demoTask: Task<Void, Never>?
    private var lastDemoWatchSend: Date = .distantPast
    private var watchNeedsSync = true // Always send first successful poll to watch
    var watchBridge: WatchBridge?

    // Adaptive polling state
    private var consecutiveUnchanged = 0
    private var consecutiveErrors = 0
    private var isInBackground = false
    private var powerStateObserver: NSObjectProtocol?

    static let bgRefreshID = "com.augustbenedikt.TerminalPulse.refresh"
    static var backgroundRefreshHandler: ((BGAppRefreshTask) -> Void)?

    var pollInterval: TimeInterval {
        Double(UserDefaults.standard.integer(forKey: "pollInterval").clamped(to: 1...120, default: 2))
    }

    /// Computed effective interval with idle/error backoff and Low Power Mode awareness.
    private var effectiveInterval: TimeInterval {
        let base = pollInterval
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        var interval: TimeInterval

        if consecutiveErrors > 0 {
            // Error backoff: base * 2^min(errors, 6), capped at 120s
            let exponent = min(consecutiveErrors, 6)
            interval = min(base * pow(2.0, Double(exponent)), 120)
        } else if consecutiveUnchanged > 2 {
            // Idle backoff: base * 2^min(unchanged-2, 2), capped at 10s
            let exponent = min(consecutiveUnchanged - 2, 2)
            interval = min(base * pow(2.0, Double(exponent)), 10)
        } else {
            interval = base
        }

        // Low Power Mode floors
        if isLowPower {
            let floor: TimeInterval = consecutiveUnchanged > 2 ? 30 : 5
            interval = max(interval, floor)
        }

        return interval
    }

    func start() {
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
        timer?.invalidate()
        timer = nil
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
            self.powerStateObserver = nil
        }
    }

    func fetchNow() {
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        Task { await poll() }
    }

    /// Watch requested a refresh — force-send result even if hash unchanged.
    func fetchForWatch() {
        watchNeedsSync = true
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        Task { await poll() }
    }

    func fetchAndWait() async {
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        await poll()
    }

    /// Call when the app moves to background — stop timer entirely to save battery.
    func enterBackground() {
        isInBackground = true
        timer?.invalidate()
        timer = nil
        stopDemoAnimation()
        scheduleBackgroundRefresh()
    }

    /// Call when the app returns to foreground.
    func enterForeground() {
        isInBackground = false
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
        // Only reschedule if terminal was active before backgrounding
        if consecutiveUnchanged == 0 {
            scheduleBackgroundRefresh()
        }
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            await poll()
            task.setTaskCompleted(success: true)
        }
    }

    private func startTimer() {
        guard !isInBackground else { return }
        timer?.invalidate()
        let interval = effectiveInterval
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
        }
        t.tolerance = interval * 0.1 // Let iOS coalesce timer wakes
        timer = t
        Task { await poll() }
    }

    func restartTimer() {
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        startTimer()
    }

    /// Restart the timer if the effective interval has changed significantly.
    private func rescheduleIfNeeded() {
        guard !isInBackground, let timer, timer.isValid else { return }
        let currentInterval = timer.timeInterval
        let newInterval = effectiveInterval
        guard abs(currentInterval - newInterval) > 0.5 else { return }
        self.timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: newInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
        }
        t.tolerance = newInterval * 0.1
        self.timer = t
    }

    /// Re-render the terminal output (e.g. after font size or theme change).
    func rerender() {
        if let cached = CaptureCache.load() {
            applyPayload(cached)
        }
    }

    /// Push current settings to the watch immediately so it re-renders.
    func syncSettingsToWatch() {
        watchBridge?.syncSettings()
    }

    func refreshSessions() {
        Task {
            if let resp = try? await api.fetchSessions() {
                sessions = resp.sessions
            }
        }
    }

    func selectTarget(_ target: String?) {
        selectedTarget = target
        lastHash = "" // Force re-render on switch
        consecutiveUnchanged = 0
        consecutiveErrors = 0
        fetchNow()
    }

    private func poll() async {
        do {
            let capture = try await api.fetchCapture(target: selectedTarget)
            isConnected = true
            errorMessage = nil
            consecutiveErrors = 0
            if DemoData.isDemo {
                DemoData.deactivate()
                stopDemoAnimation()
            }

            // Only fetch hostname once; also refresh sessions periodically
            if cachedHostname == nil {
                cachedHostname = (try? await api.fetchHealth())?.hostname
                refreshSessions()
            }
            let host = cachedHostname ?? "unknown"

            let changed = capture.hash != lastHash
            let needsWatchSync = watchNeedsSync
            lastHash = capture.hash
            lastUpdate = Date()

            // Track consecutive unchanged polls for idle backoff
            if changed {
                consecutiveUnchanged = 0
            } else {
                consecutiveUnchanged += 1
            }
            rescheduleIfNeeded()

            // Skip re-render if nothing changed on iPhone side
            guard changed else {
                // Even if hash didn't change, sync to watch if it needs fresh data
                if needsWatchSync {
                    watchNeedsSync = false
                    let payload = WatchPayload.from(capture: capture, host: host)
                    watchBridge?.send(payload: payload)
                }
                return
            }

            watchNeedsSync = false
            let payload = WatchPayload.from(capture: capture, host: host)
            applyPayload(payload)

            // Save cache off the main thread to avoid disk I/O during scrolling
            let payloadCopy = payload
            Task.detached { CaptureCache.save(payloadCopy) }

            // Detect command-finished: prompt appeared after non-prompt output
            let lastLine = lastNonEmptyLine(from: capture.parsedLines)
            let currentIsPrompt = NotificationService.isPromptLine(lastLine)
            let commandFinished = !lastLineWasPrompt && currentIsPrompt
            lastLineWasPrompt = currentIsPrompt

            watchBridge?.send(payload: payload, commandFinished: commandFinished)

            if commandFinished, let pane = capture.pane {
                let allLines = capture.parsedLines.map { line in
                    line.map(\.t).joined()
                }
                NotificationService.notifyCommandFinished(
                    session: pane.session,
                    window: pane.winName,
                    outputLines: allLines
                )
            }
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
            consecutiveErrors += 1
            rescheduleIfNeeded()
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private func applyPayload(_ payload: WatchPayload) {
        let size = CGFloat(UserDefaults.standard.integer(forKey: "fontSize").clamped(to: 8...16, default: 11))
        renderedLines = RunsRenderer.buildLines(from: payload.runs, fontSize: size)
        sessionLabel = "\(payload.session):\(payload.winName)"
        // Restore timestamp from payload if we don't have a live one yet
        if lastUpdate == nil {
            lastUpdate = Self.isoFormatter.date(from: payload.ts)
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

    // MARK: - Power State

    private func observePowerState() {
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
        stopDemoAnimation()
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
            Task.detached { CaptureCache.save(payload) }
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
        let size = CGFloat(UserDefaults.standard.integer(forKey: "fontSize").clamped(to: 8...16, default: 11))
        renderedLines = RunsRenderer.buildLines(from: runs, fontSize: size)
        lastUpdate = Date()

        // Stream to watch, throttled to ~2 updates/sec
        let now = Date()
        if now.timeIntervalSince(lastDemoWatchSend) >= 0.5 {
            lastDemoWatchSend = now
            let payload = WatchPayload(
                host: "macbook",
                ts: ISO8601DateFormatter().string(from: now),
                session: "dev", winIndex: 0, winName: "build", paneId: "%0",
                hash: "demo-\(runs.count)",
                runs: runs
            )
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

