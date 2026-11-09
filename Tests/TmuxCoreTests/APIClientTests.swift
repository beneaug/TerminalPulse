import Foundation
import XCTest
@testable import TmuxCore

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (status, headers, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private let capture = Data(#"{"raw":"","hash":"content","pane":{"session":"dev","winIndex":1,"winName":"build","paneId":"%1"},"parsed_lines":[[{"t":"日本語 ✓"}]],"ts":"2026-09-09T12:00:00.000Z"}"#.utf8)

    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.urlCache = nil
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel(); StubProtocol.handler = nil }
        return APIClient(serverURL: "https://unit-test.ts.net", authToken: "synthetic-test-token",
                         session: session, directSession: session)
    }

    func testConditionalResponseReusesDecodedUnicodeWithoutParsingABody() async throws {
        let api = client()
        var count = 0
        let capture = capture
        StubProtocol.handler = { request in
            count += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            XCTAssertTrue(request.url!.query!.contains("compact=true"))
            if count == 1 { return (200, ["ETag": "\"v1\""], capture) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
            return (304, [:], Data())
        }
        let first = try await api.fetchCapture(target: "%1")
        let second = try await api.fetchCapture(target: "%1")
        XCTAssertEqual(first.parsedLines, second.parsedLines)
        XCTAssertEqual(second.parsedLines[0][0].t, "日本語 ✓")
        XCTAssertEqual(count, 2)
    }

    func testDifferentTargetCannotReuseOldValidator() async throws {
        let api = client()
        let capture = capture
        StubProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return (200, ["ETag": "\"v1\""], capture)
        }
        _ = try await api.fetchCapture(target: "%1")
        _ = try await api.fetchCapture(target: "%2")
    }

    func testLegacyServerWithoutETagStillWorks() async throws {
        let api = client()
        let capture = capture
        StubProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return (200, [:], capture)
        }
        _ = try await api.fetchCapture()
        _ = try await api.fetchCapture()
    }

    func testAmbiguousKeystrokeFailureIsNeverRetried() async {
        let api = client()
        var count = 0
        StubProtocol.handler = { request in
            count += 1
            XCTAssertEqual(request.httpMethod, "POST")
            throw URLError(.networkConnectionLost)
        }
        do {
            _ = try await api.sendKeys(text: "echo hello", target: "%1")
            XCTFail("Expected network error")
        } catch { }
        XCTAssertEqual(count, 1)
    }

    func testProxyErrorCannotDuplicateWindowSwitch() async {
        let api = client()
        var count = 0
        StubProtocol.handler = { _ in
            count += 1
            return (502, [:], Data(#"{"detail":"Lost reply"}"#.utf8))
        }
        do {
            _ = try await api.switchWindow(direction: 1, target: "dev")
            XCTFail("Expected proxy error")
        } catch { }
        XCTAssertEqual(count, 1)
    }

    func testReadOnlyCaptureCanStillUseNetworkFallback() async throws {
        let api = client()
        var count = 0
        let capture = capture
        StubProtocol.handler = { _ in
            count += 1
            if count == 1 { throw URLError(.timedOut) }
            return (200, [:], capture)
        }
        _ = try await api.fetchCapture()
        XCTAssertEqual(count, 2)
    }

    private func readinessStub(tmux: Bool = true, sessionsStatus: Int = 200,
                               sessions: String = #"{"sessions":[{"name":"日本語","windows":1,"attached":false}]}"#,
                               captureStatus: Int = 200) {
        let capture = capture
        StubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            switch request.url!.path {
            case "/health":
                return (200, [:], Data("{\"status\":\"ok\",\"hostname\":\"test\",\"tmux\":\(tmux)}".utf8))
            case "/sessions": return (sessionsStatus, [:], Data(sessions.utf8))
            case "/capture":
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertFalse(query.contains { $0.name == "target" }, "Readiness must use the compatible default target")
                return (captureStatus, [:], capture)
            default:
                XCTFail("Unexpected endpoint")
                return (404, [:], Data())
            }
        }
    }

    func testReadinessReadsFirstOutputWithoutConstructingUnicodeTarget() async throws {
        let api = client()
        readinessStub()
        let result = try await api.checkReadiness()
        XCTAssertEqual(result, .outputReceived)
    }

    func testReadinessWithNoSessions() async throws {
        let api = client()
        readinessStub(tmux: false, sessions: #"{"sessions":[]}"#)
        let result = try await api.checkReadiness()
        XCTAssertEqual(result, .noSessions)
    }

    func testReadinessWithUnavailableTmux() async throws {
        let api = client()
        readinessStub(tmux: false, sessionsStatus: 502)
        let result = try await api.checkReadiness()
        XCTAssertEqual(result, .tmuxUnavailable)
    }

    func testReadinessDoesNotTreatHealthAsAuthentication() async {
        let api = client()
        readinessStub(tmux: false, sessionsStatus: 401)
        do {
            _ = try await api.checkReadiness()
            XCTFail("Authentication failure must not be reported as readiness")
        } catch { XCTAssertEqual((error as? APIError)?.statusCode, 401) }
    }

    func testReadinessPreservesAuthenticatedSetupWhenCaptureFails() async throws {
        let api = client()
        readinessStub(captureStatus: 404)
        let result = try await api.checkReadiness()
        XCTAssertEqual(result, .captureUnavailable)
    }

    func testReadinessCancellationDoesNotBecomeCaptureUnavailable() async {
        let api = client()
        readinessStub()
        let handler = StubProtocol.handler!
        StubProtocol.handler = { request in
            if request.url!.path == "/capture" { throw URLError(.cancelled) }
            return try handler(request)
        }
        do {
            _ = try await api.checkReadiness()
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
    }

    func testCancelledReadinessDoesNotStartNetworkRequests() async {
        let api = client()
        StubProtocol.handler = { _ in
            XCTFail("Cancelled check must not send requests")
            return (500, [:], Data())
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await api.checkReadiness()
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

}
