import Foundation
import SQLite3
import Testing
@testable import BibleReader

struct ExactAnnotationTests {
    private func fixture() throws -> (BibleStore, URL, URL) {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        return (try BibleStore(corpusURL: corpus, userURL: url), corpus, url)
    }

    private func sql(_ text: String, at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
    }

    private func passage(_ doc: ChapterDocument, verse: Int = 0, range: NSRange) throws -> ExactPassage {
        let item = doc.verses[verse]
        return ExactPassage(chapterID: doc.id, reference: doc.reference + ":" + item.label,
                            parts: [try #require(SavedTextPart(verseID: item.id, text: item.text, range: range))])
    }

    @Test func savedDeletionKeepsIndependentBookmarkAndRejectsStaleUndo() async throws {
        let (store, corpus, url) = try fixture()
        let doc = try await store.chapter(try #require(await store.chapters().first).id)
        let excerpt = try passage(doc, range: NSRange(location: 0, length: 2))
        _ = try await store.editExact(excerpt, color: .sage)
        _ = try await store.editExact(excerpt, color: nil, bookmarkAction: true)
        let highlight = try #require(await store.savedItems().first { $0.color != nil })
        let change = try await store.deleteSaved(highlight)
        #expect(try await store.savedItems().count == 1)
        #expect(try await store.savedItems().first?.bookmark == true)
        let reopened = try BibleStore(corpusURL: corpus, userURL: url)
        #expect(try await reopened.savedItems().count == 1)
        try await store.undoExact(change)
        #expect(try await store.savedItems().count == 2)
        let again = try await store.deleteSaved(highlight)
        _ = try await store.editExact(excerpt, color: .rose)
        await #expect(throws: StorageIssue.self) { try await store.undoExact(again) }
        #expect(try await store.savedItems().contains { $0.color == .rose })
        await #expect(throws: StorageIssue.self) { try await store.deleteSaved(highlight) }
    }

    @Test func groupedLegacyDeletionIsAtomicAndUndoRestoresEveryRecord() async throws {
        let (store, _, url) = try fixture()
        let doc = try await store.chapter(try #require(await store.chapters().first).id)
        let ids = Array(doc.verses.prefix(2).map(\.id))
        _ = try await store.edit(verseIDs: ids, color: .yellow, bookmark: true)
        let row = try #require(await store.savedItems().first { $0.color != nil })
        #expect(row.records.highlights.count == 2)
        try sql("CREATE TRIGGER fail_delete BEFORE DELETE ON highlight WHEN OLD.verseID = '\(ids[1])' BEGIN SELECT RAISE(ABORT,'test'); END", at: url)
        await #expect(throws: (any Error).self) { try await store.deleteSaved(row) }
        #expect(try await store.annotations().highlights.count == 2)
        try sql("DROP TRIGGER fail_delete", at: url)
        let deletion = try await store.deleteSaved(row)
        #expect(try await store.annotations().highlights.isEmpty)
        #expect(try await store.annotations().bookmarks.count == 1)
        try await store.undoExact(deletion)
        #expect(try await store.annotations().highlights == deletion.legacyBefore.highlights)
        #expect(try await store.annotations().bookmarks.count == 1)
    }

    @Test func unavailableLegacySavedRecordCanBeDeletedAndRestored() async throws {
        let (store, _, url) = try fixture()
        let edition = await store.editionID
        try sql("INSERT INTO highlight VALUES('missing','\(edition)','\(edition):MISSING:1:1','blue','missing',1,1)", at: url)
        let row = try #require(await store.savedItems().first)
        #expect(row.unavailable)
        let deletion = try await store.deleteSaved(row)
        #expect(try await store.savedItems().isEmpty)
        try await store.undoExact(deletion)
        #expect(try await store.savedItems().first?.id == row.id)
    }

    @Test func unavailableExactQuoteSurvivesDeleteUndoAndBookmarkDeleteKeepsHighlight() async throws {
        let (store, _, url) = try fixture()
        let edition = await store.editionID
        let part = try #require(SavedTextPart(verseID: "\(edition):MISSING:1:1", text: "Retained original quote", range: NSRange(location: 0, length: 8)))
        let record = ExactAnnotation(id: "unresolved", editionID: edition, revision: "old",
            passage: ExactPassage(chapterID: "\(edition):MISSING:1", reference: "Missing 1:1", parts: [part]),
            color: nil, created: 1, updated: 1)
        let hex = try JSONEncoder().encode(record).map { String(format: "%02x", $0) }.joined()
        try sql("INSERT INTO exact_annotation VALUES('unresolved','\(edition)',X'\(hex)')", at: url)
        let row = try #require(await store.savedItems().first)
        #expect(row.unavailable)
        #expect(row.text == "Retained")
        let deleted = try await store.deleteSaved(row)
        try await store.undoExact(deleted)
        #expect(try await store.exactAnnotations() == [record])
        let doc = try await store.chapter(try #require(await store.chapters().first).id)
        let excerpt = try passage(doc, range: NSRange(location: 0, length: 2))
        _ = try await store.editExact(excerpt, color: .blue)
        _ = try await store.editExact(excerpt, color: nil, bookmarkAction: true)
        let bookmark = try #require(await store.savedItems().first { $0.bookmark && !$0.unavailable })
        _ = try await store.deleteSaved(bookmark)
        #expect(try await store.savedItems().contains { $0.color == .blue })
        #expect(try await store.savedItems().contains { $0.id == "unresolved" })
    }

    @Test @MainActor func savedDeleteFailureRetainsRowAndPositionThenRetries() async throws {
        let (store, _, url) = try fixture()
        let reader = ReaderState(makeStore: { store })
        await reader.load()
        let doc = try #require(reader.document)
        await reader.saveExact(try passage(doc, range: NSRange(location: 0, length: 2)), color: .blue)
        await reader.loadSavedItems()
        let row = try #require(reader.savedItems.first)
        let anchor = reader.anchor
        try sql("CREATE TRIGGER fail_delete BEFORE DELETE ON exact_annotation BEGIN SELECT RAISE(ABORT,'test'); END", at: url)
        await reader.deleteSaved(row)
        #expect(reader.savedItems.count == 1)
        #expect(reader.canRetry)
        try sql("DROP TRIGGER fail_delete", at: url)
        await reader.retry()
        #expect(reader.savedItems.isEmpty)
        #expect(reader.canUndo)
        await reader.undo()
        await reader.loadSavedItems()
        #expect(reader.savedItems.first?.id == row.id)
        #expect(reader.chapterID == doc.id)
        #expect(reader.anchor == anchor)
    }

    @Test func unicodeBoundariesAndContextRecovery() throws {
        let text = "A e\u{301} 👨‍👩‍👧‍👦 end"
        let emoji = (text as NSString).range(of: "👨‍👩‍👧‍👦")
        let part = try #require(SavedTextPart(verseID: "synthetic", text: text, range: emoji))
        #expect(part.quote == "👨‍👩‍👧‍👦")
        #expect(part.resolvedRange(in: text) == emoji)
        #expect(SavedTextPart(verseID: "synthetic", text: text, range: NSRange(location: emoji.location, length: 2)) == nil)
        #expect(SavedTextPart(verseID: "synthetic", text: text, range: NSRange(location: 2, length: 1)) == nil)
        let shifted = "Prefix " + text
        #expect(part.resolvedRange(in: shifted) == (shifted as NSString).range(of: part.quote))
        #expect(part.resolvedRange(in: text + " / " + text) == nil)
        #expect(part.resolvedRange(in: "Prefix " + text + " / " + text) == nil)
        // Same quote at the old offset, but context has changed: do not guess.
        #expect(part.resolvedRange(in: text.replacingOccurrences(of: "end", with: "new")) == nil)
    }

    @Test func crossVerseMapKeepsOnlySelectedWords() async throws {
        let (store, _, _) = try fixture()
        let doc = try await store.chapter("eng-kjv-1769-protestant:JHN:3")
        let map = ChapterTextMap(document: doc)
        let range = NSRange(location: 6, length: map.entries[1].range.location + 8 - 6)
        let selected = try #require(map.exactPassage(range: range, document: doc))
        #expect(selected.reference == "John 3:1–2")
        #expect(selected.parts.count == 2)
        #expect(selected.parts[0].quote == String(doc.verses[0].text.dropFirst(6)))
        #expect(selected.parts[1].quote == String(doc.verses[1].text.prefix(8)))
        _ = try await store.editExact(selected, color: .sage)
        #expect(try await store.savedItems().first?.text == selected.text)
    }

    @Test func overlapRemovalBookmarksReopenAndUndo() async throws {
        let (store, corpus, url) = try fixture()
        let doc = try await store.chapter("eng-kjv-1769-protestant:JHN:3")
        let whole = try passage(doc, range: NSRange(location: 0, length: 15))
        let middle = try passage(doc, range: NSRange(location: 6, length: 5))
        _ = try await store.editExact(whole, color: .yellow)
        _ = try await store.editExact(middle, color: nil, bookmarkAction: true)
        _ = try await store.editExact(middle, color: nil, bookmarkAction: true)
        let recolor = try await store.editExact(middle, color: .blue)
        let records = try await store.exactAnnotations()
        #expect(records.filter(\.isBookmark).count == 1)
        #expect(records.first { $0.color == .yellow }?.passage.parts.map(\.quote) == ["There ", " man"])
        #expect(records.first { $0.color == .blue }?.passage.text == "was a")
        let reopened = try BibleStore(corpusURL: corpus, userURL: url)
        #expect(try await reopened.exactAnnotations() == records)
        try await reopened.undoExact(recolor)
        #expect(try await reopened.exactAnnotations().filter { !$0.isBookmark }.first?.passage == whole)
        let removal = try await reopened.editExact(middle, color: nil)
        #expect(try await reopened.exactAnnotations().filter(\.isBookmark).count == 1)
        _ = try await reopened.editExact(middle, color: .rose)
        await #expect(throws: StorageIssue.self) { try await reopened.undoExact(removal) }
        let unbookmark = try await reopened.editExact(middle, color: nil, bookmarkAction: false)
        #expect(try await reopened.exactAnnotations().filter(\.isBookmark).isEmpty)
        try await reopened.undoExact(unbookmark)
        #expect(try await reopened.exactAnnotations().filter(\.isBookmark).count == 1)
    }

    @Test func undoTracksFragmentsOutsideRemovedVerse() async throws {
        let (store, _, _) = try fixture()
        let doc = try await store.chapter("eng-kjv-1769-protestant:JHN:3")
        let map = ChapterTextMap(document: doc)
        let both = try #require(map.exactPassage(range: NSRange(location: 0, length: NSMaxRange(map.entries[1].range)), document: doc))
        _ = try await store.editExact(both, color: .sage)
        let second = try passage(doc, verse: 1, range: NSRange(location: 0, length: doc.verses[1].text.utf16.count))
        let removal = try await store.editExact(second, color: nil)
        #expect(try await store.exactAnnotations().first?.passage.reference == "John 3:1")
        try await store.undoExact(removal)
        #expect(try await store.exactAnnotations().first?.passage == both)
        let removeAgain = try await store.editExact(second, color: nil)
        let firstWord = try passage(doc, range: NSRange(location: 0, length: 5))
        _ = try await store.editExact(firstWord, color: .rose)
        await #expect(throws: StorageIssue.self) { try await store.undoExact(removeAgain) }
        #expect(try await store.exactAnnotations().contains { $0.color == .rose })
    }

    @Test func unavailableSavedWordsRemainVisibleWithoutGuessedOffsets() async throws {
        let (store, _, url) = try fixture()
        let doc = try await store.chapter("eng-kjv-1769-protestant:JHN:3")
        let part = try #require(SavedTextPart(verseID: doc.verses[0].id, text: "Synthetic former source", range: NSRange(location: 0, length: 9)))
        let record = ExactAnnotation(id: "unresolved", editionID: "eng-kjv-1769-protestant", revision: "older",
            passage: ExactPassage(chapterID: doc.id, reference: "John 3:1", parts: [part]), color: .sage, created: 1, updated: 1)
        let bytes = try JSONEncoder().encode(record).map { String(format: "%02x", $0) }.joined()
        try sql("INSERT INTO exact_annotation VALUES('unresolved','eng-kjv-1769-protestant',X'\(bytes)')", at: url)
        let item = try #require(try await store.savedItems().first)
        #expect(item.unavailable)
        #expect(item.passage == nil)
        #expect(item.text == "Synthetic")
        #expect(try await store.exactAnnotations() == [record])
    }

    @Test @MainActor func failedSaveRetainsExactIntentForRetry() async throws {
        let (store, _, url) = try fixture()
        let state = ReaderState(makeStore: { store })
        await state.load()
        let doc = try #require(state.document)
        let selected = try passage(doc, range: NSRange(location: 0, length: 5))
        try sql("CREATE TRIGGER fail_exact BEFORE INSERT ON exact_annotation BEGIN SELECT RAISE(ABORT,'injected write failure'); END", at: url)
        await state.saveExact(selected, color: .sage)
        #expect(state.savedItems.isEmpty)
        #expect(!state.isSaving)
        #expect(state.canRetry)
        #expect(state.errorMessage?.contains(selected.reference) == true)
        try sql("DROP TRIGGER fail_exact", at: url)
        await state.retry()
        #expect(state.errorMessage == nil)
        #expect(!state.canRetry)
        await state.loadSavedItems()
        #expect(state.savedItems.count == 1)
        #expect(state.savedItems.first?.text == selected.text)
        #expect(state.savedItems.first?.color == .sage)
    }

    @Test func realV1MigrationConversionRollbackAndUndo() async throws {
        let (_, corpus, seedURL) = try fixture()
        let url = seedURL.deletingLastPathComponent().appendingPathComponent("V1.sqlite")
        // Build the actual prior schema, without ever running v2 on this database.
        try sql("""
            CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES('v1_local_reader');
            CREATE TABLE highlight(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, verseID TEXT NOT NULL,
                color TEXT NOT NULL CHECK(color IN ('yellow','sage','blue','rose')), operationID TEXT NOT NULL,
                created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID,verseID));
            CREATE TABLE bookmark(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, startID TEXT NOT NULL,
                endID TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID,startID,endID));
            CREATE TABLE reading_position(editionID TEXT PRIMARY KEY, payload BLOB NOT NULL);
            INSERT INTO highlight VALUES('old-1','eng-kjv-1769-protestant','eng-kjv-1769-protestant:JHN:3:1','sage','operation',1,1);
            INSERT INTO highlight VALUES('old-2','eng-kjv-1769-protestant','eng-kjv-1769-protestant:JHN:3:2','sage','operation',1,1);
            INSERT INTO bookmark VALUES('bookmark','eng-kjv-1769-protestant','eng-kjv-1769-protestant:JHN:3:1','eng-kjv-1769-protestant:JHN:3:2',1,1);
            """, at: url)
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        let legacy = try await store.annotations()
        #expect(legacy.highlights.count == 2)
        #expect(legacy.bookmarks.count == 1)
        #expect(try await store.exactAnnotations().isEmpty)
        let doc = try await store.chapter("eng-kjv-1769-protestant:JHN:3")
        let map = ChapterTextMap(document: doc)
        let selected = try #require(map.exactPassage(range: NSRange(location: 6, length: map.entries[1].range.location + 8 - 6), document: doc))
        try sql("CREATE TRIGGER fail_exact BEFORE INSERT ON exact_annotation BEGIN SELECT RAISE(ABORT,'injected write failure'); END", at: url)
        await #expect(throws: (any Error).self) { try await store.editExact(selected, color: .blue) }
        #expect(try await store.annotations() == legacy)
        #expect(try await store.exactAnnotations().isEmpty)
        try sql("DROP TRIGGER fail_exact", at: url)
        let change = try await store.editExact(selected, color: .blue)
        let exact = try await store.exactAnnotations()
        #expect(exact.first { $0.id == "old-1" }?.passage.reference == "John 3:1")
        #expect(exact.first { $0.id == "old-2" }?.passage.reference == "John 3:2")
        #expect(try await store.annotations().bookmarks == legacy.bookmarks)
        try await store.undoExact(change)
        #expect(try await store.annotations() == legacy)
        #expect(try await store.exactAnnotations().isEmpty)
        let whole = try #require(map.exactPassage(range: NSRange(location: 0, length: NSMaxRange(map.entries[1].range)), document: doc))
        _ = try await store.editExact(whole, color: nil, bookmarkAction: true)
        #expect(try await store.exactAnnotations().isEmpty) // No duplicate of an existing whole-verse bookmark.
        let removal = try await store.editExact(whole, color: nil, bookmarkAction: false)
        #expect(try await store.annotations().bookmarks.isEmpty)
        #expect(try await store.annotations().highlights == legacy.highlights)
        try await store.undoExact(removal)
        #expect(try await store.annotations() == legacy)
    }
    @Test func annotationCacheTracksOtherConnectionsAndRejectsStaleUndo() async throws {
        let (first, corpus, url) = try fixture()
        let doc = try await first.chapter("eng-kjv-1769-protestant:JHN:3")
        let words = try passage(doc, range: NSRange(location: 0, length: 5))
        let original = try await first.editExact(words, color: .sage)
        let second = try BibleStore(corpusURL: corpus, userURL: url)
        #expect(try await second.exactAnnotations().count == 1)
        let recolor = try await second.editExact(words, color: .rose)
        await #expect(throws: StorageIssue.self) { try await first.undoExact(original) }
        #expect(try await first.exactAnnotations().first?.color == .rose)
        try await second.undoExact(recolor)
        #expect(try await first.exactAnnotations().first?.color == .sage)
    }

    @Test func warmEditsDoNotDecodeLibraryAndSavedDoesNotEvictReader() async throws {
        let (seed, corpus, url) = try fixture()
        let catalog = try await seed.chapters()
        for chapter in catalog.prefix(12) {
            let doc = try await seed.chapter(chapter.id)
            _ = try await seed.editExact(passage(doc, range: NSRange(location: 0, length: 5)), color: .yellow)
        }
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        for chapter in catalog.prefix(3) { _ = try await store.chapter(chapter.id) }
        #expect(try await store.savedItems().count == 12)
        let decoded = await store.exactDecodeCount
        let readerDecoded = await store.chapterDecodeCount
        let savedDecoded = await store.savedChapterDecodeCount
        let doc = try await store.chapter(catalog[0].id)
        #expect(await store.chapterDecodeCount == readerDecoded)
        let middle = try passage(doc, range: NSRange(location: 1, length: 2))
        let change = try await store.editExact(middle, color: .blue)
        let items = try await store.savedItems()
        #expect(items.count == 13)
        #expect(items.contains { $0.color == .blue && $0.text == middle.text })
        #expect(await store.exactDecodeCount == decoded)
        #expect(await store.savedChapterDecodeCount == savedDecoded)
        try await store.undoExact(change)
        #expect(try await store.savedItems().count == 12)
        #expect(await store.exactDecodeCount == decoded)
        let reopened = try BibleStore(corpusURL: corpus, userURL: url)
        let rebuilt = try await reopened.savedItems()
        #expect(rebuilt.map(\.id) == (try await store.savedItems()).map(\.id))
        #expect(rebuilt.map(\.text) == (try await store.savedItems()).map(\.text))
    }

    @Test @MainActor func pendingHighlightRendersThenRollsBackOnWriteFailure() async throws {
        let (store, _, url) = try fixture()
        let state = ReaderState(makeStore: { store })
        await state.load()
        let doc = try #require(state.document)
        let words = try passage(doc, range: NSRange(location: 0, length: 5))
        await state.saveExact(words, color: .sage)
        let original = state.exactAnnotations
        let savedRevision = state.savedRevision
        try sql("CREATE TRIGGER fail_exact BEFORE INSERT ON exact_annotation BEGIN SELECT RAISE(ABORT,'injected write failure'); END", at: url)
        var lock: OpaquePointer?
        #expect(sqlite3_open(url.path, &lock) == SQLITE_OK)
        defer { sqlite3_exec(lock, "ROLLBACK", nil, nil, nil); sqlite3_close(lock) }
        #expect(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        let save = Task { await state.saveExact(words, color: .rose) }
        for _ in 0..<100 where !state.isSaving { await Task.yield() }
        #expect(state.isSaving)
        #expect(state.exactAnnotations.first?.color == .rose)
        #expect(state.savedRevision == savedRevision)
        #expect(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        await save.value
        #expect(state.exactAnnotations == original)
        #expect(state.errorMessage != nil)
        #expect(state.savedRevision == savedRevision)
        #expect(try await store.exactAnnotations() == original)
    }

    @Test @MainActor func invalidEmptySelectionCannotCreatePendingAnnotation() async throws {
        let (store, _, _) = try fixture()
        let state = ReaderState(makeStore: { store })
        await state.load()
        let doc = try #require(state.document)
        await state.saveExact(ExactPassage(chapterID: doc.id, reference: doc.reference, parts: []), color: .sage)
        #expect(state.exactAnnotations.isEmpty)
        #expect(state.errorMessage != nil)
        #expect(!state.isSaving)
        #expect(try await store.exactAnnotations().isEmpty)
    }

}
