import Foundation

/// Owner-reviewed pronunciation hints for Read Aloud (plan §4.5, decision Q11). Hints only steer how
/// a voice pronounces a name; the spoken text itself never changes. The bundled list starts empty,
/// and the owner approves each entry by listening on device with the voices it was tested on.
struct NarrationLexicon: Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        /// The exact word as it appears in the corpus, matched whole-word and case-sensitively.
        let word: String
        /// International Phonetic Alphabet for `AVSpeechSynthesisIPANotationAttribute`.
        let ipa: String
        /// Voice identifiers the owner listened with.
        let voices: [String]
        /// Who approved the entry and when, for example "KP 2026-11-07".
        let reviewed: String
    }

    /// A hint for one range of the spoken text, in UTF-16.
    struct Hint: Sendable, Equatable {
        let range: NSRange
        let ipa: String
    }

    let entries: [Entry]

    static let empty = NarrationLexicon(entries: [])

    /// Entries missing a pronunciation or a review are dropped, never guessed.
    init(entries: [Entry]) {
        self.entries = entries.filter {
            !$0.word.isEmpty && !$0.ipa.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.reviewed.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    init(data: Data) throws {
        self.init(entries: try JSONDecoder().decode([Entry].self, from: data))
    }

    /// The bundled list; a missing or unreadable file means no hints, not an error.
    static func bundled(_ bundle: Bundle = .main) -> NarrationLexicon {
        guard let url = bundle.url(forResource: "NarrationLexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url), let lexicon = try? NarrationLexicon(data: data) else { return .empty }
        return lexicon
    }

    /// Whole-word, case-sensitive matches in `text`. A match must not continue a word on either
    /// side, so "Jordan" never matches inside "Jordanian".
    func hints(in text: String) -> [Hint] {
        guard !entries.isEmpty else { return [] }
        let string = text as NSString
        var hints: [Hint] = []
        for entry in entries {
            var search = NSRange(location: 0, length: string.length)
            while true {
                let found = string.range(of: entry.word, options: [.literal], range: search)
                guard found.location != NSNotFound else { break }
                if !Self.continuesWord(string, before: found.location), !Self.continuesWord(string, after: NSMaxRange(found)),
                   !hints.contains(where: { NSIntersectionRange($0.range, found).length > 0 }) {
                    hints.append(Hint(range: found, ipa: entry.ipa))
                }
                let next = NSMaxRange(found)
                search = NSRange(location: next, length: string.length - next)
            }
        }
        return hints.sorted { $0.range.location < $1.range.location }
    }

    private static func continuesWord(_ string: NSString, before index: Int) -> Bool {
        index > 0 && isWordCharacter(string.substring(with: string.rangeOfComposedCharacterSequence(at: index - 1)))
    }

    private static func continuesWord(_ string: NSString, after index: Int) -> Bool {
        index < string.length && isWordCharacter(string.substring(with: string.rangeOfComposedCharacterSequence(at: index)))
    }

    private static func isWordCharacter(_ character: String) -> Bool {
        character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
