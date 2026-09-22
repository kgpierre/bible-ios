import Testing
import Foundation
import UIKit
import SwiftUI
@testable import BibleReader

struct ChapterTextMapTests {
    private func document() -> ChapterDocument {
        ChapterDocument(id: "test:ABC:1", bookID: "ABC", bookName: "Test document", eyebrow: "TEST", label: "1", editionLabel: "Synthetic Unicode fixture", verses: [
            .init(id: "test:ABC:1:1", label: "1", runs: [.init(text: "First café 👨‍👩‍👧‍👦 line.", italic: false)], structure: "p", headings: [], notes: []),
            .init(id: "test:ABC:1:2", label: "2", runs: [.init(text: "Second e\u{301} line.", italic: true)], structure: "p", headings: [], notes: [])
        ])
    }

    @Test func crossVerseSelectionAndCopyExcludeGutters() throws {
        let document = document()
        let map = ChapterTextMap(document: document)
        let range = NSRange(location: 6, length: NSMaxRange(map.entries[1].range) - 6)
        let selection = try #require(map.selection(for: range))
        #expect(selection.start.verseID == "test:ABC:1:1")
        #expect(selection.end.verseID == "test:ABC:1:2")
        #expect(map.range(for: selection) == range)
        let copied = try #require(map.copyText(range: range, document: document))
        #expect(copied.hasPrefix("café 👨‍👩‍👧‍👦 line.\nSecond e\u{301} line."))
        #expect(copied.contains("1:1–2"))
        #expect(copied.hasSuffix("(excerpt)"))
        #expect(!copied.contains("1 First"))
    }

    @Test func revisedAnchorClampsToGraphemeBoundary() throws {
        let map = ChapterTextMap(document: document())
        let family = (map.text as NSString).range(of: "👨‍👩‍👧‍👦")
        let anchor = VerseAnchor(verseID: "test:ABC:1:1", utf16Offset: family.location + 3)
        #expect(map.offset(for: anchor) == family.location)
        #expect(map.offset(for: VerseAnchor(verseID: "missing", utf16Offset: 0)) == nil)
        #expect(map.touched(by: NSRange(location: 0, length: 0)).isEmpty)
        #expect(map.copyText(range: NSRange(location: 999, length: 1), document: document()) == nil)
    }

    @Test @MainActor func textKit2SurvivesHighlightAndResize() throws {
        let document = document()
        let state = ReaderState()
        state.chapters = [document]
        state.chapterID = document.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        #expect(view.textLayoutManager != nil)
        let map = try #require(view.map)
        let selection = NSRange(location: 0, length: NSMaxRange(map.entries[1].range))
        view.selectedRange = selection
        view.capturePosition()
        state.highlights[document.verses[0].id] = .sage
        view.configure(document: document, state: state, wide: false, scheme: .light)
        #expect(view.selectedRange == selection)
        #expect(view.text == map.text)
        view.frame.size.width = 680
        view.configure(document: document, state: state, wide: true, scheme: .dark)
        view.layoutIfNeeded()
        #expect(view.selectedRange == selection)
        #expect(view.textLayoutManager != nil)
    }

    @Test @MainActor func scrolledReaderHitTestingUsesViewportCoordinates() {
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.chromeInsets = EdgeInsets(top: 80, leading: 0, bottom: 100, trailing: 0)
        view.contentSize = CGSize(width: 390, height: 3000)
        view.contentOffset = CGPoint(x: 0, y: 900)
        #expect(view.point(inside: CGPoint(x: 150, y: 1200), with: nil))
        #expect(!view.point(inside: CGPoint(x: 150, y: 940), with: nil))
        #expect(!view.point(inside: CGPoint(x: 150, y: 1550), with: nil))
    }

