import Foundation
import Observation
import UIKit

/// What is being spoken, as semantic ranges in the narrated chapter's `ChapterTextMap.text`.
struct NarrationFocus: Equatable, Sendable {
    let chapterID: String
    let verseID: String?
    let kind: NarrationScript.Segment.Kind
    let segmentRange: NSRange?
    let wordRange: NSRange?
    let revision: Int
}

/// Corpus access and reader hooks, injected so the controller never touches the store directly.
struct NarrationSource {
    /// Bundled corpus only; never the user database.
    let chapter: @MainActor (String) async throws -> ChapterDocument
    /// Catalog order; nil at either end of the Bible.
    let adjacentChapterID: @MainActor (String, Int) -> String?
    let bookChapterCount: @MainActor (String) -> Int
    /// Where narration stopped, routed through the reader's single position writer.
    let savePosition: @MainActor (String, VerseAnchor) -> Void
    /// Narration entered `to` after `from`; the reader follows if it was showing `from`.
    let followChapter: @MainActor (_ from: String, _ to: String) -> Void
    /// False while the app is in the background, when progress is saved periodically.
    var isAppActive: @MainActor () -> Bool = { true }
}

/// Pauses narration after a while, or at the end of the chapter (plan §8.3). Session-only.
enum NarrationSleepTimer: Hashable, Sendable {
    case off, endOfChapter, minutes(Int)
    static let choices: [Self] = [.off, .endOfChapter, .minutes(15), .minutes(30), .minutes(45), .minutes(60)]
}

/// Read Aloud playback (0023): the narration cursor, queueing, chapter continuation, and endpoints.
/// The cursor is independent of the reader, so narration continues while the user browses.
@MainActor @Observable
final class NarrationController {
    enum Status: Equatable {
        case idle, preparing, playing, paused(PauseReason), finished(EndReason), unavailable(String), failed(String)
        var isActive: Bool {
            switch self {
            case .preparing, .playing, .paused: true
            default: false
            }
        }
    }
    enum PauseReason: Equatable {
        case user
        /// A call, Siri, an alarm, or another app's audio; resumes when the system recommends it.
        case interruption
        /// Headphones or a car disconnected; never resumes by itself.
        case routeLost
        case sleepTimer
        /// The media server restarted; resuming starts from the last spoken word.
        case mediaReset
    }
    enum EndReason: Equatable { case endOfChapter, endOfBible }

    private(set) var status: Status = .idle { didSet { if status != oldValue { publishNowPlaying() } } }
    private(set) var focus: NarrationFocus?
    private(set) var chapterID: String? { didSet { if chapterID != oldValue { publishNowPlaying() } } }
    private(set) var sleepTimer: NarrationSleepTimer = .off
    /// When a minutes timer will pause narration, for display.
    private(set) var sleepDeadline: Date?
    /// The spoken verse, for example "John 3:16", or the chapter during an announcement.
    private(set) var reference: String?
    /// A one-time message, such as a missing chosen voice.
    var notice: String?

    let preferences: NarrationPreferences
    let voices: NarrationVoiceCatalog
    @ObservationIgnored private let source: NarrationSource
    @ObservationIgnored private let synthesizer: any SpeechSynthesizing
    @ObservationIgnored private let audio: any NarrationAudioSession
    @ObservationIgnored private let nowPlaying: any NarrationNowPlaying
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    private struct Loaded {
        let document: ChapterDocument
        let script: NarrationScript
    }
    private struct Cursor: Equatable {
        let chapterID: String
        let segment: Int
        /// Speech offset to start from within the segment.
        var offset = 0
    }
    @ObservationIgnored private var loaded: [String: Loaded] = [:]
    @ObservationIgnored private var generation = 0
    /// Enqueued and not yet finished, in speaking order.
    @ObservationIgnored private var queued: [SpeechToken] = []
    @ObservationIgnored private var baseOffsets: [SpeechToken: Int] = [:]
    @ObservationIgnored private var pending: Cursor?
    @ObservationIgnored private var awaitingChapter: String?
    @ObservationIgnored private var endReason: EndReason?
    @ObservationIgnored private var continuationFailure: String?
    @ObservationIgnored private var current: SpeechToken?
    @ObservationIgnored private var lastSpokenOffset = 0
    @ObservationIgnored private var restartOnResume = false
    /// Where to start on resume when pausing stopped the queue instead of pausing speech.
    @ObservationIgnored private var resumeCursor: Cursor?
    @ObservationIgnored private var lastRequest: (anchor: VerseAnchor?, chapterID: String)?
    @ObservationIgnored private var focusRevision = 0
    @ObservationIgnored private var notifiedFallback = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// A minutes timer expired; pause at the next segment boundary.
    @ObservationIgnored private var sleepDue = false
    /// Where an end-of-chapter sleep stop continues from on resume.
    @ObservationIgnored private var sleepStoppedBefore: String?
    @ObservationIgnored private var lastBackgroundSave: ContinuousClock.Instant?
    /// A verse that runs on after a minutes timer expires is paused at a word boundary after this.
    private let sleepGrace: Duration = .seconds(30)
    /// Current segment plus two ahead keeps verse gaps short without a long queue to cancel (S3).
    private let queueDepth = 3

