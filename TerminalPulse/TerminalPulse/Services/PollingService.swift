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
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    var watchBridge: WatchBridge?

    static let bgRefreshID = "com.augustbenedikt.TerminalPulse.refresh"
    static var backgroundRefreshHandler: ((BGAppRefreshTask) -> Void)?

    var pollInterval: TimeInterval {
        Double(UserDefaults.standard.integer(forKey: "pollInterval").clamped(to: 1...120, default: 2))
    }

    func start() {
        if let cached = CaptureCache.load() {
            applyPayload(cached)
        }
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetchNow() {
        Task { await poll() }
    }

    func fetchAndWait() async {
        await poll()
    }

    /// Call when the app moves to background — keeps polling for as long as the OS allows.
    func enterBackground() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        scheduleBackgroundRefresh()
    }

    /// Call when the app returns to foreground.
    func enterForeground() {
        endBackgroundTask()
        startTimer() // Ensure timer is running at full speed
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 min
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called by BGTaskScheduler when the app is woken for a refresh.
    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundRefresh() // Schedule next one
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            await poll()
            task.setTaskCompleted(success: true)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.poll() }
        }
        Task { await poll() }
    }

    func restartTimer() {
        startTimer()
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
        fetchNow()
    }

    private func poll() async {
        do {
            let capture = try await api.fetchCapture(target: selectedTarget)
            isConnected = true
            errorMessage = nil

            // Only fetch hostname once; also refresh sessions periodically
            if cachedHostname == nil {
                cachedHostname = (try? await api.fetchHealth())?.hostname
                refreshSessions()
            }
            let host = cachedHostname ?? "unknown"

            let changed = capture.hash != lastHash
            lastHash = capture.hash
            lastUpdate = Date()

            // Skip re-render if nothing changed
            guard changed else { return }

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
}

