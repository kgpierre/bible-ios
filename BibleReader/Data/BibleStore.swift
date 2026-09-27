import Foundation
import Dispatch
import GRDB
import os

/// Owns isolated database access. The bundle is never copied into writable user storage.
actor BibleStore {
    // Synchronous GRDB transactions must not occupy Swift's cooperative executor.
    // Search suspends on its independent connection, allowing position/chapter work to proceed.
    private nonisolated let executor = DispatchSerialQueue(label: "BibleReader.storage", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    let editionID: String
    let revision: String
    private let corpus: DatabaseQueue
    private let searchCorpus: DatabaseQueue
    /// Ranked verse ordinals for the latest text query; the corpus is immutable, so they stay valid.
    private var rankedSearch: (expression: String, ordinals: [Int64])?
    private let user: DatabaseQueue
    private let userURL: URL
    private var cachedReferenceParser: ReferenceParser?
    private var searchPrewarmed = false
    private var chapterCache: [String: ChapterDocument] = [:]
    private var chapterRecency: [String] = []
    private let chapterCacheLimit = 6
    private let decoder = JSONDecoder()
    #if DEBUG
    func clearSavedCacheForTesting() { cachedSavedItems = nil }
    /// Awaited after a Saved rebuild resolves and before it publishes, to order overlapping rebuilds.
    private var savedResolutionHook: (@Sendable () async -> Void)?
    func setSavedResolutionHookForTesting(_ hook: (@Sendable () async -> Void)?) { savedResolutionHook = hook }
    func quickCheck() throws -> String { try user.read { try String.fetchOne($0, sql: "PRAGMA quick_check") ?? "no result" } }
    private(set) var exactDecodeCount = 0
    private(set) var chapterDecodeCount = 0
    private(set) var savedChapterDecodeCount = 0
    #endif
    /// Decoded exact annotations for chapters that have been requested. Only touched chapters are
    /// decoded, using the v3 `chapterID` column, so library size does not scale reader work.
    private var exactByChapter: [String: [ExactAnnotation]] = [:]
    private var annotationDataVersion: Int?
    private var cachedSavedItems: [SavedItem]?
    /// Chapter → generation of its latest change, so a Saved rebuild that finishes after a later
    /// edit leaves that chapter dirty.
    private var dirtySavedChapters: [String: Int] = [:]
    private var savedGeneration = 0
    /// Generation of the input behind `cachedSavedItems`; an older rebuild never replaces it.
    private var publishedSavedGeneration = -1
    private let savedCorpus: DatabaseQueue

    /// Another connection's commit changes `data_version`; our own commits do not.
    private func synchronizeAnnotationVersion(_ db: Database) throws {
        let version = try Int.fetchOne(db, sql: "PRAGMA data_version")
        if annotationDataVersion != version {
            exactByChapter = [:]
            cachedSavedItems = nil
            // Rebuilds that read before this change must not publish afterwards.
            savedGeneration += 1
            annotationDataVersion = version
        }
    }

    private func exactRecords(in chapterID: String, _ db: Database) throws -> [ExactAnnotation] {
        try synchronizeAnnotationVersion(db)
        if let cached = exactByChapter[chapterID] { return cached }
        let records = try Data.fetchAll(db, sql: "SELECT payload FROM exact_annotation WHERE editionID=? AND chapterID=? ORDER BY id",
                                        arguments: [editionID, chapterID]).map { try decoder.decode(ExactAnnotation.self, from: $0) }
        #if DEBUG
        exactDecodeCount += records.count
        #endif
        exactByChapter[chapterID] = records
        return records
    }

    private func replaceCachedExact(chapterID: String, removing: [ExactAnnotation], inserting: [ExactAnnotation]) {
        markSavedDirty([chapterID])
        guard var records = exactByChapter[chapterID] else { return }
        let removed = Set(removing.map(\.id))
        records.removeAll { removed.contains($0.id) }
        records.append(contentsOf: inserting)
        exactByChapter[chapterID] = records.sorted { $0.id < $1.id }
    }

    private func markSavedDirty(_ chapterIDs: some Sequence<String>) {
        savedGeneration += 1
        for id in chapterIDs { dirtySavedChapters[id] = savedGeneration }
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
        searchCorpus = try DatabaseQueue(path: corpusURL.path, configuration: config)
        savedCorpus = try DatabaseQueue(path: corpusURL.path, configuration: config)
        let identity = try corpus.read { db -> (String, String) in
            // Schema 2: external-content FTS keyed by verse.ordinal. Document 2: raw-DEFLATE JSON chapter payloads.
            guard try Int.fetchOne(db, sql: "PRAGMA user_version") == 2,
                  let row = try Row.fetchOne(db, sql: "SELECT * FROM edition"),
                  (row["documentVersion"] as Int) == 2 else { throw StorageIssue.incompatibleCorpus }
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
        let migrations = ["v1_local_reader", "v2_exact_annotations", "v3_exact_chapter_index"]
        let applied = try user.read { db -> [String] in
            guard try db.tableExists("grdb_migrations") else { return [] }
            return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        }
        guard applied.allSatisfy(migrations.contains) else { throw StorageIssue.incompatibleUserStore }
        // An existing store gets a consistent, protected copy before any pending migration.
        if !applied.isEmpty, applied.count < migrations.count { try Self.backupBeforeMigration(user, userURL: userURL) }
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
        // Additive: chapter and highlight columns let the reader decode one chapter's records and
        // list highlighted chapters without decoding the whole library. Payloads are unchanged.
        migrator.registerMigration("v3_exact_chapter_index") { db in
            try db.execute(sql: "ALTER TABLE exact_annotation ADD COLUMN chapterID TEXT")
            try db.execute(sql: "ALTER TABLE exact_annotation ADD COLUMN highlighted INTEGER NOT NULL DEFAULT 0")
            let decoder = JSONDecoder()
            for row in try Row.fetchAll(db, sql: "SELECT id, payload FROM exact_annotation") {
                let record = try decoder.decode(ExactAnnotation.self, from: row["payload"] as Data)
                try db.execute(sql: "UPDATE exact_annotation SET chapterID=?, highlighted=? WHERE id=?",
                               arguments: [record.passage.chapterID, record.color != nil, row["id"] as String])
            }
            try db.execute(sql: "CREATE INDEX exact_annotation_chapter ON exact_annotation(editionID, chapterID)")
        }
        try migrator.migrate(user)
        try Self.protectFiles(at: userURL)
    }

    /// Online backup API copy, so pending journal/WAL state is included. One file is retained and
    /// replaced by the next migration's copy; it is excluded from device backup because the live
    /// store already is backed up. Low space fails before migrating instead of risking the original.
    private static func backupBeforeMigration(_ source: DatabaseQueue, userURL: URL) throws {
        let backupURL = userURL.deletingLastPathComponent().appendingPathComponent("User-before-migration.sqlite")
        let size = (try? FileManager.default.attributesOfItem(atPath: userURL.path)[.size] as? Int) ?? 0
        if let free = try? userURL.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < Int64(size * 2 + 1_000_000) {
            throw StorageIssue.insufficientSpace
        }
        try? FileManager.default.removeItem(at: backupURL)
        let destination = try DatabaseQueue(path: backupURL.path)
        try source.backup(to: destination)
        try destination.close()
        try protectFiles(at: backupURL)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var url = backupURL
        try url.setResourceValues(excluded)
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
        case .text: return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .invalid(String(localized: "Enter a reference such as John 3:16 or Jude 5."))
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
        guard let chapterID else { return .invalid(String(localized: "That chapter is not in this book. Choose a chapter from Books.")) }
        let document = try chapter(chapterID)
        var verses: [ChapterDocument.Verse] = []
        if let first = parsed.firstVerse, let last = parsed.lastVerse {
            guard let start = document.verses.firstIndex(where: { $0.label == first }),
                  let end = document.verses.firstIndex(where: { $0.label == last }), start <= end else {
                return .invalid(String(localized: "That verse range is not in \(document.reference). This chapter has \(document.verses.count) source verses."))
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
        guard offset >= 0, offset <= 100_000 else { return .invalid(String(localized: "This result page is unavailable. Search again.")) }
        // Rank every match once per query (bm25, then canonical order) and keep the ordinals. Later
        // pages fetch 50 known rows instead of re-scoring and sorting all matches past an OFFSET.
        let cached = rankedSearch?.expression == query.expression ? rankedSearch?.ordinals : nil
        let expression = query.expression
        let (ordinals, page) = try await searchCorpus.read { db -> ([Int64], SearchPage) in
            let ordinals = try cached ?? Int64.fetchAll(db, sql: "SELECT rowid FROM verse_search WHERE verse_search MATCH ? ORDER BY bm25(verse_search), rowid",
                                                        arguments: [expression])
            let slice = offset < ordinals.count ? Array(ordinals[offset..<min(offset + 50, ordinals.count)]) : []
            guard !slice.isEmpty else { return (ordinals, SearchPage(hits: [], total: ordinals.count)) }
            let rows = try Row.fetchAll(db, sql: """
                SELECT verse.ordinal, verse.id, verse.chapterID, verse.label AS verseLabel, verse.text,
                       chapter.label AS chapterLabel, book.name,
                       snippet(verse_search,0,char(30),char(31),'…',28) AS excerpt
                FROM verse_search JOIN verse ON verse.ordinal=verse_search.rowid
                JOIN chapter ON chapter.id=verse.chapterID JOIN book ON book.id=chapter.bookID
                WHERE verse_search MATCH ? AND verse_search.rowid IN (\(Array(repeating: "?", count: slice.count).joined(separator: ",")))
                """, arguments: StatementArguments([expression.databaseValue] + slice.map(\.databaseValue)))
            let byOrdinal = Dictionary(uniqueKeysWithValues: rows.map { ($0["ordinal"] as Int64, $0) })
            let hits = slice.compactMap { byOrdinal[$0] }.map { row -> SearchHit in
                let name: String = row["name"], chapter: String = row["chapterLabel"], verse: String = row["verseLabel"]
                return SearchHit(id: row["id"], chapterID: row["chapterID"], reference: "\(name) \(chapter):\(verse)",
                                 excerpt: SearchExcerpt.fragments(row["excerpt"], source: row["text"]))
            }
            return (ordinals, SearchPage(hits: hits, total: ordinals.count))
        }
        rankedSearch = (expression, ordinals)
        return .results(page)
    }

    /// Builds the reference parser and runs one representative ranked query on the search
    /// connection, off the main thread. `length(block)` would not do: SQLite answers it from
    /// record headers without reading BLOB content. Ranking the most common term reads its full
    /// posting list plus the bm25 document-size table and prepares the search statements.
    /// Bounded, idempotent, and read-only.
    func prewarmSearch() async {
        guard !searchPrewarmed else { return }
        searchPrewarmed = true
        _ = try? parser()
        _ = try? await searchCorpus.read { db in
            try Int.fetchOne(db, sql: "SELECT rowid FROM verse_search WHERE verse_search MATCH 'the' ORDER BY bm25(verse_search) LIMIT 1")
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
            guard let payload = try Data.fetchOne(db, sql: "SELECT payload FROM chapter_document WHERE chapterID=?", arguments: [id]) else { throw StorageIssue.invalidPassage }
            return try decoder.decode(ChapterDocument.self, from: Self.inflate(payload))
        }
        #if DEBUG
        chapterDecodeCount += 1
        #endif
        remember(document)
        return document
    }

    /// Chapter payloads are raw DEFLATE (COMPRESSION_ZLIB); a corrupt payload is a corpus error, never placeholder text.
    private static func inflate(_ payload: Data) throws -> Data {
        do { return try (payload as NSData).decompressed(using: .zlib) as Data }
        catch { throw StorageIssue.incompatibleCorpus }
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
                try decoder.decode(StoredPosition.self, from: $0)
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

    struct ReaderAnnotations: Sendable {
        let legacy: AnnotationSnapshot
        /// Exact records only for the requested chapters; every requested chapter has an entry.
        let exact: [String: [ExactAnnotation]]
        let highlightedChapterIDs: Set<String>
    }

    func readerAnnotations(chapterIDs: [String]) throws -> ReaderAnnotations {
        let edition = editionID
        return try user.read { db in
            var exact: [String: [ExactAnnotation]] = [:]
            for id in chapterIDs { exact[id] = try exactRecords(in: id, db) }
            return ReaderAnnotations(legacy: try Self.snapshot(db, edition: edition), exact: exact,
                                     highlightedChapterIDs: try highlightedExactChapters(db))
        }
    }

    func exactAnnotations(in chapterIDs: [String]) throws -> [String: [ExactAnnotation]] {
        try user.read { db in
            var exact: [String: [ExactAnnotation]] = [:]
            for id in chapterIDs { exact[id] = try exactRecords(in: id, db) }
            return exact
        }
    }

    func highlightedExactChapterIDs() throws -> Set<String> {
        try user.read { db in try highlightedExactChapters(db) }
    }

    private func highlightedExactChapters(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT DISTINCT chapterID FROM exact_annotation WHERE editionID=? AND highlighted=1",
                                arguments: [editionID]))
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
        let chapterID = ScriptureID.chapter(containing: first)
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
        markSavedDirty(verseIDs.map { ScriptureID.chapter(containing: $0) })
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
        markSavedDirty(change.verseIDs.map { ScriptureID.chapter(containing: $0) })
    }

    /// Every exact record, decoded without caching. Tests and diagnostics only; the reader loads by chapter.
    func exactAnnotations() throws -> [ExactAnnotation] {
        try user.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM exact_annotation WHERE editionID=? ORDER BY id", arguments: [editionID])
                .map { try decoder.decode(ExactAnnotation.self, from: $0) }
        }
    }

    private static func putExact(_ record: ExactAnnotation, db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO exact_annotation(id, editionID, payload, chapterID, highlighted) VALUES(?,?,?,?,?)",
                       arguments: [record.id, record.editionID, try JSONEncoder().encode(record), record.passage.chapterID, record.color != nil])
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
            let chapterRecords = try exactRecords(in: passage.chapterID, db)
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
            let chapterID = ScriptureID.chapter(containing: change.verseIDs[0])
            let current = Self.exactScope(try exactRecords(in: chapterID, db), ids: change.verseIDs,
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
        let chapterID = ScriptureID.chapter(containing: change.verseIDs[0])
        replaceCachedExact(chapterID: chapterID, removing: change.after, inserting: change.before)
    }


    /// Delete only persisted records represented by a displayed row, even if its source is unavailable.
    func deleteSaved(_ item: SavedItem) throws -> ExactAnnotationChange {
        let selected = item.records
        var seen = Set<String>()
        let ids = (selected.exact.flatMap { $0.passage.verseIDs } + selected.highlights.map(\.verseID) +
                   selected.bookmarks.flatMap { [$0.startID, $0.endID] }).filter { seen.insert($0).inserted }
        guard !ids.isEmpty,
              ids.allSatisfy({ ScriptureID.chapter(containing: $0) == item.chapterID }) else {
            throw StorageIssue.invalidPassage
        }
        let change = try user.write { db in
            let before = Self.exactScope(try exactRecords(in: item.chapterID, db), ids: ids)
            let legacy = try Self.snapshot(db, edition: editionID, ids: ids)
            guard selected.exact.allSatisfy({ before.contains($0) }),
                  selected.highlights.allSatisfy({ legacy.highlights.contains($0) }),
                  selected.bookmarks.allSatisfy({ legacy.bookmarks.contains($0) }) else { throw StorageIssue.undoConflict }
            let exactIDs = Set(selected.exact.map(\.id))
            let highlightIDs = Set(selected.highlights.map(\.id))
            let bookmarkIDs = Set(selected.bookmarks.map(\.id))
            for record in selected.exact {
                try db.execute(sql: "DELETE FROM exact_annotation WHERE editionID=? AND id=?", arguments: [editionID, record.id])
            }
            for record in selected.highlights {
                try db.execute(sql: "DELETE FROM highlight WHERE editionID=? AND id=?", arguments: [editionID, record.id])
            }
            for record in selected.bookmarks {
                try db.execute(sql: "DELETE FROM bookmark WHERE editionID=? AND id=?", arguments: [editionID, record.id])
            }
            return ExactAnnotationChange(verseIDs: ids, before: before,
                after: before.filter { !exactIDs.contains($0.id) }, legacyBefore: legacy,
                legacyAfter: AnnotationSnapshot(highlights: legacy.highlights.filter { !highlightIDs.contains($0.id) },
                                                bookmarks: legacy.bookmarks.filter { !bookmarkIDs.contains($0.id) }))
        }
        replaceCachedExact(chapterID: item.chapterID, removing: change.before, inserting: change.after)
        return change
    }

    /// Raw rows are read on the store queue (cheap). Decoding annotations and resolving verse text run
    /// off it on a dedicated read-only corpus connection, so chapter loads and position saves are not
    /// queued behind a large library. Only chapters changed since the last pass are rebuilt.
    func savedItems() async throws -> [SavedItem] {
        let interval = ReaderPerformance.signposter.beginInterval("Saved resolution", id: ReaderPerformance.signposter.makeSignpostID())
        defer { ReaderPerformance.signposter.endInterval("Saved resolution", interval) }
        try Task.checkCancellation()
        let input = try savedInput()
        guard let (snapshot, payloads, rebuilding) = input else { return cachedSavedItems ?? [] }
        let generation = savedGeneration
        var items = try await Self.resolveSaved(snapshot: snapshot, payloads: payloads, corpus: savedCorpus)
        #if DEBUG
        await savedResolutionHook?()
        #endif
        // Rebuilds can overlap across suspensions. A newer one already published: defer to it
        // (and any later edits) rather than overwrite it with this older snapshot.
        guard generation >= publishedSavedGeneration else { return try await savedItems() }
        if let rebuilding {
            // Another connection invalidated the cache while resolving: rebuild everything.
            guard let cached = cachedSavedItems else { return try await savedItems() }
            items.append(contentsOf: cached.filter { !rebuilding.contains($0.chapterID) })
        }
        let sorted = items.sorted { $0.updated == $1.updated ? $0.id < $1.id : $0.updated > $1.updated }
        cachedSavedItems = sorted
        publishedSavedGeneration = generation
        dirtySavedChapters = dirtySavedChapters.filter { $0.value > generation }
        return sorted
    }

    /// Synchronous on the store queue: raw payloads and legacy rows for a full or incremental rebuild.
    private func savedInput() throws -> (AnnotationSnapshot, [Data], Set<String>?)? {
        let edition = editionID
        return try user.read { db -> (AnnotationSnapshot, [Data], Set<String>?)? in
            try synchronizeAnnotationVersion(db)
            let rebuilding: Set<String>? = cachedSavedItems == nil ? nil : Set(dirtySavedChapters.keys)
            if rebuilding?.isEmpty == true { return nil }
            var payloads: [Data] = []
            if let rebuilding {
                let ids = rebuilding.sorted()
                for start in stride(from: 0, to: ids.count, by: 200) {
                    let chunk = Array(ids[start..<min(start + 200, ids.count)])
                    payloads += try Data.fetchAll(db, sql: "SELECT payload FROM exact_annotation WHERE editionID=? AND chapterID IN (\(Array(repeating: "?", count: chunk.count).joined(separator: ",")))",
                                                  arguments: StatementArguments([edition] + chunk))
                }
            } else {
                payloads = try Data.fetchAll(db, sql: "SELECT payload FROM exact_annotation WHERE editionID=?", arguments: [edition])
            }
            return (try Self.snapshot(db, edition: edition, chapters: rebuilding), payloads, rebuilding)
        }
    }

    @concurrent private static func resolveSaved(snapshot: AnnotationSnapshot, payloads: [Data], corpus: DatabaseQueue) async throws -> [SavedItem] {
        let decoder = JSONDecoder()
        let exactRecords = try payloads.map { try decoder.decode(ExactAnnotation.self, from: $0) }
        // Saved needs canonical verse text and order, not chapter runs, notes, or typography.
        let verseIDs = snapshot.highlights.map(\.verseID) + snapshot.bookmarks.flatMap { [$0.startID, $0.endID] }
        let chapterIDs = Array(Set(verseIDs.map { ScriptureID.chapter(containing: $0) } + exactRecords.map { $0.passage.chapterID })).sorted()
        struct Verse: Sendable {
            let id: String
            let label: String
            let text: String
        }
        struct Chapter {
            let reference: String
            var verses: [Verse] = []
            var index: [String: Int] = [:]
        }
        var documents: [String: Chapter] = [:]
        for start in stride(from: 0, to: chapterIDs.count, by: 200) {
            try Task.checkCancellation()
            let chunk = Array(chapterIDs[start..<min(start + 200, chapterIDs.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let rows = try await corpus.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT verse.id, verse.chapterID, verse.label, verse.text,
                           book.name || ' ' || chapter.label AS reference
                    FROM verse JOIN chapter ON chapter.id=verse.chapterID JOIN book ON book.id=chapter.bookID
                    WHERE verse.chapterID IN (\(placeholders)) ORDER BY verse.ordinal
                    """, arguments: StatementArguments(chunk)).map {
                        (chapterID: $0["chapterID"] as String, reference: $0["reference"] as String,
                         verse: Verse(id: $0["id"], label: $0["label"], text: $0["text"]))
                    }
            }
            for row in rows {
                let chapterID = row.chapterID
                if documents[chapterID] == nil { documents[chapterID] = Chapter(reference: row.reference) }
                let verse = row.verse
                let index = documents[chapterID]?.verses.count ?? 0
                documents[chapterID]?.index[verse.id] = index
                documents[chapterID]?.verses.append(verse)
            }
        }
        var items: [SavedItem] = []
        let byVerse = Dictionary(uniqueKeysWithValues: snapshot.highlights.map { ($0.verseID, $0) })
        var resolved = Set<String>()
        for chapterID in chapterIDs {
            try Task.checkCancellation()
            guard let doc = documents[chapterID] else { continue }
            var group: [(Verse, HighlightRecord)] = []
            func finishGroup() {
                guard let first = group.first, let last = group.last else { return }
                let reference = "\(doc.reference):\(first.0.label)\(first.0.id == last.0.id ? "" : "–" + last.0.label)"
                items.append(SavedItem(id: first.1.id, chapterID: chapterID, verseID: first.0.id,
                                       reference: reference, text: group.map { $0.0.text }.joined(separator: " "),
                                       color: first.1.color, bookmark: false, updated: group.map { $0.1.updated }.max() ?? 0,
                                       verseOrder: doc.index[first.0.id],
                                       records: SavedRecords(highlights: group.map { $0.1 })))
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
            items.append(SavedItem(id: h.id, chapterID: ScriptureID.chapter(containing: h.verseID),
                                   verseID: h.verseID, reference: h.verseID, text: String(localized: "This saved reference is unavailable in the installed edition."),
                                   color: h.color, bookmark: false, updated: h.updated, unavailable: true, records: SavedRecords(highlights: [h])))
        }
        for b in snapshot.bookmarks {
            let chapterID = ScriptureID.chapter(containing: b.startID)
            let doc = documents[chapterID]
            let verses = doc?.verses ?? []
            let start = doc?.index[b.startID]
            let end = doc?.index[b.endID]
            let passage = if let start, let end, start <= end { Array(verses[start...end]) } else { [Verse]() }
            let reference = if let first = passage.first, let last = passage.last { "\(doc!.reference):\(first.label)\(first.id == last.id ? "" : "–" + last.label)" } else { b.startID }
            items.append(SavedItem(id: b.id, chapterID: chapterID, verseID: b.startID, reference: reference,
                                   text: passage.isEmpty ? String(localized: "This saved reference is unavailable in the installed edition.") : passage.map(\.text).joined(separator: " "),
                                   color: nil, bookmark: true, updated: b.updated, unavailable: passage.isEmpty, verseOrder: start, records: SavedRecords(bookmarks: [b])))
        }
        for record in exactRecords {
            guard let first = record.passage.parts.first else { continue }
            let doc = documents[record.passage.chapterID]
            let verses = doc?.verses ?? []
            let parts = record.passage.parts.compactMap { part -> SavedTextPart? in
                guard let index = doc?.index[part.verseID] else { return nil }
                let text = verses[index].text
                guard let range = part.resolvedRange(in: text) else { return nil }
                return SavedTextPart(verseID: part.verseID, text: text, range: range)
            }
            let unavailable = parts.count != record.passage.parts.count
            var resolved = record.passage
            resolved.parts = parts
            items.append(SavedItem(id: record.id, chapterID: record.passage.chapterID, verseID: first.verseID,
                reference: String(localized: "\(record.passage.reference) (excerpt)"), text: record.passage.text,
                color: record.color, bookmark: record.isBookmark, updated: record.updated, passage: unavailable ? nil : resolved, unavailable: unavailable,
                verseOrder: doc?.index[first.verseID], records: SavedRecords(exact: [record])))
        }
        return items
    }
}
