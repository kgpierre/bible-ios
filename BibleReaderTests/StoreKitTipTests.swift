import StoreKit
import StoreKitTest
import XCTest
import UIKit
@testable import BibleReader

final class StoreKitTipTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BIBLE_LOCAL_STOREKIT_TESTS"] != "1",
                      "Use the BibleReader-Tips scheme for local StoreKit integration tests.")
    }

    @MainActor
    func testRealProductsRepeatedPurchasesAndPendingApproval() async throws {
        // Product.purchase() requires a live confirmation scene, even with test dialogs disabled.
        for _ in 0..<100 {
            if UIApplication.shared.connectedScenes.contains(where: {
                $0.activationState == .foregroundActive && ($0 as? UIWindowScene)?.windows.contains(where: \.isKeyWindow) == true
            }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BibleTips", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let client = StoreKitTipClient()
        let store = TipStore(client: client)
        await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), TipCatalog.identifiers)
        XCTAssertEqual(store.products.map(\.displayPrice), ["$0.99", "$2.99", "$4.99"])
        let small = try XCTUnwrap(store.products.first)
        await store.purchase(small)
        XCTAssertEqual(store.message, .thanks)
        await store.purchase(small)
        XCTAssertEqual(store.message, .thanks)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == small.id }.count, 2)
        // StoreKit's daemon updates this sequence asynchronously after finish() returns.
        var unfinished: [String] = []
        for _ in 0..<100 {
            unfinished = []
            for await result in Transaction.unfinished {
                if case .verified(let transaction) = result { unfinished.append("\(transaction.id): \(transaction.productID), \(transaction.environment)") }
            }
            if unfinished.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(unfinished.isEmpty, "Consumable tips must finish; remaining: \(unfinished); test session: \(session.allTransactions().map { "\($0.identifier):\($0.productIdentifier)" })")

        session.askToBuyEnabled = true
        let medium = store.products[1]
        await store.purchase(medium)
        XCTAssertEqual(store.message, .pending)
        let pending = try XCTUnwrap(session.allTransactions().last { $0.productIdentifier == medium.id })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        for _ in 0..<100 where store.message != .thanks { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.message, .thanks)
    }
}
