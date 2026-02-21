import Foundation

actor APIClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    private var serverURL: String {
        let raw = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var authToken: String {
        KeychainService.load(key: "authToken") ?? ""
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

    func fetchCapture(lines: Int = 80, target: String? = nil) async throws -> CaptureResponse {
        var items: [URLQueryItem] = [.init(name: "lines", value: "\(lines)")]
        if let target { items.append(.init(name: "target", value: target)) }
        let req = try request(path: "/capture", queryItems: items)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(CaptureResponse.self, from: data)
    }

    func fetchHealth() async throws -> HealthResponse {
        let req = try request(path: "/health")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func fetchSessions() async throws -> SessionsResponse {
        let req = try request(path: "/sessions")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(SessionsResponse.self, from: data)
    }
}

enum APIError: LocalizedError {
    case badStatus(Int)
    case badURL(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Server returned status \(code)"
        case .badURL(let url): return "Invalid URL: \(url)"
        }
    }
}
