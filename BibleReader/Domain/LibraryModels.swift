import Foundation

struct BookSummary: Identifiable, Sendable {
    let id: String
    let name: String
    let shortName: String
    let chapterCount: Int
    let ordinal: Int
}

struct ChapterSummary: Identifiable, Sendable {
    let id: String
    let bookID: String
    let bookName: String
    let label: String
    let ordinal: Int
    var reference: String { "\(bookName) \(label)" }
}

struct HighlightRecord: Codable, Equatable, Sendable {
    let id: String
    let verseID: String
    let color: HighlightColor
    let operationID: String
    let created: Double
    let updated: Double
}

struct BookmarkRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let startID: String
    let endID: String
    let created: Double
    let updated: Double
}

/// A whole chapter saved by identity, independent of verse highlights and bookmarks.
struct SavedChapterRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let chapterID: String
    let created: Double
    let updated: Double
}

/// One save or removal; Undo restores `before` only while the store still holds `after`.
struct SavedChapterChange: Sendable {
    let chapterID: String
    let before: SavedChapterRecord?
    let after: SavedChapterRecord?
}

struct AnnotationSnapshot: Equatable, Sendable {
    var highlights: [HighlightRecord]
    var bookmarks: [BookmarkRecord]
}

struct AnnotationChange: Sendable {
    let verseIDs: [String]
    let before: AnnotationSnapshot
    let after: AnnotationSnapshot
}

struct StoredPosition: Codable, Equatable, Sendable {
    let chapterID: String
    let anchor: ReadingAnchor?
    let revision: String
    var updated: Double? = nil
}

struct SavedItem: Identifiable, Sendable {
    let id: String
    let chapterID: String
    let verseID: String
    let reference: String
    let text: String
    let color: HighlightColor?
    let bookmark: Bool
    let updated: Double
    var passage: ExactPassage? = nil
    var unavailable = false
    var verseOrder: Int? = nil
    var records = SavedRecords()
    /// A saved whole chapter; `text` is its opening verse and `verseCount` its length.
    var savedChapter = false
    var verseCount: Int? = nil
}

/// Original persisted values identify exactly what the user saw before deleting.
struct SavedRecords: Equatable, Sendable {
    var exact: [ExactAnnotation] = []
    var highlights: [HighlightRecord] = []
    var bookmarks: [BookmarkRecord] = []
    var chapters: [SavedChapterRecord] = []
}

enum StorageIssue: Error {
    case incompatibleCorpus, incompatibleUserStore, invalidPassage, undoConflict, insufficientSpace
}
