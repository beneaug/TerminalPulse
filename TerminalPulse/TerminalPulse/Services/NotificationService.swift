import Foundation
import OSLog
import UIKit
import UserNotifications

enum NotificationService {
    private static let logger = Logger(subsystem: "com.augustbenedikt.TerminalPulse", category: "NotificationService")

    private static let notifyTokenKey = "notifyToken"
    private static let notifyWebhookURLKey = "notifyWebhookURL"
    private static let notifyRegisterURLKey = "notifyRegisterURL"
    private static let notifyUnregisterURLKey = "notifyUnregisterURL"
    private static let remotePushEnabledKey = "remotePushEnabled"
    private static let apnsDeviceTokenHexKey = "apnsDeviceTokenHex"
    private static let registeredDeviceTokenKey = "registeredPushDeviceToken"
    private static let registeredNotifyTokenKey = "registeredPushNotifyToken"

    static let defaultWebhookURL = "https://www.tmuxonwatch.com/api/webhook"
    static let defaultRegisterURL = "https://www.tmuxonwatch.com/api/push/register"
    static let defaultUnregisterURL = "https://www.tmuxonwatch.com/api/push/unregister"

    struct RemoteConfig {
        let notifyToken: String?
        let notifyWebhookURL: String?
        let notifyRegisterURL: String?
        let notifyUnregisterURL: String?
    }

    static func remoteConfig(from dictionary: [String: Any]) -> RemoteConfig {
        let nestedNotify = dictionary["notify"] as? [String: Any]

        func readString(_ keys: [String]) -> String? {
            for key in keys {
                if let value = dictionary[key] as? String, !value.isEmpty { return value }
            }
            if let nestedNotify {
                for key in keys {
                    if let value = nestedNotify[key] as? String, !value.isEmpty { return value }
                }
            }
            return nil
        }

        return RemoteConfig(
            notifyToken: readString(["notifyToken", "notify_token"]),
            notifyWebhookURL: readString(["notifyWebhook", "notifyWebhookURL", "notify_webhook"]),
            notifyRegisterURL: readString(["notifyRegister", "notifyRegisterURL", "notify_register"]),
            notifyUnregisterURL: readString(["notifyUnregister", "notifyUnregisterURL", "notify_unregister"])
        )
    }

