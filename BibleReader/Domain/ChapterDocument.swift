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
        let text: String

        private enum CodingKeys: String, CodingKey { case id, label, runs, structure, headings, notes }

        init(id: String, label: String, runs: [Run], structure: String, headings: [String], notes: [String]) {
            self.id = id
            self.label = label
            self.runs = runs
            self.structure = structure
            self.headings = headings
            self.notes = notes
            text = runs.map(\.text).joined()
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(id: try values.decode(String.self, forKey: .id),
                label: try values.decode(String.self, forKey: .label),
                runs: try values.decode([Run].self, forKey: .runs),
                structure: try values.decode(String.self, forKey: .structure),
                headings: try values.decode([String].self, forKey: .headings),
                notes: try values.decode([String].self, forKey: .notes))
        }
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
