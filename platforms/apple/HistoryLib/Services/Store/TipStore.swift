import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class TipStore {
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
    private(set) var statusMessage: String?
    private(set) var successfulPurchase = false
    private var hasLoaded = false

    func loadProducts() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let loaded = try await Product.products(for: Self.options.map(\.productID))
            products = Self.options.compactMap { option in
                loaded.first(where: { $0.id == option.productID })
            }
            if products.isEmpty {
                statusMessage = String(localized: "Purchases are currently unavailable. Try again later.")
            }
        } catch {
            products = []
            statusMessage = String(localized: "Purchases are currently unavailable. Try again later.")
        }
    }

    func purchase(_ product: Product) async {
        statusMessage = nil
        successfulPurchase = false

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                successfulPurchase = true
                statusMessage = String(localized: "Your tip was processed by Apple. Thank you for supporting HistoryLib.")
            case .userCancelled:
                statusMessage = String(localized: "The tip was cancelled.")
            case .pending:
                statusMessage = String(localized: "Payment is pending. Apple will finish processing it later.")
            @unknown default:
                statusMessage = String(localized: "The tip could not be completed. Please try again.")
            }
        } catch {
            statusMessage = String(localized: "The tip could not be completed. Please try again.")
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
