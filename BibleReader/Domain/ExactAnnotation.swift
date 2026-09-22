import Foundation

/// Offsets are revision-scoped anchors. Quoted text and context verify them before rendering.
struct SavedTextPart: Codable, Equatable, Sendable {
    let verseID: String
    let start: Int
    let end: Int
    let quote: String
    let before: String
    let after: String

    init?(verseID: String, text: String, range: NSRange) {
        guard range.length > 0, let swiftRange = Range(range, in: text),
              text.indices.contains(swiftRange.lowerBound),
              swiftRange.upperBound == text.endIndex || text.indices.contains(swiftRange.upperBound) else { return nil }
        self.verseID = verseID
        start = range.location; end = NSMaxRange(range)
        quote = String(text[swiftRange])
        before = String(text[..<swiftRange.lowerBound].suffix(24))
        after = String(text[swiftRange.upperBound...].prefix(24))
    }

    func resolvedRange(in text: String) -> NSRange? {
        guard start >= 0, end > start, !quote.isEmpty else { return nil }
        // A compatible correction can shift offsets or duplicate text. Require a unique contextual match,
        // even when one candidate occupies the old offset; never guess from position alone.
        var matches: [NSRange] = []
        var search = text.startIndex..<text.endIndex
        while let found = text.range(of: quote, range: search) {
            if (found.lowerBound == text.endIndex || text.indices.contains(found.lowerBound)),
               (found.upperBound == text.endIndex || text.indices.contains(found.upperBound)),
               text[..<found.lowerBound].hasSuffix(before), text[found.upperBound...].hasPrefix(after) {
                matches.append(NSRange(found, in: text))
            }
            guard found.upperBound < text.endIndex else { break }
            search = found.upperBound..<text.endIndex
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

struct ExactPassage: Codable, Equatable, Sendable {
    let chapterID: String
    var reference: String
    var parts: [SavedTextPart]
    var text: String { parts.map(\.quote).joined(separator: "\n") }
    var verseIDs: [String] { parts.map(\.verseID) }
}

struct ExactAnnotation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let editionID: String
    let revision: String
    var passage: ExactPassage
    let color: HighlightColor? // nil denotes a bookmark; highlights and bookmarks are independent.
    let created: Double
    var updated: Double
    var isBookmark: Bool { color == nil }
}

struct ExactAnnotationChange: Sendable {
    let verseIDs: [String]
    let before: [ExactAnnotation]
    let after: [ExactAnnotation]
    let legacyBefore: AnnotationSnapshot
    let legacyAfter: AnnotationSnapshot
}

enum ReaderAnnotationChange {
    case legacy(AnnotationChange)
    case exact(ExactAnnotationChange)
}

extension ChapterTextMap {
    func exactPassage(range: NSRange, document: ChapterDocument) -> ExactPassage? {
        let entries = touched(by: range)
        guard let first = entries.first, let last = entries.last else { return nil }
        let parts = entries.compactMap { entry -> SavedTextPart? in
            let overlap = NSIntersectionRange(entry.range, range)
            return SavedTextPart(verseID: entry.verse.id, text: entry.verse.text,
                                 range: NSRange(location: overlap.location - entry.range.location, length: overlap.length))
        }
        guard parts.count == entries.count else { return nil }
        let labels = first.verse.label + (first.verse.id == last.verse.id ? "" : "–" + last.verse.label)
        return ExactPassage(chapterID: document.id, reference: document.reference + ":" + labels, parts: parts)
    }
}
