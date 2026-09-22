import Foundation

struct TextSearchQuery: Equatable, Sendable {
    let expression: String

    init?(_ input: String) throws {
        guard input.count <= 200 else { throw SearchInputError.tooLong }
        let input = input.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        var quoted = false
        var buffer = ""
        var clauses: [String] = []
        var tokenCount = 0
        func finish() {
            let tokens = buffer.unicodeScalars.split { !CharacterSet.alphanumerics.union(.nonBaseCharacters).contains($0) }
                .map(String.init)
            tokenCount += tokens.count
            if !tokens.isEmpty { clauses.append("\"" + tokens.joined(separator: " ") + "\"") }
            buffer = ""
        }
        for char in input {
            if char == "\"" { finish(); quoted.toggle() }
            else if char.isWhitespace && !quoted { finish() }
            else { buffer.append(char) }
        }
        guard !quoted else { throw SearchInputError.unmatchedQuote }
        finish()
        guard tokenCount <= 32 else { throw SearchInputError.tooManyTerms }
        guard !clauses.isEmpty else { return nil }
        expression = clauses.joined(separator: " AND ")
    }
}

enum SearchExcerpt {
    /// FTS delimiters are parsed as data, never rendered as HTML or Markdown.
    static func fragments(_ marked: String, source: String) -> [SearchFragment] {
        let fallback = [SearchFragment(text: String(source.prefix(240)), isMatch: false)]
        guard !source.contains("\u{1e}"), !source.contains("\u{1f}") else { return fallback }
        var fragments: [SearchFragment] = []
        var buffer = ""
        var active = false
        func flush() {
            if !buffer.isEmpty { fragments.append(SearchFragment(text: buffer, isMatch: active)); buffer = "" }
        }
        for char in marked {
            if char == "\u{1e}" {
                guard !active else { return fallback }
                flush(); active = true
            } else if char == "\u{1f}" {
                guard active else { return fallback }
                flush(); active = false
            } else { buffer.append(char) }
        }
        guard !active else { return fallback }
        flush()
        let plain = fragments.map(\.text).joined().trimmingCharacters(in: CharacterSet(charactersIn: "…"))
        guard !plain.isEmpty, source.contains(plain) else { return fallback }
        return fragments
    }
}