    @Test @MainActor func verseAccessibilityOrderAndAnnotationActions() throws {
        let document = document()
        let state = ReaderState()
        state.chapters = [document]
        state.chapterID = document.id
        state.bookmarks.insert(document.verses[0].id)
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        view.prepareVerseAccessibility()
        let elements = try #require(view.accessibilityElements).compactMap { $0 as? UIAccessibilityElement }
        #expect(elements.count == 2)
        #expect(elements[0].accessibilityLabel?.hasPrefix("Test document 1:1.") == true)
        #expect(elements[1].accessibilityLabel?.hasPrefix("Test document 1:2.") == true)
        #expect(elements[0].accessibilityValue == "Bookmarked")
        #expect(elements[0].accessibilityCustomActions?.first?.name == "Highlight verse yellow")
    }

    @Test @MainActor func exactHighlightMenuReflectsCoverageAndKeepsSelection() throws {
        let doc = document()
        let state = ReaderState()
        state.chapters = [doc]
        state.chapterID = doc.id
        let word = (doc.verses[0].text as NSString).range(of: "café")
        let part = try #require(SavedTextPart(verseID: doc.verses[0].id, text: doc.verses[0].text, range: word))
        let passage = ExactPassage(chapterID: doc.id, reference: "Test document 1:1", parts: [part])
        state.exactAnnotations = [ExactAnnotation(id: "fixture", editionID: "test", revision: "fixture", passage: passage, color: .sage, created: 1, updated: 1)]
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        let selected = NSRange(location: map.entries[0].range.location + word.location, length: word.length)
        view.selectedRange = selected
        #expect(view.selectionHighlightStatus(in: selected).color == .sage)
        #expect(view.selectionHighlightStatus(in: map.entries[0].range).color == nil)
        #expect(view.selectionHighlightStatus(in: map.entries[0].range).hasHighlights)
        #expect(!view.selectionHighlightStatus(in: map.entries[1].range).hasHighlights)
        let menu = try #require(view.textView(view, editMenuForTextIn: selected, suggestedActions: []))
        let palette = try #require(menu.children.first as? UIMenu)
        #expect((palette.children.first { $0.accessibilityLabel == "Sage" } as? UIAction)?.state == .on)
        #expect((palette.children.first { $0.accessibilityLabel == "Blue" } as? UIAction)?.state == .off)
        #expect(menu.children.contains { $0.title == "Remove Highlight" })
        let unhighlighted = try #require(view.textView(view, editMenuForTextIn: map.entries[1].range, suggestedActions: []))
        #expect(!unhighlighted.children.contains { $0.title == "Remove Highlight" })
        state.exactAnnotations = []
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        #expect(view.selectedRange == selected)
        #expect(!view.selectionHighlightStatus(in: selected).hasHighlights)
        #expect(view.text == map.text)
    }

    @Test @MainActor func sourceHeadingAnchorsToFollowingVerse() async throws {
        let doc = try #require(try await PrototypeLibrary.load().first { $0.bookID == "PSA" })
        let state = ReaderState()
        state.chapters = [doc]
        state.chapterID = doc.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 700, height: 700)
        view.chromeInsets = EdgeInsets(top: 80, leading: 0, bottom: 100, trailing: 0)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        let heading = try #require(map.sourceHeadingRanges.dropFirst().first)
        let manager = try #require(view.textLayoutManager)
        manager.ensureLayout(for: try #require(manager.textContentManager).documentRange)
        let position = try #require(view.position(from: view.beginningOfDocument, offset: heading.location))
        view.setContentOffset(CGPoint(x: 0, y: view.caretRect(for: position).minY - 88), animated: false)
        view.capturePosition()
        let following = try #require(map.entries.first { $0.range.location > heading.location })
        #expect(state.anchor?.text.verseID == following.verse.id)
        #expect(state.anchor?.text.utf16Offset == 0)
    }

