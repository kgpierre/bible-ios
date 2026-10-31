import CoreGraphics
import Foundation
import Testing
@testable import BibleReader

struct ChapterPaginationTests {
    /// Ten 30-point lines, each 10 characters, starting at the container top.
    private func lines(_ count: Int = 10, headings: Set<Int> = []) -> [ChapterPagination.Line] {
        (0..<count).map { ChapterPagination.Line(offset: $0 * 10, top: CGFloat($0) * 30, bottom: CGFloat($0 + 1) * 30,
                                                 keepsWithNext: headings.contains($0)) }
    }

    @Test func breaksAtLinesWithSmallerFirstPage() {
        let pagination = ChapterPagination(lines: lines(), textLength: 100, firstPageHeight: 95, pageHeight: 125)
        // The titled first page fits three lines; later pages fit four.
        #expect(pagination.pages.map(\.start) == [0, 30, 70])
        #expect(pagination.pages.map(\.end) == [30, 70, 100])
        #expect(pagination.pages[1].top == 90)
        #expect(pagination.pages[1].bottom == 210)
        #expect(pagination.pages.allSatisfy { $0.height <= 125 })
        #expect(pagination.page(containing: 45) == 1)
        #expect(pagination.page(containing: 100) == 2)
    }

    @Test func oddPagesBesideTheSelectorHoldFewerLines() {
        // Even (left) pages run to the screen edge: four lines. Odd (right) pages stop above the
        // passage selector: three lines.
        let pagination = ChapterPagination(lines: lines(), textLength: 100, firstPageHeight: 125, pageHeight: 125, oddPageHeight: 95)
        #expect(pagination.pages.map(\.start) == [0, 40, 70])
        #expect(pagination.pages.map(\.end) == [40, 70, 100])
        #expect(pagination.pages[1].height <= 95)
    }

    @Test func everyCharacterIsOnExactlyOnePage() {
        let pagination = ChapterPagination(lines: lines(37), textLength: 371, firstPageHeight: 200, pageHeight: 260)
        #expect(pagination.pages.first?.start == 0)
        #expect(pagination.pages.last?.end == 371)
        for (page, next) in zip(pagination.pages, pagination.pages.dropFirst()) { #expect(page.end == next.start) }
    }

    @Test func headingsStayWithTheTextTheyIntroduce() {
        // Line 2 is a heading that would otherwise end the first page.
        let pagination = ChapterPagination(lines: lines(headings: [2]), textLength: 100, firstPageHeight: 95, pageHeight: 300)
        #expect(pagination.pages.map(\.start) == [0, 20])
    }

    @Test func aPageOfOnlyHeadingsStillAdvances() {
        let pagination = ChapterPagination(lines: lines(4, headings: [0, 1, 2]), textLength: 40, firstPageHeight: 65, pageHeight: 65)
        #expect(pagination.pages.map(\.start) == [0, 20])
    }

    @Test func singlePageAndEmptyChapters() {
        #expect(ChapterPagination(lines: lines(3), textLength: 30, firstPageHeight: 500, pageHeight: 600).pages.count == 1)
        let empty = ChapterPagination(lines: [], textLength: 0, firstPageHeight: 500, pageHeight: 600)
        #expect(empty.pages == [.init(start: 0, end: 0, top: 0, bottom: 0)])
    }
}
