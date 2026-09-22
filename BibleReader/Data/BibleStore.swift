import Foundation
import GRDB
import os

/// Owns isolated database access. The bundle is never copied into writable user storage.
actor BibleStore {
    let editionID: String
    let revision: String
    private let corpus: DatabaseQueue
    private let user: DatabaseQueue
    private let userURL: URL
    private var cachedReferenceParser: ReferenceParser?
    private var chapterCache: [String: ChapterDocument] = [:]
    private var chapterRecency: [String] = []
    private let chapterCacheLimit = 6
    private let decoder = JSONDecoder()
    #if DEBUG
    private(set) var exactDecodeCount = 0
    private(set) var chapterDecodeCount = 0
    private(set) var savedChapterDecodeCount = 0
    #endif
    private var exactByChapter: [String: [ExactAnnotation]]?
    private var annotationDataVersion: Int?
    private var cachedSavedItems: [SavedItem]?
    private var dirtySavedChapters = Set<String>()

    private func cachedExact(_ db: Database) throws -> [String: [ExactAnnotation]] {
        let version = try Int.fetchOne(db, sql: "PRAGMA data_version")
        if annotationDataVersion != version {
            exactByChapter = nil
            cachedSavedItems = nil
            annotationDataVersion = version
        }
        if let exactByChapter { return exactByChapter }
        let records = try Data.fetchAll(db, sql: "SELECT payload FROM exact_annotation WHERE editionID=? ORDER BY id", arguments: [editionID])
            .map { try decoder.decode(ExactAnnotation.self, from: $0) }
        #if DEBUG
        exactDecodeCount += records.count
        #endif
        let grouped = Dictionary(grouping: records, by: { $0.passage.chapterID })
        exactByChapter = grouped
        return grouped
    }

    private func replaceCachedExact(chapterID: String, removing: [ExactAnnotation], inserting: [ExactAnnotation]) {
        let removed = Set(removing.map(\.id))
        var records = exactByChapter?[chapterID] ?? []
        records.removeAll { removed.contains($0.id) }
        records.append(contentsOf: inserting)
        exactByChapter?[chapterID] = records.sorted { $0.id < $1.id }
        dirtySavedChapters.insert(chapterID)
    }


    private func remember(_ document: ChapterDocument) {
        chapterCache[document.id] = document
        chapterRecency.removeAll { $0 == document.id }
        chapterRecency.append(document.id)
        while chapterRecency.count > chapterCacheLimit {
            chapterCache.removeValue(forKey: chapterRecency.removeFirst())
        }
    }

    init(corpusURL: URL, userURL: URL) throws {
        var config = Configuration()
        config.readonly = true
        corpus = try DatabaseQueue(path: corpusURL.path, configuration: config)
        let identity = try corpus.read { db -> (String, String) in
            guard try Int.fetchOne(db, sql: "PRAGMA user_version") == 1,
                  let row = try Row.fetchOne(db, sql: "SELECT * FROM edition"),
                  (row["documentVersion"] as Int) == 1 else { throw StorageIssue.incompatibleCorpus }
            return (row["id"], row["revision"])
        }
        editionID = identity.0
        revision = identity.1
        self.userURL = userURL
        let directory = userURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.protectionKey: FileProtectionType.complete])
        var writable = Configuration()
        writable.busyMode = .timeout(2)
        user = try DatabaseQueue(path: userURL.path, configuration: writable)
        try user.read { db in
            if try db.tableExists("grdb_migrations") {
                let known = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
                guard known.allSatisfy({ ["v1_local_reader", "v2_exact_annotations"].contains($0) }) else { throw StorageIssue.incompatibleUserStore }
            }
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_local_reader") { db in
            try db.execute(sql: """
                CREATE TABLE highlight(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, verseID TEXT NOT NULL,
                    color TEXT NOT NULL CHECK(color IN ('yellow','sage','blue','rose')), operationID TEXT NOT NULL,
                    created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID,verseID));
                CREATE TABLE bookmark(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, startID TEXT NOT NULL,
                    endID TEXT NOT NULL, created REAL NOT NULL, updated REAL NOT NULL, UNIQUE(editionID,startID,endID));
                CREATE TABLE reading_position(editionID TEXT PRIMARY KEY, payload BLOB NOT NULL);
                """)
        }
        migrator.registerMigration("v2_exact_annotations") { db in
            try db.execute(sql: "CREATE TABLE exact_annotation(id TEXT PRIMARY KEY, editionID TEXT NOT NULL, payload BLOB NOT NULL)")
            try db.execute(sql: "CREATE INDEX exact_annotation_edition ON exact_annotation(editionID)")
        }
        try migrator.migrate(user)
        try Self.protectFiles(at: userURL)
    }

    private static func protectFiles(at url: URL) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let path = url.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
            }
        }
    }

    func lookupReference(_ input: String) throws -> SearchResponse {
        switch try parser().parse(input) {
        case .text: return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .invalid("Enter a reference such as John 3:16 or Jude 5.")
        case .invalid(let message): return .invalid(message)
        case .reference(let parsed): return try resolve(parsed, suggested: false)
        case .suggestion(let parsed): return try resolve(parsed, suggested: true)
        }
    }

    private func parser() throws -> ReferenceParser {
        if let cachedReferenceParser { return cachedReferenceParser }
        let aliases = try corpus.read { db in
            try Row.fetchAll(db, sql: "SELECT alias,bookID FROM reference_alias").map { ReferenceAlias(alias: $0["alias"], bookID: $0["bookID"]) }
        }
        let parser = ReferenceParser(books: try books(), aliases: aliases)
        cachedReferenceParser = parser
        return parser
    }

    private func resolve(_ parsed: ParsedReference, suggested: Bool) throws -> SearchResponse {
        let chapterID = try corpus.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM chapter WHERE bookID=? AND label=?", arguments: [parsed.bookID,parsed.chapter])
        }
        guard let chapterID else { return .invalid("That chapter is not in this book. Choose a chapter from Books.") }
        let document = try chapter(chapterID)
        var verses: [ChapterDocument.Verse] = []
        if let first = parsed.firstVerse, let last = parsed.lastVerse {
            guard let start = document.verses.firstIndex(where: { $0.label == first }),
                  let end = document.verses.firstIndex(where: { $0.label == last }), start <= end else {
                return .invalid("That verse range is not in \(document.reference). This chapter has \(document.verses.count) source verses.")
            }
            verses = Array(document.verses[start...end])
        }
        let labels = verses.first.map { first in ":\(first.label)\(first.id == verses.last?.id ? "" : "–" + (verses.last?.label ?? ""))" } ?? ""
        let passage = ResolvedPassage(chapterID: chapterID, verseIDs: verses.map(\.id), reference: document.reference + labels,
                                      preview: (verses.isEmpty ? Array(document.verses.prefix(1)) : verses).map(\.text).joined(separator: " "))
        return suggested ? .suggestion(passage) : .reference(passage)
    }

    func search(_ input: String, offset: Int = 0) async throws -> SearchResponse {
        let interval = ReaderPerformance.signposter.beginInterval("Local search", id: ReaderPerformance.signposter.makeSignpostID())
        defer { ReaderPerformance.signposter.endInterval("Local search", interval) }
        try Task.checkCancellation()
        switch try parser().parse(input) {
        case .reference(let parsed): return try resolve(parsed, suggested: false)
        case .suggestion(let parsed): return try resolve(parsed, suggested: true)
        case .invalid(let message): return .invalid(message)
        case .text: break
        }
        let query: TextSearchQuery
        do {
            guard let parsed = try TextSearchQuery(input) else { return .empty }
            query = parsed
        } catch let error as SearchInputError { return .invalid(error.message) }
        guard offset >= 0, offset <= 100_000 else { return .invalid("This result page is unavailable. Search again.") }
        return try await corpus.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT count(*) FROM verse_search WHERE verse_search MATCH ?", arguments: [query.expression]) ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT verse.id, verse.chapterID, verse.label AS verseLabel, verse.text,
                       chapter.label AS chapterLabel, book.name,
                       snippet(verse_search,1,char(30),char(31),'…',28) AS excerpt
                FROM verse_search JOIN verse ON verse.id=verse_search.verseID
                JOIN chapter ON chapter.id=verse.chapterID JOIN book ON book.id=chapter.bookID
                WHERE verse_search MATCH ? ORDER BY bm25(verse_search), verse.ordinal
                LIMIT 50 OFFSET ?
                """, arguments: [query.expression,offset])
            let hits = rows.map { row -> SearchHit in
                let name: String = row["name"], chapter: String = row["chapterLabel"], verse: String = row["verseLabel"]
                return SearchHit(id: row["id"], chapterID: row["chapterID"], reference: "\(name) \(chapter):\(verse)",
                                 excerpt: SearchExcerpt.fragments(row["excerpt"], source: row["text"]))
            }
            return .results(SearchPage(hits: hits,total: total))
        }
    }

    func editionNotice() throws -> String {
        guard let url = Bundle.main.url(forResource: "EditionNotice", withExtension: "txt") else { throw StorageIssue.incompatibleCorpus }
        return try String(contentsOf: url, encoding: .utf8)
    }

    struct ReaderBootstrap: Sendable {
        let books: [BookSummary]
        let catalog: [ChapterSummary]
        let position: StoredPosition?
        let notice: String
    }

    func readerBootstrap() throws -> ReaderBootstrap {
        let interval = ReaderPerformance.signposter.beginInterval("Reader bootstrap", id: ReaderPerformance.signposter.makeSignpostID())
        defer { ReaderPerformance.signposter.endInterval("Reader bootstrap", interval) }
        return ReaderBootstrap(books: try books(), catalog: try chapters(), position: try position(), notice: try editionNotice())
    }

    func books() throws -> [BookSummary] {
        try corpus.read { db in
            try Row.fetchAll(db, sql: "SELECT book.*,count(chapter.id) AS count FROM book JOIN chapter ON chapter.bookID=book.id GROUP BY book.id ORDER BY book.ordinal").map {
                BookSummary(id: $0["id"], name: $0["name"], shortName: $0["shortName"], chapterCount: $0["count"], ordinal: $0["ordinal"])
            }
        }
    }

    func chapters() throws -> [ChapterSummary] {
        try corpus.read { db in
            try Row.fetchAll(db, sql: "SELECT chapter.*,book.name FROM chapter JOIN book ON book.id=chapter.bookID ORDER BY chapter.ordinal").map {
                ChapterSummary(id: $0["id"], bookID: $0["bookID"], bookName: $0["name"], label: $0["label"], ordinal: $0["ordinal"])
            }
        }
    }

    func chapter(_ id: String) throws -> ChapterDocument {
        if let cached = chapterCache[id] {
            remember(cached)
            return cached
        }
        let document = try corpus.read { db in
            guard let payload = try String.fetchOne(db, sql: "SELECT payload FROM chapter_document WHERE chapterID=?", arguments: [id]) else { throw StorageIssue.invalidPassage }
            return try JSONDecoder().decode(ChapterDocument.self, from: Data(payload.utf8))
        }
        #if DEBUG
        chapterDecodeCount += 1
        #endif
        remember(document)
        return document
    }

    func summarySources(bookID: String, chapterID: String, question: String, preferred: [SummarySource.Reference] = [], preferredOnly: Bool = false) throws -> [SummarySource] {
        let interval = ReaderPerformance.signposter.beginInterval("Book source retrieval", id: ReaderPerformance.signposter.makeSignpostID())
        defer { ReaderPerformance.signposter.endInterval("Book source retrieval", interval) }
        try Task.checkCancellation()
        return try corpus.read { db in
            let locations = Array(preferred.prefix(6).filter { $0.chapter.count <= 8 && $0.verse.count <= 8 })
            let filter = preferredOnly ? " AND (" + (locations.isEmpty ? "0" : Array(repeating: "(chapter.label=? AND verse.label=?)", count: locations.count).joined(separator: " OR ")) + ")" : ""
            let arguments = StatementArguments([bookID] + (preferredOnly ? locations.flatMap { [$0.chapter, $0.verse] } : []))
            let sources = try Row.fetchAll(db, sql: """
                SELECT verse.id, verse.chapterID, verse.label, verse.text, chapter.label AS chapterLabel, book.name
                FROM verse JOIN chapter ON chapter.id=verse.chapterID JOIN book ON book.id=chapter.bookID
                WHERE book.id=?\(filter) ORDER BY verse.ordinal
                """, arguments: arguments).map { row -> SummarySource in
                    let name: String = row["name"], label: String = row["chapterLabel"], verse: String = row["label"]
                    return SummarySource(id: row["id"], bookID: bookID, chapterID: row["chapterID"],
                                         reference: "\(name) \(label):\(verse)", text: row["text"])
                }
            try Task.checkCancellation()
            let wanted = Set(preferred.prefix(6).filter { $0.chapter.count <= 8 && $0.verse.count <= 8 }.map { "\($0.chapter):\($0.verse)" })
            let verified = Set(sources.filter { source in
                wanted.contains(String(source.reference.split(separator: " ").last ?? ""))
            }.map(\.id))
            let candidates = preferredOnly ? sources.filter { verified.contains($0.id) } : sources
            return SummarySource.select(candidates, question: question, chapterID: chapterID, preferredIDs: verified)
        }
    }

    func position() throws -> StoredPosition? {
        let edition = editionID
        return try user.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM reading_position WHERE editionID=?", arguments: [edition]).map {
                try JSONDecoder().decode(StoredPosition.self, from: $0)
            }
        }
    }

    func savePosition(chapterID: String, anchor: ReadingAnchor?) throws {
        try Task.checkCancellation()
        let valid = try corpus.read { db in
            if let anchor {
                return try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM verse WHERE id=? AND chapterID=?)", arguments: [anchor.text.verseID, chapterID]) ?? false
            }
            return try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM chapter WHERE id=?)", arguments: [chapterID]) ?? false
        }
        guard valid else { throw StorageIssue.invalidPassage }
        let payload = try JSONEncoder().encode(StoredPosition(chapterID: chapterID, anchor: anchor, revision: revision, updated: Date().timeIntervalSince1970))
        let edition = editionID
        try user.write { db in
            try db.execute(sql: "INSERT INTO reading_position VALUES(?,?) ON CONFLICT(editionID) DO UPDATE SET payload=excluded.payload", arguments: [edition, payload])
        }
    }

    func readerAnnotations() throws -> (AnnotationSnapshot, [ExactAnnotation]) {
        let edition = editionID
        return try user.read { db in
            (try Self.snapshot(db, edition: edition), try cachedExact(db).values.flatMap { $0 }.sorted { $0.id < $1.id })
        }
    }

    func annotations() throws -> AnnotationSnapshot {
        let edition = editionID
        return try user.read { db in try Self.snapshot(db, edition: edition) }
    }

    private static func snapshot(_ db: Database, edition: String, ids: [String]? = nil, chapters: Set<String>? = nil) throws -> AnnotationSnapshot {
        func chapterPredicate(_ column: String) -> String {
            guard let chapters else { return "" }
            return " AND (" + (chapters.isEmpty ? "0" : Array(repeating: "(\(column)>=? AND \(column)<?)", count: chapters.count).joined(separator: " OR ")) + ")"
        }
        let chapterArguments = (chapters?.sorted() ?? []).flatMap { [$0 + ":", $0 + ";"] }
        let placeholders = ids.map { Array(repeating: "?", count: $0.count).joined(separator: ",") }
        let highlightSQL = "SELECT * FROM highlight WHERE editionID=?" + (placeholders.map { " AND verseID IN (\($0))" } ?? "") + chapterPredicate("verseID") + " ORDER BY verseID"
        let highlightArguments = StatementArguments([edition] + (ids ?? []) + chapterArguments)
        let highlights = try Row.fetchAll(db, sql: highlightSQL, arguments: highlightArguments).map { row -> HighlightRecord in
            guard let color = HighlightColor(rawValue: row["color"]) else { throw StorageIssue.incompatibleUserStore }
            return HighlightRecord(id: row["id"], verseID: row["verseID"], color: color, operationID: row["operationID"], created: row["created"], updated: row["updated"])
        }
        let bookmarkSQL = "SELECT * FROM bookmark WHERE editionID=?" + (ids == nil ? "" : " AND startID=? AND endID=?") + chapterPredicate("startID") + " ORDER BY id"
        let bookmarkArguments = StatementArguments([edition] + (ids.map { [$0.first ?? "", $0.last ?? ""] } ?? []) + chapterArguments)
        let bookmarks = try Row.fetchAll(db, sql: bookmarkSQL, arguments: bookmarkArguments).map {
            BookmarkRecord(id: $0["id"], startID: $0["startID"], endID: $0["endID"], created: $0["created"], updated: $0["updated"])
        }
        return AnnotationSnapshot(highlights: highlights, bookmarks: bookmarks)
    }

    private func validate(_ ids: [String]) throws {
        guard let first = ids.first else { throw StorageIssue.invalidPassage }
        let chapterID = first.split(separator: ":").dropLast().joined(separator: ":")
        let verses = try chapter(chapterID).verses.map(\.id)
        guard let start = verses.firstIndex(of: first), start + ids.count <= verses.count,
              Array(verses[start..<start + ids.count]) == ids else { throw StorageIssue.invalidPassage }
    }

    func edit(verseIDs: [String], color: HighlightColor?, bookmark: Bool, updateHighlights: Bool = true) throws -> AnnotationChange {
        try validate(verseIDs)
        let edition = editionID
        let now = Date().timeIntervalSince1970
        let operation = UUID().uuidString
        let change = try user.write { db in
            let before = try Self.snapshot(db, edition: edition, ids: verseIDs)
            for id in updateHighlights ? verseIDs : [] {
                if let color {
                    try db.execute(sql: """
                        INSERT INTO highlight VALUES(?,?,?,?,?,?,?) ON CONFLICT(editionID,verseID)
                        DO UPDATE SET color=excluded.color,operationID=excluded.operationID,updated=excluded.updated
                        """, arguments: [UUID().uuidString, edition, id, color.rawValue, operation, now, now])
                } else {
                    try db.execute(sql: "DELETE FROM highlight WHERE editionID=? AND verseID=?", arguments: [edition,id])
                }
            }
            if bookmark {
                try db.execute(sql: "INSERT INTO bookmark VALUES(?,?,?,?,?,?) ON CONFLICT(editionID,startID,endID) DO NOTHING",
                               arguments: [UUID().uuidString,edition,verseIDs.first!,verseIDs.last!,now,now])
            } else {
                try db.execute(sql: "DELETE FROM bookmark WHERE editionID=? AND startID=? AND endID=?", arguments: [edition,verseIDs.first!,verseIDs.last!])
            }
            let after = try Self.snapshot(db, edition: edition, ids: verseIDs)
            return AnnotationChange(verseIDs: verseIDs, before: before, after: after)
        }
        dirtySavedChapters.formUnion(verseIDs.map { $0.split(separator: ":").dropLast().joined(separator: ":") })
        return change
    }

    func undo(_ change: AnnotationChange) throws {
        let edition = editionID
        try user.write { db in
            let current = try Self.snapshot(db, edition: edition, ids: change.verseIDs)
            guard current == change.after else { throw StorageIssue.undoConflict }
            for id in change.verseIDs {
                try db.execute(sql: "DELETE FROM highlight WHERE editionID=? AND verseID=?", arguments: [edition,id])
            }
            try db.execute(sql: "DELETE FROM bookmark WHERE editionID=? AND startID=? AND endID=?", arguments: [edition,change.verseIDs.first!,change.verseIDs.last!])
            for h in change.before.highlights {
                try db.execute(sql: "INSERT INTO highlight VALUES(?,?,?,?,?,?,?)", arguments: [h.id,edition,h.verseID,h.color.rawValue,h.operationID,h.created,h.updated])
            }
            for b in change.before.bookmarks {
                try db.execute(sql: "INSERT INTO bookmark VALUES(?,?,?,?,?,?)", arguments: [b.id,edition,b.startID,b.endID,b.created,b.updated])
            }
        }
        dirtySavedChapters.formUnion(change.verseIDs.map { $0.split(separator: ":").dropLast().joined(separator: ":") })
    }

    func exactAnnotations() throws -> [ExactAnnotation] {
        try user.read { db in try cachedExact(db).values.flatMap { $0 }.sorted { $0.id < $1.id } }
    }

    private static func putExact(_ record: ExactAnnotation, db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO exact_annotation VALUES(?,?,?)",
                       arguments: [record.id, record.editionID, try JSONEncoder().encode(record)])
    }

    private static func exactScope(_ records: [ExactAnnotation], ids: [String], recordIDs: Set<String> = []) -> [ExactAnnotation] {
        let set = Set(ids)
        return records.filter { recordIDs.contains($0.id) || !$0.passage.parts.allSatisfy { !set.contains($0.verseID) } }.sorted { $0.id < $1.id }
    }

    /// A single transaction preserves legacy records outside the selection, splits overlaps,
    /// and writes exact text. A nil color only removes highlights when bookmarkAction is nil.
    func editExact(_ passage: ExactPassage, color: HighlightColor?, bookmarkAction: Bool? = nil) throws -> ExactAnnotationChange {
        let interval = ReaderPerformance.signposter.beginInterval("Annotation transaction", id: ReaderPerformance.signposter.makeSignpostID())
        defer { ReaderPerformance.signposter.endInterval("Annotation transaction", interval) }
        try validate(passage.verseIDs)
        let document = try chapter(passage.chapterID)
        let edition = editionID, revision = revision
        // The cache is checked inside the transaction so another connection cannot make Undo stale.
        let change = try user.write { db in
            let chapterRecords = try cachedExact(db)[passage.chapterID] ?? []
            let before = Self.exactScope(chapterRecords, ids: passage.verseIDs)
            let legacyBefore = try Self.snapshot(db, edition: edition, ids: passage.verseIDs)
            let change = try ExactAnnotationEditor.change(passage: passage, document: document, before: before,
                legacyBefore: legacyBefore, color: color, bookmarkAction: bookmarkAction,
                edition: edition, revision: revision, now: Date().timeIntervalSince1970, newID: UUID().uuidString)
            for record in change.before { try db.execute(sql: "DELETE FROM exact_annotation WHERE id=?", arguments: [record.id]) }
            for record in change.after { try Self.putExact(record, db: db) }
            for record in change.legacyBefore.highlights where !change.legacyAfter.highlights.contains(where: { $0.id == record.id }) {
                try db.execute(sql: "DELETE FROM highlight WHERE id=?", arguments: [record.id])
            }
            for record in change.legacyBefore.bookmarks where !change.legacyAfter.bookmarks.contains(where: { $0.id == record.id }) {
                try db.execute(sql: "DELETE FROM bookmark WHERE id=?", arguments: [record.id])
            }
            return change
        }
        replaceCachedExact(chapterID: passage.chapterID, removing: change.before, inserting: change.after)
        return change
    }

    func undoExact(_ change: ExactAnnotationChange) throws {
        let edition = editionID
        try user.write { db in
            let chapterID = change.verseIDs[0].split(separator: ":").dropLast().joined(separator: ":")
            let current = Self.exactScope(try cachedExact(db)[chapterID] ?? [], ids: change.verseIDs,
                                          recordIDs: Set((change.before + change.after).map(\.id)))
            let legacy = try Self.snapshot(db, edition: edition, ids: change.verseIDs)
            guard current == change.after, legacy == change.legacyAfter else { throw StorageIssue.undoConflict }
            for record in current { try db.execute(sql: "DELETE FROM exact_annotation WHERE id=?", arguments: [record.id]) }
            for record in change.before { try Self.putExact(record, db: db) }
            for id in change.verseIDs { try db.execute(sql: "DELETE FROM highlight WHERE editionID=? AND verseID=?", arguments: [edition,id]) }
            for h in change.legacyBefore.highlights {
                try db.execute(sql: "INSERT INTO highlight VALUES(?,?,?,?,?,?,?)", arguments: [h.id,edition,h.verseID,h.color.rawValue,h.operationID,h.created,h.updated])
            }
            for bookmark in change.legacyAfter.bookmarks {
                try db.execute(sql: "DELETE FROM bookmark WHERE id=?", arguments: [bookmark.id])
            }
            for bookmark in change.legacyBefore.bookmarks {
                try db.execute(sql: "INSERT INTO bookmark VALUES(?,?,?,?,?,?)",
                    arguments: [bookmark.id, edition, bookmark.startID, bookmark.endID, bookmark.created, bookmark.updated])
            }
        }
        let chapterID = change.verseIDs[0].split(separator: ":").dropLast().joined(separator: ":")
        replaceCachedExact(chapterID: chapterID, removing: change.after, inserting: change.before)
    }


    func savedItems() throws -> [SavedItem] {
        let interval = ReaderPerformance.signposter.beginInterval("Saved resolution", id: ReaderPerformance.signposter.makeSignpostID())
        defer { ReaderPerformance.signposter.endInterval("Saved resolution", interval) }
        try Task.checkCancellation()
        let edition = editionID
        let data = try user.read { db -> (AnnotationSnapshot, [ExactAnnotation], Set<String>?)? in
            let exact = try cachedExact(db)
            let rebuilding = cachedSavedItems == nil ? nil : dirtySavedChapters
            if rebuilding?.isEmpty == true { return nil }
            let records = rebuilding.map { ids in ids.flatMap { exact[$0] ?? [] } } ?? exact.values.flatMap { $0 }
            return (try Self.snapshot(db, edition: edition, chapters: rebuilding), records, rebuilding)
        }
        guard let (snapshot, exactRecords, rebuilding) = data else { return cachedSavedItems ?? [] }
        // Fetch chapter payloads in a batch, then resolve all saved passages in memory.
        let verseIDs = snapshot.highlights.map(\.verseID) + snapshot.bookmarks.flatMap { [$0.startID,$0.endID] }
        let chapterIDs = Array(Set(verseIDs.map { $0.split(separator: ":").dropLast().joined(separator: ":") } + exactRecords.map { $0.passage.chapterID })).sorted()
        var documents = chapterCache.filter { chapterIDs.contains($0.key) }
        let missing = chapterIDs.filter { documents[$0] == nil }
        for start in stride(from: 0, to: missing.count, by: 200) {
            try Task.checkCancellation()
            let chunk = Array(missing[start..<min(start+200,missing.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let payloads = try corpus.read { db in
                try String.fetchAll(db, sql: "SELECT payload FROM chapter_document WHERE chapterID IN (\(placeholders))", arguments: StatementArguments(chunk))
            }
            for payload in payloads {
                let doc = try JSONDecoder().decode(ChapterDocument.self, from: Data(payload.utf8))
                documents[doc.id] = doc
                #if DEBUG
                savedChapterDecodeCount += 1
                #endif
            }
        }
        var items: [SavedItem] = []
        let byVerse = Dictionary(uniqueKeysWithValues: snapshot.highlights.map { ($0.verseID, $0) })
        var resolved = Set<String>()
        for chapterID in chapterIDs {
            try Task.checkCancellation()
            guard let doc = documents[chapterID] else { continue }
            var group: [(ChapterDocument.Verse, HighlightRecord)] = []
            func finishGroup() {
                guard let first = group.first, let last = group.last else { return }
                let reference = "\(doc.reference):\(first.0.label)\(first.0.id == last.0.id ? "" : "–" + last.0.label)"
                items.append(SavedItem(id: first.1.id, chapterID: chapterID, verseID: first.0.id,
                                       reference: reference, text: group.map { $0.0.text }.joined(separator: " "),
                                       color: first.1.color, bookmark: false, updated: group.map { $0.1.updated }.max() ?? 0))
                group.removeAll()
            }
            for verse in doc.verses {
                guard let highlight = byVerse[verse.id] else { finishGroup(); continue }
                resolved.insert(verse.id)
                if let previous = group.last, previous.1.operationID != highlight.operationID || previous.1.color != highlight.color { finishGroup() }
                group.append((verse, highlight))
            }
            finishGroup()
        }
        for h in snapshot.highlights where !resolved.contains(h.verseID) {
            items.append(SavedItem(id: h.id, chapterID: h.verseID.split(separator: ":").dropLast().joined(separator: ":"),
                                   verseID: h.verseID, reference: h.verseID, text: "This saved reference is unavailable in the installed edition.",
                                   color: h.color, bookmark: false, updated: h.updated))
        }
        for b in snapshot.bookmarks {
            let chapterID = b.startID.split(separator: ":").dropLast().joined(separator: ":")
            let doc = documents[chapterID]
            let verses = doc?.verses ?? []
            let start = verses.firstIndex { $0.id == b.startID }
            let end = verses.firstIndex { $0.id == b.endID }
            let passage = if let start, let end, start <= end { Array(verses[start...end]) } else { [ChapterDocument.Verse]() }
            let reference = if let first = passage.first, let last = passage.last { "\(doc!.reference):\(first.label)\(first.id == last.id ? "" : "–" + last.label)" } else { b.startID }
            items.append(SavedItem(id: b.id, chapterID: chapterID, verseID: b.startID, reference: reference,
                                   text: passage.isEmpty ? "This saved reference is unavailable in the installed edition." : passage.map(\.text).joined(separator: " "),
                                   color: nil, bookmark: true, updated: b.updated))
        }
        for record in exactRecords {
            guard let first = record.passage.parts.first else { continue }
            let verses = documents[record.passage.chapterID]?.verses ?? []
            let parts = record.passage.parts.compactMap { part -> SavedTextPart? in
                guard let text = verses.first(where: { $0.id == part.verseID })?.text,
                      let range = part.resolvedRange(in: text) else { return nil }
                return SavedTextPart(verseID: part.verseID, text: text, range: range)
            }
            let unavailable = parts.count != record.passage.parts.count
            var resolved = record.passage
            resolved.parts = parts
            items.append(SavedItem(id: record.id, chapterID: record.passage.chapterID, verseID: first.verseID,
                reference: record.passage.reference + " (excerpt)", text: record.passage.text,
                color: record.color, bookmark: record.isBookmark, updated: record.updated, passage: unavailable ? nil : resolved, unavailable: unavailable))
        }
        if let rebuilding { items.append(contentsOf: (cachedSavedItems ?? []).filter { !rebuilding.contains($0.chapterID) }) }
        let sorted = items.sorted { $0.updated == $1.updated ? $0.id < $1.id : $0.updated > $1.updated }
        cachedSavedItems = sorted
        dirtySavedChapters.removeAll()
        return sorted
    }
}
