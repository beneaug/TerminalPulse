import XCTest
@testable import TmuxCore

final class WatchDisplayPolicyTests: XCTestCase {
    func testPrivacyCoversInactiveBackgroundAndAlwaysOn() {
        for isActive in [false, true] {
            for reduced in [false, true] {
                XCTAssertEqual(
                    WatchDisplayPolicy.shouldConceal(protectScreenPreviews: true, isActive: isActive, isLuminanceReduced: reduced),
                    !isActive || reduced
                )
            }
        }
    }

    func testExplicitOptOutRevealsRegardlessOfWristOrScene() {
        for isActive in [false, true] {
            for reduced in [false, true] {
                XCTAssertFalse(WatchDisplayPolicy.shouldConceal(
                    protectScreenPreviews: false, isActive: isActive, isLuminanceReduced: reduced))
            }
        }
    }

    func testReadingRetainsLinesAndSessionWhileLatestChanges() {
        var liveLines = ["build started", "working"]
        var liveSession = "work:0 shell"
        let reading = WatchReadingSnapshot(lines: liveLines, sessionLabel: liveSession)
        liveLines[1] = "build finished"
        liveLines.append("next command")
        liveSession = "private:1 logs"
        XCTAssertEqual(reading.lines, ["build started", "working"])
        XCTAssertEqual(reading.sessionLabel, "work:0 shell")
        XCTAssertNotEqual(reading.lines, liveLines)
        XCTAssertNotEqual(reading.sessionLabel, liveSession)
    }
}
