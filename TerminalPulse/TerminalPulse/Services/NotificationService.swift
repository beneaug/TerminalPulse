import UserNotifications

enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Detect if a line looks like a shell prompt.
    static func isPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Common prompt endings: "$ ", "# ", "% ", "> ", "❯ "
        let promptEndings = ["$ ", "# ", "% ", "> ", "❯ ", "❯"]
        for ending in promptEndings {
            if trimmed.hasSuffix(ending) { return true }
        }

        // Line is just a prompt char (e.g. "$ " or ">" alone)
        let promptChars: [Character] = ["$", ">", "#", "%", "❯"]
        if let first = trimmed.first, promptChars.contains(first), trimmed.count <= 2 {
            return true
        }

        // user@host:path$ pattern
        if trimmed.contains("@") && (trimmed.hasSuffix("$") || trimmed.hasSuffix("#")) {
            return true
        }

        return false
    }

    static func notifyCommandFinished(session: String, window: String, outputLines: [String]) {
        let enabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        guard enabled else { return }

        // Build body from last few non-empty output lines
        let meaningful = outputLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isPromptLine($0) }
            .suffix(3)

        let body = meaningful.joined(separator: "\n")
        guard !body.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(session):\(window) finished"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "terminalpulse.\(session).\(window)"
        content.interruptionLevel = .active

        // Use stable identifier per session:window so new notifications replace old ones
        let request = UNNotificationRequest(
            identifier: "terminalpulse.\(session).\(window)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