    enum RemotePushError: LocalizedError {
        case missingNotifyToken
        case badWebhookURL
        case badResponse(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingNotifyToken:
                return "Notification token missing. Re-run install and scan QR again."
            case .badWebhookURL:
                return "Webhook URL is invalid. Re-scan the install QR code."
            case .badResponse(let code, let body):
                if body.isEmpty {
                    return "Webhook failed with status \(code)."
                }
                return "Webhook failed with status \(code): \(body)"
            }
        }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                logger.error("Notification permission error: \(error.localizedDescription, privacy: .public)")
            }
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    static func configureAtLaunch() {
        let defaults = UserDefaults.standard
        let remoteEnabled = defaults.bool(forKey: remotePushEnabledKey)
        guard remoteEnabled else {
            return
        }

        // If permission was already granted in a prior run, re-register with APNs
        // so we can refresh the token after reinstalls or provisioning changes.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        Task {
            await registerDeviceWithRelayIfPossible(force: false)
        }
    }

    static func applyRemoteConfig(_ config: RemoteConfig) {
        let defaults = UserDefaults.standard

        if let rawToken = config.notifyToken?.trimmingCharacters(in: .whitespacesAndNewlines), !rawToken.isEmpty {
            defaults.set(rawToken, forKey: notifyTokenKey)
        }
        if let rawWebhook = acceptedRemoteURLString(config.notifyWebhookURL) {
            defaults.set(rawWebhook, forKey: notifyWebhookURLKey)
        }
        if let rawRegister = acceptedRemoteURLString(config.notifyRegisterURL) {
            defaults.set(rawRegister, forKey: notifyRegisterURLKey)
        }
        if let rawUnregister = acceptedRemoteURLString(config.notifyUnregisterURL) {
            defaults.set(rawUnregister, forKey: notifyUnregisterURLKey)
        }

        Task {
            await registerDeviceWithRelayIfPossible(force: true)
        }
    }

    static func handleAPNsDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: apnsDeviceTokenHexKey)

        Task {
            await registerDeviceWithRelayIfPossible(force: true)
        }
    }

    static func handleAPNsRegistrationFailure(_ error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    static func notifyToken() -> String? {
        let token = UserDefaults.standard.string(forKey: notifyTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    static func webhookURL() -> URL? {
        endpointURL(forKey: notifyWebhookURLKey, defaultValue: defaultWebhookURL)
    }

    static func registerURL() -> URL? {
        endpointURL(forKey: notifyRegisterURLKey, defaultValue: defaultRegisterURL)
    }

    static func unregisterURL() -> URL? {
        endpointURL(forKey: notifyUnregisterURLKey, defaultValue: defaultUnregisterURL)
    }

    static func webhookURLString() -> String {
        UserDefaults.standard.string(forKey: notifyWebhookURLKey) ?? defaultWebhookURL
    }

    static func curlExample() -> String? {
        guard let token = notifyToken() else { return nil }
        let url = webhookURLString()
        return [
            "curl -X POST \\",
            "  \"\(url)\" \\",
            "  -H \"Authorization: Bearer \(token)\" \\",
            "  -H \"Content-Type: application/json\" \\",
            "  -d '{",
            "    \"title\": \"Task complete\",",
            "    \"message\": \"Your command finished.\"",
            "  }'"
        ].joined(separator: "\n")
    }

    static func sendTestWebhook() async throws {
        guard let token = notifyToken() else {
            throw RemotePushError.missingNotifyToken
        }
        guard let url = webhookURL() else {
            throw RemotePushError.badWebhookURL
        }

        struct Body: Encodable {
            let title: String
            let message: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONEncoder().encode(
            Body(
                title: "tmuxonwatch test",
                message: "Remote push path is configured."
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemotePushError.badResponse(0, "No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RemotePushError.badResponse(http.statusCode, text)
        }
    }

    static func registerDeviceWithRelayIfPossible(force: Bool) async {
        let defaults = UserDefaults.standard
        let remoteEnabled = defaults.bool(forKey: remotePushEnabledKey)
        guard remoteEnabled else { return }

        guard let notifyToken = notifyToken() else { return }
        guard let deviceToken = defaults.string(forKey: apnsDeviceTokenHexKey), !deviceToken.isEmpty else { return }

        if !force,
           defaults.string(forKey: registeredDeviceTokenKey) == deviceToken,
           defaults.string(forKey: registeredNotifyTokenKey) == notifyToken {
            return
        }

        guard let url = registerURL() else {
            logger.error("Push register URL invalid")
            return
        }

        struct RegisterBody: Encodable {
            let deviceToken: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notifyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONEncoder().encode(
                RegisterBody(deviceToken: deviceToken)
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.error("Push registration failed with status \(http.statusCode, privacy: .public): \(body, privacy: .public)")
                return
            }

            defaults.set(deviceToken, forKey: registeredDeviceTokenKey)
            defaults.set(notifyToken, forKey: registeredNotifyTokenKey)
        } catch {
            logger.error("Push registration request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func unregisterDeviceFromRelayIfPossible(clearRegistrationState: Bool = true) async {
        let defaults = UserDefaults.standard
        guard let notifyToken = notifyToken() else {
            if clearRegistrationState {
                defaults.removeObject(forKey: registeredDeviceTokenKey)
                defaults.removeObject(forKey: registeredNotifyTokenKey)
            }
            return
        }
        guard let deviceToken = defaults.string(forKey: apnsDeviceTokenHexKey), !deviceToken.isEmpty else {
            if clearRegistrationState {
                defaults.removeObject(forKey: registeredDeviceTokenKey)
                defaults.removeObject(forKey: registeredNotifyTokenKey)
            }
            return
        }
        guard let url = unregisterURL() else { return }

        struct Body: Encodable {
            let deviceToken: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(notifyToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try JSONEncoder().encode(Body(deviceToken: deviceToken))
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if clearRegistrationState {
                    defaults.removeObject(forKey: registeredDeviceTokenKey)
                    defaults.removeObject(forKey: registeredNotifyTokenKey)
                }
            }
        } catch {
            logger.error("Push unregister request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func endpointURL(forKey key: String, defaultValue: String) -> URL? {
        let raw = UserDefaults.standard.string(forKey: key) ?? defaultValue
        guard let accepted = acceptedRemoteURLString(raw) else { return nil }
        return URL(string: accepted)
    }

    private static func acceptedRemoteURLString(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return nil
        }

        if scheme == "https" {
            return canonicalizedRelayURLString(trimmed)
        }

        if scheme == "http", let host = url.host?.lowercased(), ["localhost", "127.0.0.1"].contains(host) {
            return trimmed
        }

        return nil
    }

    private static func canonicalizedRelayURLString(_ raw: String) -> String {
        guard var components = URLComponents(string: raw),
              let host = components.host?.lowercased() else {
            return raw
        }

        if host == "tmuxonwatch.com" {
            components.host = "www.tmuxonwatch.com"
            return components.string ?? raw
        }

        return raw
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

    static func notifyCommandFinished(session: String, windowIndex: Int, window: String, outputLines: [String]) {
        // Build body from last few non-empty output lines
        let meaningful = outputLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isPromptLine($0) }
            .suffix(3)

        let body = meaningful.isEmpty ? "Ready for input." : meaningful.joined(separator: "\n")
        let windowLabel = window.trimmingCharacters(in: .whitespacesAndNewlines)
        let threadID = "terminalpulse.\(session).\(windowIndex)"
        let notificationID = "terminalpulse.\(session).\(windowIndex)"

        let content = UNMutableNotificationContent()
        content.title = "\(session):\(windowIndex) \(windowLabel) finished"
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadID
        content.interruptionLevel = .active

        // Use stable identifier per session:windowIndex so new notifications replace old ones
        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
