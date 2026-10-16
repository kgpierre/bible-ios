import Foundation
import Observation

enum TipCatalog {
    static let identifiers = ["dev.kpierre.bible.tip.small", "dev.kpierre.bible.tip.medium", "dev.kpierre.bible.tip.large"]
}

struct TipProduct: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let displayPrice: String
}

enum TipPurchaseResult: Equatable, Sendable {
    case completed
    case cancelled
    case pending
    case ignored
    case unverified
}

@MainActor
protocol TipClient {
    var canMakePayments: Bool { get }
    func products() async throws -> [TipProduct]
    func purchase(_ id: String) async throws -> TipPurchaseResult
    func observeTransactions(_ receive: @escaping @MainActor (TipPurchaseResult) -> Void) async
}

/// Owned by the app, so a purchase or delayed approval survives closing About.
@MainActor @Observable
final class TipStore {
    enum Message: Equatable {
        case thanks, pending, failed, unverified

        var text: String {
            switch self {
            case .thanks: String(localized: "Thank you for supporting Bible!")
            case .pending: String(localized: "Your tip is awaiting approval. Apple will complete it once approved. You can keep reading.")
            case .failed: String(localized: "Your tip could not be completed. Please try again.")
            case .unverified: String(localized: "Apple’s purchase could not be verified. Please check your App Store purchase history before trying again.")
            }
        }
    }

    private(set) var products: [TipProduct] = []
    private(set) var isLoading = false
    private(set) var loadFailed = false
    private(set) var paymentsAllowed = true
    private(set) var purchasingID: String?
    private(set) var message: Message?
    @ObservationIgnored private let client: any TipClient
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(client: any TipClient = StoreKitTipClient(), observeTransactions: Bool = true) {
        self.client = client
        // Intentionally app-lived, independent of any presented screen's task.
        if observeTransactions {
            updatesTask = Task { [weak self, client] in
                await client.observeTransactions { [weak self] result in self?.receiveBackground(result) }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    /// The load belongs to the store, not the presenting view: leaving and reopening the screen
    /// mid-load joins the same request instead of discarding its result.
    func loadProducts() async {
        paymentsAllowed = client.canMakePayments
        guard paymentsAllowed else { return }
        if let loadTask { return await loadTask.value }
        isLoading = true
        loadFailed = false
        let task = Task { [self] in
            do {
                let available = try await client.products()
                products = TipCatalog.identifiers.compactMap { id in available.first { $0.id == id } }
            } catch {
                loadFailed = true
            }
            isLoading = false
            loadTask = nil
        }
        loadTask = task
        await task.value
    }

    func purchase(_ product: TipProduct) async {
        paymentsAllowed = client.canMakePayments
        guard paymentsAllowed, purchasingID == nil, products.contains(product) else { return }
        purchasingID = product.id
        message = nil
        defer { purchasingID = nil }
        do {
            receive(try await client.purchase(product.id))
        } catch {
            message = .failed
        }
    }

    /// Clears the outcome once the screen closes, including an awaiting-approval notice: a declined
    /// Ask to Buy never produces a transaction, so keeping it would leave a stale notice forever.
    /// A later approval still arrives through the app-lived listener and shows the thank-you.
    func dismissMessage() {
        message = nil
    }

    /// Deliveries outside a purchase (delayed approval, launch recovery) only ever thank. An
    /// unverified record stays unfinished and is redelivered at each launch, so warning about it
    /// here would show an unexplained error unrelated to anything the person just did.
    private func receiveBackground(_ result: TipPurchaseResult) {
        if result == .completed { message = .thanks }
    }

    private func receive(_ result: TipPurchaseResult) {
        switch result {
        case .completed: message = .thanks
        case .pending: message = .pending
        case .unverified: message = .unverified
        case .cancelled, .ignored: break
        }
    }
}
