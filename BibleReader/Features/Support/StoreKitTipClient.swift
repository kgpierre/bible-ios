import StoreKit

@MainActor
final class StoreKitTipClient: TipClient {
    private var available: [String: Product] = [:]
    var canMakePayments: Bool { AppStore.canMakePayments }

    func products() async throws -> [TipProduct] {
        let products = try await Product.products(for: TipCatalog.identifiers)
            .filter { $0.type == .consumable && TipCatalog.identifiers.contains($0.id) }
        available = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return products.map { TipProduct(id: $0.id, name: $0.displayName, displayPrice: $0.displayPrice) }
    }

    func purchase(_ id: String) async throws -> TipPurchaseResult {
        guard let product = available[id], TipCatalog.identifiers.contains(id) else {
            throw TipError.unavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            let result = await complete(verification)
            // Reconcile the queue using StoreKit's latest transaction records. Local StoreKit
            // can still list a repeated consumable after finish() on the purchase result returns.
            if result == .completed { await recoverUnfinished { _ in } }
            return result
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw TipError.unavailable
        }
    }

    func observeTransactions(_ receive: @escaping @MainActor (TipPurchaseResult) -> Void) async {
        // Start the updates sequence before scanning unfinished purchases, closing the launch gap.
        // Both paths finish verified deliveries; tips grant no balance or entitlement twice.
        let updates = Transaction.updates
        async let recovery: Void = recoverUnfinished(receive)
        for await verification in updates {
            guard !Task.isCancelled else { break }
            receive(await complete(verification))
        }
        await recovery
    }

    private func recoverUnfinished(_ receive: @escaping @MainActor (TipPurchaseResult) -> Void) async {
        for await verification in Transaction.unfinished {
            guard !Task.isCancelled else { return }
            receive(await complete(verification))
        }
    }

    private func complete(_ verification: VerificationResult<Transaction>) async -> TipPurchaseResult {
        guard case .verified(let transaction) = verification else { return .unverified }
        guard TipCatalog.identifiers.contains(transaction.productID), transaction.productType == .consumable else {
            return .ignored
        }
        // Tips grant no entitlement. Acknowledge every verified delivery, including redelivery:
        // an in-memory "finished" flag must never hide a transaction StoreKit still delivers.
        await transaction.finish()
        return transaction.revocationDate == nil ? .completed : .ignored
    }

    private enum TipError: Error { case unavailable }
}