    init(source: NarrationSource, synthesizer: any SpeechSynthesizing, audio: any NarrationAudioSession,
         nowPlaying: any NarrationNowPlaying, preferences: NarrationPreferences, voices: NarrationVoiceCatalog,
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.source = source
        self.synthesizer = synthesizer
        self.audio = audio
        self.nowPlaying = nowPlaying
        self.sleep = sleep
        self.preferences = preferences
        self.voices = voices
        Task { [weak self, events = synthesizer.events] in
            for await event in events { self?.handle(event) }
        }
        Task { [weak self, events = audio.events] in
            for await event in events { self?.handle(event) }
        }
        Task { [weak self, commands = nowPlaying.commands] in
            for await command in commands { self?.handle(command) }
        }
    }

    var unavailableReason: String? {
        voices.voices.isEmpty
            ? String(localized: "No English speech voice is installed. Add one in Settings → Accessibility → Spoken Content.") : nil
    }

    // MARK: Commands

    /// Starts at a verse, or at the chapter's beginning (with its announcement) when `anchor` is nil.
    func play(from anchor: VerseAnchor?, in chapterID: String) {
        if let reason = unavailableReason { status = .unavailable(reason); return }
        let generation = restart()
        status = .preparing
        self.chapterID = chapterID
        lastRequest = (anchor, chapterID)
        Task {
            do {
                let loaded = try await load(chapterID)
                guard generation == self.generation else { return }
                let start = anchor.flatMap { loaded.script.segmentIndex(startingAt: $0) } ?? (0, 0)
                begin(at: Cursor(chapterID: chapterID, segment: start.index, offset: start.speechOffset))
            } catch {
                guard generation == self.generation else { return }
                fail(String(localized: "This chapter could not be read aloud. Your reading position and saved data have been kept."))
            }
        }
    }

    func togglePlayPause() {
        switch status {
        case .playing, .preparing: pause(.user)
        case .paused: resume()
        default: break
        }
    }

    func pause(_ reason: PauseReason) {
        guard status == .playing || status == .preparing else { return }
        savePosition()
        if !synthesizer.pause() {
            // Nothing is speaking yet (or the synthesizer refused): hold the start point and
            // cancel the queue, so queued speech cannot begin while paused.
            let cursor = currentCursor()
            _ = restart()
            resumeCursor = cursor
        }
        status = .paused(reason)
    }

    func resume() {
        guard case .paused = status else { return }
        // An interruption or route change may have deactivated the session.
        if resumeCursor == nil, !restartOnResume, current != nil || !queued.isEmpty {
            do { try audio.activate() } catch { return }
        }
        if let cursor = resumeCursor ?? (restartOnResume ? currentCursor() : nil) {
            _ = restart()
            status = .preparing
            begin(at: cursor)
        } else if current != nil || !queued.isEmpty, synthesizer.resume() {
            status = .playing
        } else if let currentCursor = currentCursor() {
            _ = restart()
            status = .preparing
            begin(at: currentCursor)
        } else if let lastRequest {
            play(from: lastRequest.anchor, in: lastRequest.chapterID)
        }
    }

    func stop() {
        savePosition()
        _ = restart()
        status = .idle
        clearCursor()
        setSleepTimer(.off)
        audio.deactivate()
    }

    /// The Lock Screen's previous track: restart the chapter, or the previous chapter from its
    /// first verse or announcement. Never before Genesis 1.
    func previousChapterOrRestart() {
        guard let token = current ?? queued.first, let loaded = loaded[token.chapterID] else { skipChapter(by: -1); return }
        let firstVerse = loaded.script.segments.firstIndex { $0.kind == .verse } ?? 0
        if token.segment > firstVerse { play(from: nil, in: token.chapterID) } else { skipChapter(by: -1) }
    }

