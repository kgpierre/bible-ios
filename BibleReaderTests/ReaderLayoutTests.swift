import CoreGraphics
import Testing
import SwiftUI
import UIKit
@testable import BibleReader

struct ReaderLayoutTests {
    @Test func regularWidthPhoneSizedWindowCanShowFacingPages() {
        // Synthetic usable window sizes, not claims about unreleased hardware dimensions.
        #expect(supports(width: 900, height: 600))
        #expect(supports(width: 840, height: 600))
        #expect(!supports(width: 839, height: 600))
        #expect(!supports(width: 900, height: 600, regular: false))
    }

    @Test func foldingAndResizingFallBackToScroll() {
        #expect(!supports(width: 420, height: 680, regular: false))
        #expect(!supports(width: 600, height: 900))
        #expect(!supports(width: 900, height: 900))
        #expect(!supports(width: 1000, height: 300))
        #expect(supports(width: 1100, height: 700))
    }

    @Test func typographyMustFitBothPages() {
        #expect(!supports(width: 900, height: 600, pageWidth: 480))
        #expect(supports(width: 1000, height: 650, pageWidth: 480))
        #expect(!supports(width: 1400, height: 900, accessibility: true))
        #expect(!supports(width: .infinity, height: 600))
        #expect(!supports(width: 900, height: .nan))
    }

    @Test func bookFoldCentersPagesOnTheActualDivision() throws {
        let fold = try #require(ReaderFoldLayout(size: CGSize(width: 960, height: 650),
            divisions: [CGRect(x: 420, y: 0, width: 60, height: 650)]))
        #expect(fold.kind == .book)
        #expect(fold.spreadFrame.midX == 450)
        #expect(fold.spreadFrame.width == 900)
        #expect(fold.innerPageInset == 10)
        #expect(fold.supportsBookPages(minimumPageWidth: 420, accessibilitySize: false))
        #expect(!fold.supportsBookPages(minimumPageWidth: 480, accessibilitySize: false))
        #expect(!fold.supportsBookPages(minimumPageWidth: 420, accessibilitySize: true))
    }

    @Test func tabletopAndFlatAreNotBookPoses() throws {
        let size = CGSize(width: 900, height: 650)
        let fold = try #require(ReaderFoldLayout(size: size,
            divisions: [CGRect(x: 0, y: 300, width: 900, height: 50)]))
        #expect(fold.kind == .tabletop)
        #expect(!fold.supportsBookPages(minimumPageWidth: 420, accessibilitySize: false))
        #expect(ReaderFoldLayout(size: size, divisions: []) == nil)
        #expect(ReaderFoldLayout(size: size, divisions: [.zero]) == nil)
        #expect(ReaderFoldLayout(size: size, divisions: [CGRect(x: 100, y: 100, width: 30, height: 30)]) == nil)
    }

    @Test func scrollingFallbackStaysClearOfTheDivision() throws {
        let book = try #require(ReaderFoldLayout(size: CGSize(width: 867, height: 543),
            divisions: [CGRect(x: 435.5, y: 0, width: 80, height: 543)]))
        #expect(book.clearPane == CGRect(x: 0, y: 0, width: 435.5, height: 543))
        #expect(!book.clearPane.intersects(book.division))
        let trailing = try #require(ReaderFoldLayout(size: CGSize(width: 900, height: 650),
            divisions: [CGRect(x: 300, y: 0, width: 60, height: 650)]))
        #expect(trailing.clearPane == CGRect(x: 360, y: 0, width: 540, height: 650))
        // Tabletop reads above the division whenever that side is usable, even if it is smaller.
        let tabletop = try #require(ReaderFoldLayout(size: CGSize(width: 900, height: 650),
            divisions: [CGRect(x: 0, y: 250, width: 900, height: 50)]))
        #expect(tabletop.clearPane == CGRect(x: 0, y: 0, width: 900, height: 250))
        let low = try #require(ReaderFoldLayout(size: CGSize(width: 900, height: 650),
            divisions: [CGRect(x: 0, y: 120, width: 900, height: 50)]))
        #expect(low.clearPane == CGRect(x: 0, y: 170, width: 900, height: 480))
    }

    @Test func bookPagesFitBesideAnAsymmetricSystemBar() throws {
        // Geometry observed in Device Hub; keep this a regression input, never a device lookup.
        let fold = try #require(ReaderFoldLayout(size: CGSize(width: 867, height: 543),
            divisions: [CGRect(x: 435.5, y: 0, width: 80, height: 543)]))
        #expect(fold.spreadFrame.midX == 475.5)
        #expect(fold.innerPageInset == 20)
        #expect(fold.supportsBookPages(minimumPageWidth: ReaderLayout.minimumBookPageWidth, accessibilitySize: false))
        #expect(!fold.supportsBookPages(minimumPageWidth: 400, accessibilitySize: false))
    }

    @Test @MainActor func nativeSpreadWorksInPhoneWindowAndPreservesAnchorAfterResize() async throws {
        let document = try #require(await PrototypeLibrary.load().first { $0.bookID == "JHN" })
        let state = ReaderState()
        state.chapters = [document]
        state.chapterID = document.id
        let verse = document.verses[10]
        let anchor = ReadingAnchor(text: VerseAnchor(verseID: verse.id, utf16Offset: 0), viewportY: 0.1)
        state.anchor = anchor
        let selection = PassageSelection(start: VerseAnchor(verseID: verse.id, utf16Offset: 0),
                                         end: VerseAnchor(verseID: verse.id, utf16Offset: 5))
        state.selection = selection
        let configuration = SpreadChapterView(document: document, state: state, innerPageInset: 24)
        let coordinator = configuration.makeCoordinator()
        let container = SpreadContainer()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        window.rootViewController = container
        coordinator.attach(container)
        window.makeKeyAndVisible()
        defer {
            coordinator.detach()
            window.isHidden = true
            originalWindow?.makeKey()
        }
        container.view.frame = window.bounds
        container.view.layoutIfNeeded()
        coordinator.update(configuration)
        for width: CGFloat in [900, 1000, 850, 900] {
            container.view.frame.size = CGSize(width: width, height: 650)
            container.view.setNeedsLayout()
            container.view.layoutIfNeeded()
            coordinator.update(configuration)
            let pages = try #require(container.pager.viewControllers?.compactMap { $0 as? SpreadPageController })
            #expect(pages.count == 2)
            let visibleIDs = pages.flatMap { $0.page?.document.verses.map(\.id) ?? [] }
            #expect(visibleIDs.contains(verse.id))
            #expect(Set(visibleIDs).count == visibleIDs.count)
            for page in pages.compactMap(\.page) {
                page.textView.layoutIfNeeded()
                let insets = page.textView.textContainerInset
                if page.textView.isLeftSpreadPage { #expect(insets.right >= 44) }
                else { #expect(insets.left >= 84) }
            }
            #expect(state.anchor == anchor)
            #expect(state.selection == selection)
            #expect(state.chapterID == document.id)
            let selectedPage = try #require(pages.compactMap(\.page).first { $0.document.verses.contains { $0.id == verse.id } })
            selectedPage.textView.layoutIfNeeded()
            #expect(selectedPage.textView.map?.selection(for: selectedPage.textView.selectedRange) == selection)
        }
    }

    private func supports(width: CGFloat, height: CGFloat, regular: Bool = true,
                          pageWidth: CGFloat = 420, accessibility: Bool = false) -> Bool {
        ReaderLayout.supportsTwoPages(in: CGSize(width: width, height: height),
            regularWidth: regular, minimumPageWidth: pageWidth, accessibilitySize: accessibility)
    }
}
