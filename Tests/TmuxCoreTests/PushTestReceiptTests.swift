import XCTest
@testable import TmuxCore

final class PushTestReceiptTests: XCTestCase {
    private func receipt(_ json: String) -> PushTestReceipt { .parse(Data(json.utf8)) }

    func testAPNsAcceptanceAndPartialFailure() {
        XCTAssertEqual(receipt(#"{"delivered":2,"failed":0}"#), .accepted(2, failed: 0))
        XCTAssertEqual(receipt(#"{"delivered":1,"failed":3}"#), .accepted(1, failed: 3))
    }

    func testZeroRecipientsAndAllRejectedAreNotSuccess() {
        XCTAssertEqual(receipt(#"{"delivered":0,"failed":0}"#), .noRecipients)
        XCTAssertEqual(receipt(#"{"delivered":0,"failed":4}"#), .rejected(4))
    }

    func testLegacyMalformedAndPartialReceiptsStayUnconfirmed() {
        for json in [#"{"ok":false,"delivered":2,"failed":0}"#, "", "ok", "{}", #"{"ok":true}"#, #"{"delivered":1}"#,
                     #"{"delivered":-1,"failed":0}"#, #"{"delivered":1,"failed":-1}"#,
                     #"{"delivered":true,"failed":0}"#, #"{"delivered":"1","failed":0}"#,
                     #"{"delivered":0.5,"failed":0}"#] {
            XCTAssertEqual(receipt(json), .unconfirmed, json)
        }
    }
}
