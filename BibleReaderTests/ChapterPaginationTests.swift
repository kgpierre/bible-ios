import CoreGraphics
import Foundation
import Testing
@testable import BibleReader

struct ChapterPaginationTests {
    @Test func breaksBetweenVersesWithSmallerFirstPage() {
        // Five 100-point verses; the titled first page fits two, later pages fit three.
        let pagination = ChapterPagination(verseEnds: [100, 200, 300, 400, 500], contentEnd: 500,
                                           firstPageHeight: 250, pageHeight: 300)
        #expect(pagination.pages == [0..<2, 2..<5])
        #expect(!pagination.trailingOnLastPage)
        #expect(pagination.page(containingVerse: 3) == 1)
        #expect(pagination.page(containingVerse: 99) == 0)
    }

    @Test func oversizedVerseGetsItsOwnPageAndIsNeverSplit() {
        let pagination = ChapterPagination(verseEnds: [50, 950, 1000], contentEnd: 1000,
                                           firstPageHeight: 400, pageHeight: 400)
        #expect(pagination.pages == [0..<1, 1..<2, 2..<3])
    }

    @Test func trailingBlocksStayOnLastPageOrTakeTheirOwn() {
        let fits = ChapterPagination(verseEnds: [100, 200], contentEnd: 240, firstPageHeight: 300, pageHeight: 300)
        #expect(fits.pages == [0..<2])
        #expect(fits.trailingOnLastPage)
        let overflows = ChapterPagination(verseEnds: [100, 200], contentEnd: 380, firstPageHeight: 300, pageHeight: 300)
        #expect(overflows.pages == [0..<2, 2..<2])
        #expect(overflows.trailingOnLastPage)
    }

    @Test func singlePageChapter() {
        let pagination = ChapterPagination(verseEnds: [80], contentEnd: 80, firstPageHeight: 500, pageHeight: 600)
        #expect(pagination.pages == [0..<1])
    }

    @Test @MainActor func pageDocumentsKeepChapterIdentityAndCoverEveryVerseOnce() async throws {
        let document = try #require(try await PrototypeLibrary.load().first { $0.bookID == "JHN" })
        let pagination = ChapterPagination(verseEnds: document.verses.indices.map { CGFloat($0 + 1) * 120 },
                                           contentEnd: CGFloat(document.verses.count) * 120,
                                           firstPageHeight: 400, pageHeight: 700)
        let pages = pagination.pages.map { document.page($0, includesTrailingBlocks: false) }
        #expect(pages.allSatisfy { $0.id == document.id && $0.reference == document.reference })
        #expect(pages.flatMap(\.verses).map(\.id) == document.verses.map(\.id))
        // Exact annotations anchor to verse IDs and in-verse offsets, so a page resolves them unchanged.
        let map = ChapterTextMap(document: pages[1])
        let verse = pages[1].verses[0]
        #expect(map.offset(for: VerseAnchor(verseID: verse.id, utf16Offset: 3)) == 3)
    }
}
