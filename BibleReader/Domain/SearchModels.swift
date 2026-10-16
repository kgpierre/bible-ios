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
    /// A bare book name such as `Mark`: also an ordinary word, so Search runs a text query and
    /// offers the book explicitly instead of navigating.
    case book(ParsedReference)
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

/// An explicit "Open <Book>" offer shown above text results for a bare book-name query.
struct BookShortcut: Equatable, Sendable {
    let name: String
    let passage: ResolvedPassage
}

struct SearchPage: Equatable, Sendable {
    var hits: [SearchHit]
    let total: Int
    var book: BookShortcut? = nil
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
        case .tooLong: String(localized: "Use 200 characters or fewer.")
        case .unmatchedQuote: String(localized: "Close the quotation marks to search for a phrase.")
        case .tooManyTerms: String(localized: "Use 32 search terms or fewer.")
        }
    }
}
