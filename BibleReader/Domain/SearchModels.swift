import Foundation

struct ReferenceAlias: Sendable {
    let alias: String
    let bookID: String
}

struct ParsedReference: Equatable, Sendable {
    let bookID: String
    let chapter: String
    let firstVerse: String?
    let lastVerse: String?
}

enum ReferenceIntent: Equatable, Sendable {
    case text
    case reference(ParsedReference)
    case suggestion(ParsedReference)
    case invalid(String)
}

struct ResolvedPassage: Equatable, Sendable {
    let chapterID: String
    let verseIDs: [String]
    let reference: String
    let preview: String
}

struct SearchFragment: Equatable, Sendable {
    let text: String
    let isMatch: Bool
}

struct SearchHit: Identifiable, Equatable, Sendable {
    let id: String
    let chapterID: String
    let reference: String
    let excerpt: [SearchFragment]
    var plainExcerpt: String { excerpt.map(\.text).joined() }
}

struct SearchPage: Equatable, Sendable {
    var hits: [SearchHit]
    let total: Int
    var hasMore: Bool { hits.count < total }
}

enum SearchResponse: Equatable, Sendable {
    case empty
    case invalid(String)
    case reference(ResolvedPassage)
    case suggestion(ResolvedPassage)
    case results(SearchPage)
}

enum SearchInputError: Error, Equatable {
    case tooLong, unmatchedQuote, tooManyTerms
    var message: String {
        switch self {
        case .tooLong: "Use 200 characters or fewer."
        case .unmatchedQuote: "Close the quotation marks to search for a phrase."
        case .tooManyTerms: "Use 32 search terms or fewer."
        }
    }
}
