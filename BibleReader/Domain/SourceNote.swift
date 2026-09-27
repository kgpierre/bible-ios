import Foundation

/// A marginal note from the source edition ("1.4 the light from…: Heb. between the light…").
/// Notes are editorial source material: never verse text, copied text, or search content.
struct SourceNote: Equatable, Identifiable, Sendable {
    let id: String
    /// The source's lead words for the note, when present ("the light from…").
    let catchphrase: String?
    let text: String

    init(raw: String, id: String) {
        self.id = id
        // Every note in the pinned corpus has a "chapter.verse catchphrase: text" shape. Anything
        // else is shown whole rather than guessed at.
        if let match = raw.wholeMatch(of: #/(\d+\.\d+(?:-\d+)?)\s+(.*?):\s+(.+)/#.dotMatchesNewlines()) {
            let lead = String(match.2).trimmingCharacters(in: .whitespaces)
            catchphrase = lead.isEmpty ? nil : lead
            text = String(match.3)
        } else {
            catchphrase = nil
            text = raw
        }
    }
}

struct SourceNoteGroup: Equatable, Identifiable, Sendable {
    let id: String
    let verseLabel: String
    let notes: [SourceNote]
}

/// Notes shown together: one verse from its marker, or the whole chapter from More.
struct SourceNotesRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let title: String
    let groups: [SourceNoteGroup]
    let showsVerseLabels: Bool

    static func verse(_ verse: ChapterDocument.Verse, in document: ChapterDocument) -> SourceNotesRequest {
        SourceNotesRequest(title: "\(document.reference):\(verse.label)", groups: [group(verse)], showsVerseLabels: false)
    }

    static func chapter(_ document: ChapterDocument) -> SourceNotesRequest {
        SourceNotesRequest(title: document.reference, groups: document.verses.filter { !$0.notes.isEmpty }.map(group),
                           showsVerseLabels: true)
    }

    private static func group(_ verse: ChapterDocument.Verse) -> SourceNoteGroup {
        SourceNoteGroup(id: verse.id, verseLabel: verse.label,
                        notes: verse.notes.enumerated().map { SourceNote(raw: $0.element, id: "\(verse.id)#\($0.offset)") })
    }
}