    func setSleepTimer(_ timer: NarrationSleepTimer) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDue = false
        sleepDeadline = nil
        sleepTimer = timer
        switch timer {
        case .off: break
        case .endOfChapter:
            // Speech already queued past the chapter end is requeued without it.
            if status == .playing, queued.contains(where: { $0.chapterID != current?.chapterID }) || awaitingChapter != nil || pending.map({ $0.chapterID != current?.chapterID }) == true {
                restartFromLastWord()
            }
        case .minutes(let minutes):
            sleepDeadline = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
            sleepTask = Task { [weak self, sleep, sleepGrace] in
                do { try await sleep(.seconds(minutes * 60)) } catch { return }
                guard let self, self.sleepTimer == timer else { return }
                guard self.status == .playing || self.status == .preparing else { self.setSleepTimer(.off); return }
                self.sleepDue = true
                do { try await sleep(sleepGrace) } catch { return }
                guard self.sleepDue, self.sleepTimer == timer else { return }
                self.pause(.sleepTimer)
                self.setSleepTimer(.off)
            }
        }
    }

    /// Moves to the start of an adjacent verse (with its heading). Past the last verse it moves to
    /// the next chapter; before the first verse it restarts that verse.
    func skipVerse(by delta: Int) {
        guard let current = current ?? queued.first, let loaded = loaded[current.chapterID] else { return }
        let verses = loaded.script.segments.filter { $0.kind == .verse }
        let currentVerse = loaded.script.segments[current.segment].verseID
        let position = verses.firstIndex { $0.verseID == currentVerse } ?? (delta > 0 ? -1 : 0)
        let target = position + delta
        if verses.indices.contains(target), let verseID = verses[target].verseID {
            play(from: VerseAnchor(verseID: verseID, utf16Offset: 0), in: current.chapterID)
        } else if delta > 0 {
            skipChapter(by: 1)
        } else if let verseID = verses.first?.verseID {
            play(from: VerseAnchor(verseID: verseID, utf16Offset: 0), in: current.chapterID)
        }
    }

    /// Starts an adjacent chapter. Never wraps; before Genesis 1 it restarts Genesis 1.
    func skipChapter(by delta: Int) {
        guard let chapterID = current?.chapterID ?? chapterID else { return }
        if let target = source.adjacentChapterID(chapterID, delta) { play(from: nil, in: target) }
        else if delta < 0 { play(from: nil, in: chapterID) }
    }

    /// Voice and rate apply only to new utterances, so a change restarts the current segment
    /// from the last spoken word (or on resume, when paused).
    func speechSettingsChanged() {
        switch status {
        case .playing: restartFromLastWord()
        case .paused: restartOnResume = true
        default: break
        }
    }

    // MARK: Queueing

    /// Cancels everything queued and returns the new generation.
    private func restart() -> Int {
        generation += 1
        loadTask?.cancel()
        synthesizer.stop()
        queued = []
        baseOffsets = [:]
        pending = nil
        awaitingChapter = nil
        endReason = nil
        continuationFailure = nil
        current = nil
        restartOnResume = false
        resumeCursor = nil
        sleepStoppedBefore = nil
        return generation
    }

    private func begin(at cursor: Cursor) {
        do { try audio.activate() } catch {
            fail(String(localized: "Read Aloud couldn’t start while another app is using audio. Try again."))
            return
        }
        pending = cursor
        lastSpokenOffset = cursor.offset
        fill()
    }

    private func currentCursor() -> Cursor? {
        guard let token = current ?? queued.first else { return nil }
        return Cursor(chapterID: token.chapterID, segment: token.segment,
                      offset: token == current ? lastSpokenOffset : baseOffsets[token] ?? 0)
    }

    private func restartFromLastWord() {
        guard let cursor = currentCursor() else { return }
        _ = restart()
        status = .preparing
        begin(at: cursor)
    }

    private func fill() {
        while queued.count < queueDepth, let cursor = pending, let loaded = loaded[cursor.chapterID] {
            let segment = loaded.script.segments[cursor.segment]
            let token = SpeechToken(generation: generation, chapterID: cursor.chapterID, segment: cursor.segment)
            let speech = segment.speech as NSString
            let offset = min(cursor.offset, speech.length)
            let resolved = voices.resolve(preferences.voiceID)
            if resolved.isFallback, !notifiedFallback, let voice = resolved.voice {
                notifiedFallback = true
                notice = String(localized: "Your chosen voice isn’t available on this device. Reading with \(voice.name) instead.")
            }
            synthesizer.enqueue(SpeechRequest(
                token: token, text: speech.substring(from: offset), voiceID: resolved.voice?.id, rate: preferences.rate.utteranceRate,
                usesAssistiveSettings: preferences.usesVoiceOverSettings && UIAccessibility.isVoiceOverRunning,
                postDelay: Self.pause(after: segment.kind)))
            queued.append(token)
            baseOffsets[token] = offset
            advance(past: cursor, in: loaded)
        }
    }

    private static func pause(after kind: NarrationScript.Segment.Kind) -> TimeInterval {
        switch kind {
        case .chapterAnnouncement: 0.5
        case .heading, .trailing: 0.3
        case .verseAnnouncement, .verse: 0
        }
    }

    private func advance(past cursor: Cursor, in loaded: Loaded) {
        if cursor.segment + 1 < loaded.script.segments.count {
            pending = Cursor(chapterID: cursor.chapterID, segment: cursor.segment + 1)
            return
        }
        pending = nil
        guard preferences.continuesToNextChapter else { endReason = .endOfChapter; return }
        guard let next = source.adjacentChapterID(cursor.chapterID, 1) else { endReason = .endOfBible; return }
        if sleepTimer == .endOfChapter {
            endReason = .endOfChapter
            sleepStoppedBefore = next
            return
        }
        // Prefetch while the chapter's last segments are still queued.
        awaitingChapter = next
        let generation = generation
        loadTask = Task {
            do {
                _ = try await load(next)
                guard generation == self.generation, awaitingChapter == next else { return }
                awaitingChapter = nil
                pending = Cursor(chapterID: next, segment: 0)
                fill()
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                awaitingChapter = nil
                endReason = .endOfChapter
                continuationFailure = String(localized: "The next chapter could not be read aloud. Your reading position and saved data have been kept.")
                finishIfDrained()
            }
        }
    }

    private func load(_ chapterID: String) async throws -> Loaded {
        if let loaded = loaded[chapterID] { return loaded }
        let document = try await source.chapter(chapterID)
        let script = NarrationScript(document: document, options: preferences.scriptOptions,
                                     bookChapterCount: source.bookChapterCount(document.bookID))
        let result = Loaded(document: document, script: script)
        // Keep only the chapters a queue can reference: the narrated one and the next.
        loaded = loaded.filter { $0.key == current?.chapterID || $0.key == self.chapterID }
        loaded[chapterID] = result
        return result
    }

    // MARK: Events

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .started(let token):
            guard token.generation == generation, let loaded = loaded[token.chapterID] else { return }
            if case .paused = status {
                // The synthesizer accepted a pause but kept going: stop it, and resume from here.
                holdPause(at: Cursor(chapterID: token.chapterID, segment: token.segment, offset: baseOffsets[token] ?? 0))
                return
            }
            let previous = current?.chapterID ?? chapterID
            current = token
            lastSpokenOffset = baseOffsets[token] ?? 0
            chapterID = token.chapterID
            if status == .preparing { status = .playing }
            updateFocus(token, loaded: loaded, spoken: nil)
            saveProgressInBackground(token, loaded: loaded)
            if let previous, previous != token.chapterID {
                self.loaded = self.loaded.filter { $0.key == token.chapterID || $0.key == awaitingChapter || $0.key == pending?.chapterID }
                source.followChapter(previous, token.chapterID)
            }
        case .willSpeak(let token, let range):
            guard token.generation == generation, token == current, let loaded = loaded[token.chapterID] else { return }
            let base = baseOffsets[token] ?? 0
            let spoken = NSRange(location: range.location + base, length: range.length)
            if case .paused = status {
                holdPause(at: Cursor(chapterID: token.chapterID, segment: token.segment, offset: spoken.location))
                return
            }
            lastSpokenOffset = spoken.location
            updateFocus(token, loaded: loaded, spoken: spoken)
        case .finished(let token), .cancelled(let token):
            guard token.generation == generation else { return }
            queued.removeAll { $0 == token }
            baseOffsets[token] = nil
            if case .finished = event, sleepDue, status == .playing {
                pauseAtBoundary(.sleepTimer)
                setSleepTimer(.off)
                return
            }
            if case .finished = event { fill() }
            finishIfDrained()
        }
    }

    private func handle(_ event: NarrationAudioEvent) {
        switch event {
        case .interrupted: pause(.interruption)
        case .interruptionEnded(let shouldResume):
            if shouldResume, status == .paused(.interruption) { resume() }
        case .routeLost: pause(.routeLost)
        case .mediaServicesReset:
            guard status.isActive else { synthesizer.reset(); return }
            savePosition()
            let cursor = currentCursor() ?? resumeCursor
            _ = restart()
            synthesizer.reset()
            resumeCursor = cursor
            status = .paused(.mediaReset)
        }
    }

    private func handle(_ command: NarrationRemoteCommand) {
        switch command {
        case .play: if case .paused = status { resume() }
        case .pause: pause(.user)
        case .togglePlayPause: togglePlayPause()
        case .nextChapter: if status.isActive { skipChapter(by: 1) }
        case .previousChapter: if status.isActive { previousChapterOrRestart() }
        }
    }

    /// Speech reported while paused means the pause didn't take: cancel the queue and keep the spot,
    /// so the status the user sees is the truth and resume starts where speech was.
    private func holdPause(at cursor: Cursor) {
        let reason = status
        _ = restart()
        resumeCursor = cursor
        status = reason
    }

    /// Stops between segments so resuming starts cleanly at the next one.
    private func pauseAtBoundary(_ reason: PauseReason) {
        let next = queued.first.map { Cursor(chapterID: $0.chapterID, segment: $0.segment, offset: baseOffsets[$0] ?? 0) } ?? pending
        guard let next else { pause(reason); return }
        savePosition()
        _ = restart()
        resumeCursor = next
        status = .paused(reason)
    }

    /// While backgrounded the reader isn't scrolling to record progress, so narration saves its
    /// verse at most every five seconds, in case the app is ended before it pauses.
    private func saveProgressInBackground(_ token: SpeechToken, loaded: Loaded) {
        guard !source.isAppActive(), loaded.script.segments[token.segment].kind == .verse else { return }
        let now = ContinuousClock.now
        if let last = lastBackgroundSave, now - last < .seconds(5) { return }
        lastBackgroundSave = now
        savePosition()
    }

    private func publishNowPlaying() {
        guard status.isActive, let chapterID else { nowPlaying.update(nil); return }
        let document = loaded[chapterID]?.document
        let title = document?.reference ?? reference ?? ""
        nowPlaying.update(NarrationNowPlayingInfo(title: title, edition: document?.editionLabel ?? "KJV", isPlaying: status == .playing))
    }

    private func updateFocus(_ token: SpeechToken, loaded: Loaded, spoken: NSRange?) {
        let segment = loaded.script.segments[token.segment]
        let verse = segment.verseID.flatMap { id in loaded.document.verses.first { $0.id == id } }
        switch segment.kind {
        case .chapterAnnouncement, .trailing: reference = loaded.document.reference
        case .heading, .verseAnnouncement, .verse: reference = verse.map { "\(loaded.document.reference):\($0.label)" } ?? loaded.document.reference
        }
        focusRevision += 1
        focus = NarrationFocus(chapterID: token.chapterID, verseID: segment.verseID, kind: segment.kind, segmentRange: segment.displayRange,
                               wordRange: spoken.flatMap { segment.displayRange(forSpoken: $0) }, revision: focusRevision)
    }

    private func finishIfDrained() {
        guard queued.isEmpty, pending == nil, awaitingChapter == nil, let endReason, status.isActive else { return }
        savePosition()
        if let continuationFailure { fail(continuationFailure); return }
        if let next = sleepStoppedBefore {
            // Shows the finished chapter while paused; resume starts the next one with its announcement.
            let finished = chapterID, finishedReference = finished.flatMap { loaded[$0]?.document.reference }
            _ = restart()
            lastRequest = (nil, next)
            clearCursor()
            chapterID = finished
            reference = finishedReference
            status = .paused(.sleepTimer)
            setSleepTimer(.off)
            return
        }
        status = .finished(endReason)
        clearCursor()
        audio.deactivate()
    }

    private func fail(_ message: String) {
        _ = restart()
        status = .failed(message)
        clearCursor()
        audio.deactivate()
    }

    private func clearCursor() {
        focus = nil
        reference = nil
        chapterID = nil
        current = nil
    }

    /// The verse and offset last spoken. Headings save their verse's start; announcements and
    /// colophons are not positions.
    private func savePosition() {
        guard let token = current, let loaded = loaded[token.chapterID] else { return }
        let segment = loaded.script.segments[token.segment]
        guard let verseID = segment.verseID, let range = segment.displayRange else { return }
        var offset = 0
        if segment.kind == .verse, let spoken = segment.displayRange(forSpoken: NSRange(location: lastSpokenOffset, length: 0)) {
            offset = spoken.location - range.location
        }
        source.savePosition(token.chapterID, VerseAnchor(verseID: verseID, utf16Offset: offset))
    }
}
