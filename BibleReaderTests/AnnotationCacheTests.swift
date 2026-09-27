import Foundation
import Testing
@testable import BibleReader

struct AnnotationCacheTests {
    @Test @MainActor func distantNavigationPreservesAnnotationsAfterCachePrunes() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let userURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: userURL)
        let reader = ReaderState(makeStore: { store })
        await reader.load()
        #expect(!reader.loadFailed)
        let catalog = reader.catalog
        // Initial load caches chapter zero. Load 23 further chapters, reaching exactly 24.
        for chapter in catalog[1..<24] { _ = try await reader.chapterForTurn(chapter.id) }
        let target = catalog[100]
        let document = try await store.chapter(target.id)
        let verse = try #require(document.verses.first)
        let part = try #require(SavedTextPart(verseID: verse.id, text: verse.text, range: NSRange(location: 0, length: 2)))
        let passage = ExactPassage(chapterID: document.id, reference: document.reference + ":" + verse.label, parts: [part])
        _ = try await store.editExact(passage, color: .sage)
        _ = try await store.editExact(passage, color: nil, bookmarkAction: true)
        #expect(try await store.exactAnnotations(in: [target.id])[target.id]?.count == 2)
        reader.navigate(to: target)
        for _ in 0..<500 {
            if !reader.isNavigating { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reader.chapterID == target.id)
        #expect(reader.exactAnnotations(in: target.id).count == 2)
        #expect(reader.bookmarkIndicators(in: document).contains(verse.id))
        #expect(try await store.exactAnnotations(in: [target.id])[target.id]?.count == 2)
    }

    /// An older Saved rebuild that finishes after a newer one must not replace its published cache.
    @Test func overlappingSavedRebuildsKeepTheNewestResult() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let userURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: userURL)
        let document = try await store.chapter(try #require(await store.chapters().first).id)
        let verse = try #require(document.verses.first)
        let part = try #require(SavedTextPart(verseID: verse.id, text: verse.text, range: NSRange(location: 0, length: 2)))
        let passage = ExactPassage(chapterID: document.id, reference: document.reference + ":" + verse.label, parts: [part])
        func color() async throws -> HighlightColor? { try await store.savedItems().first { $0.color != nil }?.color }

        _ = try await store.editExact(passage, color: .sage)
        #expect(try await color() == .sage)
        _ = try await store.editExact(passage, color: .blue)
        let gate = RebuildGate()
        await store.setSavedResolutionHookForTesting { await gate.pass() }
        // Rebuild A resolves the blue edit, then is held before publishing.
        let older = Task { try await store.savedItems() }
        await gate.waitForArrival()
        _ = try await store.editExact(passage, color: .rose)
        // Rebuild B resolves and publishes the rose edit while A is still held.
        #expect(try await color() == .rose)
        await gate.release()
        #expect(try await older.value.first { $0.color != nil }?.color == .rose)
        await store.setSavedResolutionHookForTesting(nil)
        #expect(try await color() == .rose)
    }
}

/// Holds the first rebuild that reaches it; later rebuilds pass straight through.
private actor RebuildGate {
    private var held = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func pass() async {
        guard !held else { return }
        held = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { waiter = $0 }
    }

    func waitForArrival() async {
        guard !held else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}
