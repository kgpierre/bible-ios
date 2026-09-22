import Testing
import Foundation
import SQLite3
@testable import BibleReader

struct StorageTests {
    private func locations() throws -> (URL, URL) {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        return (corpus,user)
    }

    private func sql(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
    }

    @Test func completeCorpusAndPackagedFTS() async throws {
        let (corpus,url) = try locations()
        let store = try BibleStore(corpusURL: corpus,userURL: url)
        #expect(try await store.books().count == 66)
        let chapters = try await store.chapters()
        #expect(chapters.count == 1189)
        #expect(chapters.first?.bookID == "GEN")
        #expect(chapters.last?.bookID == "REV")
        let document = try await store.chapter(chapters.last!.id)
        #expect(document.verses.count == 21)
        var db: OpaquePointer?
        #expect(sqlite3_open_v2(corpus.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT count(*) FROM verse_search WHERE verse_search MATCH 'beginning'", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement,0) > 0)
    }

    @Test func annotationsPositionAndUndoSurviveReopening() async throws {
        let (corpus,url) = try locations()
        let store = try BibleStore(corpusURL: corpus,userURL: url)
        let chapterID = "eng-kjv-1769-protestant:JHN:3"
        let chapter = try await store.chapter(chapterID)
        let ids = Array(chapter.verses.prefix(3).map(\.id))
        _ = try await store.edit(verseIDs: ids, color: .sage, bookmark: true)
        _ = try await store.edit(verseIDs: ids, color: .sage, bookmark: true)
        let anchor = ReadingAnchor(text: VerseAnchor(verseID: ids[1], utf16Offset: 12), viewportY: 0.25)
        try await store.savePosition(chapterID: chapterID,anchor: anchor)
        let reopened = try BibleStore(corpusURL: corpus,userURL: url)
        #expect(try await reopened.annotations().bookmarks.count == 1)
        #expect(try await reopened.annotations().highlights.count == 3)
        #expect(try await reopened.position()?.anchor == anchor)
        let recolor = try await reopened.edit(verseIDs: [ids[1]], color: .rose, bookmark: false)
        let saved = try await reopened.savedItems()
        #expect(saved.filter { !$0.bookmark }.count == 3) // Recolor splits the original contiguous group.
        try await reopened.undo(recolor)
        #expect(try await reopened.savedItems().filter { !$0.bookmark }.count == 1)
        #expect(try await reopened.annotations().bookmarks.count == 1) // Exact-range editing preserves overlapping bookmarks.
    }

    @Test func failedRangeWriteRollsBackEveryVerse() async throws {
        let (corpus,url) = try locations()
        let store = try BibleStore(corpusURL: corpus,userURL: url)
        let ids = try await store.chapter("eng-kjv-1769-protestant:GEN:1").verses.prefix(2).map(\.id)
        try sql("CREATE TRIGGER fail_second BEFORE INSERT ON highlight WHEN NEW.verseID='eng-kjv-1769-protestant:GEN:1:2' BEGIN SELECT RAISE(ABORT,'injected write failure'); END",at: url)
        await #expect(throws: (any Error).self) { try await store.edit(verseIDs: ids,color: .blue,bookmark: true) }
        let snapshot = try await store.annotations()
        #expect(snapshot.highlights.isEmpty)
        #expect(snapshot.bookmarks.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func bookmarkOnlyEditPreservesMixedHighlights() async throws {
        let (corpus,url) = try locations()
        let store = try BibleStore(corpusURL: corpus,userURL: url)
        let ids = ["eng-kjv-1769-protestant:GEN:1:1", "eng-kjv-1769-protestant:GEN:1:2"]
        _ = try await store.edit(verseIDs: [ids[0]],color: .blue,bookmark: false)
        _ = try await store.edit(verseIDs: [ids[1]],color: .sage,bookmark: false)
        let before = try await store.annotations().highlights
        _ = try await store.edit(verseIDs: ids,color: nil,bookmark: true,updateHighlights: false)
        #expect(try await store.annotations().highlights == before)
        #expect(try await store.annotations().bookmarks.count == 1)
    }

    @Test func staleUndoCannotOverwriteLaterEdits() async throws {
        let (corpus,url) = try locations()
        let store = try BibleStore(corpusURL: corpus,userURL: url)
        let ids = ["eng-kjv-1769-protestant:GEN:1:1"]
        let first = try await store.edit(verseIDs: ids,color: .blue,bookmark: false)
        _ = try await store.edit(verseIDs: ids,color: .rose,bookmark: false)
        await #expect(throws: StorageIssue.self) { try await store.undo(first) }
        #expect(try await store.annotations().highlights.first?.color == .rose)
        await #expect(throws: StorageIssue.self) { try await store.edit(verseIDs: ids + ["eng-kjv-1769-protestant:GEN:2:1"],color: nil,bookmark: true) }
    }

    @Test func futureMigrationAndCorruptionNeverResetData() async throws {
        let (corpus,url) = try locations()
        let store = try BibleStore(corpusURL: corpus,userURL: url)
        _ = try await store.edit(verseIDs: ["eng-kjv-1769-protestant:GEN:1:1"],color: .yellow,bookmark: true)
        try sql("INSERT INTO grdb_migrations VALUES('future_version')",at: url)
        #expect(throws: StorageIssue.self) { try BibleStore(corpusURL: corpus,userURL: url) }
        #expect(try await store.annotations().highlights.count == 1)
        let broken = url.deletingLastPathComponent().appendingPathComponent("Broken.sqlite")
        let original = Data("deliberately invalid database; preserve this data".utf8)
        try original.write(to: broken)
        #expect(throws: (any Error).self) { try BibleStore(corpusURL: corpus,userURL: broken) }
        #expect(try Data(contentsOf: broken) == original)
    }
}
