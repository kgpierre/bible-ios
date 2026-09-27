import Foundation
import SQLite3
import Testing
import UIKit
import SwiftUI
@testable import BibleReader

struct SourceNotesTests {
    private func store() throws -> BibleStore {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        return try BibleStore(corpusURL: corpus, userURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite"))
    }

    @Test func notesParseFromTheBundledCorpusAndStayOutOfCopiedText() async throws {
        let document = try await store().chapter("eng-kjv-1769-protestant:GEN:1")
        let verse = try #require(document.verses.first { $0.label == "4" })
        let request = SourceNotesRequest.verse(verse, in: document)
        #expect(request.title == "Genesis 1:4")
        let note = try #require(request.groups.first?.notes.first)
        #expect(note.catchphrase == "the light from…")
        #expect(note.text == "Heb. between the light and between the darkness")
        let chapter = SourceNotesRequest.chapter(document)
        #expect(chapter.showsVerseLabels)
        #expect(chapter.groups.map(\.verseLabel).contains("4"))
        #expect(chapter.groups.allSatisfy { !$0.notes.isEmpty })
        // Notes are source apparatus: never in verse text, the rendered document, or a copy.
        let map = ChapterTextMap(document: document)
        #expect(!map.text.contains("Heb. between"))
        let copied = try #require(map.copyText(range: NSRange(location: 0, length: (map.text as NSString).length), document: document))
        #expect(!copied.contains("Heb."))
    }

    @Test func unexpectedNoteShapeIsShownWhole() {
        let note = SourceNote(raw: "A note without a reference", id: "x")
        #expect(note.catchphrase == nil)
        #expect(note.text == "A note without a reference")
    }

    @Test @MainActor func markersOnlyForNotedVersesAndCanBeHidden() async throws {
        let document = try await store().chapter("eng-kjv-1769-protestant:GEN:1")
        let state = ReaderState()
        state.chapters = [document]
        state.chapterID = document.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 2000)
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let buttons = view.subviews.compactMap { $0 as? UIButton }.filter { !$0.isHidden }
        #expect(!buttons.isEmpty)
        // Every marker target stays in the gutter, left of the selectable text column.
        #expect(buttons.allSatisfy { $0.frame.maxX <= view.textContainerInset.left && $0.frame.height >= 44 })
        buttons.first?.sendActions(for: .touchUpInside)
        #expect(state.notesRequest?.groups.count == 1)
        #expect(state.notesRequest?.groups.first?.notes.isEmpty == false)
        state.typography.showsNotes = false
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        #expect(view.subviews.compactMap { $0 as? UIButton }.allSatisfy { $0.isHidden })
    }

    @Test func preferencesSavedBeforeNotesKeepTheirValues() throws {
        let stored = #"{"face":"sans","sizeAdjustment":3,"spacing":"relaxed"}"#
        let typography = try JSONDecoder().decode(ReadingTypography.self, from: Data(stored.utf8))
        #expect(typography == ReadingTypography(face: .sans, sizeAdjustment: 3, spacing: .relaxed, showsNotes: true))
    }
}

struct SummaryRefusalTests {
    @Test func proseRefusalsAreDetectedButOverviewsAreNot() {
        for refusal in ["I'm sorry, but I can't help with that.", "I’m sorry, I cannot summarize this content.",
                        "I cannot assist with this request.", "As an AI language model, I can't…", "Unfortunately, I am unable to", "  "] {
            #expect(SummaryRefusal.looksLikeRefusal(refusal), "\(refusal)")
        }
        for overview in ["Lot receives two visitors in Sodom. The men of the city cannot find the door, and the family flees.",
                         "In this chapter, Israel refuses to obey. Joshua cannot stop the people, and Jericho falls.",
                         "Sorrow fills the psalm as the exiles remember Zion by the rivers of Babylon."] {
            #expect(!SummaryRefusal.looksLikeRefusal(overview), "\(overview)")
        }
    }
}

struct SearchPagingTests {
    /// Cached ranking must return exactly what bm25-then-canonical ORDER BY with OFFSET would.
    @Test func deepPagesMatchRankedOffsetQuery() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let store = try BibleStore(corpusURL: corpus, userURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite"))
        var db: OpaquePointer?
        #expect(sqlite3_open_v2(corpus.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func expected(_ offset: Int) -> [String] {
            var statement: OpaquePointer?
            let sql = """
                SELECT verse.id FROM verse_search JOIN verse ON verse.ordinal=verse_search.rowid
                WHERE verse_search MATCH 'the' ORDER BY bm25(verse_search), verse.ordinal LIMIT 50 OFFSET \(offset)
                """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            var ids: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW { ids.append(String(cString: sqlite3_column_text(statement, 0))) }
            return ids
        }
        var total = 0
        for offset in [0, 50, 1000, 10_000] {
            guard case .results(let page) = try await store.search("the", offset: offset) else { Issue.record("Search failed"); return }
            #expect(page.hits.map(\.id) == expected(offset))
            #expect(page.hits.allSatisfy { $0.excerpt.contains(where: \.isMatch) })
            if total == 0 { total = page.total }
            #expect(page.total == total)
        }
        guard case .results(let past) = try await store.search("the", offset: total) else { Issue.record("Search failed"); return }
        #expect(past.hits.isEmpty)
        #expect(past.total == total)
    }
}
