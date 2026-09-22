import Foundation
import Testing
@testable import BibleReader

struct SearchTests {
    private func store() throws -> BibleStore {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        return try BibleStore(corpusURL: corpus, userURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite"))
    }

    @Test func referencesValidateAgainstTheEdition() async throws {
        let store = try store()
        for (input, expected) in [("Jn 3:16-18", "John 3:16–18"), ("1 John 2:1", "1 John 2:1"),
                                  ("Jude 5", "Jude 1:5"), ("Jude 1:5", "Jude 1:5"), ("Jude", "Jude 1"),
                                  ("Psalm 119:176", "Psalms 119:176")] {
            guard case .reference(let passage) = try await store.lookupReference(input) else {
                Issue.record("Reference failed: \(input)"); continue
            }
            #expect(passage.reference == expected)
        }
        for input in ["John 22", "John 3:99", "John 3:18-16", "John 3:16-4:2", "John 3:16,18", "Jude 26", "John 3:", "John 0"] {
            guard case .invalid = try await store.lookupReference(input) else { Issue.record("Accepted invalid reference: \(input)"); continue }
        }
        guard case .suggestion(let passage) = try await store.lookupReference("Jhon 3") else { Issue.record("Missing explicit suggestion"); return }
        #expect(passage.reference == "John 3")
    }

    @Test func searchIsSafePagedAndDeterministic() async throws {
        let store = try store()
        guard case .results(let first) = try await store.search("light"),
              case .results(let second) = try await store.search("light", offset: 50),
              case .results(let repeated) = try await store.search("LIGHT") else { Issue.record("Search failed"); return }
        #expect(first.total > 100)
        #expect(first.hits.count == 50)
        #expect(second.hits.count == 50)
        #expect(first.total == second.total)
        #expect(first.hits.map(\.id) == repeated.hits.map(\.id))
        #expect(Set(first.hits.map(\.id)).isDisjoint(with: second.hits.map(\.id)))
        #expect(first.hits.allSatisfy { $0.excerpt.contains(where: \.isMatch) })
        guard case .results(let phrase) = try await store.search("\"In the beginning God created\""),
              case .results(let lastBook) = try await store.search("\"grace of our Lord Jesus Christ be with you all\"") else { Issue.record("Phrase search failed"); return }
        #expect(phrase.hits.contains { $0.reference == "Genesis 1:1" })
        #expect(lastBook.hits.contains { $0.reference == "Revelation 22:21" })
        guard case .results(let none) = try await store.search("nonexistentscriptureword") else { Issue.record("Negative search failed"); return }
        #expect(none.total == 0)
        #expect(try await store.search("!!!") == .empty)
        // SQL/FTS metacharacters are ordinary text, not operators or executable input.
        for input in ["NEAR(light)", "light OR darkness", "God's", "\"' ; DROP TABLE verse; --\"", "light*"] {
            _ = try await store.search(input)
        }
        guard case .invalid = try await store.search("\"unclosed phrase") else { Issue.record("Unmatched quote accepted"); return }
        #expect(try await store.books().count == 66)
        #expect(Set(try await store.books().map(\.id)) == Set(BookDescriptions.values.keys))
    }

    @Test func queryAndExcerptBoundaries() throws {
        #expect(try TextSearchQuery("light darkness")?.expression == "\"light\" AND \"darkness\"")
        #expect(try TextSearchQuery("\"light of the world\"")?.expression == "\"light of the world\"")
        #expect(try TextSearchQuery("light OR dark*")?.expression == "\"light\" AND \"OR\" AND \"dark\"")
        #expect(throws: SearchInputError.tooLong) { try TextSearchQuery(String(repeating: "a", count: 201)) }
        #expect(throws: SearchInputError.tooManyTerms) { try TextSearchQuery(Array(repeating: "a", count: 33).joined(separator: " ")) }
        let source = "Light and truth."
        #expect(SearchExcerpt.fragments("\u{1e}Light\u{1f} and truth.", source: source).first?.isMatch == true)
        #expect(SearchExcerpt.fragments("\u{1e}invented\u{1f}", source: source) == [SearchFragment(text: source, isMatch: false)])
        #expect(SearchExcerpt.fragments("\u{1e}Light", source: source).first?.isMatch == false)
    }

    @MainActor @Test func lateSearchCannotReplaceNewQuery() async throws {
        let pending = PendingSearch()
        let model = SearchState { input, _ in await pending.response(for: input) }
        model.query = "old"
        let old = Task { await model.run(debounce: false) }
        await pending.waitForRequest("old")
        model.query = "new"
        let new = Task { await model.run(debounce: false) }
        await pending.waitForRequest("new")
        await pending.finish("new", response: .results(SearchPage(hits: [], total: 0)))
        await new.value
        model.scrollID = "saved-position"
        await pending.finish("old", response: .invalid("stale result"))
        await old.value
        #expect(model.status == .loaded(.results(SearchPage(hits: [], total: 0))))
        await model.run(debounce: false) // Returning to the destination keeps its completed search.
        #expect(model.scrollID == "saved-position")
        #expect(model.query == "new")
    }
}

private actor PendingSearch {
    private var requests: [String: CheckedContinuation<SearchResponse, Never>] = [:]
    func response(for input: String) async -> SearchResponse {
        await withCheckedContinuation { requests[input] = $0 }
    }
    func waitForRequest(_ input: String) async {
        while requests[input] == nil { await Task.yield() }
    }
    func finish(_ input: String, response: SearchResponse) { requests.removeValue(forKey: input)?.resume(returning: response) }
}
