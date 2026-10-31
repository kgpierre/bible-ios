// Two Pages pagination at real page sizes: every page shows exactly its band of lines, the pages
// cover the chapter once, and a page's starting words round-trip through the reading anchor.
import SwiftUI
import UIKit
import XCTest
@testable import BibleReader

final class SpreadPaginationIntegrityTests: XCTestCase {
    private let edition = "eng-kjv-1769-protestant"
    /// iPad Pro 13-inch landscape, with the regular-width top bar and bottom passage capsule.
    private let size = CGSize(width: 1376, height: 1032)
    private let insets = EdgeInsets(top: 74, leading: 0, bottom: 88, trailing: 0)

    @MainActor private func reader() async throws -> ReaderState {
        let corpus = try XCTUnwrap(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let state = ReaderState(makeStore: { store })
        await state.load()
        return state
    }

    @MainActor private func open(_ chapter: String, verse: String? = nil, offset: Int = 0, in state: ReaderState) async throws {
        let summary = try XCTUnwrap(state.catalogChapter("\(edition):\(chapter)"))
        state.navigate(to: summary, verseID: verse, utf16Offset: offset)
        let deadline = ContinuousClock.now + .seconds(5)
        while state.isNavigating || state.chapterID != summary.id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(state.chapterID, summary.id)
    }

    @MainActor private struct Spread {
        let coordinator: SpreadChapterView.Coordinator
        let container: SpreadContainer
        let configuration: SpreadChapterView
        let cleanUp: () -> Void
        var shown: SpreadChapterView.PageKey? { (container.pager.viewControllers?.first as? SpreadPageController)?.key }
    }

    @MainActor private func spread(_ state: ReaderState, size: CGSize? = nil) throws -> Spread {
        let document = try XCTUnwrap(state.document)
        let configuration = SpreadChapterView(document: document, state: state, chromeInsets: insets)
        let coordinator = configuration.makeCoordinator()
        let container = SpreadContainer()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size ?? self.size)
        window.rootViewController = container
        coordinator.attach(container)
        window.isHidden = false
        container.view.frame = window.bounds
        container.view.layoutIfNeeded()
        coordinator.update(configuration)
        return Spread(coordinator: coordinator, container: container, configuration: configuration,
                      cleanUp: { coordinator.detach(); window.isHidden = true })
    }

    /// Every page of the current chapter, laid out at page size, in order.
    @MainActor private func pages(of spread: Spread, timings: ((Duration) -> Void)? = nil) throws -> [ChapterPageController] {
        let pager = spread.container.pager
        let chapterID = try XCTUnwrap(spread.shown?.chapterID)
        var current = pager.viewControllers?.first as? SpreadPageController
        while let page = current, let before = spread.coordinator.pageViewController(pager, viewControllerBefore: page) as? SpreadPageController,
              before.key.chapterID == chapterID { current = before }
        let pageSize = try XCTUnwrap(pager.viewControllers?.first?.view.bounds.size)
        var result: [ChapterPageController] = []
        while let page = current, page.key.chapterID == chapterID {
            let start = ContinuousClock.now
            // The size UIKit's mid-spine pager gives the page on screen.
            page.view.frame = CGRect(origin: .zero, size: pageSize)
            page.view.layoutIfNeeded()
            if let text = page.page { text.textView.layoutIfNeeded(); result.append(text) }
            timings?(ContinuousClock.now - start)
            let next = spread.coordinator.pageViewController(pager, viewControllerAfter: page)
            current = next as? SpreadPageController
        }
        return result
    }

