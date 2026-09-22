import Foundation

/// A transient mapping for one rendered chapter. Gutter numbers and the chapter header are excluded; source superscriptions remain selectable.
struct ChapterTextMap {
    struct Entry {
        let verse: ChapterDocument.Verse
        let range: NSRange
    }
    let text: String
    let entries: [Entry]
    let sourceHeadingRanges: [NSRange]

    init(document: ChapterDocument) {
        var buffer = ""
        var entries: [Entry] = []
        var sourceHeadingRanges: [NSRange] = []
        for verse in document.verses {
            for heading in verse.headings {
                sourceHeadingRanges.append(NSRange(location: buffer.utf16.count, length: heading.utf16.count))
                buffer += heading + "\n"
            }
            let start = buffer.utf16.count
            buffer += verse.text
            entries.append(Entry(verse: verse, range: NSRange(location: start, length: verse.text.utf16.count)))
            buffer += "\n"
        }
        for block in document.trailingBlocks ?? [] {
            sourceHeadingRanges.append(NSRange(location: buffer.utf16.count, length: block.text.utf16.count))
            buffer += block.text + "\n"
        }
        self.sourceHeadingRanges = sourceHeadingRanges
        self.text = buffer
        self.entries = entries
    }

    func touched(by range: NSRange) -> [Entry] {
        guard range.location != NSNotFound, range.length > 0 else { return [] }
        return entries.filter { NSIntersectionRange($0.range, range).length > 0 }
    }

    func selection(for range: NSRange) -> PassageSelection? {
        let touched = touched(by: range)
        guard let first = touched.first, let last = touched.last else { return nil }
        return PassageSelection(
            start: VerseAnchor(verseID: first.verse.id, utf16Offset: max(0, range.location - first.range.location)),
            end: VerseAnchor(verseID: last.verse.id, utf16Offset: min(last.range.length, NSMaxRange(range) - last.range.location)),
            leadingContextUTF16: max(0, first.range.location - range.location),
            trailingContextUTF16: max(0, NSMaxRange(range) - NSMaxRange(last.range))
        )
    }

    func offset(for anchor: VerseAnchor) -> Int? {
        guard let entry = entries.first(where: { $0.verse.id == anchor.verseID }) else { return nil }
        let offset = min(max(0, anchor.utf16Offset), entry.range.length)
        let string = entry.verse.text as NSString
        // Clamp a revised anchor to a composed-character boundary.
        let safeOffset = offset == string.length ? offset : string.rangeOfComposedCharacterSequence(at: offset).location
        return entry.range.location + safeOffset
    }

    func range(for selection: PassageSelection) -> NSRange? {
        guard let start = offset(for: selection.start), let end = offset(for: selection.end), end >= start else { return nil }
        // Source superscriptions are separate from verse identity but remain selectable.
        // Preserve their transient boundary offsets while remapping the verse anchors.
        let lower = max(0, start - selection.leadingContextUTF16)
        let upper = min(text.utf16.count, end + selection.trailingContextUTF16)
        return NSRange(location: lower, length: upper - lower)
    }

    func copyText(range: NSRange, document: ChapterDocument) -> String? {
        guard let swiftRange = Range(range, in: text), let first = touched(by: range).first,
              let last = touched(by: range).last else { return nil }
        let labels = first.verse.id == last.verse.id ? first.verse.label : "\(first.verse.label)–\(last.verse.label)"
        let partial = range.location != first.range.location || NSMaxRange(range) < NSMaxRange(last.range)
        return "\(text[swiftRange].trimmingCharacters(in: .newlines))\n— \(document.reference):\(labels), \(document.editionLabel)\(partial ? " (excerpt)" : "")"
    }
}
