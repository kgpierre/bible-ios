import Foundation
import GRDB

/// Owns isolated database access. The bundle is never copied into writable user storage.
actor BibleStore {
    let editionID: String
    let revision: String
    private let corpus: DatabaseQueue
    private let user: DatabaseQueue
    private let userURL: URL
    private var cachedReferenceParser: ReferenceParser?

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
        try corpus.read { db in
            guard let payload = try String.fetchOne(db, sql: "SELECT payload FROM chapter_document WHERE chapterID=?", arguments: [id]) else { throw StorageIssue.invalidPassage }
            return try JSONDecoder().decode(ChapterDocument.self, from: Data(payload.utf8))
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
        let document = try chapter(chapterID)
        if let anchor, !document.verses.contains(where: { $0.id == anchor.text.verseID }) { throw StorageIssue.invalidPassage }
        let payload = try JSONEncoder().encode(StoredPosition(chapterID: chapterID, anchor: anchor, revision: revision, updated: Date().timeIntervalSince1970))
        let edition = editionID
        try user.write { db in
            try db.execute(sql: "INSERT INTO reading_position VALUES(?,?) ON CONFLICT(editionID) DO UPDATE SET payload=excluded.payload", arguments: [edition, payload])
        }
    }

    func annotations() throws -> AnnotationSnapshot {
        let edition = editionID
        return try user.read { db in try Self.snapshot(db, edition: edition) }
    }

    private static func snapshot(_ db: Database, edition: String) throws -> AnnotationSnapshot {
        let highlights = try Row.fetchAll(db, sql: "SELECT * FROM highlight WHERE editionID=? ORDER BY verseID", arguments: [edition]).map { row -> HighlightRecord in
            guard let color = HighlightColor(rawValue: row["color"]) else { throw StorageIssue.incompatibleUserStore }
            return HighlightRecord(id: row["id"], verseID: row["verseID"], color: color, operationID: row["operationID"], created: row["created"], updated: row["updated"])
        }
        let bookmarks = try Row.fetchAll(db, sql: "SELECT * FROM bookmark WHERE editionID=? ORDER BY id", arguments: [edition]).map {
            BookmarkRecord(id: $0["id"], startID: $0["startID"], endID: $0["endID"], created: $0["created"], updated: $0["updated"])
        }
        return AnnotationSnapshot(highlights: highlights, bookmarks: bookmarks)
    }

    private static func scoped(_ snapshot: AnnotationSnapshot, ids: [String]) -> AnnotationSnapshot {
        let set = Set(ids)
        return AnnotationSnapshot(highlights: snapshot.highlights.filter { set.contains($0.verseID) },
                                  bookmarks: snapshot.bookmarks.filter { $0.startID == ids.first && $0.endID == ids.last })
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
        return try user.write { db in
            let before = Self.scoped(try Self.snapshot(db, edition: edition), ids: verseIDs)
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
            let after = Self.scoped(try Self.snapshot(db, edition: edition), ids: verseIDs)
            return AnnotationChange(verseIDs: verseIDs, before: before, after: after)
        }
    }

    func undo(_ change: AnnotationChange) throws {
        let edition = editionID
        try user.write { db in
            let current = Self.scoped(try Self.snapshot(db, edition: edition), ids: change.verseIDs)
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
    }

    func exactAnnotations() throws -> [ExactAnnotation] {
        let edition = editionID
        return try user.read { try Self.exactSnapshot($0, edition: edition) }
    }

    private static func exactSnapshot(_ db: Database, edition: String) throws -> [ExactAnnotation] {
        try Data.fetchAll(db, sql: "SELECT payload FROM exact_annotation WHERE editionID=? ORDER BY id", arguments: [edition])
            .map { try JSONDecoder().decode(ExactAnnotation.self, from: $0) }
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
        try validate(passage.verseIDs)
        let document = try chapter(passage.chapterID)
        let texts = Dictionary(uniqueKeysWithValues: document.verses.map { ($0.id, $0.text) })
        func reference(for parts: [SavedTextPart]) -> String {
            let selected = Set(parts.map(\.verseID))
            let verses = document.verses.filter { selected.contains($0.id) }
            guard let first = verses.first, let last = verses.last else { return document.reference }
            return document.reference + ":" + first.label + (first.id == last.id ? "" : "–" + last.label)
        }
        guard passage.parts.allSatisfy({ part in
            guard let text = texts[part.verseID], let range = part.resolvedRange(in: text) else { return false }
            return range.location == part.start && NSMaxRange(range) == part.end
        }) else { throw StorageIssue.invalidPassage }
        var passage = passage
        passage.reference = reference(for: passage.parts)
        let edition = editionID, revision = revision, now = Date().timeIntervalSince1970
        return try user.write { db in
            let before = Self.exactScope(try Self.exactSnapshot(db, edition: edition), ids: passage.verseIDs)
            let legacyBefore = Self.scoped(try Self.snapshot(db, edition: edition), ids: passage.verseIDs)
            if let bookmarkAction {
                let matches = before.filter { $0.isBookmark && $0.passage.parts == passage.parts }
                let coversWholeVerses = passage.parts.allSatisfy { $0.start == 0 && $0.end == texts[$0.verseID]?.utf16.count }
                let legacyMatches = coversWholeVerses ? legacyBefore.bookmarks : []
                if bookmarkAction, matches.isEmpty, legacyMatches.isEmpty {
                    try Self.putExact(ExactAnnotation(id: UUID().uuidString, editionID: edition, revision: revision,
                        passage: passage, color: nil, created: now, updated: now), db: db)
                } else if !bookmarkAction {
                    for match in matches { try db.execute(sql: "DELETE FROM exact_annotation WHERE id=?", arguments: [match.id]) }
                    for match in legacyMatches { try db.execute(sql: "DELETE FROM bookmark WHERE id=?", arguments: [match.id]) }
                }
            } else {
                var old = before.filter { !$0.isBookmark }
                // Convert only touched legacy highlights, transactionally; all other old data remains intact.
                for legacy in legacyBefore.highlights {
                    guard let text = texts[legacy.verseID], let part = SavedTextPart(verseID: legacy.verseID, text: text,
                        range: NSRange(location: 0, length: text.utf16.count)) else { throw StorageIssue.invalidPassage }
                    old.append(ExactAnnotation(id: legacy.id, editionID: edition, revision: revision,
                        passage: ExactPassage(chapterID: passage.chapterID, reference: reference(for: [part]), parts: [part]),
                        color: legacy.color, created: legacy.created, updated: legacy.updated))
                    try db.execute(sql: "DELETE FROM highlight WHERE id=?", arguments: [legacy.id])
                }
                for var record in old {
                    var remaining: [SavedTextPart] = []
                    for part in record.passage.parts {
                        guard let cut = passage.parts.first(where: { $0.verseID == part.verseID }),
                              let text = texts[part.verseID], let range = part.resolvedRange(in: text) else {
                            remaining.append(part); continue
                        }
                        let overlap = NSIntersectionRange(range, NSRange(location: cut.start, length: cut.end - cut.start))
                        guard overlap.length > 0 else { remaining.append(part); continue }
                        for span in [NSRange(location: range.location, length: overlap.location - range.location),
                                     NSRange(location: NSMaxRange(overlap), length: NSMaxRange(range) - NSMaxRange(overlap))] {
                            if let retained = SavedTextPart(verseID: part.verseID, text: text, range: span) { remaining.append(retained) }
                        }
                    }
                    try db.execute(sql: "DELETE FROM exact_annotation WHERE id=?", arguments: [record.id])
                    if !remaining.isEmpty {
                        record.passage.parts = remaining
                        record.passage.reference = reference(for: remaining)
                        record.updated = now
                        try Self.putExact(record, db: db)
                    }
                }
                if let color {
                    try Self.putExact(ExactAnnotation(id: UUID().uuidString, editionID: edition, revision: revision,
                        passage: passage, color: color, created: now, updated: now), db: db)
                }
            }
            return ExactAnnotationChange(verseIDs: passage.verseIDs, before: before,
                after: Self.exactScope(try Self.exactSnapshot(db, edition: edition), ids: passage.verseIDs, recordIDs: Set(before.map(\.id))),
                legacyBefore: legacyBefore, legacyAfter: Self.scoped(try Self.snapshot(db, edition: edition), ids: passage.verseIDs))
        }
    }

    func undoExact(_ change: ExactAnnotationChange) throws {
        let edition = editionID
        try user.write { db in
            let current = Self.exactScope(try Self.exactSnapshot(db, edition: edition), ids: change.verseIDs,
                                          recordIDs: Set((change.before + change.after).map(\.id)))
            let legacy = Self.scoped(try Self.snapshot(db, edition: edition), ids: change.verseIDs)
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
    }

    func savedItems() throws -> [SavedItem] {
        let snapshot = try annotations()
        let exactRecords = try exactAnnotations()
        // Fetch chapter payloads in a batch, then resolve all saved passages in memory.
        let verseIDs = snapshot.highlights.map(\.verseID) + snapshot.bookmarks.flatMap { [$0.startID,$0.endID] }
        let chapterIDs = Array(Set(verseIDs.map { $0.split(separator: ":").dropLast().joined(separator: ":") } + exactRecords.map { $0.passage.chapterID })).sorted()
        var documents: [String: ChapterDocument] = [:]
        for start in stride(from: 0, to: chapterIDs.count, by: 200) {
            let chunk = Array(chapterIDs[start..<min(start+200,chapterIDs.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let payloads = try corpus.read { db in
                try String.fetchAll(db, sql: "SELECT payload FROM chapter_document WHERE chapterID IN (\(placeholders))", arguments: StatementArguments(chunk))
            }
            for payload in payloads {
                let doc = try JSONDecoder().decode(ChapterDocument.self, from: Data(payload.utf8))
                documents[doc.id] = doc
            }
        }
        var items: [SavedItem] = []
        let byVerse = Dictionary(uniqueKeysWithValues: snapshot.highlights.map { ($0.verseID, $0) })
        var resolved = Set<String>()
        for chapterID in chapterIDs {
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
        return items.sorted { $0.updated == $1.updated ? $0.id < $1.id : $0.updated > $1.updated }
    }
}
