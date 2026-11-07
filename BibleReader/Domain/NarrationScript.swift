import Foundation

/// Options that change which metadata Read Aloud speaks. Scripture segments never depend on them.
struct NarrationScriptOptions: Sendable, Equatable {
    var announcesChapter = true
    var announcesVerseNumbers = false
}

/// The ordered speech segments for one chapter (0023). Verse, heading, and trailing segments speak
/// the corpus text exactly, minus only the approved speech-only omissions; announcements are separate
/// metadata segments with no display range.
struct NarrationScript: Sendable, Equatable {
    struct Segment: Sendable, Equatable, Identifiable {
        enum Kind: Sendable, Equatable { case chapterAnnouncement, verseAnnouncement, heading, verse, trailing }
        /// Order within the chapter.
        let id: Int
        let kind: Kind
        /// The verse for verse and verse-announcement segments, and the following verse for a heading.
        let verseID: String?
        /// The range in `ChapterTextMap.text`; nil for announcements.
        let displayRange: NSRange?
        let speech: String
        /// Removed display sub-ranges, relative to `displayRange`, in ascending order.
        let omissions: [NSRange]
        private let display: String

        fileprivate init(id: Int, kind: Kind, verseID: String?, location: Int?, display: String) {
            self.id = id
            self.kind = kind
            self.verseID = verseID
            self.display = display
            let omissions: [NSRange]
            switch kind {
            case .verse: omissions = NarrationOmission.leadingPilcrow(in: display)
            case .heading: omissions = NarrationOmission.leadingHebrewLetter(in: display)
            case .trailing, .chapterAnnouncement, .verseAnnouncement: omissions = []
            }
            self.omissions = omissions
            let remaining = NSMutableString(string: display)
            for omission in omissions.reversed() { remaining.deleteCharacters(in: omission) }
            speech = remaining as String
            displayRange = location.map { NSRange(location: $0, length: display.utf16.count) }
        }

        /// Maps a range the synthesizer reports in `speech` to the chapter text, adding back omitted
        /// characters and widening to composed-character boundaries.
        func displayRange(forSpoken range: NSRange) -> NSRange? {
            guard let displayRange, range.location != NSNotFound else { return nil }
            let length = speech.utf16.count
            let lower = min(max(0, range.location), length)
            let upper = min(max(lower, NSMaxRange(range)), length)
            let string = display as NSString
            var start = displayOffset(forSpoken: lower, isEnd: false)
            var end = displayOffset(forSpoken: upper, isEnd: true)
            if start < string.length { start = string.rangeOfComposedCharacterSequence(at: start).location }
            if end > start, end < string.length {
                let composed = string.rangeOfComposedCharacterSequence(at: end)
                if composed.location < end { end = NSMaxRange(composed) }
            }
            return NSRange(location: displayRange.location + start, length: max(0, end - start))
        }

        /// The speech offset for a display offset relative to `displayRange`. An offset inside an
        /// omission moves to where speech resumes.
        func spokenOffset(forDisplay offset: Int) -> Int {
            let clamped = min(max(0, offset), display.utf16.count)
            var removed = 0
            for omission in omissions where omission.location < clamped {
                removed += min(omission.length, clamped - omission.location)
            }
            return clamped - removed
        }

        private func displayOffset(forSpoken offset: Int, isEnd: Bool) -> Int {
            var result = offset
            for omission in omissions {
                // A start at an omission boundary skips past it; an end at that boundary stays before it.
                guard isEnd ? omission.location < result : omission.location <= result else { break }
                result += omission.length
            }
            return result
        }
    }

    let chapterID: String
    let segments: [Segment]

