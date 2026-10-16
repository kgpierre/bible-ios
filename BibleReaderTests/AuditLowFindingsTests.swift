import Testing
import Foundation
@testable import BibleReader

struct ExcerptMarkerTests {
    /// A Psalm-like chapter whose first verse is preceded by a source superscription.
    private func document() -> ChapterDocument {
        ChapterDocument(id: "test:PSA:23", bookID: "PSA", bookName: "Psalms", eyebrow: "PSALMS", label: "23", editionLabel: "KJV", verses: [
            .init(id: "test:PSA:23:1", label: "1", runs: [.init(text: "The LORD is my shepherd; I shall not want.", italic: false)],
                  structure: "q", headings: ["A Psalm of David."], notes: []),
            .init(id: "test:PSA:23:2", label: "2", runs: [.init(text: "He maketh me to lie down in green pastures.", italic: false)],
                  structure: "q", headings: [], notes: [])
        ])
    }

    @Test func wholeVerseWithPrecedingSuperscriptionIsNotAnExcerpt() throws {
        let document = document()
        let map = ChapterTextMap(document: document)
        let heading = try #require(map.sourceHeadingRanges.first)
        let range = NSRange(location: heading.location, length: NSMaxRange(map.entries[0].range) - heading.location)
        let copied = try #require(map.copyText(range: range, document: document))
        #expect(copied.hasPrefix("A Psalm of David.\nThe LORD is my shepherd"))
        #expect(copied.hasSuffix("— Psalms 23:1, KJV"))
    }

    @Test func midVerseStartIsAnExcerpt() throws {
        let document = document()
        let map = ChapterTextMap(document: document)
        let range = NSRange(location: map.entries[0].range.location + 4, length: map.entries[0].range.length - 4)
        let copied = try #require(map.copyText(range: range, document: document))
        #expect(copied.hasSuffix("— Psalms 23:1, KJV" + String(localized: " (excerpt)")))
    }

    @Test func earlyEndInLastVerseIsAnExcerpt() throws {
        let document = document()
        let map = ChapterTextMap(document: document)
        let start = map.entries[0].range.location
        let range = NSRange(location: start, length: map.entries[1].range.location + 5 - start)
        let copied = try #require(map.copyText(range: range, document: document))
        #expect(copied.hasSuffix("— Psalms 23:1–2, KJV" + String(localized: " (excerpt)")))
    }

    @Test func wholeCrossVerseSelectionIsNotAnExcerpt() throws {
        let document = document()
        let map = ChapterTextMap(document: document)
        let start = map.entries[0].range.location
        // Including the trailing line break, as a drag to the end of the line does.
        let range = NSRange(location: start, length: NSMaxRange(map.entries[1].range) + 1 - start)
        let copied = try #require(map.copyText(range: range, document: document))
        #expect(copied.hasSuffix("— Psalms 23:1–2, KJV"))
        #expect(!copied.contains("excerpt"))
    }
}

struct CardLinkPathTests {
    private let chapter = "eng-kjv-1769-protestant:JHN:3"

    @Test func acceptsOnlyTheBuiltForm() throws {
        let built = try #require(CardLink.url(chapterID: chapter, verseID: "\(chapter):16"))
        #expect(CardLink.parse(built)?.verseID == "\(chapter):16")
        #expect(CardLink.parse(try #require(URL(string: "dev.kpierre.bible://open/?chapter=\(chapter)")))?.chapterID == chapter)
        for bad in ["dev.kpierre.bible://open/anything?chapter=\(chapter)",
                    "dev.kpierre.bible://open/delete/all?chapter=\(chapter)",
                    "dev.kpierre.bible://user@open?chapter=\(chapter)",
                    "dev.kpierre.bible://open:8080?chapter=\(chapter)",
                    "dev.kpierre.bible://open?chapter=\(chapter)#x",
                    "dev.kpierre.bible:open?chapter=\(chapter)"] {
            #expect(CardLink.parse(try #require(URL(string: bad))) == nil, "\(bad)")
        }
    }
}

@MainActor
struct ReaderShortcutAvailabilityTests {
    @Test func chapterShortcutsRequireTheFrontmostReader() {
        let state = AppState()
        #expect(state.acceptsReaderShortcuts)
        // Compact Search hides the reader; its field may be focused.
        state.destination = .search
        #expect(!state.acceptsReaderShortcuts)
        state.destination = .saved
        #expect(!state.acceptsReaderShortcuts)
        state.destination = .read
        state.isChapterPickerPresented = true
        #expect(!state.acceptsReaderShortcuts)
        state.isChapterPickerPresented = false
        state.isAboutPresented = true
        #expect(!state.acceptsReaderShortcuts)
        state.isAboutPresented = false
        state.cardsRequest = .library
        #expect(!state.acceptsReaderShortcuts)
        state.cardsRequest = nil
        #expect(state.acceptsReaderShortcuts)
    }
}
