import XCTest
@testable import TmuxCore

final class WatchInputContextTests: XCTestCase {
    let a = WatchConnectionIdentity(serverURL: "https://private-a.invalid", authToken: "secret-a")
    let b = WatchConnectionIdentity(serverURL: "https://private-b.invalid", authToken: "secret-a")
    let rotatedToken = WatchConnectionIdentity(serverURL: "https://private-a.invalid", authToken: "secret-b")

    func testOnlyEstablishedCurrentContextPasses() {
        var context = WatchInputContext()
        XCTAssertFalse(context.accepts(nil, connection: a))
        XCTAssertNil(context.id(for: a))
        let id = context.establish(for: a)
        XCTAssertTrue(context.accepts(id, connection: a))
        XCTAssertFalse(context.accepts(nil, connection: a))
        XCTAssertFalse(context.accepts("", connection: a))
        XCTAssertFalse(context.accepts(UUID().uuidString, connection: a))
        XCTAssertFalse(context.accepts(id, connection: b))
        XCTAssertFalse(context.accepts(id, connection: rotatedToken))
        XCTAssertEqual(context.establish(for: a), id)
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertFalse(id.contains(a.serverURL))
        XCTAssertFalse(id.contains(a.authToken))
    }

    func testChangesInvalidateUntilFreshCaptureAndRotateID() {
        var context = WatchInputContext()
        let old = context.establish(for: a)
        context.observe(b)
        XCTAssertNil(context.id(for: b))
        XCTAssertFalse(context.accepts(old, connection: a))
        context.observe(a)
        XCTAssertFalse(context.accepts(old, connection: a))
        let fresh = context.establish(for: a)
        XCTAssertNotEqual(old, fresh)
        let newTokenID = context.establish(for: rotatedToken)
        XCTAssertNotEqual(fresh, newTokenID)
        XCTAssertFalse(context.accepts(fresh, connection: rotatedToken))
        XCTAssertTrue(context.accepts(newTokenID, connection: rotatedToken))
        XCTAssertFalse(WatchInputContext().accepts(newTokenID, connection: rotatedToken))
    }

    func testPhoneDraftPinsDisplayedCaptureRatherThanCurrentSettings() {
        var context = WatchInputContext()
        let displayedCaptureID = context.establish(for: a)
        let draftID = displayedCaptureID
        context.observe(b) // Settings changed, but B's capture has not succeeded.
        XCTAssertFalse(context.accepts(draftID, connection: b))
        XCTAssertFalse(context.accepts(displayedCaptureID, connection: b))
        XCTAssertFalse(context.accepts(nil, connection: b)) // Cache/demo has no ID.
        let newCaptureID = context.establish(for: b)
        XCTAssertFalse(context.accepts(draftID, connection: b))
        XCTAssertTrue(context.accepts(newCaptureID, connection: b))
        context.observe(rotatedToken)
        XCTAssertFalse(context.accepts(draftID, connection: rotatedToken))
    }


    func testUnchangedFreshCaptureCanRenewRevokedContext() {
        var context = WatchInputContext()
        let originalID = context.establish(for: a)
        context.observe(b)
        context.observe(a)
        let renewedID = context.establish(for: a)
        XCTAssertNotEqual(originalID, renewedID)
        XCTAssertFalse(context.accepts(originalID, connection: a))
        // Accepted unchanged captures must publish this ID to the displayed
        // payload and Watch, even when the renderer skips replacing its lines.
        XCTAssertTrue(context.accepts(renewedID, connection: a))
        XCTAssertEqual(context.id(for: a), renewedID)
    }


    func testDisplayReplacementKeepsPaneAndAuthorityTogether() {
        XCTAssertTrue(CaptureDisplayPolicy.requiresReplacement(
            acceptedIdentity: "real-pane-7", displayedIdentity: "demo-pane-0",
            acceptedContextID: "real-context", displayedContextID: nil))
        XCTAssertTrue(CaptureDisplayPolicy.requiresReplacement(
            acceptedIdentity: "same-output", displayedIdentity: "same-output",
            acceptedContextID: "renewed-context", displayedContextID: "revoked-context"))
        XCTAssertTrue(CaptureDisplayPolicy.requiresReplacement(
            acceptedIdentity: "same-output", displayedIdentity: "same-output",
            acceptedContextID: "live-context", displayedContextID: nil))
        XCTAssertFalse(CaptureDisplayPolicy.requiresReplacement(
            acceptedIdentity: "same-output", displayedIdentity: "same-output",
            acceptedContextID: "live-context", displayedContextID: "live-context"))
    }

}
