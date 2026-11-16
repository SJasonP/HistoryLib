import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class TipPurchaseActivity {
    var isActive = false
}

@MainActor
@Observable
final class TipStore {
    static let shared = TipStore()

    struct Option: Identifiable {
        let productID: String

        var id: String { productID }
    }

    static let options = [
        Option(productID: "com.SJasonP.HistoryLib.Tips.Level1"),
        Option(productID: "com.SJasonP.HistoryLib.Tips.Level2"),
        Option(productID: "com.SJasonP.HistoryLib.Tips.Level3"),
        Option(productID: "com.SJasonP.HistoryLib.Tips.Level4"),
        Option(productID: "com.SJasonP.HistoryLib.Tips.Level5")
    ]

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var statusMessage: String?
    private(set) var productLoadingMessage: String?
    private(set) var successfulPurchase = false
    private(set) var purchaseCompletionID: UUID?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var unfinishedTask: Task<Void, Never>?
    private var handledTransactions: Set<UInt64> = []

    func startObservingTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await complete(result)
            }
        }
        unfinishedTask = Task {
            for await result in Transaction.unfinished {
                guard !Task.isCancelled else { return }
                await complete(result)
            }
        }
    }

    private func complete(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result,
              Self.options.contains(where: { $0.productID == transaction.productID }),
              transaction.productType == .consumable,
              handledTransactions.insert(transaction.id).inserted else { return }
        await transaction.finish()
        guard transaction.revocationDate == nil else { return }
        successfulPurchase = true
        statusMessage = nil
        purchaseCompletionID = UUID()
    }

    /// Owned by the visible support page; cancellation stops further retries.
    func loadProductsWhileVisible() async {
        while !Task.isCancelled {
            if products.count < Self.options.count, !isPurchasing {
                await loadProducts()
            }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
        }
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let loaded = try await Product.products(for: Self.options.map(\.productID))
            guard !Task.isCancelled else { return }
            products = Self.options.compactMap { option in
                loaded.first(where: { $0.id == option.productID })
            }
            productLoadingMessage = nil
            if products.isEmpty {
                productLoadingMessage = String(localized: "Purchases are currently unavailable. Try again later.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            productLoadingMessage = String(localized: "Purchases are currently unavailable. Try again later.")
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        statusMessage = nil
        successfulPurchase = false
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                _ = try checkVerified(verification)
                await complete(verification)
            case .userCancelled:
                statusMessage = nil
            case .pending:
                statusMessage = String(localized: "Payment is pending. Apple will finish processing it later.")
            @unknown default:
                statusMessage = String(localized: "Apple could not complete the payment. Please try again or contact Apple Support.")
            }
        } catch {
            statusMessage = String(localized: "Apple could not complete the payment. Please try again or contact Apple Support.")
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw TipStoreError.failedVerification
        }
    }
}

private enum TipStoreError: Error {
    case failedVerification
}
