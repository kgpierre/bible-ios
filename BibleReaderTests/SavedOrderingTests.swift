import Testing
@testable import BibleReader

struct SavedOrderingTests {
    @Test func filtersAndCanonicalOrderUseCorpusPositionsNotLexicalVerseLabels() {
        let rows = [
            SavedItem(id: "later", chapterID: "a", verseID: "a:10", reference: "A 1:10", text: "Test", color: .blue, bookmark: false, updated: 3, verseOrder: 9),
            SavedItem(id: "early", chapterID: "a", verseID: "a:2", reference: "A 1:2", text: "Test", color: nil, bookmark: true, updated: 1, verseOrder: 1),
            SavedItem(id: "missing", chapterID: "missing", verseID: "missing:1", reference: "Unavailable", text: "Test", color: .sage, bookmark: false, updated: 4, unavailable: true)
        ]
        #expect(SavedOrdering.items(rows, filter: .all, sort: .recent, chapters: ["a": 0]).map(\.id) == ["missing", "later", "early"])
        #expect(SavedOrdering.items(rows, filter: .all, sort: .bible, chapters: ["a": 0]).map(\.id) == ["early", "later", "missing"])
        #expect(SavedOrdering.items(rows, filter: .bookmarks, sort: .recent, chapters: [:]).map(\.id) == ["early"])
        #expect(SavedOrdering.items(rows, filter: .highlights, sort: .recent, chapters: [:]).map(\.id) == ["missing", "later"])
    }
}
