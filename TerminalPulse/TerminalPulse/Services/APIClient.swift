import Foundation
import OSLog

actor APIClient {
    private let session: URLSession
    private let directSession: URLSession
    private let configuredServerURL: String?
    private let configuredAuthToken: String?
    private var cachedCapture: (key: String, etag: String, value: CaptureResponse)?
    private let logger = Logger(subsystem: "com.augustbenedikt.TerminalPulse", category: "APIClient")

    init(serverURL: String? = nil, authToken: String? = nil,
         session: URLSession? = nil, directSession: URLSession? = nil) {
        configuredServerURL = serverURL
        configuredAuthToken = authToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        self.session = session ?? URLSession(configuration: config)

        // Direct session bypasses system HTTP(S)/SOCKS proxies. This helps when
        // iCloud Private Relay/proxy paths return 502 for private tailnet hosts.
        let direct = URLSessionConfiguration.default
        direct.timeoutIntervalForRequest = 10
        direct.timeoutIntervalForResource = 30
        direct.waitsForConnectivity = true
        direct.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0,
            "ProxyAutoConfigEnable": 0,
            "ProxyAutoDiscoveryEnable": 0
        ]
        self.directSession = directSession ?? URLSession(configuration: direct)
    }

    private var serverURL: String {
        let raw = configuredServerURL ?? UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var authToken: String {
        configuredAuthToken ?? KeychainService.load(key: "authToken") ?? ""
    }

    private func postRequest(path: String, body: some Encodable) throws -> URLRequest {
        guard let url = URL(string: serverURL + path) else {
            throw APIError.badURL(serverURL + path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    private func request(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(string: serverURL + path) else {
            throw APIError.badURL(serverURL + path)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.badURL(serverURL + path)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func isTailnetLikeHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host.hasSuffix(".ts.net")
            || host.hasSuffix(".tail-scale.ts.net")
            || host.hasSuffix(".local")
    }

    private func shouldRetryDirect(request: URLRequest, statusCode: Int) -> Bool {
        guard isTailnetLikeHost(request.url?.host) else { return false }
        return statusCode == 502 || statusCode == 503 || statusCode == 504
    }

    private func shouldRetryDirect(request: URLRequest, error: Error) -> Bool {
        guard isTailnetLikeHost(request.url?.host) else { return false }
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        let retryable = [
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorTimedOut
        ]
        return retryable.contains(ns.code)
    }

    private func dataWithDirectFallback(for req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // A failed response does not prove a keystroke/window switch failed.
        // Never automatically replay a mutation through another network path.
        if req.httpMethod != nil && req.httpMethod != "GET" {
            let transport = isTailnetLikeHost(req.url?.host) ? directSession : session
            let (data, response) = try await transport.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
            return (data, http)
        }
        if isTailnetLikeHost(req.url?.host) {
            do {
                let (data, response) = try await directSession.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.badStatus(0)
                }
                return (data, http)
            } catch {
                try Task.checkCancellation()
                logger.notice("Tailnet direct request failed for \(req.url?.host ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public). Falling back to system session")
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.badStatus(0)
                }

                if shouldRetryDirect(request: req, statusCode: http.statusCode) {
                    logger.notice("System session returned \(http.statusCode, privacy: .public) for \(req.url?.host ?? "unknown", privacy: .public); retrying direct once")
                    if let (directData, directResponse) = try? await directSession.data(for: req),
                       let directHTTP = directResponse as? HTTPURLResponse {
                        logger.notice("Direct retry after system session returned \(directHTTP.statusCode, privacy: .public)")
                        return (directData, directHTTP)
                    }
                }
                return (data, http)
            }
        }

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.badStatus(0)
            }

            if shouldRetryDirect(request: req, statusCode: http.statusCode) {
                logger.notice("Proxy-like status \(http.statusCode, privacy: .public) for \(req.url?.host ?? "unknown", privacy: .public); retrying direct")
                if let (directData, directResponse) = try? await directSession.data(for: req),
                   let directHTTP = directResponse as? HTTPURLResponse,
                   (200...299).contains(directHTTP.statusCode) {
                    logger.notice("Direct retry succeeded with \(directHTTP.statusCode, privacy: .public)")
                    return (directData, directHTTP)
                }
            }
            return (data, http)
        } catch {
            try Task.checkCancellation()
            guard shouldRetryDirect(request: req, error: error) else {
                throw error
            }
            logger.notice("Network error \(error.localizedDescription, privacy: .public) for \(req.url?.host ?? "unknown", privacy: .public); retrying direct")
            let (directData, directResponse) = try await directSession.data(for: req)
            guard let directHTTP = directResponse as? HTTPURLResponse else {
                throw APIError.badStatus(0)
            }
            logger.notice("Direct retry finished with status \(directHTTP.statusCode, privacy: .public)")
            return (directData, directHTTP)
        }
    }

    private func statusDetail(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String,
           !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detail
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return nil
    }

    func fetchCapture(lines: Int = 80, target: String? = nil) async throws -> CaptureResponse {
        var items: [URLQueryItem] = [.init(name: "lines", value: "\(lines)"), .init(name: "compact", value: "true")]
        if let target { items.append(.init(name: "target", value: target)) }
        var req = try request(path: "/capture", queryItems: items)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let key = (req.url?.absoluteString ?? "") + (req.value(forHTTPHeaderField: "Authorization") ?? "")
        let cached = cachedCapture.flatMap { $0.key == key ? $0 : nil }
        if let cached { req.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
        let (data, http) = try await dataWithDirectFallback(for: req)
        if http.statusCode == 304, let cached {
            let value = cached.value
            return CaptureResponse(raw: value.raw, hash: value.hash, pane: value.pane,
                                   parsedLines: value.parsedLines, ts: TerminalTimestamp.string(from: Date()))
        }
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        let value = try JSONDecoder().decode(CaptureResponse.self, from: data)
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            cachedCapture = (key, etag, value)
        } else {
            cachedCapture = nil
        }
        return value
    }

    /// Checks the authenticated terminal path without changing focus or guessing a target.
    func checkReadiness() async throws -> TerminalReadiness {
        try Task.checkCancellation()
        let health = try await fetchHealth()
        try Task.checkCancellation()
        let sessions: SessionsResponse
        do {
            sessions = try await fetchSessions()
        } catch let error as APIError {
            try Task.checkCancellation()
            guard error.statusCode == 502, !health.tmux else { throw error }
            return .tmuxUnavailable
        }
        try Task.checkCancellation()
        guard !sessions.sessions.isEmpty else { return .noSessions }
        do {
            // The default target also supports older servers and Unicode session names.
            _ = try await fetchCapture()
            try Task.checkCancellation()
            return .outputReceived
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            return .captureUnavailable
        }
    }

    func fetchHealth() async throws -> HealthResponse {
        let req = try request(path: "/health")
        let (data, http) = try await dataWithDirectFallback(for: req)
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func fetchNotifyConfig() async throws -> NotifyConfigResponse {
        let req = try request(path: "/notify-config")
        let (data, http) = try await dataWithDirectFallback(for: req)
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        return try JSONDecoder().decode(NotifyConfigResponse.self, from: data)
    }

    func fetchSessions() async throws -> SessionsResponse {
        let req = try request(path: "/sessions")
        let (data, http) = try await dataWithDirectFallback(for: req)
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        return try JSONDecoder().decode(SessionsResponse.self, from: data)
    }

    func fetchWindows(session: String? = nil) async throws -> WindowsResponse {
        var items: [URLQueryItem] = []
        if let session {
            items.append(.init(name: "session", value: session))
        }
        let req = try request(path: "/windows", queryItems: items)
        let (data, http) = try await dataWithDirectFallback(for: req)
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        return try JSONDecoder().decode(WindowsResponse.self, from: data)
    }

    func switchWindow(direction: Int, target: String? = nil) async throws -> SwitchWindowResponse {
        let body = SwitchWindowRequest(direction: direction, target: target)
        let req = try postRequest(path: "/switch-window", body: body)
        let (data, http) = try await dataWithDirectFallback(for: req)
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        return try JSONDecoder().decode(SwitchWindowResponse.self, from: data)
    }

    func sendKeys(text: String? = nil, special: String? = nil, target: String? = nil) async throws -> SendKeysResponse {
        let body = SendKeysRequest(text: text, special: special, target: target)
        let req = try postRequest(path: "/send-keys", body: body)
        let (data, http) = try await dataWithDirectFallback(for: req)
        guard http.statusCode == 200 else {
            throw APIError.badStatus(http.statusCode, statusDetail(from: data))
        }
        return try JSONDecoder().decode(SendKeysResponse.self, from: data)
    }
}

enum APIError: LocalizedError {
    case badStatus(Int, String? = nil)
    case badURL(String)

    var statusCode: Int? {
        if case .badStatus(let code, _) = self {
            return code
        }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let detail):
            if let detail, !detail.isEmpty {
                return "Server returned status \(code): \(detail)"
            }
            return "Server returned status \(code)"
        case .badURL(let url): return "Invalid URL: \(url)"
        }
    }
}
