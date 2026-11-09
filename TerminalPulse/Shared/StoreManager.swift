import Foundation
import StoreKit

@Observable
@MainActor
final class StoreManager {
    static let shared = StoreManager()

    private(set) var isProUnlocked = false {
        didSet {
            if isProUnlocked != oldValue {
                onProStatusChanged?(isProUnlocked)
            }
        }
    }
    private(set) var proProduct: Product?
    private(set) var purchaseState: PurchaseState = .idle

    /// Called when pro status changes — iPhone uses this to sync to watch.
    var onProStatusChanged: ((Bool) -> Void)?

    static let proProductID = "tmuxonwatchpro"

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case restoring
        case restored
        case failed(String)
    }

    private var updateTask: Task<Void, Never>?

    private init() {
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.checkEntitlement()
            await self?.loadProductsWithRetry()
        }
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            // Products unavailable — StoreKit config may not be set up yet
        }
    }

    private func loadProductsWithRetry(maxAttempts: Int = 3) async {
        guard maxAttempts > 0 else { return }
        for attempt in 1...maxAttempts {
            await loadProducts()
            if proProduct != nil { return }
            if attempt < maxAttempts {
                try? await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
    }

    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil, !transaction.isUpgraded {
                isProUnlocked = true
                return
            }
        }
        isProUnlocked = false
    }

    func purchase() async {
        guard purchaseState != .purchasing && purchaseState != .restoring else { return }
        purchaseState = .purchasing
        if proProduct == nil {
            await loadProductsWithRetry(maxAttempts: 2)
        }
        guard let product = proProduct else {
            purchaseState = .failed("Product not available yet. Try again in a moment.")
            return
        }

        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isProUnlocked = true
                    purchaseState = .purchased
                } else {
                    purchaseState = .failed("The purchase could not be verified. Please try restoring it.")
                }
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        guard purchaseState != .purchasing && purchaseState != .restoring else { return }
        purchaseState = .restoring
        if proProduct == nil {
            await loadProductsWithRetry(maxAttempts: 2)
        }
        purchaseState = .restoring
        do {
            try await AppStore.sync()
        } catch {
            purchaseState = .failed(error.localizedDescription)
            return
        }
        await checkEntitlement()
        purchaseState = isProUnlocked ? .restored : .failed("No previous Pro purchase was found for this Apple ID.")
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proProductID {
                    await checkEntitlement()
                }
                await transaction.finish()
            }
        }
    }
}
