import Foundation
import SQLite3
import Testing
import UIKit
@testable import BibleReader

/// Open-failure guidance, undo conflicts, unlock waiting, and split-record labels.
struct StorageRecoveryTests {
    private let edition = "eng-kjv-1769-protestant"

    private func locations() throws -> (URL, URL) {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        return (corpus, url)
    }

    private func sql(_ text: String, at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
    }

    private func count(_ query: String, at url: URL) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw StorageIssue.incompatibleUserStore }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw StorageIssue.incompatibleUserStore }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func whole(_ doc: ChapterDocument, verses: Range<Int>) throws -> ExactPassage {
        let parts = try verses.map { index in
            let verse = doc.verses[index]
            return try #require(SavedTextPart(verseID: verse.id, text: verse.text, range: NSRange(location: 0, length: verse.text.utf16.count)))
        }
        return ExactPassage(chapterID: doc.id, reference: doc.reference, parts: parts)
    }

    // MARK: Open failures

    @Test func undecodableV2PayloadFailsMigrationAndKeepsData() async throws {
        let (corpus, url) = try locations()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sql("""
            CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES('v1_local_reader');
            INSERT INTO grdb_migrations VALUES('v2_exact_annotations');
            CREATE TABLE highlight(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, verseID TEXT NOT NULL,
                color TEXT NOT NULL CHECK(color IN ('yellow','sage','blue','rose')), operationID TEXT NOT NULL,
                created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID,verseID));
            CREATE TABLE bookmark(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, startID TEXT NOT NULL,
                endID TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID,startID,endID));
            CREATE TABLE reading_position(editionID TEXT PRIMARY KEY, payload BLOB NOT NULL);
            CREATE TABLE exact_annotation(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, payload BLOB NOT NULL);
            CREATE INDEX exact_annotation_edition ON exact_annotation(editionID);
            INSERT INTO exact_annotation VALUES('broken','eng-kjv-1769-protestant',X'7B6E6F74');
            """, at: url)
        var thrown: (any Error)?
        do { _ = try BibleStore(corpusURL: corpus, userURL: url) } catch { thrown = error }
        let error = try #require(thrown)
        #expect(error is BibleStore.MigrationFailure)
        #expect(ReaderOpenFailure(error, protectedDataAvailable: true).kind == .migrationFailed)
        #expect(ReaderOpenFailure(error, protectedDataAvailable: true).isRetryable)
        // Rolled back: still v2, the undecodable record kept, and a pre-migration copy made.
        #expect(try count("SELECT count(*) FROM grdb_migrations", at: url) == 2)
        #expect(try count("SELECT count(*) FROM exact_annotation WHERE id='broken'", at: url) == 1)
        let backup = url.deletingLastPathComponent().appendingPathComponent("User-before-migration.sqlite")
        #expect(try count("SELECT count(*) FROM exact_annotation WHERE id='broken'", at: backup) == 1)
    }

    @Test @MainActor func newerUserStoreIsReportedAsUpdateRequiredWithoutRetry() async throws {
        let (corpus, url) = try locations()
        let original = try BibleStore(corpusURL: corpus, userURL: url)
        _ = try await original.edit(verseIDs: ["\(edition):GEN:1:1"], color: .yellow, bookmark: false)
        try sql("INSERT INTO grdb_migrations VALUES('future_version')", at: url)
        let reader = ReaderState(makeStore: { try BibleStore(corpusURL: corpus, userURL: url) })
        await reader.load()
        #expect(reader.loadFailed)
        #expect(reader.openFailure?.kind == .newerUserStore)
        #expect(reader.errorTitle == ReaderOpenFailure(kind: .newerUserStore).title)
        #expect(reader.errorMessage == ReaderOpenFailure(kind: .newerUserStore).message)
        #expect(!reader.canRetry)
        #expect(try await original.annotations().highlights.count == 1)
    }

    @Test @MainActor func eachOpenFailureGetsItsOwnGuidance() async throws {
        let cases: [(any Error, Bool, ReaderOpenFailure.Kind, Bool)] = [
            (StorageIssue.insufficientSpace, true, .insufficientSpace, true),
            (CocoaError(.fileWriteOutOfSpace), true, .insufficientSpace, true),
            (BibleStore.MigrationFailure(underlying: CocoaError(.fileWriteOutOfSpace)), true, .insufficientSpace, true),
            (StorageIssue.incompatibleUserStore, true, .newerUserStore, false),
            (StorageIssue.incompatibleCorpus, true, .corpusUnavailable, false),
            (BibleStore.MigrationFailure(underlying: CocoaError(.fileReadCorruptFile)), true, .migrationFailed, true),
            (BibleStore.MigrationFailure(underlying: CocoaError(.fileReadNoPermission)), false, .locked, true),
            (CocoaError(.fileReadNoPermission), false, .locked, true),
            (CocoaError(.fileReadUnknown), true, .other, true),
        ]
        var messages = Set<String>()
        for (error, available, kind, retryable) in cases {
            let failure = ReaderOpenFailure(error, protectedDataAvailable: available)
            #expect(failure.kind == kind)
            #expect(failure.isRetryable == retryable)
            #expect(!failure.message.localizedCaseInsensitiveContains("delete"))
            #expect(!failure.message.localizedCaseInsensitiveContains("reinstall"))
            messages.insert(failure.message)
        }
        #expect(messages.count == 6)
        // Only the locked case tells the user to unlock.
        #expect(ReaderOpenFailure(kind: .locked).message.localizedCaseInsensitiveContains("unlock"))
        #expect(!ReaderOpenFailure(kind: .insufficientSpace).message.localizedCaseInsensitiveContains("unlock"))

        let reader = ReaderState(makeStore: { throw StorageIssue.insufficientSpace })
        await reader.load()
        #expect(reader.openFailure?.kind == .insufficientSpace)
        #expect(reader.canRetry)
    }

    // MARK: Undo conflicts

    @Test @MainActor func conflictingUndoIsDroppedSoEarlierEditsStayUndoable() async throws {
        let (corpus, url) = try locations()
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        let reader = ReaderState(makeStore: { store })
        await reader.load()
        let doc = try #require(reader.document)
        let first = try whole(doc, verses: 0..<1)
        let later = try whole(doc, verses: 4..<5)
        await reader.saveExact(first, color: .sage)
        await reader.saveExact(later, color: .blue)
        #expect(reader.canUndo)

        // Another connection recolors the later words, so that undo can no longer apply.
        let other = try BibleStore(corpusURL: corpus, userURL: url)
        _ = try await other.editExact(later, color: .rose)

        await reader.undo()
        #expect(reader.errorMessage != nil)
        #expect(reader.canUndo)
        #expect(reader.undoActionName == String(localized: "Highlight"))
        #expect(!reader.canRetry)
        let afterConflict = try await other.exactAnnotations()
        #expect(afterConflict.compactMap(\.color).sorted { $0.rawValue < $1.rawValue } == [.rose, .sage])

        reader.dismissError()
        await reader.undo()
        #expect(reader.errorMessage == nil)
        #expect(!reader.canUndo)
        let remaining = try await other.exactAnnotations()
        #expect(remaining.count == 1)
        #expect(remaining.first?.color == .rose)
        #expect(remaining.first?.passage.verseIDs == later.verseIDs)
    }

    // MARK: Unlock waiting

    @Test @MainActor func unlockJustAfterTheCheckIsNotMissed() async throws {
        let center = NotificationCenter()
        let started = ContinuousClock.now
        let waiter = Task { @MainActor in
            var checks = 0
            return await ReaderState.waitForProtectedData(center: center) {
                checks += 1
                // Unlock lands between the locked check and any later subscription.
                if checks == 1 { center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil); return false }
                return true
            }
        }
        let timeout = Task { try await Task.sleep(for: .seconds(5)); waiter.cancel() }
        #expect(await waiter.value)
        timeout.cancel()
        #expect(ContinuousClock.now - started < .seconds(4))
    }

    @Test @MainActor func availableDataIsNotTreatedAsALockedWrite() async {
        #expect(await ReaderState.waitForProtectedData(center: NotificationCenter()) { true } == false)
    }

    @Test @MainActor func becomingActiveWhileStillLockedKeepsWaiting() async throws {
        let center = NotificationCenter()
        var unlocked = false
        let waiter = Task { @MainActor in
            await ReaderState.waitForProtectedData(center: center) { unlocked }
        }
        for _ in 0..<20 { await Task.yield() }
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        unlocked = true
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let timeout = Task { try await Task.sleep(for: .seconds(5)); waiter.cancel() }
        #expect(await waiter.value)
        timeout.cancel()
    }

    // MARK: Split-record labels

    @Test func removingAMiddleVerseLabelsOnlyTheRemainingVerses() async throws {
        let (corpus, url) = try locations()
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        let doc = try await store.chapter("\(edition):JHN:3")
        _ = try await store.editExact(try whole(doc, verses: 0..<3), color: .yellow)
        #expect(try await store.exactAnnotations().first?.passage.reference == "\(doc.reference):1–3")

        // A partial cut keeps every verse, so the range label stays contiguous.
        let middle = doc.verses[1]
        let partial = ExactPassage(chapterID: doc.id, reference: doc.reference,
            parts: [try #require(SavedTextPart(verseID: middle.id, text: middle.text, range: NSRange(location: 0, length: 3)))])
        _ = try await store.editExact(partial, color: nil)
        #expect(try await store.exactAnnotations().first?.passage.reference == "\(doc.reference):1–3")

        _ = try await store.editExact(try whole(doc, verses: 1..<2), color: nil)
        let records = try await store.exactAnnotations()
        #expect(records.count == 1)
        #expect(records.first?.passage.reference == "\(doc.reference):1, 3")
        #expect(records.first?.passage.verseIDs == [doc.verses[0].id, doc.verses[2].id])
        let saved = try await store.savedItems()
        #expect(saved.first?.reference.hasPrefix("\(doc.reference):1, 3") == true)
    }
}
