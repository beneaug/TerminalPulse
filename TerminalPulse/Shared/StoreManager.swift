import Foundation
import StoreKit

@Observable
@MainActor
final class StoreManager {
    static let shared = StoreManager()

    private(set) var isProUnlocked = false
    private(set) var proProduct: Product?
    private(set) var purchaseState: PurchaseState = .idle

    static let proProductID = "com.tmuxonwatch.pro"

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
    }

    private var updateTask: Task<Void, Never>?

    private init() {
        updateTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.checkEntitlement()
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

    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                isProUnlocked = true
                return
            }
        }
        isProUnlocked = false
    }

    func purchase() async {
        guard let product = proProduct else {
            purchaseState = .failed("Product not available")
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
        try? await AppStore.sync()
        await checkEntitlement()
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proProductID {
                    isProUnlocked = true
                }
                await transaction.finish()
            }
        }
    }
}
