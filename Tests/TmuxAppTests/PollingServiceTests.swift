import XCTest
@testable import TerminalPulse

@MainActor
final class PollingServiceTests: XCTestCase {
    private var service: PollingService!
    private var previousDemo = false

    override func setUp() async throws {
        // The hosted test app can resume an existing simulator's onboarding state.
        // Stop its singleton so only this test's service drives demo frames.
        PollingService.shared.stop()
        previousDemo = DemoData.isDemo
        UserDefaults.standard.set(true, forKey: DemoData.isDemoKey)
        service = PollingService()
    }

    override func tearDown() async throws {
        service.stop()
        UserDefaults.standard.set(previousDemo, forKey: DemoData.isDemoKey)
        service = nil
    }

    func testLeavingDemoPreventsFurtherDemoFrames() async throws {
        service.startDemoAnimation()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(service.renderedLines.isEmpty)
        // Settings deactivates demo before invoking its connection callback.
        DemoData.deactivate()
        let displayed = service.renderedLines
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(service.renderedLines, displayed,
                       "A completed connection must not keep receiving demo frames")
    }

    func testReadingTextAlwaysMatchesDisplayedDemoFrame() async throws {
        service.startDemoAnimation()
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(90))
            let visible = service.renderedLines.map {
                String($0.characters).trimmingCharacters(in: .whitespaces)
            }.joined(separator: "\n")
            let copied = service.plainOutput.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.joined(separator: "\n")
            XCTAssertEqual(copied, visible,
                           "Read & Find/copy must snapshot the visible frame, not the throttled Watch frame")
            XCTAssertNil(service.currentPayloadInputContextID)
        }
    }
}