    /// The lines a page's own text view laid out, in text-container coordinates.
    @MainActor private func laidOutLines(in view: ChapterTextView, through end: Int) -> [(offset: Int, top: CGFloat, bottom: CGFloat)] {
        guard let manager = view.textLayoutManager, let content = manager.textContentManager else { return [] }
        var lines: [(offset: Int, top: CGFloat, bottom: CGFloat)] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments where line.characterRange.length > 0 {
                let origin = fragment.layoutFragmentFrame.minY
                lines.append((start + line.characterRange.location, origin + line.typographicBounds.minY, origin + line.typographicBounds.maxY))
            }
            return start <= end
        }
        return lines
    }

    @MainActor private func checkPagination(_ chapter: String, sizeAdjustment: Int, size: CGSize? = nil,
                                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let state = try await reader()
        state.typography.sizeAdjustment = sizeAdjustment
        try await open(chapter, in: state)
        let spread = try spread(state, size: size)
        defer { spread.cleanUp() }
        let pages = try pages(of: spread)
        let label = "\(chapter) size \(sizeAdjustment) at \(size ?? self.size)"
        XCTAssertGreaterThan(pages.count, 0, label, file: file, line: line)
        let windows = pages.compactMap(\.textView.pageWindow)
        XCTAssertEqual(windows.count, pages.count, label, file: file, line: line)
        let map = try XCTUnwrap(pages.first?.textView.map)
        let length = map.text.utf16.count
        // The pages cover the chapter exactly once, in order.
        XCTAssertEqual(windows.first?.start, 0, label, file: file, line: line)
        XCTAssertEqual(windows.last?.end, length, label, file: file, line: line)
        for (page, next) in zip(windows, windows.dropFirst()) {
            XCTAssertEqual(page.end, next.start, "\(label): pages must be contiguous", file: file, line: line)
        }
        for (index, (page, window)) in zip(pages, windows).enumerated() {
            let view = page.textView
            let where_ = "\(label) page \(index + 1) of \(pages.count)"
            XCTAssertLessThan(window.start, window.end, "\(where_): empty page", file: file, line: line)
            XCTAssertLessThanOrEqual(window.height, view.pageTextHeight + 0.5, "\(where_): band taller than the page", file: file, line: line)
            XCTAssertFalse(view.panGestureRecognizer.isEnabled, "\(where_): a book page never scrolls", file: file, line: line)
            // The page's own layout puts the band's lines exactly where they were measured, wholly
            // inside the band, with the neighboring pages' lines wholly outside it.
            let lines = laidOutLines(in: view, through: window.end)
            let inBand = lines.filter { window.contains($0.offset) }
            XCTAssertFalse(inBand.isEmpty, where_, file: file, line: line)
            XCTAssertEqual(inBand.first?.top ?? -1, window.top, accuracy: 0.5,
                           "\(where_): first line moved from its measured position", file: file, line: line)
            XCTAssertEqual(inBand.last?.bottom ?? -1, window.bottom, accuracy: 0.5, "\(where_): last line moved from its measured position", file: file, line: line)
            XCTAssertTrue(inBand.allSatisfy { $0.top >= window.top - 0.5 && $0.bottom <= window.bottom + 0.5 }, "\(where_): text overflows its band", file: file, line: line)
            if let before = lines.last(where: { $0.offset < window.start }) {
                XCTAssertLessThanOrEqual(before.bottom, window.top + 0.5, "\(where_): previous page's line shows in this band", file: file, line: line)
            }
            if let after = lines.first(where: { $0.offset >= window.end }) {
                XCTAssertGreaterThanOrEqual(after.top, window.bottom - 0.5, "\(where_): next page's line shows in this band", file: file, line: line)
            }
            // Pinned to its band, the page shows the whole band above the bottom chrome.
            XCTAssertEqual(view.contentOffset.y, window.top, accuracy: 0.5, "\(where_): page is pinned to its band", file: file, line: line)
            XCTAssertLessThanOrEqual(view.textContainerInset.top + window.bottom - view.contentOffset.y,
                                     view.bounds.height - view.textContainerInset.bottom + 0.5, "\(where_): band runs under the bottom chrome", file: file, line: line)
            // A page's starting words round-trip through the reading anchor the spread records.
            let entry = try XCTUnwrap(map.entries.first { NSMaxRange($0.range) > window.start } ?? map.entries.last)
            let local = min(max(0, window.start - entry.range.location), entry.range.length)
            let offset = try XCTUnwrap(map.offset(for: VerseAnchor(verseID: entry.verse.id, utf16Offset: local)))
            XCTAssertEqual(windows.firstIndex { $0.contains(offset) }, index, "\(where_): anchor resolves to another page", file: file, line: line)
        }
    }

    @MainActor func testGenesis1PagesFitTheirBands() async throws {
        try await checkPagination("GEN:1", sizeAdjustment: 0)
        try await checkPagination("GEN:1", sizeAdjustment: 4)
        try await checkPagination("GEN:1", sizeAdjustment: -4)
    }

    /// An odd window width gives each page a fractional width; the measurement must use the
    /// same width as the visible page, or a line rewraps and the page's band cuts through it.
    @MainActor func testPagesFitTheirBandsAtFractionalPageWidths() async throws {
        let odd = CGSize(width: 1211, height: 834)
        try await checkPagination("GEN:1", sizeAdjustment: 0, size: odd)
        try await checkPagination("JHN:3", sizeAdjustment: -2, size: odd)
        try await checkPagination("PSA:119", sizeAdjustment: -4, size: odd)
    }

    @MainActor func testJohn3PagesFitTheirBands() async throws {
        try await checkPagination("JHN:3", sizeAdjustment: 0)
        try await checkPagination("JHN:3", sizeAdjustment: 4)
    }

    @MainActor func testPsalm119PagesFitTheirBands() async throws {
        try await checkPagination("PSA:119", sizeAdjustment: 0)
        try await checkPagination("PSA:119", sizeAdjustment: 4)
        try await checkPagination("PSA:119", sizeAdjustment: -4)
    }

    /// Simulator timing for creating and laying out each Psalm 119 page (printed, not asserted:
    /// simulator times are not device performance).
    @MainActor func testPsalm119PageCreationTime() async throws {
        let state = try await reader()
        try await open("PSA:119", in: state)
        let spread = try spread(state)
        defer { spread.cleanUp() }
        var times: [Duration] = []
        let pages = try pages(of: spread) { times.append($0) }
        let ms = times.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }
        let elements = pages.map { $0.textView.accessibilityElements?.count ?? 0 }
        print(String(format: "SPREAD-TIMING PSA119 pages %d total %.1f ms, first %.1f, median %.1f, last %.1f, max %.1f ms; a11y elements/page max %d",
                     ms.count, ms.reduce(0, +), ms.first ?? 0, ms.sorted()[ms.count / 2], ms.last ?? 0, ms.max() ?? 0, elements.max() ?? 0))
    }

    /// Turning through Psalm 119 keeps only the spread on screen and the spreads one turn away.
    @MainActor func testTurningKeepsTheSpreadCacheBounded() async throws {
        let state = try await reader()
        try await open("PSA:119", in: state)
        let spread = try spread(state)
        defer { spread.cleanUp() }
        let pager = spread.container.pager
        var turns = 0
        while let previous = pager.viewControllers, let right = previous.last,
              let nextLeft = spread.coordinator.pageViewController(pager, viewControllerAfter: right) as? SpreadPageController,
              nextLeft.key.chapterID == state.chapterID,
              let nextRight = spread.coordinator.pageViewController(pager, viewControllerAfter: nextLeft) {
            spread.coordinator.pageViewController(pager, willTransitionTo: [nextLeft, nextRight])
            pager.setViewControllers([nextLeft, nextRight], direction: .forward, animated: false)
            spread.coordinator.pageViewController(pager, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: true)
            turns += 1
            let shown = try XCTUnwrap(spread.shown)
            let cached = spread.coordinator.cachedPageKeys
            XCTAssertLessThanOrEqual(cached.count, 8, "turn \(turns): \(cached.count) cached pages")
            for key in cached where key.chapterID == shown.chapterID {
                XCTAssertTrue((shown.index - 2...shown.index + 3).contains(key.index), "turn \(turns): stale page \(key.index + 1) cached")
            }
        }
        XCTAssertGreaterThan(turns, 4)
    }

    /// The selection handles on a later page's first line stay above the paper covers and in the
    /// page's touch area, so both knobs can be seen and dragged.
    @MainActor func testSelectionHandlesOnALaterPageStayVisibleAndDraggable() async throws {
        let state = try await reader()
        try await open("JHN:3", in: state)
        let spread = try spread(state)
        defer { spread.cleanUp() }
        spread.container.view.window?.makeKeyAndVisible()
        let page = try XCTUnwrap((spread.container.pager.viewControllers?.last as? SpreadPageController)?.page?.textView)
        page.layoutIfNeeded()
        let window = try XCTUnwrap(page.pageWindow)
        XCTAssertGreaterThan(window.start, 0, "the right page is a later page")
        XCTAssertTrue(page.becomeFirstResponder())
        page.selectedRange = NSRange(location: window.start, length: 3)
        // Let UIKit create the handles and run its own layout passes.
        try await Task.sleep(for: .milliseconds(400))
        let display = try XCTUnwrap(page.interactions.compactMap { $0 as? UITextSelectionDisplayInteraction }.first)
        XCTAssertEqual(display.handleViews.count, 2)
        for (index, handle) in display.handleViews.enumerated() {
            let frame = handle.convert(handle.bounds, to: page)
            // The start knob sits above the first line, the end knob below the selection's line.
            let knob = CGPoint(x: frame.midX, y: index == 0 ? frame.minY - 6 : frame.maxY + 6)
            XCTAssertTrue(page.point(inside: knob, with: nil), "handle \(index) knob must be touchable")
            let front = page.subviews.last { !$0.isHidden && $0.alpha > 0 && $0.frame.contains(knob) }
            XCTAssertTrue(front.map { handle.isDescendant(of: $0) } ?? false, "handle \(index) knob is drawn under \(String(describing: front))")
        }
        // Without a selection, the page answers only on its own lines.
        page.selectedRange = NSRange(location: window.start, length: 0)
        let bandTop = page.textContainerInset.top + window.top
        XCTAssertFalse(page.point(inside: CGPoint(x: page.bounds.midX, y: bandTop - 6), with: nil))
    }

    /// VoiceOver reads each page's own words: a verse split across pages is two elements, the
    /// second marked as continued, together reading the verse once.
    @MainActor func testSplitVersesAreReadOncePerPage() async throws {
        let state = try await reader()
        try await open("JHN:3", in: state)
        let spread = try spread(state)
        defer { spread.cleanUp() }
        let pages = try pages(of: spread)
        let document = try XCTUnwrap(state.document)
        var fragments: [String: [String]] = [:]
        var continued = 0
        for page in pages {
            let view = page.textView
            view.prepareVerseAccessibility()
            let window = try XCTUnwrap(view.pageWindow), map = try XCTUnwrap(view.map)
            let labels = (view.accessibilityElements ?? []).dropFirst().compactMap { ($0 as? NSObject)?.accessibilityLabel }
            let expected = map.entries.filter { NSIntersectionRange($0.range, NSRange(location: window.start, length: window.end - window.start)).length > 0 }
            XCTAssertEqual(labels.count, expected.count + map.sourceHeadingRanges.filter { window.contains($0.location) }.count)
            for (entry, label) in zip(expected, labels.suffix(expected.count)) {
                let plain = "\(document.reference):\(entry.verse.label). "
                let resumed = "\(document.reference):\(entry.verse.label), continued. "
                if entry.range.location < window.start {
                    XCTAssertTrue(label.hasPrefix(resumed), label)
                    continued += 1
                    fragments[entry.verse.id, default: []].append(String(label.dropFirst(resumed.count)))
                } else {
                    XCTAssertTrue(label.hasPrefix(plain), label)
                    fragments[entry.verse.id, default: []].append(String(label.dropFirst(plain.count)))
                }
            }
        }
        XCTAssertGreaterThan(continued, 0, "John 3 at this size splits at least one verse")
        for verse in document.verses {
            let squeezed = { (text: String) in text.filter { !$0.isWhitespace } }
            XCTAssertEqual(squeezed(fragments[verse.id, default: []].joined()), squeezed(verse.text), "verse \(verse.label)")
        }
    }

    /// Navigating to the words a page begins with (mid-verse included) opens the spread holding that page.
    @MainActor func testNavigatingToAPageStartOpensItsSpread() async throws {
        let state = try await reader()
        try await open("PSA:119", in: state)
        let spread = try spread(state)
        defer { spread.cleanUp() }
        let windows = try pages(of: spread).compactMap(\.textView.pageWindow)
        let map = ChapterTextMap(document: try XCTUnwrap(state.document))
        XCTAssertGreaterThan(windows.count, 4)
        for index in [1, 2, windows.count / 2, windows.count - 1] {
            let start = windows[index].start
            let entry = try XCTUnwrap(map.entries.first { NSMaxRange($0.range) > start })
            try await open("PSA:119", verse: entry.verse.id, offset: max(0, start - entry.range.location), in: state)
            spread.coordinator.update(spread.configuration)
            XCTAssertEqual(spread.shown?.index, index - index % 2, "page \(index + 1)")
        }
    }
}
