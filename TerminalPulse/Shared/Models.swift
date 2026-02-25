import Foundation

// MARK: - Server Response Types

struct HealthResponse: Codable {
    let status: String
    let hostname: String
    let tmux: Bool
}

struct PaneInfo: Codable {
    let session: String
    let winIndex: Int
    let winName: String
    let paneId: String
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

struct TerminalRun: Codable, Sendable {
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
