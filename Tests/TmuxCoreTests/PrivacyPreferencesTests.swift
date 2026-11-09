import XCTest
@testable import TmuxCore

final class PrivacyPreferencesTests: XCTestCase {
    func testMissingAndExplicitPreferences() {
        let name = "PrivacyPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(PrivacyPreferences.protectScreenPreviews(in: defaults))
        XCTAssertTrue(PrivacyPreferences.hideNotificationDetails(in: defaults))
        for value in [false, true] {
            defaults.set(value, forKey: "protectScreenPreviews")
            defaults.set(value, forKey: "hideNotificationDetails")
            XCTAssertEqual(PrivacyPreferences.protectScreenPreviews(in: defaults), value)
            XCTAssertEqual(PrivacyPreferences.hideNotificationDetails(in: defaults), value)
        }
        defaults.set("unexpected", forKey: "protectScreenPreviews")
        defaults.set("unexpected", forKey: "hideNotificationDetails")
        XCTAssertTrue(PrivacyPreferences.protectScreenPreviews(in: defaults))
        XCTAssertTrue(PrivacyPreferences.hideNotificationDetails(in: defaults))
    }

    func testPrivateNoticeNeverIncludesSensitiveContent() {
        let notice = LocalCompletionNotice(session: "secret-session", windowIndex: 987,
                                           window: "secret-window", outputLines: ["secret-token"])
        XCTAssertEqual(notice.title, "Command finished")
        XCTAssertEqual(notice.body, "Open tmuxonwatch to view your terminal.")
        let other = LocalCompletionNotice(session: "other", windowIndex: 0,
                                          window: "different", outputLines: [])
        XCTAssertEqual(notice, other)
    }

    func testDetailsRequireExplicitOptIn() {
        let notice = LocalCompletionNotice(session: "work", windowIndex: 2, window: " build ",
                                           outputLines: ["first", "second", "third", "fourth"], hideDetails: false)
        XCTAssertEqual(notice.title, "work:2 build finished")
        XCTAssertEqual(notice.body, "second\nthird\nfourth")
        let empty = LocalCompletionNotice(session: "work", windowIndex: 0, window: "zsh",
                                          outputLines: ["", "  "], hideDetails: false)
        XCTAssertEqual(empty.body, "Ready for input.")
    }
}
