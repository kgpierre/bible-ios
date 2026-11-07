import Testing
import Foundation
@testable import BibleReader

struct NarrationScriptTests {
    private func verse(_ label: String, _ text: String, headings: [String] = [], italic: Bool = false) -> ChapterDocument.Verse {
        .init(id: "test:ABC:1:\(label)", label: label, runs: [.init(text: text, italic: italic)], structure: "p", headings: headings, notes: ["A source note."])
    }

    private func document(_ verses: [ChapterDocument.Verse], trailing: [String] = [], bookID: String = "ABC", label: String = "1") -> ChapterDocument {
        ChapterDocument(id: "test:\(bookID):\(label)", bookID: bookID, bookName: "Test", eyebrow: "THE BOOK OF", label: label, editionLabel: "KJV", verses: verses,
                        trailingBlocks: trailing.map { .init(kind: "p", text: $0, sourceXML: "") })
    }

    @Test func pilcrowIsOmittedAndSpokenRangesMapPastIt() throws {
        let document = document([verse("1", "¶ For God so loved the world.")])
        let script = NarrationScript(document: document, options: .init(announcesChapter: false), bookChapterCount: 2)
        let segment = try #require(script.segments.first)
        #expect(segment.speech == "For God so loved the world.")
        #expect(segment.omissions == [NSRange(location: 0, length: 2)])
        let map = ChapterTextMap(document: document)
        let god = try #require(segment.displayRange(forSpoken: (segment.speech as NSString).range(of: "God")))
        #expect((map.text as NSString).substring(with: god) == "God")
        // A spoken start at the omission boundary lands past the mark.
        #expect(segment.displayRange(forSpoken: NSRange(location: 0, length: 0)) == NSRange(location: 2, length: 0))
        #expect(segment.displayRange(forSpoken: NSRange(location: 900, length: 5)) == NSRange(location: NSMaxRange(map.entries[0].range), length: 0))
        #expect(segment.displayRange(forSpoken: NSRange(location: NSNotFound, length: 0)) == nil)
        #expect(segment.spokenOffset(forDisplay: 1) == 0)
        #expect(segment.spokenOffset(forDisplay: 6) == 4)
    }

    @Test func hebrewHeadingLetterIsOmittedButTransliterationIsSpoken() throws {
        let document = document([verse("1", "Blessed are the undefiled.", headings: ["א ALEPH."])])
        let script = NarrationScript(document: document, options: .init(announcesChapter: false), bookChapterCount: 2)
        #expect(script.segments.map(\.kind) == [.heading, .verse])
        #expect(script.segments[0].speech == "ALEPH.")
        #expect(script.segments[0].verseID == "test:ABC:1:1")
        #expect(NarrationOmission.leadingHebrewLetter(in: "א") == [])
        #expect(NarrationOmission.leadingHebrewLetter(in: "א ") == [])
        #expect(NarrationOmission.leadingHebrewLetter(in: "A Psalm of David.") == [])
    }

    @Test func segmentsFollowChapterTextMapOrderAndRanges() throws {
        let document = document([
            verse("1", "A Psalm of David first.", headings: ["A Psalm of David."]),
            verse("2", "Second e\u{301} 👨‍👩‍👧‍👦 line.", italic: true)
        ], trailing: ["Written from Corinthus."])
        let script = NarrationScript(document: document, options: .init(announcesChapter: true, announcesVerseNumbers: true), bookChapterCount: 2)
        #expect(script.segments.map(\.kind) == [.chapterAnnouncement, .heading, .verseAnnouncement, .verse, .verseAnnouncement, .verse, .trailing])
        #expect(script.segments.map(\.id) == Array(0..<7))
        #expect(script.segments.filter { $0.kind == .chapterAnnouncement || $0.kind == .verseAnnouncement }.allSatisfy { $0.displayRange == nil })
        let map = ChapterTextMap(document: document)
        #expect(script.segments.filter { $0.kind == .verse }.map(\.displayRange) == map.entries.map(\.range))
        #expect(script.segments.filter { $0.kind == .heading || $0.kind == .trailing }.map(\.displayRange) == map.sourceHeadingRanges)
        // Italic supplied words are spoken plainly, and notes are never spoken.
        #expect(script.segments[5].speech == "Second e\u{301} 👨‍👩‍👧‍👦 line.")
        #expect(!script.segments.contains { $0.speech.contains("source note") })
    }

    @Test func spokenRangesWidenToComposedCharacters() throws {
        let document = document([verse("1", "Then e\u{301} and 👨‍👩‍👧‍👦 end.")])
        let segment = try #require(NarrationScript(document: document, options: .init(announcesChapter: false), bookChapterCount: 2).segments.first)
        let speech = segment.speech as NSString
        let accent = speech.range(of: "e\u{301}")
        #expect(segment.displayRange(forSpoken: NSRange(location: accent.location, length: 1)) == accent)
        let family = speech.range(of: "👨‍👩‍👧‍👦")
        #expect(segment.displayRange(forSpoken: NSRange(location: family.location + 3, length: 2)) == family)
    }

