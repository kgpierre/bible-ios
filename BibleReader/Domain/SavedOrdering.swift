import Foundation

// Session choices live in AppState so compact/wide presentations share them.
enum SavedFilter: String, CaseIterable, Identifiable {
    case all, highlights, bookmarks
    var id: Self { self }
    var title: String {
        switch self { case .all: String(localized: "All"); case .highlights: String(localized: "Highlights"); case .bookmarks: String(localized: "Bookmarks") }
    }
}

enum SavedSort: String, CaseIterable, Identifiable {
    case recent, bible
    var id: Self { self }
    var title: String { self == .recent ? String(localized: "Most recent") : String(localized: "Bible order") }
}

enum SavedOrdering {
    static func items(_ items: [SavedItem], filter: SavedFilter, sort: SavedSort,
                      chapters: [String: Int]) -> [SavedItem] {
        items.filter { filter == .all || (filter == .bookmarks ? $0.bookmark : $0.color != nil) }
            .sorted { lhs, rhs in
                if sort == .bible {
                    let left = chapters[lhs.chapterID] ?? Int.max, right = chapters[rhs.chapterID] ?? Int.max
                    if left != right { return left < right }
                    if lhs.chapterID != rhs.chapterID { return lhs.chapterID < rhs.chapterID }
                    let lv = lhs.verseOrder ?? Int.max, rv = rhs.verseOrder ?? Int.max
                    if lv != rv { return lv < rv }
                    let lo = lhs.passage?.parts.first?.start ?? 0, ro = rhs.passage?.parts.first?.start ?? 0
                    if lo != ro { return lo < ro }
                }
                if lhs.updated != rhs.updated { return lhs.updated > rhs.updated }
                return lhs.id < rhs.id
            }
    }
}