    @Test @MainActor func longChapterNativeSelectionAndRecreation() async throws {
        let chapters = try await PrototypeLibrary.load()
        let document = try #require(chapters.first { $0.bookID == "PSA" })
        let state = ReaderState()
        state.chapters = chapters
        state.chapterID = document.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let manager = try #require(view.textLayoutManager)
        let content = try #require(manager.textContentManager)
        manager.ensureLayout(for: content.documentRange)
        let map = try #require(view.map)
        let whole = NSRange(location: 0, length: map.text.utf16.count - 1)
        view.selectedRange = whole
        view.capturePosition()
        #expect(state.selection?.end.verseID == document.verses.last?.id)
        let recreated = ChapterTextView()
        recreated.frame = CGRect(x: 0, y: 0, width: 700, height: 650)
        recreated.configure(document: document, state: state, wide: true, scheme: .dark)
        recreated.layoutIfNeeded()
        #expect(recreated.selectedRange == whole)
        #expect(recreated.textLayoutManager != nil)
    }

    @Test @MainActor func completeLongFixtureRemainsSelectable() async throws {
        let chapters = try await PrototypeLibrary.load()
        let psalm = try #require(chapters.first { $0.bookID == "PSA" })
        #expect(psalm.verses.count == 176)
        #expect(psalm.verses.last?.label == "176")
        let map = ChapterTextMap(document: psalm)
        let wholeChapter = NSRange(location: 0, length: map.text.utf16.count)
        #expect(map.touched(by: wholeChapter).count == 176)
        #expect(psalm.verses.first?.headings.isEmpty == false)
        #expect(psalm.verses.contains { $0.runs.contains(where: \.italic) })
    }
    @Test @MainActor func unrelatedStateAndSameChapterNavigationDoNotRebuildText() throws {
        let doc = document(), state = ReaderState(), view = ChapterTextView()
        state.chapters = [doc]; state.chapterID = doc.id
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        view.prepareVerseAccessibility()
        let builds = view.documentBuildCount, frames = view.accessibilityFrameUpdateCount
        let gutters = view.gutterPassCount
        state.isSaving = true
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        state.isSaving = false
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.setNeedsLayout(); view.layoutIfNeeded()
        #expect(view.documentBuildCount == builds)
        #expect(view.gutterPassCount == gutters)
        state.highlights[doc.verses[0].id] = .sage
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.prepareVerseAccessibility()
        #expect(view.highlightVerseUpdateCount == 1)
        #expect(view.accessibilityFrameUpdateCount == frames)
        let elements = try #require(view.accessibilityElements).compactMap { $0 as? UIAccessibilityElement }
        #expect(elements.first?.accessibilityValue == "sage highlight")
        state.navigationRevision += 1
        state.anchor = ReadingAnchor(text: VerseAnchor(verseID: doc.verses[1].id, utf16Offset: 0), viewportY: 0.2)
        state.navigationCue = [doc.verses[1].id]
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        #expect(view.documentBuildCount == builds)
        #expect(view.highlightVerseUpdateCount == 1)
        let map = try #require(view.map)
        #expect(view.textStorage.attribute(.underlineStyle, at: map.entries[1].range.location, effectiveRange: nil) != nil)
        #expect(view.textStorage.attribute(.backgroundColor, at: map.entries[0].range.location, effectiveRange: nil) != nil)
    }

    @Test @MainActor func pageContainerPassesSidebarAndChromeTouchesThrough() {
        let region = ChapterTouchRegion()
        region.frame = CGRect(x: 330, y: 0, width: 803, height: 744)
        region.chromeInsets = EdgeInsets(top: 86, leading: 330, bottom: 20, trailing: 0)
        #expect(!region.point(inside: CGPoint(x: -160, y: 120), with: nil))
        #expect(region.point(inside: CGPoint(x: 100, y: 400), with: nil))
        #expect(!region.point(inside: CGPoint(x: 600, y: 50), with: nil))
        #expect(region.point(inside: CGPoint(x: 600, y: 400), with: nil))
        #expect(!region.point(inside: CGPoint(x: 600, y: 735), with: nil))
    }

}
