import Testing
import Foundation
import SQLite3
@testable import BibleReader

struct SavedChapterTests {
    private let john3 = "eng-kjv-1769-protestant:JHN:3"
    private let psalm23 = "eng-kjv-1769-protestant:PSA:23"

    private func makeStore() throws -> (BibleStore, URL, URL) {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        return (try BibleStore(corpusURL: corpus, userURL: user), corpus, user)
    }

    private func sql(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
    }

    @Test func v3StoreMigratesWithBackupAndKeepsAnnotations() async throws {
        let (store, corpus, url) = try makeStore()
        _ = try await store.edit(verseIDs: [john3 + ":16"], color: .yellow, bookmark: true)
        // Return the store to the shipped v3 schema: no saved_chapter table, v4 not applied.
        try sql("DROP TABLE saved_chapter; DELETE FROM grdb_migrations WHERE identifier='v4_saved_chapters'", at: url)
        let migrated = try BibleStore(corpusURL: corpus, userURL: url)
        #expect(try await migrated.annotations().highlights.count == 1)
        #expect(try await migrated.annotations().bookmarks.count == 1)
        #expect(try await migrated.savedChapterIDs().isEmpty)
        let backup = url.deletingLastPathComponent().appendingPathComponent("User-before-migration.sqlite")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        _ = try await migrated.setChapterSaved(john3, saved: true)
        #expect(try await migrated.savedChapterIDs() == [john3])
    }

    @Test func savingIsIdempotentAndSurvivesReopening() async throws {
        let (store, corpus, url) = try makeStore()
        let first = try await store.setChapterSaved(john3, saved: true)
        let second = try await store.setChapterSaved(john3, saved: true)
        #expect(first.before == nil)
        #expect(second.before == first.after)
        #expect(second.after == first.after)
        let reopened = try BibleStore(corpusURL: corpus, userURL: url)
        #expect(try await reopened.savedChapterIDs() == [john3])
        await #expect(throws: StorageIssue.self) {
            try await reopened.setChapterSaved("eng-kjv-1769-protestant:JHN:99", saved: true)
        }
    }

    @Test func savedListShowsChapterRowWithOpeningVerse() async throws {
        let (store, _, _) = try makeStore()
        _ = try await store.setChapterSaved(psalm23, saved: true)
        _ = try await store.edit(verseIDs: [psalm23 + ":1"], color: .sage, bookmark: false)
        let items = try await store.savedItems()
        let chapter = try #require(items.first { $0.savedChapter })
        let document = try await store.chapter(psalm23)
        #expect(chapter.reference == "Psalms 23")
        #expect(chapter.text == document.verses[0].text)
        #expect(chapter.verseCount == document.verses.count)
        #expect(!chapter.bookmark && chapter.color == nil && !chapter.unavailable)
        let catalog = Dictionary(uniqueKeysWithValues: try await store.chapters().map { ($0.id, $0.ordinal) })
        let bookmarks = SavedOrdering.items(items, filter: .bookmarks, sort: .recent, chapters: catalog)
        #expect(bookmarks.map(\.id) == [chapter.id])
        #expect(SavedOrdering.items(items, filter: .highlights, sort: .recent, chapters: catalog).allSatisfy { !$0.savedChapter })
        // In Bible order a saved chapter leads its own verses.
        #expect(SavedOrdering.items(items, filter: .all, sort: .bible, chapters: catalog).first?.id == chapter.id)
    }

    @Test func removalRequiresTheDisplayedRecordAndUndoRestoresIt() async throws {
        let (store, _, _) = try makeStore()
        let saved = try await store.setChapterSaved(john3, saved: true)
        let record = try #require(saved.after)
        let removed = try await store.setChapterSaved(john3, saved: false, expecting: record)
        #expect(try await store.savedChapterIDs().isEmpty)
        #expect(try await store.savedItems().isEmpty)
        try await store.undoChapter(removed)
        #expect(try await store.savedItems().first?.records.chapters == [record])
        // A stale row (the chapter was removed and saved again) cannot delete the newer save.
        _ = try await store.setChapterSaved(john3, saved: false)
        let resaved = try await store.setChapterSaved(john3, saved: true)
        await #expect(throws: StorageIssue.self) { try await store.setChapterSaved(john3, saved: false, expecting: record) }
        // Undo of an older change cannot overwrite the later state either.
        await #expect(throws: StorageIssue.self) { try await store.undoChapter(removed) }
        #expect(try await store.savedItems().first?.records.chapters == [try #require(resaved.after)])
    }

    @Test func unavailableChapterIsRetained() async throws {
        let (store, _, url) = try makeStore()
        try sql("INSERT INTO saved_chapter VALUES('legacy','eng-kjv-1769-protestant','eng-kjv-1769-protestant:XYZ:1',1,1)", at: url)
        let item = try #require(try await store.savedItems().first)
        #expect(item.savedChapter && item.unavailable)
        #expect(try await store.savedChapterIDs().contains("eng-kjv-1769-protestant:XYZ:1"))
    }
}
