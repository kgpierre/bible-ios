import Foundation

struct SummarySource: Codable, Equatable, Identifiable, Sendable {
    struct Reference: Sendable {
        let chapter: String
        let verse: String
    }
    let id: String
    let bookID: String
    let chapterID: String
    let reference: String
    let text: String
}

extension SummarySource {
    /// Deterministic lexical retrieval, not semantic search. Whole source verses remain untouched.
    static func select(_ sources: [SummarySource], question: String, chapterID: String, preferredIDs: Set<String> = []) -> [SummarySource] {
        let stop: Set<String> = ["the", "a", "an", "in", "on", "of", "and", "or", "is", "are", "was", "were", "what", "who", "why", "how", "does", "do", "this", "that", "chapter", "book", "about", "tell", "me", "to", "it", "his", "her"]
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let terms = words(question).subtracting(stop)
        var ranked: [(Int, SummarySource, Int)] = []
        for (index, source) in sources.enumerated() {
            let matches = words(source.text + " " + source.reference).intersection(terms).count
            let score = (preferredIDs.contains(source.id) ? 10000 : 0) + matches * 10 + (source.chapterID == chapterID ? 1 : 0)
            ranked.append((index, source, score))
        }
        ranked.sort { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }
        var result: [(Int, SummarySource)] = [], count = 0
        for (index, source, score) in ranked where score > 0 {
            guard result.count < 24 else { break }
            guard count + source.text.count <= 6500 else { continue }
            result.append((index, source)); count += source.text.count
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
