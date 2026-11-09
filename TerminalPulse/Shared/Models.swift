import Foundation

// MARK: - Server Response Types

struct HealthResponse: Codable {
    let status: String
    let hostname: String
    let tmux: Bool
}

struct NotifyConfigResponse: Codable {
    let notifyToken: String?
    let notifyWebhookURL: String?
    let notifyRegisterURL: String?
    let notifyUnregisterURL: String?

    enum CodingKeys: String, CodingKey {
        case notifyToken = "notify_token"
        case notifyWebhookURL = "notify_webhook_url"
        case notifyRegisterURL = "notify_register_url"
        case notifyUnregisterURL = "notify_unregister_url"
    }
}

struct PaneInfo: Codable {
    let session: String
    let winIndex: Int
    let winName: String
    let paneId: String
    let paneCurrentCommand: String?
}

struct CaptureResponse: Codable {
    let raw: String
    let hash: String
    let pane: PaneInfo?
    let parsedLines: [[TerminalRun]]
    let ts: String

    enum CodingKeys: String, CodingKey {
        case raw, hash, pane, ts
        case parsedLines = "parsed_lines"
    }
}

struct SessionInfo: Codable {
    let name: String
    let windows: Int
    let attached: Bool
}

struct SessionsResponse: Codable {
    let sessions: [SessionInfo]
}

struct WindowInfoResponse: Codable {
    let session: String
    let index: Int
    let name: String
    let active: Bool
}

struct WindowsResponse: Codable {
    let windows: [WindowInfoResponse]
}

// MARK: - Terminal Run

struct TerminalRun: Codable, Sendable, Equatable {
    let t: String
    let fg: String?
    let bg: String?
    let b: Bool?
    let d: Bool?
    let i: Bool?
    let u: Bool?

    init(t: String, fg: String? = nil, bg: String? = nil,
         b: Bool? = nil, d: Bool? = nil, i: Bool? = nil, u: Bool? = nil) {
        self.t = t
        self.fg = fg
        self.bg = bg
        self.b = b
        self.d = d
        self.i = i
        self.u = u
    }
}

// MARK: - Send Keys

struct SendKeysRequest: Codable {
    var text: String?
    var special: String?
    var target: String?
}

struct SendKeysResponse: Codable {
    let ok: Bool
}

struct SwitchWindowRequest: Codable {
    var direction: Int
    var target: String?
}

struct SwitchWindowResponse: Codable {
    let ok: Bool
    let pane: PaneInfo?
}

// MARK: - Watch Payload

extension Int {
    func clamped(to range: ClosedRange<Int>, default defaultValue: Int) -> Int {
        if self == 0 { return defaultValue } // UserDefaults returns 0 for missing keys
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

struct WatchPayload: Codable, Sendable {
    let host: String
    let ts: String
    let session: String
    let winIndex: Int
    let winName: String
    let paneId: String
    let hash: String
    let runs: [[TerminalRun]]

    var renderIdentity: String { "\(host)|\(session)|\(winIndex)|\(winName)|\(paneId)|\(hash)" }

    func checked(at date: Date) -> WatchPayload {
        WatchPayload(host: host, ts: TerminalTimestamp.string(from: date), session: session,
                     winIndex: winIndex, winName: winName, paneId: paneId, hash: hash, runs: runs)
    }

    static func from(capture: CaptureResponse, host: String) -> WatchPayload {
        WatchPayload(
            host: host,
            ts: capture.ts,
            session: capture.pane?.session ?? "?",
            winIndex: capture.pane?.winIndex ?? 0,
            winName: capture.pane?.winName ?? "?",
            paneId: capture.pane?.paneId ?? "?",
            hash: capture.hash,
            runs: capture.parsedLines
        )
    }

    func toDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    static func from(dictionary: [String: Any]) -> WatchPayload? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }
}

enum TerminalTimestamp {
    private static let lock = NSLock()
    private static let whole = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        // Python's isoformat includes fractions; older cached snapshots may not.
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: value) ?? whole.date(from: value)
    }

    static func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return whole.string(from: date)
    }
}

enum RefreshPolicy {
    static func phoneInterval(base: TimeInterval, unchanged: Int, errors: Int, lowPower: Bool) -> TimeInterval {
        var interval = base
        if errors > 0 {
            interval = min(base * pow(2, Double(min(errors, 6))), max(base, 120))
        } else if unchanged > 6 {
            interval = min(base * pow(2, Double(min(unchanged - 6, 4))), max(base, 20))
        }
        return lowPower ? max(interval, unchanged > 6 ? 30 : 5) : interval
    }

    static func watchInterval(base: TimeInterval, unchanged: Int, failures: Int, reduced: Bool) -> TimeInterval {
        let minimum = reduced ? max(8, base * 2.5) : max(2.6, base + 0.6)
        let cap = max(minimum, reduced ? 30 : 15)
        var interval = min(minimum * pow(1.8, Double(max(0, min(unchanged - 2, 3)))), cap)
        if failures > 0 { interval = max(interval, min(60, 5 * pow(2, Double(min(failures, 3))))) }
        return interval
    }

    static func delay(interval: TimeInterval, payloadAge: TimeInterval, requestAge: TimeInterval) -> TimeInterval {
        // Failed/missing replies must not schedule another wake every second.
        max(1, interval - min(payloadAge, requestAge))
    }

