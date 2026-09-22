import Foundation
import Observation

@MainActor
@Observable
final class SearchState {
    enum Status: Equatable { case idle, loading, loaded(SearchResponse), failed }
    var query = "" {
        didSet {
            guard oldValue != query else { return }
            requestID = UUID()
            completedQuery = nil
            status = query.isEmpty ? .idle : .loading
            scrollID = nil
            selectedID = nil
            pageError = false
            isLoadingMore = false
        }
    }
    private(set) var status: Status = .idle
    private(set) var isLoadingMore = false
    private(set) var pageError = false
    var retryToken = 0
    var focusRequest = 0
    var scrollID: String?
    var selectedID: String?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var completedQuery: String?
    @ObservationIgnored private let search: @Sendable (String, Int) async throws -> SearchResponse

    init(search: @escaping @Sendable (String, Int) async throws -> SearchResponse) { self.search = search }

    func run(debounce: Bool = true) async {
        guard completedQuery != query else { return }
        let request = UUID()
        requestID = request
        let input = query
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = .idle; return }
        status = .loading
        do {
            if debounce { try await Task.sleep(for: .milliseconds(200)) }
            let response = try await search(input,0)
            try Task.checkCancellation()
            guard request == requestID else { return }
            status = .loaded(response)
            completedQuery = input
        } catch is CancellationError {
            if request == requestID { status = .idle }
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            status = .failed
        }
    }

    func loadMore() async {
        guard case .loaded(.results(var page)) = status, page.hasMore, !isLoadingMore else { return }
        let request = requestID, input = query
        isLoadingMore = true
        pageError = false
        defer { if request == requestID { isLoadingMore = false } }
        do {
            let response = try await search(input,page.hits.count)
            try Task.checkCancellation()
            guard request == requestID, case .results(let next) = response else { return }
            page.hits.append(contentsOf: next.hits)
            status = .loaded(.results(page))
        } catch is CancellationError { } catch {
            if request == requestID { pageError = true }
        }
    }

    func retry() { completedQuery = nil; retryToken += 1 }
}
