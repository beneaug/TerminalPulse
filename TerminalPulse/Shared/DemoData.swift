import Foundation

enum DemoData {
    /// A realistic demo WatchPayload simulating a colorful terminal session.
    /// Shows a mix of: colored prompt, htop-style header, build output, and git status.
    static let payload: WatchPayload = {
        // Helper to create a run with just text
        func plain(_ t: String) -> TerminalRun { TerminalRun(t: t) }
        func fg(_ t: String, _ color: String) -> TerminalRun { TerminalRun(t: t, fg: color) }
        func bold(_ t: String, _ color: String) -> TerminalRun { TerminalRun(t: t, fg: color, b: true) }
        func bg(_ t: String, fg: String, bg: String) -> TerminalRun { TerminalRun(t: t, fg: fg, bg: bg) }
        func dim(_ t: String) -> TerminalRun { TerminalRun(t: t, d: true) }

        let lines: [[TerminalRun]] = [
            // ── htop-style system header ──
            [bold("  CPU", "cyan"), dim(" ["), fg("||||||||||||", "green"), fg("||||||", "yellow"), fg("|||", "red"), dim("           37.2%"), dim("]")],
            [bold("  Mem", "cyan"), dim(" ["), fg("||||||||||||||||||", "green"), dim("              1.24G"), dim("/"), dim("4.00G"), dim("]")],
            [bold("  Swp", "cyan"), dim(" ["), dim("                              0K"), dim("/"), dim("2.00G"), dim("]")],
            [],
            // ── Process list header ──
            [bg("  PID USER      PRI  NI  VIRT   RES   SHR S CPU%  MEM%  TIME+  Command", fg: "black", bg: "green")],
            [bold(" 1842", "cyan"), plain(" august    "), fg("20", "white"), plain("   0 "), fg("824M", "yellow"), fg(" 142M", "green"), plain(" 38M S "), bold("12.4", "red"), plain("   3.5  2:31.08 "), fg("node server.js", "green")],
            [bold(" 2901", "cyan"), plain(" august    "), fg("20", "white"), plain("   0 "), fg("412M", "yellow"), fg("  89M", "green"), plain(" 22M S "), fg(" 4.2", "yellow"), plain("   2.2  0:44.12 "), fg("python3 capture.py", "green")],
            [bold(" 1203", "cyan"), plain(" root      "), fg("20", "white"), plain("   0 "), fg("1.2G", "yellow"), fg(" 201M", "green"), plain(" 54M S "), fg(" 2.1", "white"), plain("   5.0  5:12.44 "), fg("tmux: server", "green")],
            [bold("  891", "cyan"), plain(" august    "), fg("20", "white"), plain("   0 "), fg("312M", "yellow"), fg("  44M", "green"), plain(" 18M S "), fg(" 0.7", "white"), plain("   1.1  0:08.33 "), fg("nvim main.swift", "green")],
            [bold("    1", "cyan"), plain(" root      "), fg("20", "white"), plain("   0 "), fg("168M", "yellow"), fg("  12M", "green"), plain("  9M S "), fg(" 0.0", "white"), plain("   0.3  0:02.11 "), fg("/sbin/launchd", "white")],
            [],
            // ── tmux divider ──
            [fg("────────────────────────────────────────────────────────────────────────────────", "brBlack")],
            [],
            // ── Build output ──
            [bold("$", "green"), plain(" "), fg("swift build", "white")],
            [fg("Building for debugging...", "cyan")],
            [fg("Compiling ", "white"), bold("TerminalPulse", "yellow"), fg(" (14 sources)", "white")],
            [fg("Compiling ", "white"), bold("WatchBridge.swift", "yellow")],
            [fg("Compiling ", "white"), bold("PollingService.swift", "yellow")],
            [fg("Compiling ", "white"), bold("RunsRenderer.swift", "yellow")],
            [fg("Linking ", "white"), bold("TerminalPulse", "magenta")],
            [bold("Build complete!", "green"), fg(" (6.42s)", "brBlack")],
            [],
            // ── Git status ──
            [bold("$", "green"), plain(" "), fg("git status", "white")],
            [fg("On branch ", "white"), bold("main", "magenta")],
            [fg("Changes not staged for commit:", "yellow")],
            [fg("  modified:   ", "red"), plain("Sources/App/ContentView.swift")],
            [fg("  modified:   ", "red"), plain("Sources/App/PollingService.swift")],
            [],
            [fg("Untracked files:", "yellow")],
            [fg("  ", "white"), fg("Sources/App/DemoData.swift", "red")],
            [],
            // ── Prompt ──
            [bold("august", "green"), fg("@", "white"), bold("macbook", "blue"), fg(":", "white"), bold("~/TerminalPulse", "cyan"), fg(" (main) ", "magenta"), bold("$ ", "green"), fg("_", "white")],
        ]

        return WatchPayload(
            host: "macbook",
            ts: ISO8601DateFormatter().string(from: Date()),
            session: "dev",
            winIndex: 0,
            winName: "build",
            paneId: "%0",
            hash: "demo-\(UUID().uuidString.prefix(8))",
            runs: lines
        )
    }()

    /// Key used to track demo mode state
    static let isDemoKey = "isDemoMode"

    /// Whether the app is currently showing demo data (no real server configured)
    static var isDemo: Bool {
        UserDefaults.standard.bool(forKey: isDemoKey)
    }

    /// Activate demo mode: save demo payload to cache and mark as demo
    #if os(iOS)
    static func activate() {
        CaptureCache.save(payload)
        UserDefaults.standard.set(true, forKey: isDemoKey)
    }
    #endif

    /// Deactivate demo mode (called when a real server connects)
    static func deactivate() {
        UserDefaults.standard.set(false, forKey: isDemoKey)
    }
}