    @Test func startingPointsUseVerseIdentityAndWordStarts() throws {
        let document = document([
            verse("1", "First verse.", headings: ["A Psalm of David."]),
            verse("2", "¶ And the second verse.")
        ])
        let script = NarrationScript(document: document, options: .init(announcesChapter: true, announcesVerseNumbers: true), bookChapterCount: 2)
        // Verse start includes that verse's heading and announcement, but not the chapter announcement.
        let first = try #require(script.segmentIndex(startingAt: VerseAnchor(verseID: "test:ABC:1:1", utf16Offset: 0)))
        #expect(first.index == 1 && first.speechOffset == 0)
        let pilcrow = try #require(script.segmentIndex(startingAt: VerseAnchor(verseID: "test:ABC:1:2", utf16Offset: 1)))
        #expect(pilcrow.index == 4 && pilcrow.speechOffset == 0)
        // "se|cond" starts at "second".
        let start = try #require(script.segmentIndex(startingAt: VerseAnchor(verseID: "test:ABC:1:2", utf16Offset: 12)))
        #expect(start.index == 5)
        #expect((script.segments[5].speech as NSString).substring(from: start.speechOffset) == "second verse.")
        #expect(script.segmentIndex(startingAt: VerseAnchor(verseID: "missing", utf16Offset: 0)) == nil)
    }

    @Test func announcementWording() {
        #expect(NarrationAnnouncement.chapter(bookID: "JHN", bookName: "John", label: "3", bookChapterCount: 21) == "John, Chapter 3")
        #expect(NarrationAnnouncement.chapter(bookID: "PSA", bookName: "Psalms", label: "23", bookChapterCount: 150) == "Psalm 23")
        #expect(NarrationAnnouncement.chapter(bookID: "JUD", bookName: "Jude", label: "1", bookChapterCount: 1) == "Jude")
        #expect(NarrationAnnouncement.verse(label: "16") == "Verse 16")
        #expect(NarrationAnnouncement.verse(label: "3-4") == "Verses 3 to 4")
        #expect(NarrationAnnouncement.verse(label: "3–4") == "Verses 3 to 4")
        #expect(NarrationAnnouncement.verse(label: "12a") == "Verse 12a")
    }

    @Test func bridgedVerseStaysOneSegment() {
        let script = NarrationScript(document: document([verse("3-4", "Bridged text.")]), options: .init(announcesChapter: false, announcesVerseNumbers: true), bookChapterCount: 2)
        #expect(script.segments.map(\.kind) == [.verseAnnouncement, .verse])
        #expect(script.segments.map(\.speech) == ["Verses 3 to 4", "Bridged text."])
        #expect(Set(script.segments.compactMap(\.verseID)) == ["test:ABC:1:3-4"])
    }

    /// Every chapter of the bundled corpus: speech equals the corpus text minus only the approved
    /// omissions, and display ranges equal the reader's text map.
    @Test func fullCorpusFidelity() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let chapterCounts = Dictionary(uniqueKeysWithValues: try await store.books().map { ($0.id, $0.chapterCount) })
        let chapters = try await store.chapters()
        #expect(chapters.count == 1_189)
        var verses = 0, pilcrows = 0, hebrew = 0, trailing = 0
        for summary in chapters {
            let document = try await store.chapter(summary.id)
            let script = NarrationScript(document: document, options: .init(announcesChapter: true, announcesVerseNumbers: true),
                                         bookChapterCount: try #require(chapterCounts[document.bookID]))
            let map = ChapterTextMap(document: document)
            let text = map.text as NSString
            let verseSegments = script.segments.filter { $0.kind == .verse }
            #expect(verseSegments.map(\.displayRange) == map.entries.map(\.range), "\(summary.id)")
            #expect(script.segments.filter { $0.kind == .heading || $0.kind == .trailing }.map(\.displayRange) == map.sourceHeadingRanges, "\(summary.id)")
            for (segment, verse) in zip(verseSegments, document.verses) {
                let expected = verse.text.hasPrefix("¶ ") ? String(verse.text.dropFirst(2)) : verse.text
                if expected != verse.text { pilcrows += 1 }
                #expect(segment.speech == expected, "\(verse.id)")
                #expect(!segment.speech.isEmpty && !segment.speech.contains("¶"), "\(verse.id)")
                let spoken = try #require(segment.displayRange(forSpoken: NSRange(location: 0, length: segment.speech.utf16.count)))
                #expect(text.substring(with: spoken) == segment.speech, "\(verse.id)")
            }
            for segment in script.segments where segment.kind == .heading || segment.kind == .trailing {
                let source = text.substring(with: try #require(segment.displayRange))
                if segment.kind == .trailing { trailing += 1 }
                if let first = source.unicodeScalars.first, (0x05D0...0x05EA).contains(first.value) {
                    hebrew += 1
                    #expect(segment.speech == String(source.drop { $0 != " " }.dropFirst()), "\(summary.id)")
                } else {
                    #expect(segment.speech == source, "\(summary.id)")
                }
                #expect(!segment.speech.isEmpty)
            }
            verses += verseSegments.count
        }
        // Measured counts for the bundled edition (narration plan §3).
        #expect(verses == 31_102)
        #expect(pilcrows == 2_970)
        #expect(hebrew == 22)
        #expect(trailing == 14)
    }
}
