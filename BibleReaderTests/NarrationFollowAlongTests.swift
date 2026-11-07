import Testing
import Foundation
import UIKit
import SwiftUI
@testable import BibleReader

@MainActor
struct NarrationFollowAlongTests {
    /// A chapter long enough to scroll, with a heading, italics, and a composed character.
    private static func document(verses count: Int = 40) -> ChapterDocument {
        ChapterDocument(id: "test:ABC:1", bookID: "ABC", bookName: "Test", eyebrow: "TEST", label: "1", editionLabel: "Fixture",
                        verses: (1...count).map { number in
            .init(id: "test:ABC:1:\(number)", label: "\(number)",
                  runs: [.init(text: "Verse \(number) of the café and ", italic: false), .init(text: "all", italic: true),
                         .init(text: " the earth was without form and void, and darkness was upon the deep.", italic: false)],
                  structure: "p", headings: number == 1 ? ["A heading."] : [], notes: [])
        })
    }

    private static func focus(_ map: ChapterTextMap, verse index: Int, word: Int = 0, revision: Int, chapterID: String = "test:ABC:1") -> NarrationFocus {
        let entry = map.entries[index]
        let words = (entry.verse.text as NSString)
        var ranges: [NSRange] = []
        let regex = try! NSRegularExpression(pattern: #"\S+"#)
        regex.enumerateMatches(in: entry.verse.text, range: NSRange(location: 0, length: words.length)) { match, _, _ in
            if let match { ranges.append(match.range) }
        }
        let local = ranges[min(word, ranges.count - 1)]
        return NarrationFocus(chapterID: chapterID, verseID: entry.verse.id, kind: .verse, segmentRange: entry.range,
                              wordRange: NSRange(location: entry.range.location + local.location, length: local.length), revision: revision)
    }

    // MARK: Decisions

    @Test func scrollingFollowsOnlyOutsideTheComfortBand() {
        // Visible text band 100…900 in content coordinates, offset 0.
        let inBand = CGRect(x: 0, y: 400, width: 100, height: 30)
        #expect(NarrationFollow.scrollOffset(for: inBand, top: 100, bottom: 900, currentOffset: 0, maxOffset: 5000) == nil)
        // Below 70% of the band (660): moves the line to 30% (340).
        let low = CGRect(x: 0, y: 700, width: 100, height: 30)
        #expect(NarrationFollow.scrollOffset(for: low, top: 100, bottom: 900, currentOffset: 0, maxOffset: 5000) == 360)
        // Above the band: moves back, clamped at the top of the chapter.
        let above = CGRect(x: 0, y: 50, width: 100, height: 30)
        #expect(NarrationFollow.scrollOffset(for: above, top: 100, bottom: 900, currentOffset: 0, maxOffset: 5000) == nil)
        #expect(NarrationFollow.scrollOffset(for: CGRect(x: 0, y: 1050, width: 1, height: 30), top: 1100, bottom: 1900,
                                             currentOffset: 1000, maxOffset: 5000) == 710)
        // Clamped at the end of the chapter.
        #expect(NarrationFollow.scrollOffset(for: CGRect(x: 0, y: 4950, width: 1, height: 30), top: 100, bottom: 900,
                                             currentOffset: 0, maxOffset: 4000) == 4000)
        #expect(NarrationFollow.scrollOffset(for: .null, top: 100, bottom: 900, currentOffset: 0, maxOffset: 4000) == nil)
    }

    @Test func followingResumesOnlyNearTheScreen() {
        #expect(NarrationFollow.isNear(CGRect(x: 0, y: 1200, width: 1, height: 20), top: 100, bottom: 900))
        #expect(!NarrationFollow.isNear(CGRect(x: 0, y: 2000, width: 1, height: 20), top: 100, bottom: 900))
        #expect(!NarrationFollow.isNear(CGRect(x: 0, y: -1000, width: 1, height: 20), top: 100, bottom: 900))
    }

    @Test func twoPagesTurnsOnceAndNeverJumps() {
        #expect(NarrationFollow.spreadAction(focusPage: 4, displayedLeftPage: 4) == .stay)
        #expect(NarrationFollow.spreadAction(focusPage: 5, displayedLeftPage: 4) == .stay)
        #expect(NarrationFollow.spreadAction(focusPage: 6, displayedLeftPage: 4) == .turnForward)
        #expect(NarrationFollow.spreadAction(focusPage: 7, displayedLeftPage: 4) == .turnForward)
        // The reader flipped back or far ahead: stay where they are.
        #expect(NarrationFollow.spreadAction(focusPage: 8, displayedLeftPage: 4) == .away)
        #expect(NarrationFollow.spreadAction(focusPage: 2, displayedLeftPage: 4) == .away)
    }

    @Test func focusLocationPrefersWordThenSegmentThenAnnouncedVerse() throws {
        let map = ChapterTextMap(document: Self.document(verses: 3))
        let word = Self.focus(map, verse: 1, word: 2, revision: 1)
        #expect(NarrationFollow.location(of: word, in: map) == word.wordRange)
        let verse = NarrationFocus(chapterID: "test:ABC:1", verseID: map.entries[1].verse.id, kind: .verse,
                                   segmentRange: map.entries[1].range, wordRange: nil, revision: 2)
        #expect(NarrationFollow.location(of: verse, in: map) == map.entries[1].range)
        let announcement = NarrationFocus(chapterID: "test:ABC:1", verseID: map.entries[2].verse.id, kind: .verseAnnouncement,
                                          segmentRange: nil, wordRange: nil, revision: 3)
        #expect(NarrationFollow.location(of: announcement, in: map) == map.entries[2].range)
        let chapter = NarrationFocus(chapterID: "test:ABC:1", verseID: nil, kind: .chapterAnnouncement, segmentRange: nil, wordRange: nil, revision: 4)
        #expect(NarrationFollow.location(of: chapter, in: map) == nil)
    }

    // MARK: Renderer

    @Test func narratingAChapterLeavesTextSelectionHighlightsAndCopyUnchanged() throws {
        let doc = Self.document(), state = ReaderState(), view = ChapterTextView()
        state.chapters = [doc]; state.chapterID = doc.id
        state.highlights[doc.verses[2].id] = .rose
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        let selection = NSRange(location: map.entries[2].range.location + 3, length: 20)
        view.selectedRange = selection
        let text = try #require(view.attributedText)
        let copied = map.copyText(range: selection, document: doc)
        #if DEBUG
        let builds = view.documentBuildCount, highlights = view.highlightVerseUpdateCount
        #endif
        var revision = 0
        for index in map.entries.indices {
            for word in 0..<3 {
                revision += 1
                view.narrationFocus = Self.focus(map, verse: index, word: word, revision: revision)
                view.layoutIfNeeded()
            }
        }
        #if DEBUG
        #expect(view.documentBuildCount == builds)
        #expect(view.highlightVerseUpdateCount == highlights)
        let marks = view.narrationMarkFrames
        #expect(marks.verse != nil)
        #expect(marks.word != nil)
        #endif
        #expect(view.attributedText == text, "Read Aloud must never write into the text")
        #expect(view.selectedRange == selection)
        #expect(map.copyText(range: view.selectedRange, document: doc) == copied)
        #expect(view.textStorage.attribute(.backgroundColor, at: map.entries[2].range.location, effectiveRange: nil) != nil)

        // Another chapter's focus, or none, shows nothing here.
        view.narrationFocus = Self.focus(map, verse: 0, revision: revision + 1, chapterID: "test:XYZ:1")
        view.layoutIfNeeded()
        #if DEBUG
        #expect(view.narrationMarkFrames.verse == nil)
        #expect(view.narrationMarkFrames.word == nil)
        #endif
        view.narrationFocus = nil
        view.layoutIfNeeded()
        #if DEBUG
        #expect(view.narrationMarkFrames.verse == nil)
        #endif
    }

    @Test func markUnderlinesTheSpokenWordWithinItsVerse() throws {
        let doc = Self.document(verses: 3), state = ReaderState(), view = ChapterTextView()
        state.chapters = [doc]; state.chapterID = doc.id
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .dark)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        let focus = Self.focus(map, verse: 1, word: 1, revision: 1)
        view.narrationFocus = focus
        view.layoutIfNeeded()
        #if DEBUG
        let verse = try #require(view.narrationMarkFrames.verse)
        let word = try #require(view.narrationMarkFrames.word)
        #expect(verse.contains(CGPoint(x: word.midX, y: word.midY)))
        #expect(word.height <= 3)
        let wordRange = try #require(focus.wordRange)
        let start = try #require(view.position(from: view.beginningOfDocument, offset: wordRange.location))
        #expect(abs(view.caretRect(for: start).minX - word.minX) < 2)
        #endif
    }

    @Test func scrollingReaderFollowsUnlessTheReaderIsSelecting() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let doc = Self.document(), state = ReaderState(), view = ChapterTextView()
        state.chapters = [doc]; state.chapterID = doc.id
        view.frame = root.view.bounds
        root.view.addSubview(view)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        view.followsNarration = true

        // A selection holds the reader still.
        view.selectedRange = NSRange(location: map.entries[0].range.location, length: 5)
        view.narrationFocus = Self.focus(map, verse: 30, revision: 1)
        view.layoutIfNeeded()
        #expect(view.contentOffset.y == 0)

        view.selectedRange = NSRange(location: 0, length: 0)
        view.narrationFocus = Self.focus(map, verse: 30, word: 1, revision: 2)
        view.layoutIfNeeded()
        // Animated unless Reduce Motion; wait for the move to finish either way.
        let deadline = Date().addingTimeInterval(2)
        while view.contentOffset.y == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let spoken = try #require(view.position(from: view.beginningOfDocument, offset: map.entries[30].range.location))
        let line = view.caretRect(for: spoken)
        #expect(view.contentOffset.y > 0)
        #expect(line.minY >= view.contentOffset.y && line.maxY <= view.contentOffset.y + view.bounds.height,
                "The spoken verse is on screen after following")
        // A paused reader position follows the scroll through the ordinary capture path.
        #expect(state.anchor != nil)

        // Not following (another destination is showing): no movement.
        view.followsNarration = false
        let offset = view.contentOffset
        view.narrationFocus = Self.focus(map, verse: 2, revision: 3)
        view.layoutIfNeeded()
        #expect(view.contentOffset == offset)
    }

    @Test func readAloudActionsStartAtTheChosenVerse() throws {
        let doc = Self.document(verses: 3), state = ReaderState(), view = ChapterTextView()
        state.chapters = [doc]; state.chapterID = doc.id
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        var requests: [(String, VerseAnchor)] = []
        view.readAloud = { requests.append(($0, $1)) }
        view.prepareVerseAccessibility()
        let elements = try #require(view.accessibilityElements).compactMap { $0 as? UIAccessibilityElement }
        let verse = try #require(elements.first { $0.accessibilityLabel?.contains(":2.") == true })
        let action = try #require(verse.accessibilityCustomActions?.first { $0.name == "Read aloud from this verse" })
        #expect(action.actionHandler?(action) == true)
        #expect(requests.first?.0 == doc.id)
        #expect(requests.first?.1 == VerseAnchor(verseID: doc.verses[1].id, utf16Offset: 0))

        let map = try #require(view.map)
        let range = NSRange(location: map.entries[2].range.location + 6, length: 4)
        let menu = try #require(view.textView(view, editMenuForTextIn: range, suggestedActions: []))
        let item = try #require(menu.children.compactMap { $0 as? UIAction }.first { $0.identifier.rawValue == "readAloudFromHere" })
        item.performWithSender(nil, target: nil)
        #expect(requests.last?.1 == VerseAnchor(verseID: doc.verses[2].id, utf16Offset: 6))

        // Without Read Aloud (for example, an adjacent preview page) neither action is offered.
        view.readAloud = nil
        view.prepareVerseAccessibility()
        let refreshed = try #require(view.accessibilityElements).compactMap { $0 as? UIAccessibilityElement }
        #expect(!refreshed.contains { $0.accessibilityCustomActions?.contains { $0.name == "Read aloud from this verse" } == true })
    }
}