    static func isFresh(payloadAge: TimeInterval, interval: TimeInterval) -> Bool {
        payloadAge >= -60 && payloadAge <= max(30, interval * 2 + 10)
    }
}

enum PromptDetector {
    static func isPrompt(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = text.last, "$#%>❯".contains(last) else { return false }
        if text.count == 1 { return true }
        // Be conservative: ordinary output ending in '%' or '>' isn't a prompt.
        return text.contains("@") || text.contains("~") || text.contains(":/")
            || text.hasSuffix(" ❯") || text.hasSuffix(" $") || text.hasSuffix(" #")
            || text.hasSuffix(" %") || text.hasSuffix(" >")
    }
}

// Relay counts describe APNs acceptance, never arrival on a device.
enum PushTestReceipt: Equatable {
    case accepted(Int, failed: Int)
    case noRecipients
    case rejected(Int)
    case unconfirmed

    static func parse(_ data: Data) -> PushTestReceipt {
        struct Counts: Decodable { let ok: Bool?; let delivered: Int; let failed: Int }
        guard let counts = try? JSONDecoder().decode(Counts.self, from: data),
              counts.ok != false, counts.delivered >= 0, counts.failed >= 0 else { return .unconfirmed }
        if counts.delivered > 0 { return .accepted(counts.delivered, failed: counts.failed) }
        return counts.failed > 0 ? .rejected(counts.failed) : .noRecipients
    }

    var message: String {
        switch self {
        case .accepted(let count, let failed):
            return String(format: String(localized: "APNs accepted %1$lld; %2$lld failed. Device delivery is not confirmed."), count, failed)
        case .noRecipients:
            return String(localized: "No registered devices. Enable Remote Push and notification permission, then try again.")
        case .rejected:
            return String(localized: "APNs accepted no notifications. Check the relay configuration and device registration.")
        case .unconfirmed:
            return String(localized: "Relay accepted the request but did not confirm APNs acceptance. Check your device before testing again.")
        }
    }
}

enum TerminalReadiness: Equatable {
    case tmuxUnavailable, noSessions, captureUnavailable, outputReceived

    var message: String {
        switch self {
        case .tmuxUnavailable:
            return String(localized: "Server reachable; authentication passed. Start a tmux session with tmux new -s work (install tmux if needed).")
        case .noSessions:
            return String(localized: "Server reachable; authentication passed. Start a session on the server with tmux new -s work, then test again.")
        case .captureUnavailable:
            return String(localized: "Server reachable; authentication passed; session found. First output could not be read. Check the session and test again.")
        case .outputReceived:
            return String(localized: "Server reachable; authentication passed; session found; first output received.")
        }
    }
}


/// Missing preferences are private by default, including before app registration.
enum PrivacyPreferences {
    static func protectScreenPreviews(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "protectScreenPreviews") as? Bool ?? true
    }

    static func hideNotificationDetails(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "hideNotificationDetails") as? Bool ?? true
    }
}

struct LocalCompletionNotice: Equatable {
    let title: String
    let body: String

    init(session: String, windowIndex: Int, window: String, outputLines: [String], hideDetails: Bool = true) {
        // Return before inspecting terminal content: private alerts never derive
        // any visible fields from the session, window name, or captured output.
        if hideDetails {
            title = String(localized: "Command finished")
            body = String(localized: "Open tmuxonwatch to view your terminal.")
            return
        }
        let meaningful = outputLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !PromptDetector.isPrompt($0) }
            .suffix(3)
        let windowLabel = window.trimmingCharacters(in: .whitespacesAndNewlines)
        title = String(format: String(localized: "%1$@:%2$lld %3$@ finished"), session, windowIndex, windowLabel)
        body = meaningful.isEmpty ? String(localized: "Ready for input.") : meaningful.joined(separator: "\n")
    }
}


/// Credentials stay in phone memory. Only the random ID crosses WatchConnectivity.
struct WatchConnectionIdentity: Equatable {
    let serverURL: String
    let authToken: String
}

struct WatchInputContext {
    private var identity: WatchConnectionIdentity?
    private var id: String?

    mutating func observe(_ connection: WatchConnectionIdentity) {
        if identity != connection {
            identity = connection
            id = nil
        }
    }

    mutating func establish(for connection: WatchConnectionIdentity) -> String {
        if identity != connection || id == nil {
            identity = connection
            id = UUID().uuidString
        }
        return id!
    }

    func accepts(_ suppliedID: String?, connection: WatchConnectionIdentity) -> Bool {
        guard let suppliedID, !suppliedID.isEmpty, let id else { return false }
        return id == suppliedID && identity == connection
    }

    func id(for connection: WatchConnectionIdentity) -> String? {
        identity == connection ? id : nil
    }
}


/// Displayed pane metadata and input authority must advance together. A matching
/// network hash alone says nothing about demo/cache content currently on screen.
enum CaptureDisplayPolicy {
    static func requiresReplacement(acceptedIdentity: String, displayedIdentity: String?,
                                    acceptedContextID: String, displayedContextID: String?) -> Bool {
        acceptedIdentity != displayedIdentity || acceptedContextID != displayedContextID
    }
}
