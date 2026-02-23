import Foundation
import WatchConnectivity

@Observable
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    var isReachable = false
    private var session: WCSession?
    var onRefreshRequested: (() -> Void)?
    var onSendKeysRequested: ((_ text: String?, _ special: String?, _ paneId: String?, _ reply: @escaping (Bool, String?) -> Void) -> Void)?
    private var syncSettingsTask: Task<Void, Never>?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        self.session = s
    }

    func send(payload: WatchPayload, commandFinished: Bool = false) {
        guard let session, session.activationState == .activated else { return }

        let fontSize = UserDefaults.standard.integer(forKey: "watchFontSize")
        let maxChars = Self.watchCharactersPerLine(fontSize: fontSize > 0 ? fontSize : 10)

        // Collapse tmux border lines that would wrap on the narrow watch screen
        let optimizedRuns = Self.collapseBorderLines(in: payload.runs, maxWidth: maxChars)
        let optimized = WatchPayload(
            host: payload.host, ts: payload.ts,
            session: payload.session, winIndex: payload.winIndex,
            winName: payload.winName, paneId: payload.paneId,
            hash: payload.hash, runs: optimizedRuns
        )

        guard var dict = optimized.toDictionary() else { return }
        if commandFinished {
            dict["commandFinished"] = true
        }
        injectSettings(into: &dict)
        transmit(dict, via: session)
    }

    /// Push current settings to the watch after a brief debounce.
    /// Prevents WCSession rate-limit flooding when sliders are dragged.
    func syncSettings() {
        syncSettingsTask?.cancel()
        syncSettingsTask = Task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            guard let session, session.activationState == .activated else { return }

            var dict: [String: Any] = ["_settingsOnly": true]
            injectSettings(into: &dict)
            transmit(dict, via: session)
        }
    }

    /// Push pro status to the watch immediately after purchase.
    func syncProStatus() {
        guard let session, session.activationState == .activated else { return }
        var dict: [String: Any] = ["_settingsOnly": true]
        injectSettings(into: &dict)
        transmit(dict, via: session)
    }

    private func injectSettings(into dict: inout [String: Any]) {
        let watchFontSize = UserDefaults.standard.integer(forKey: "watchFontSize")
        if watchFontSize > 0 {
            dict["_watchFontSize"] = watchFontSize
        }
        if let colorTheme = UserDefaults.standard.string(forKey: "colorTheme") {
            dict["_colorTheme"] = colorTheme
        }
        let pollInterval = UserDefaults.standard.integer(forKey: "pollInterval")
        if pollInterval > 0 {
            dict["_pollInterval"] = pollInterval
        }
        dict["_proUnlocked"] = StoreManager.shared.isProUnlocked
    }

    private func transmit(_ dict: [String: Any], via session: WCSession) {
        if session.isReachable {
            let wcSession = session
            session.sendMessage(dict, replyHandler: nil) { _ in
                try? wcSession.updateApplicationContext(dict)
            }
        } else {
            try? session.updateApplicationContext(dict)
        }
    }

    // MARK: - Border line collapsing

    /// Characters used in tmux horizontal pane borders and separators.
    private static let borderScalars: Set<Unicode.Scalar> = {
        var s = Set<Unicode.Scalar>()
        // Box-drawing block U+2500–U+257F
        for v in 0x2500...0x257F {
            s.insert(Unicode.Scalar(v)!)
        }
        // Common dash/dot characters that appear in borders
        for c in "-—–·.╌╍┄┅┈┉" {
            for scalar in c.unicodeScalars { s.insert(scalar) }
        }
        return s
    }()

    /// How many monospaced characters fit on the watch screen at a given font size.
    /// Watch usable width ≈ 194pt (screen minus horizontal padding).
    /// SF Mono advance ≈ fontSize × 0.78 (empirically: 24 at size 10, 35 at size 7).
    private static func watchCharactersPerLine(fontSize: Int) -> Int {
        let usableWidth: Double = 194
        let charWidth = Double(max(fontSize, 7)) * 0.78
        return Int(usableWidth / charWidth)
    }

    /// Detect lines that are predominantly horizontal border characters and replace
    /// them with a short divider that won't wrap on the watch screen.
    static func collapseBorderLines(in runs: [[TerminalRun]], maxWidth: Int = 24) -> [[TerminalRun]] {
        runs.map { line in
            let text = line.map(\.t).joined()
            let nonSpace = text.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) }
            guard nonSpace.count > 4 else { return line }

            let borderCount = nonSpace.filter { borderScalars.contains($0) }.count
            let ratio = Double(borderCount) / Double(nonSpace.count)
            guard ratio > 0.7 else { return line }

            // Find the most common border character to use in the replacement
            var freq: [Unicode.Scalar: Int] = [:]
            for s in nonSpace where borderScalars.contains(s) { freq[s, default: 0] += 1 }
            let dominant = freq.max(by: { $0.value < $1.value })?.key ?? Unicode.Scalar(0x2500)! // ─
            let divider = String(repeating: String(dominant), count: maxWidth)

            // Preserve the color from the original line
            let fg = line.first(where: { $0.fg != nil })?.fg
            let bg = line.first(where: { $0.bg != nil })?.bg
            return [TerminalRun(t: divider, fg: fg, bg: bg)]
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["action"] as? String == "refresh" {
            Task { @MainActor in
                self.onRefreshRequested?()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["action"] as? String == "sendKeys" {
            let text = message["text"] as? String
            let special = message["special"] as? String
            let paneId = message["paneId"] as? String
            Task { @MainActor in
                guard let handler = self.onSendKeysRequested else {
                    replyHandler(["ok": false, "error": "Not configured"])
                    return
                }
                handler(text, special, paneId) { ok, error in
                    if ok {
                        replyHandler(["ok": true])
                    } else {
                        replyHandler(["ok": false, "error": error ?? "Unknown error"])
                    }
                }
            }
        } else if message["action"] as? String == "refresh" {
            Task { @MainActor in
                self.onRefreshRequested?()
            }
            replyHandler(["ok": true])
        } else {
            replyHandler(["ok": false, "error": "Unknown action"])
        }
    }
}
