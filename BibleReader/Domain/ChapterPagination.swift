import CoreGraphics

/// Splits a chapter into book pages at verse boundaries, from measured layout.
///
/// Heights come from one continuous layout of the chapter at page width, so a page lays out
/// exactly as measured. Verses are never split: a verse taller than a page gets a page of its
/// own and scrolls there. Source headings travel with the verse they precede.
struct ChapterPagination: Equatable {
    /// Verse index ranges, one per page. A page may be empty only when it carries trailing blocks.
    let pages: [Range<Int>]
    /// Whether the final page carries the chapter's trailing source blocks.
    let trailingOnLastPage: Bool

    /// - Parameters:
    ///   - verseEnds: bottom of each verse's last line (including any preceding headings),
    ///     in one continuous text-container coordinate space starting at 0.
    ///   - contentEnd: bottom of the chapter's content, including trailing blocks.
    ///   - firstPageHeight: text height available on the chapter's first page (below its title).
    ///   - pageHeight: text height available on every later page.
    init(verseEnds: [CGFloat], contentEnd: CGFloat, firstPageHeight: CGFloat, pageHeight: CGFloat) {
        var pages: [Range<Int>] = []
        var start = 0
        var top: CGFloat = 0
        func available(_ page: Int) -> CGFloat { page == 0 ? firstPageHeight : pageHeight }
        for index in verseEnds.indices where index > start && verseEnds[index] - top > available(pages.count) {
            pages.append(start..<index)
            top = verseEnds[index - 1]
            start = index
        }
        pages.append(start..<verseEnds.count)
        let trailing = contentEnd - (verseEnds.last ?? 0)
        if trailing > 0.5, contentEnd - top > available(pages.count - 1), !(pages.last?.isEmpty ?? true) {
            pages.append(verseEnds.count..<verseEnds.count)
        }
        self.pages = pages
        trailingOnLastPage = trailing > 0.5
    }

    /// The index of the page that contains a verse; the first page when the verse is absent.
    func page(containingVerse index: Int) -> Int {
        pages.firstIndex { $0.contains(index) } ?? 0
    }
}

extension ChapterDocument {
    /// One book page of this chapter. It keeps the chapter's identity, so annotations,
    /// notes, copy references, and anchors resolve exactly as in the continuous reader.
    func page(_ verses: Range<Int>, includesTrailingBlocks: Bool) -> ChapterDocument {
        ChapterDocument(id: id, bookID: bookID, bookName: bookName, eyebrow: eyebrow, label: label,
                        editionLabel: editionLabel, verses: Array(self.verses[verses]),
                        trailingBlocks: includesTrailingBlocks ? trailingBlocks : nil)
    }
}
