import XCTest
@testable import TmuxCore

final class RefreshTests: XCTestCase {
    func testDelayedSnapshotsNeverMasqueradeAsFreshConnections() {
        XCTAssertFalse(RefreshPolicy.isFresh(payloadAge: 3600, interval: 15))
        XCTAssertTrue(RefreshPolicy.isFresh(payloadAge: 5, interval: 2.6))
        XCTAssertTrue(RefreshPolicy.isFresh(payloadAge: 125, interval: 120.6))
        XCTAssertFalse(RefreshPolicy.isFresh(payloadAge: -3600, interval: 15))
    }

    func testTwoHoursOfMissingRepliesHasBoundedWakeups() {
        var elapsed = 0.0
        var requests = 0
        while elapsed < 7200 {
            let interval = RefreshPolicy.watchInterval(base: 2, unchanged: 0, failures: requests, reduced: true)
            let delay = RefreshPolicy.delay(interval: interval, payloadAge: elapsed + 3600, requestAge: 0)
            XCTAssertGreaterThanOrEqual(delay, 8)
            elapsed += delay
            requests += 1
        }
        XCTAssertLessThan(requests, 200)
    }

    func testFreshHeartbeatPreservesContentIdentity() {
        let payload = WatchPayload(host: "mac", ts: "old", session: "dev", winIndex: 0,
                                   winName: "build", paneId: "%1", hash: "same", runs: [])
        let updated = payload.checked(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(updated.renderIdentity, payload.renderIdentity)
        XCTAssertEqual(TerminalTimestamp.date(from: updated.ts), Date(timeIntervalSince1970: 0))
    }

    func testUserIntervalNeverBecomesFasterAfterIdleBackoff() {
        for base in [2.0, 10, 30, 60, 120] {
            for unchanged in [0, 7, 12, 100] {
                XCTAssertGreaterThanOrEqual(RefreshPolicy.phoneInterval(base: base, unchanged: unchanged, errors: 0, lowPower: false), base)
                for reduced in [true, false] {
                    XCTAssertGreaterThanOrEqual(RefreshPolicy.watchInterval(base: base, unchanged: unchanged, failures: 0, reduced: reduced), base)
                }
            }
        }
    }

    func testActiveCadenceAndPowerMode() {
        XCTAssertEqual(RefreshPolicy.phoneInterval(base: 2, unchanged: 0, errors: 0, lowPower: false), 2)
        XCTAssertEqual(RefreshPolicy.phoneInterval(base: 2, unchanged: 0, errors: 0, lowPower: true), 5)
        XCTAssertEqual(RefreshPolicy.phoneInterval(base: 2, unchanged: 50, errors: 0, lowPower: true), 30)
        XCTAssertEqual(RefreshPolicy.phoneInterval(base: 2, unchanged: 0, errors: 100, lowPower: false), 120)
    }

    func testStalePayloadDoesNotCauseOneSecondRetryLoop() {
        XCTAssertEqual(RefreshPolicy.delay(interval: 30, payloadAge: 300, requestAge: 0), 30)
        XCTAssertEqual(RefreshPolicy.delay(interval: 30, payloadAge: 300, requestAge: 5), 25)
        XCTAssertEqual(RefreshPolicy.delay(interval: 30, payloadAge: 2, requestAge: 20), 28)
    }

    func testTimestampFormatsAgree() {
        let whole = TerminalTimestamp.date(from: "2026-09-09T12:00:00+00:00")
        let fractional = TerminalTimestamp.date(from: "2026-09-09T12:00:00.000000+00:00")
        XCTAssertNotNil(whole)
        XCTAssertEqual(whole, fractional)
        XCTAssertNil(TerminalTimestamp.date(from: "invalid"))
    }

    func testPromptTrailingWhitespaceAndOrdinaryOutput() {
        for prompt in ["$ ", "❯ ", "user@mac:~% ", "~/work ❯", "dev > ", "root@host:/tmp#"] {
            XCTAssertTrue(PromptDetector.isPrompt(prompt), prompt)
        }
        for output in ["", "Compiling…", "Progress 100%", "<html>", "echo hello"] {
            XCTAssertFalse(PromptDetector.isPrompt(output), output)
        }
    }

    func testIdenticalTextInDifferentPanesHasDifferentIdentity() {
        func payload(pane: String, window: String) -> WatchPayload {
            WatchPayload(host: "mac", ts: "now", session: "dev", winIndex: 0,
                         winName: window, paneId: pane, hash: "same", runs: [])
        }
        XCTAssertNotEqual(payload(pane: "%1", window: "sh").renderIdentity,
                          payload(pane: "%2", window: "sh").renderIdentity)
        XCTAssertNotEqual(payload(pane: "%1", window: "sh").renderIdentity,
                          payload(pane: "%1", window: "build").renderIdentity)
    }
}
