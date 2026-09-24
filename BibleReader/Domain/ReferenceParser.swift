import Foundation

/// Parses references, never Scripture. Corpus metadata supplies identities and aliases.
struct ReferenceParser: Sendable {
    private let books: [String: BookSummary]
    private let aliases: [String: Set<String>]

    init(books: [BookSummary], aliases: [ReferenceAlias]) {
        self.books = Dictionary(uniqueKeysWithValues: books.map { ($0.id,$0) })
        var index: [String: Set<String>] = [:]
        for alias in aliases { index[Self.key(alias.alias), default: []].insert(alias.bookID) }
        for book in books {
            for name in [book.name,book.shortName,book.id] { index[Self.key(name), default: []].insert(book.id) }
        }
        let conventional = ["JHN": ["Jn"], "PSA": ["Psalm","Ps","Pss"], "SNG": ["Song of Songs","Song","Canticles"],
                            "GEN": ["Ge"], "EXO": ["Ex"], "MAT": ["Mt","Matt"], "MRK": ["Mk"], "LUK": ["Lk"],
                            "JAS": ["Jm"], "JUD": ["Jude"], "REV": ["Re","Rev"], "1SA": ["1 Sam"], "2SA": ["2 Sam"],
                            "1KI": ["1 Kgs"], "2KI": ["2 Kgs"], "1CO": ["1 Cor"], "2CO": ["2 Cor"],
                            "1TH": ["1 Thess"], "2TH": ["2 Thess"], "1TI": ["1 Tim"], "2TI": ["2 Tim"],
                            "1PE": ["1 Pet"], "2PE": ["2 Pet"]]
        for (id,names) in conventional where self.books[id] != nil {
            for name in names { index[Self.key(name), default: []].insert(id) }
        }
        self.aliases = index
    }

    private static func key(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "." }
    }

    func parse(_ input: String) -> ReferenceIntent {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        guard input.count <= 200 else { return .invalid(SearchInputError.tooLong.message) }
        guard !input.isEmpty else { return .text }
        if input.contains("\"") || input.contains("“") || input.contains("”") { return .text }
        let pattern = #"^([1-3]?\s*[\p{L}.]+(?:\s+[\p{L}.]+)*?)\s*(\d.*)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let nameRange = Range(match.range(at: 1), in: input) else {
            return input.contains(":") ? .invalid(String(localized: "Use one reference, such as John 3:16–18.")) : .text
        }
        let name = Self.key(String(input[nameRange]))
        let suffix = Range(match.range(at: 2), in: input).map { String(input[$0]).filter { !$0.isWhitespace } }
        let targets = aliases[name] ?? []
        if targets.count > 1 { return .invalid(String(localized: "That book abbreviation is ambiguous. Enter the full book name.")) }
        if let id = targets.first { return parseSuffix(suffix, bookID: id, suggested: false) }
        guard suffix != nil else { return .text }
        // A typo is an explicit proposal, never a navigation or query rewrite.
        var distances: [String: Int] = [:]
        // Suggest full names only: short aliases such as Jon must not tie with John
        // for the transposition Jhon, or turn an unrelated word into a book.
        for book in books.values {
            let fullName = Self.key(book.name)
            guard abs(fullName.count - name.count) <= 2,
                  fullName.first?.isNumber == name.first?.isNumber else { continue }
            distances[book.id] = Self.distance(name, fullName)
        }
        let threshold = name.count >= 5 ? 2 : 1
        if let best = distances.values.min(), best <= threshold {
            let candidates = distances.filter { $0.value == best }.map(\.key)
            if candidates.count == 1 { return parseSuffix(suffix, bookID: candidates[0], suggested: true) }
        }
        return .invalid(String(localized: "Book not recognized. Try a full name, such as John 3:16."))
    }

    private func parseSuffix(_ suffix: String?, bookID: String, suggested: Bool) -> ReferenceIntent {
        guard let book = books[bookID] else { return .invalid(String(localized: "This book is unavailable in this edition.")) }
        var chapter = "1"
        var first: String?
        var last: String?
        if let suffix {
            let pieces = suffix.split(separator: ":", omittingEmptySubsequences: false)
            if pieces.count > 2 || suffix.contains(",") || suffix.contains(";") {
                return .invalid(String(localized: "Use one chapter and one continuous verse range at a time."))
            }
            let versePart: String?
            if pieces.count == 1, book.chapterCount == 1 {
                versePart = String(pieces[0])
            } else {
                guard pieces[0].utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(pieces[0]), number > 0 else {
                    return .invalid(String(localized: "Enter a valid chapter number. Chapter ranges are not supported."))
                }
                chapter = String(number)
                versePart = pieces.count == 2 ? String(pieces[1]) : nil
            }
            if let versePart {
                let range = versePart.split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(range.count), range.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }), let start = Int(range[0]), start > 0,
                      let end = Int(range.last!), end >= start else {
                    return .invalid(String(localized: "Enter a valid verse or increasing range, such as 16–18."))
                }
                first = String(start)
                last = String(end)
            }
        }
        let reference = ParsedReference(bookID: bookID, chapter: chapter, firstVerse: first, lastVerse: last)
        return suggested ? .suggestion(reference) : .reference(reference)
    }

    // Optimal string alignment distance includes adjacent transpositions (Jhon → John).
    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: b.count+1), count: a.count+1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count,b.count) }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                matrix[i][j] = min(matrix[i-1][j]+1, matrix[i][j-1]+1, matrix[i-1][j-1]+cost)
                if i > 1, j > 1, a[i-1] == b[j-2], a[i-2] == b[j-1] {
                    matrix[i][j] = min(matrix[i][j], matrix[i-2][j-2]+1)
                }
            }
        }
        return matrix[a.count][b.count]
    }
}
