import XCTest
import StoreKit
import StoreKitTest
@testable import TerminalPulse

@MainActor
final class StoreManagerTests: XCTestCase {
    private var session: SKTestSession!
    private var store: StoreManager { .shared }

    override func setUp() async throws {
        PollingService.shared.stop()
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Products", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        await store.checkEntitlement()
        await store.loadProducts()
        XCTAssertNotNil(store.proProduct)
        XCTAssertFalse(store.isProUnlocked)
    }

    override func tearDown() async throws {
        session.clearTransactions()
        session.resetToDefaultState()
        await store.checkEntitlement()
        session = nil
    }

    func testLocalPurchaseRestoreAndRefund() async throws {
        await store.purchase()
        XCTAssertEqual(store.purchaseState, .purchased)
        XCTAssertTrue(store.isProUnlocked)
        await store.restore()
        XCTAssertEqual(store.purchaseState, .restored)
        XCTAssertTrue(store.isProUnlocked)
        let purchase = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: purchase.identifier)
        await waitForEntitlement(false)
        XCTAssertFalse(store.isProUnlocked, "Refunded entitlements must not retain input access")
    }

    func testPendingPurchaseDoesNotGrantInput() async throws {
        session.askToBuyEnabled = true
        await store.purchase()
        XCTAssertFalse(store.isProUnlocked)
        XCTAssertEqual(store.purchaseState, .pending)
        let pending = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        await waitForEntitlement(true)
        XCTAssertTrue(store.isProUnlocked)
        XCTAssertEqual(store.purchaseState, .purchased)
    }

    private func waitForEntitlement(_ expected: Bool) async {
        // StoreKit delivers approval/refund updates asynchronously.
        for _ in 0..<50 {
            await store.checkEntitlement()
            if store.isProUnlocked == expected { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func testCancelledPurchaseAndEmptyRestoreDoNotUnlock() async throws {
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await store.purchase()
        XCTAssertFalse(store.isProUnlocked)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        await store.restore()
        XCTAssertFalse(store.isProUnlocked)
        guard case .failed = store.purchaseState else {
            return XCTFail("An empty restore must not report success")
        }
    }
}
