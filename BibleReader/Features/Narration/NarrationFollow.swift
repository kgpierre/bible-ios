import CoreGraphics
import Foundation
import Observation

/// Follow-along decisions (0023, plan §6.3–6.4), kept apart from UIKit so they can be tested.
enum NarrationFollow {
    /// The scrolling reader's new offset that keeps the spoken line readable, or nil to stay put.
    /// `top` and `bottom` bound the text visible between the floating chrome, in content coordinates.
    /// A line above the band or below 70% of it moves to about 30% from the top.
    static func scrollOffset(for line: CGRect, top: CGFloat, bottom: CGFloat, currentOffset: CGFloat, maxOffset: CGFloat) -> CGFloat? {
        let height = bottom - top
        guard height > 0, !line.isNull, !line.isEmpty else { return nil }
        guard line.minY < top || line.maxY > top + height * 0.7 else { return nil }
        let target = min(max(0, currentOffset + line.minY - (top + height * 0.3)), max(0, maxOffset))
        return abs(target - currentOffset) < 1 ? nil : target
    }

    /// After the reader scrolls away, following resumes only once the spoken line is back
    /// within about a screen, so narration never pulls a reader from a passage they chose.
    static func isNear(_ line: CGRect, top: CGFloat, bottom: CGFloat) -> Bool {
        let height = bottom - top
        return line.maxY >= top - height && line.minY <= bottom + height
    }

    enum SpreadAction: Equatable {
        /// The spoken words are on the spread on screen.
        case stay
        /// They reached the next spread: turn once.
        case turnForward
        /// The reader flipped elsewhere: never jump.
        case away
    }

    /// Two Pages: pages are counted from 0 and a spread begins on an even (left) page.
    static func spreadAction(focusPage: Int, displayedLeftPage: Int) -> SpreadAction {
        switch focusPage - displayedLeftPage {
        case 0, 1: .stay
        case 2, 3: .turnForward
        default: .away
        }
    }

    /// Where to locate the spoken words: the word, else the segment, else the announced verse.
    /// A chapter announcement has no location.
    static func location(of focus: NarrationFocus, in map: ChapterTextMap) -> NSRange? {
        if let word = focus.wordRange, word.length > 0 { return word }
        if let segment = focus.segmentRange { return segment }
        return focus.verseID.flatMap { id in map.entries.first { $0.verse.id == id }?.range }
    }
}

/// Delivers Read Aloud focus changes to a reader coordinator without routing them through SwiftUI
/// updates, so word-by-word progress never reconfigures the reader.
@MainActor final class NarrationObserver {
    private(set) var focus: NarrationFocus?
    private weak var narration: NarrationController?
    private var task: Task<Void, Never>?
    var onChange: ((NarrationFocus?) -> Void)?

    func observe(_ narration: NarrationController?) {
        guard narration !== self.narration else { return }
        self.narration = narration
        task?.cancel()
        focus = narration?.focus
        guard let narration else { return }
        task = Task { [weak self] in
            for await focus in Observations({ @MainActor in narration.focus }) {
                guard let self, !Task.isCancelled else { return }
                guard focus != self.focus else { continue }
                self.focus = focus
                self.onChange?(focus)
            }
        }
    }

    /// "Read Aloud from Here" and the VoiceOver verse action, when Read Aloud is available.
    var readAloud: ((String, VerseAnchor) -> Void)? {
        guard narration != nil else { return nil }
        return { [weak self] chapterID, anchor in self?.narration?.play(from: anchor, in: chapterID) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        narration = nil
    }
}
