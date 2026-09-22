import Foundation

struct ChapterDocument: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let bookID: String
    let bookName: String
    let eyebrow: String
    let label: String
    let editionLabel: String
    let verses: [Verse]
    var trailingBlocks: [SourceBlock]? = nil

    struct SourceBlock: Codable, Equatable, Sendable {
        let kind: String
        let text: String
        let sourceXML: String
    }

    var reference: String { "\(bookName) \(label)" }

    struct Verse: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let label: String
        let runs: [Run]
        let structure: String
        let headings: [String]
        let notes: [String]
        var text: String { runs.map(\.text).joined() }
    }

    struct Run: Codable, Equatable, Sendable {
        let text: String
        let italic: Bool
    }
}

/// Offsets are relative to a stable verse, never a database identity or a pixel position.
struct VerseAnchor: Codable, Equatable, Sendable {
    let verseID: String
    let utf16Offset: Int
}

struct PassageSelection: Equatable, Sendable {
    let start: VerseAnchor
    let end: VerseAnchor
    var leadingContextUTF16 = 0
    var trailingContextUTF16 = 0
}

struct ReadingAnchor: Codable, Equatable, Sendable {
    let text: VerseAnchor
    let viewportY: Double
}