    /// Walks the document in the same order and UTF-16 arithmetic as `ChapterTextMap`.
    /// - Parameter bookChapterCount: chapters in the document's book, for the announcement wording.
    init(document: ChapterDocument, options: NarrationScriptOptions = .init(), bookChapterCount: Int) {
        var segments: [Segment] = []
        var location = 0
        func append(_ kind: Segment.Kind, verseID: String?, text: String, displayed: Bool) {
            segments.append(Segment(id: segments.count, kind: kind, verseID: verseID, location: displayed ? location : nil, display: text))
            if displayed { location += text.utf16.count + 1 }
        }
        if options.announcesChapter {
            append(.chapterAnnouncement, verseID: nil, text: NarrationAnnouncement.chapter(
                bookID: document.bookID, bookName: document.bookName, label: document.label, bookChapterCount: bookChapterCount), displayed: false)
        }
        for verse in document.verses {
            for heading in verse.headings { append(.heading, verseID: verse.id, text: heading, displayed: true) }
            if options.announcesVerseNumbers {
                append(.verseAnnouncement, verseID: verse.id, text: NarrationAnnouncement.verse(label: verse.label), displayed: false)
            }
            append(.verse, verseID: verse.id, text: verse.text, displayed: true)
        }
        for block in document.trailingBlocks ?? [] { append(.trailing, verseID: nil, text: block.text, displayed: true) }
        chapterID = document.id
        self.segments = segments
    }

    /// Where Read Aloud from Here starts. A verse-start anchor begins with that verse's headings and
    /// announcement; a later offset begins at the start of the word containing it.
    func segmentIndex(startingAt anchor: VerseAnchor) -> (index: Int, speechOffset: Int)? {
        guard let index = segments.firstIndex(where: { $0.kind == .verse && $0.verseID == anchor.verseID }) else { return nil }
        let segment = segments[index]
        let offset = segment.spokenOffset(forDisplay: anchor.utf16Offset)
        guard offset > 0 else {
            let first = segments[..<index].lastIndex { $0.verseID != anchor.verseID }.map { $0 + 1 } ?? 0
            return (first, 0)
        }
        let speech = segment.speech as NSString
        var start = min(offset, speech.length)
        while start > 0, let scalar = UnicodeScalar(speech.character(at: start - 1)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start -= 1
        }
        return (index, start)
    }
}

/// The speech-only omissions approved in 0023. Each returns ranges relative to the given text.
enum NarrationOmission {
    /// A leading paragraph sign and the single space after it.
    static func leadingPilcrow(in text: String) -> [NSRange] {
        let string = text as NSString
        guard string.length > 0, string.character(at: 0) == 0x00B6 else { return [] }
        let length = string.length > 1 && string.character(at: 1) == 0x20 ? 2 : 1
        return [NSRange(location: 0, length: length)]
    }

    /// A leading Hebrew letter (Psalm 119 acrostic headings) and the single space after it. The
    /// transliteration that follows is still spoken, so the heading is never silenced entirely.
    static func leadingHebrewLetter(in text: String) -> [NSRange] {
        let string = text as NSString
        var end = 0
        while end < string.length, (0x05D0...0x05EA).contains(string.character(at: end)) { end += 1 }
        guard end > 0, end < string.length, string.character(at: end) == 0x20, end + 1 < string.length else { return [] }
        return [NSRange(location: 0, length: end + 1)]
    }
}

/// Spoken metadata wording (0023). These strings are not Scripture.
enum NarrationAnnouncement {
    /// "John, Chapter 3"; "Psalm 23"; the book name alone for a single-chapter book.
    static func chapter(bookID: String, bookName: String, label: String, bookChapterCount: Int) -> String {
        if bookChapterCount == 1 { return bookName }
        if bookID == "PSA" { return String(localized: "Psalm \(label)", comment: "Spoken Read Aloud announcement for one psalm") }
        return String(localized: "\(bookName), Chapter \(label)", comment: "Spoken Read Aloud chapter announcement")
    }

    /// "Verse 16", or "Verses 3 to 4" for a bridged label, which stays one verse.
    static func verse(label: String) -> String {
        let parts = label.split(whereSeparator: { $0 == "-" || $0 == "–" }).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return String(localized: "Verses \(parts[0]) to \(parts[1])", comment: "Spoken Read Aloud announcement for a bridged verse")
        }
        return String(localized: "Verse \(label)", comment: "Spoken Read Aloud verse number announcement")
    }
}
