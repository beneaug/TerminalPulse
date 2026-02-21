import Foundation

enum CaptureCache {
    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("capture_cache.json")
    }

    static func save(_ payload: WatchPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    static func load() -> WatchPayload? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
