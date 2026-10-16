import Foundation
import Testing
@testable import BibleReader

@MainActor
struct TipStoreTests {
    @Test func cancellationPendingVerificationAndRetry() async {
        let client = TestTipClient()
        let store = TipStore(client: client, observeTransactions: false)
        await store.loadProducts()
        let small = client.catalog[0]
        client.result = .cancelled
        await store.purchase(small)
        #expect(store.message == nil)
        #expect(store.purchasingID == nil)
        client.result = .pending
        await store.purchase(small)
        #expect(store.message == .pending)
        client.result = .unverified
        await store.purchase(small)
        #expect(store.message == .unverified)
        client.purchaseFails = true
        await store.purchase(small)
        #expect(store.message == .failed)
        client.purchaseFails = false
        client.result = .completed
        await store.purchase(small)
        #expect(store.message == .thanks)
        await store.purchase(small)
        #expect(client.purchaseIDs == Array(repeating: small.id, count: 6))
    }

    @Test func missingProductsOfflineRetryAndPaymentRestrictions() async {
        let client = TestTipClient()
        let store = TipStore(client: client, observeTransactions: false)
        client.loadFails = true
        await store.loadProducts()
        #expect(store.loadFailed)
        #expect(!store.isLoading)
        client.loadFails = false
        client.catalog = [client.catalog[2], client.catalog[0], TipProduct(id: "unrelated", name: "Other", displayPrice: "$100")]
        await store.loadProducts()
        #expect(!store.loadFailed)
        #expect(store.products.map(\.id) == [TipCatalog.identifiers[0], TipCatalog.identifiers[2]])
        await store.purchase(client.catalog[2])
        #expect(client.purchaseIDs.isEmpty)
        client.canMakePayments = false
        await store.purchase(client.catalog[0])
        #expect(!store.paymentsAllowed)
        #expect(client.purchaseIDs.isEmpty)
    }

    @Test func duplicateTapDoesNotStartAnotherPurchase() async {
        let client = TestTipClient()
        let store = TipStore(client: client, observeTransactions: false)
        await store.loadProducts()
        client.suspendPurchase = true
        let first = Task { await store.purchase(client.catalog[0]) }
        while client.purchaseContinuation == nil { await Task.yield() }
        await store.purchase(client.catalog[1])
        #expect(client.purchaseIDs == [client.catalog[0].id])
        client.purchaseContinuation?.resume()
        await first.value
        #expect(store.purchasingID == nil)
        #expect(store.message == .thanks)
    }

    @Test func delayedApprovalUpdatesAppOwnedStore() async {
        let client = TestTipClient()
        let store = TipStore(client: client)
        while client.receiver == nil { await Task.yield() }
        await store.loadProducts()
        client.result = .pending
        await store.purchase(client.catalog[0])
        #expect(store.message == .pending)
        client.receiver?(.completed)
        #expect(store.message == .thanks)
    }

    @Test func reopeningDuringALoadJoinsItInsteadOfDiscardingProducts() async {
        let client = TestTipClient()
        let store = TipStore(client: client, observeTransactions: false)
        client.suspendLoad = true
        // The first screen's .task is cancelled when the person backs out mid-load.
        let first = Task { await store.loadProducts() }
        while client.loadContinuation == nil { await Task.yield() }
        first.cancel()
        let reopened = Task { await store.loadProducts() }
        await Task.yield()
        client.loadContinuation?.resume()
        await first.value
        await reopened.value
        #expect(store.products.map(\.id) == TipCatalog.identifiers)
        #expect(!store.loadFailed)
        #expect(!store.isLoading)
        #expect(client.loadCount == 1)
    }

    @Test func backgroundDeliveriesOnlyThankAndFinishedMessagesClear() async {
        let client = TestTipClient()
        let store = TipStore(client: client)
        while client.receiver == nil { await Task.yield() }
        // A stale unverified record redelivered at launch must not surface an unexplained warning.
        client.receiver?(.unverified)
        client.receiver?(.ignored)
        #expect(store.message == nil)
        await store.loadProducts()
        client.result = .pending
        await store.purchase(client.catalog[0])
        store.dismissMessage()
        #expect(store.message == nil)
        client.receiver?(.completed)
        #expect(store.message == .thanks)
        store.dismissMessage()
        #expect(store.message == nil)
    }

    @Test func declinedAskToBuyDoesNotLeaveAStalePendingNotice() async {
        let client = TestTipClient()
        let store = TipStore(client: client)
        while client.receiver == nil { await Task.yield() }
        await store.loadProducts()
        client.result = .pending
        await store.purchase(client.catalog[0])
        #expect(store.message == .pending)
        // The parent declines: StoreKit delivers nothing. Closing the screen must clear the notice,
        // and reopening must not show it again.
        store.dismissMessage()
        #expect(store.message == nil)
        await store.loadProducts()
        #expect(store.message == nil)
        // Background non-completions still never surface a message.
        client.receiver?(.pending)
        client.receiver?(.cancelled)
        #expect(store.message == nil)
    }
}

@MainActor
private final class TestTipClient: TipClient {
    var canMakePayments = true
    var loadFails = false
    var purchaseFails = false
    var suspendPurchase = false
    var suspendLoad = false
    var loadCount = 0
    var loadContinuation: CheckedContinuation<Void, Never>?
    var purchaseContinuation: CheckedContinuation<Void, Never>?
    var catalog = zip(TipCatalog.identifiers, ["Small Tip", "Medium Tip", "Large Tip"]).map {
        TipProduct(id: $0.0, name: $0.1, displayPrice: "£1.23")
    }
    var result: TipPurchaseResult = .completed
    var purchaseIDs: [String] = []
    var receiver: (@MainActor (TipPurchaseResult) -> Void)?
    func products() async throws -> [TipProduct] {
        loadCount += 1
        if suspendLoad { await withCheckedContinuation { loadContinuation = $0 } }
        if loadFails { throw Failure.test }
        return catalog
    }
    func purchase(_ id: String) async throws -> TipPurchaseResult {
        purchaseIDs.append(id)
        if suspendPurchase { await withCheckedContinuation { purchaseContinuation = $0 } }
        if purchaseFails { throw Failure.test }
        return result
    }
    func observeTransactions(_ receive: @escaping @MainActor (TipPurchaseResult) -> Void) async { receiver = receive }
    private enum Failure: Error { case test }
}
