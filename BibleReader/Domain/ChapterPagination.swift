import CoreGraphics

/// Splits a chapter into book pages at line boundaries, from measured layout.
///
/// Every page renders the whole chapter with the same layout used to measure it and shows only
/// its own band of lines, so a page always fits exactly and never scrolls. A verse that does
/// not fit continues on the next page, as in a printed book. Source headings stay with the
/// text they introduce.
struct ChapterPagination: Equatable {
    /// One measured line of the chapter, in text-container coordinates.
    struct Line: Equatable {
        /// UTF-16 offset of the line's first character in the chapter text.
        let offset: Int
        let top: CGFloat
        let bottom: CGFloat
        /// A source heading line, which should not end a page.
        var keepsWithNext = false
    }

    /// The text and the band of lines one page shows.
    struct Page: Equatable {
        /// UTF-16 range of the chapter text on this page.
        let start: Int
        let end: Int
        /// Container coordinates of the first line's top and the last line's bottom.
        let top: CGFloat
        let bottom: CGFloat

        var height: CGFloat { bottom - top }
        func contains(_ offset: Int) -> Bool { offset >= start && offset < end }
    }

    let pages: [Page]

    /// - Parameters:
    ///   - firstPageHeight: text height available on the chapter's first page (below its title).
    ///   - pageHeight: text height available on every later page.
    ///   - oddPageHeight: text height on later odd-numbered pages (index 1, 3, …), when it differs:
    ///     the page beside the floating passage selector stops above it; its facing page need not.
    init(lines: [Line], textLength: Int, firstPageHeight: CGFloat, pageHeight: CGFloat, oddPageHeight: CGFloat? = nil) {
        guard !lines.isEmpty else {
            pages = [Page(start: 0, end: textLength, top: 0, bottom: 0)]
            return
        }
        var pages: [Page] = []
        var first = 0
        while first < lines.count {
            let top = pages.isEmpty ? 0 : lines[first].top
            let available = pages.isEmpty ? firstPageHeight : (pages.count % 2 == 1 ? oddPageHeight ?? pageHeight : pageHeight)
            var last = first
            while last + 1 < lines.count, lines[last + 1].bottom - top <= available { last += 1 }
            // A heading never ends a page when the text it introduces follows on the next one.
            if last + 1 < lines.count {
                var kept = last
                while kept > first, lines[kept].keepsWithNext { kept -= 1 }
                if !lines[kept].keepsWithNext { last = kept }
            }
            let end = last + 1 < lines.count ? lines[last + 1].offset : textLength
            pages.append(Page(start: pages.isEmpty ? 0 : lines[first].offset, end: end, top: top, bottom: lines[last].bottom))
            first = last + 1
        }
        self.pages = pages
    }

    /// The index of the page showing a UTF-16 offset; the last page for the end of the text.
    func page(containing offset: Int) -> Int {
        pages.firstIndex { $0.contains(offset) } ?? max(0, pages.count - 1)
    }
}
