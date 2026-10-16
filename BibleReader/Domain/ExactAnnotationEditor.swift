import Foundation

/// The same deterministic edit is used for a pending preview and the durable transaction.
/// Inputs are restricted to touched verses; retained fragments and legacy records stay intact.
enum ExactAnnotationEditor {
    static func change(passage: ExactPassage, document: ChapterDocument, before: [ExactAnnotation],
                       legacyBefore: AnnotationSnapshot, color: HighlightColor?, bookmarkAction: Bool?,
                       edition: String, revision: String, now: Double, newID: String) throws -> ExactAnnotationChange {
        let ids = document.verses.map(\.id)
        guard passage.chapterID == document.id, let first = passage.verseIDs.first,
              let start = ids.firstIndex(of: first), start + passage.parts.count <= ids.count,
              Array(ids[start..<start + passage.parts.count]) == passage.verseIDs else { throw StorageIssue.invalidPassage }
        let texts = Dictionary(uniqueKeysWithValues: document.verses.map { ($0.id, $0.text) })
        // Labels only the verses that hold parts: a record split around a removed middle verse
        // reads "John 3:1, 3", never "John 3:1–3". Contiguous verses still collapse to a range.
        func reference(for parts: [SavedTextPart]) -> String {
            let selected = Set(parts.map(\.verseID))
            var runs: [(first: ChapterDocument.Verse, last: ChapterDocument.Verse)] = []
            var previous: Int?
            for (index, verse) in document.verses.enumerated() where selected.contains(verse.id) {
                if let previous, previous == index - 1, !runs.isEmpty { runs[runs.count - 1].last = verse }
                else { runs.append((verse, verse)) }
                previous = index
            }
            guard !runs.isEmpty else { return document.reference }
            let labels = runs.map { $0.first.id == $0.last.id ? $0.first.label : $0.first.label + "–" + $0.last.label }
            return document.reference + ":" + labels.joined(separator: ", ")
        }
        guard passage.parts.allSatisfy({ part in
            guard let text = texts[part.verseID], let range = part.resolvedRange(in: text) else { return false }
            return range.location == part.start && NSMaxRange(range) == part.end
        }) else { throw StorageIssue.invalidPassage }
        var passage = passage
        passage.reference = reference(for: passage.parts)
        var records = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        var legacyAfter = legacyBefore
        func put(_ record: ExactAnnotation) { records[record.id] = record }
        if let bookmarkAction {
            let matches = before.filter { $0.isBookmark && $0.passage.parts == passage.parts }
            let coversWholeVerses = passage.parts.allSatisfy { $0.start == 0 && $0.end == texts[$0.verseID]?.utf16.count }
            let legacyMatches = coversWholeVerses ? legacyBefore.bookmarks : []
            if bookmarkAction, matches.isEmpty, legacyMatches.isEmpty {
                put(ExactAnnotation(id: newID, editionID: edition, revision: revision,
                    passage: passage, color: nil, created: now, updated: now))
            } else if !bookmarkAction {
                for match in matches { records.removeValue(forKey: match.id) }
                legacyAfter.bookmarks.removeAll { record in legacyMatches.contains { $0.id == record.id } }
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
                legacyAfter.highlights.removeAll { $0.id == legacy.id }
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
                records.removeValue(forKey: record.id)
                if !remaining.isEmpty {
                    record.passage.parts = remaining
                    record.passage.reference = reference(for: remaining)
                    record.updated = now
                    put(record)
                }
            }
            if let color {
                put(ExactAnnotation(id: newID, editionID: edition, revision: revision,
                    passage: passage, color: color, created: now, updated: now))
            }
        }
        return ExactAnnotationChange(verseIDs: passage.verseIDs, before: before,
            after: records.values.sorted { $0.id < $1.id }, legacyBefore: legacyBefore, legacyAfter: legacyAfter)
    }
}
