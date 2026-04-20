import Foundation
import StoreKit
import Observation

@Observable
@MainActor
final class StoreManager {

    static let shared = StoreManager()

    /// Non-consumable product ID — must match your App Store Connect configuration.
    nonisolated static let premiumProductID = "gduvalsc.PhotoVideoBackupIOS.premium"

    private(set) var isPremium: Bool = false
    private(set) var product: Product?
    private(set) var isLoading: Bool = false
    private(set) var isLoadingProduct: Bool = true
    private(set) var productLoadFailed: Bool = false
    var purchaseError: String?

    private var listenerTask: Task<Void, Never>?

    private init() {
        listenerTask = startTransactionListener()
        Task { await loadAndVerify() }
    }

    // MARK: - Load products & check existing entitlements

    private func loadAndVerify() async {
        async let a: Void = fetchProduct()
        async let b: Void = verifyEntitlements()
        _ = await (a, b)
    }

    private func fetchProduct() async {
        isLoadingProduct = true
        productLoadFailed = false
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [Self.premiumProductID])
            if let p = products.first {
                product = p
            } else {
                productLoadFailed = true
            }
        } catch {
            productLoadFailed = true
        }
    }

    func retryLoadProduct() async {
        await fetchProduct()
    }

    func verifyEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.premiumProductID,
               tx.revocationDate == nil {
                found = true
                break
            }
        }
        isPremium = found
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product, !isLoading else { return }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else { return }
                await tx.finish()
                isPremium = true
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await verifyEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Background transaction listener

    private func startTransactionListener() -> Task<Void, Never> {
        Task.detached(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let tx) = result,
                      tx.productID == StoreManager.premiumProductID else { continue }
                await tx.finish()
                await MainActor.run { StoreManager.shared.isPremium = true }
            }
        }
    }
}
