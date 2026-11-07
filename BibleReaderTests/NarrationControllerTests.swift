import Testing
import Foundation
@testable import BibleReader

@MainActor
struct NarrationControllerTests {
    /// Three chapters in catalog order: AAA 1–2 then BBB 1, the end of this miniature Bible.
    private static let order = ["t:AAA:1", "t:AAA:2", "t:BBB:1"]

    private static func document(_ id: String) -> ChapterDocument {
        let parts = id.split(separator: ":"), book = String(parts[1]), label = String(parts[2])
        func verse(_ number: String, _ text: String, headings: [String] = []) -> ChapterDocument.Verse {
            .init(id: "\(id):\(number)", label: number, runs: [.init(text: text, italic: false)], structure: "p", headings: headings, notes: [])
        }
        return ChapterDocument(id: id, bookID: book, bookName: book == "AAA" ? "Alpha" : "Beta", eyebrow: "", label: label, editionLabel: "KJV",
                               verses: [verse("1", "¶ In the beginning God created.", headings: ["A song."]), verse("2", "And the earth was.")])
    }

    private final class Recorder {
        var positions: [(String, VerseAnchor)] = []
        var follows: [(String, String)] = []
        var failing: Set<String> = []
        var isAppActive = true
        /// Pending sleeps from the sleep timer, resumed by the test in order.
        var sleeps: [CheckedContinuation<Void, Error>] = []
        func elapseSleep() { if !sleeps.isEmpty { sleeps.removeFirst().resume() } }
    }

    private struct Harness {
        let controller: NarrationController
        let synth: ScriptedSpeechSynthesizer
        let audio: SilentNarrationAudioSession
        let nowPlaying: RecordingNowPlaying
        let recorder: Recorder
        let preferences: NarrationPreferences
    }

    private static let voice = NarrationVoice(id: "com.apple.voice.test", name: "Test", language: "en-US", quality: .enhanced)

    private func harness(voices: [NarrationVoice] = [voice], lexicon: NarrationLexicon = .empty,
                         configure: (NarrationPreferences) -> Void = { _ in }) -> Harness {
        let recorder = Recorder()
        let preferences = NarrationPreferences(defaults: UserDefaults(suiteName: "NarrationTests-\(UUID().uuidString)")!)
        configure(preferences)
        let source = NarrationSource(
            chapter: { id in
                if recorder.failing.contains(id) { throw StorageIssue.invalidPassage }
                return Self.document(id)
            },
            adjacentChapterID: { id, delta in
                Self.order.firstIndex(of: id).flatMap { Self.order.indices.contains($0 + delta) ? Self.order[$0 + delta] : nil }
            },
            bookChapterCount: { $0 == "AAA" ? 2 : 1 },
            savePosition: { recorder.positions.append(($0, $1)) },
            followChapter: { recorder.follows.append(($0, $1)) },
            isAppActive: { recorder.isAppActive })
        let synth = ScriptedSpeechSynthesizer()
        let audio = SilentNarrationAudioSession()
        let nowPlaying = RecordingNowPlaying()
        let controller = NarrationController(source: source, synthesizer: synth, audio: audio, nowPlaying: nowPlaying, preferences: preferences,
                                             voices: NarrationVoiceCatalog(load: { voices }, preferredLanguage: "en-US",
                                                                           personalStatus: { .unsupported }, requestPersonal: { .unsupported }),
                                             lexicon: lexicon,
                                             sleep: { _ in try await withCheckedThrowingContinuation { recorder.sleeps.append($0) } })
        return Harness(controller: controller, synth: synth, audio: audio, nowPlaying: nowPlaying, recorder: recorder, preferences: preferences)
    }

    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Timed out"); return }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Starts the queued head and waits until the controller has processed it.
    private func start(_ h: Harness) async throws -> SpeechRequest {
        let revision = h.controller.focus?.revision ?? 0
        let request = try #require(h.synth.startNext())
        try await until { (h.controller.focus?.revision ?? 0) > revision }
        return request
    }

    private func finish(_ h: Harness) async throws {
        h.synth.finishCurrent()
        try await Task.sleep(for: .milliseconds(10))
    }

    @Test func playsAnnouncementHeadingAndVerseInOrderWithWordFocus() async throws {
        let h = harness()
        h.controller.play(from: nil, in: "t:AAA:1")
        try await until { h.synth.queue.count == 3 }
        #expect(h.synth.history.map(\.text) == ["Alpha, Chapter 1", "A song.", "In the beginning God created."])
        #expect(h.synth.history.allSatisfy { $0.voiceID == Self.voice.id })
        #expect(h.audio.activations == 1)

        _ = try await start(h)
        #expect(h.controller.status == .playing)
        #expect(h.controller.focus?.kind == .chapterAnnouncement)
        #expect(h.controller.focus?.segmentRange == nil)
        #expect(h.controller.reference == "Alpha 1")
        try await finish(h)
        _ = try await start(h)
        #expect(h.controller.focus?.kind == .heading)
        #expect(h.controller.reference == "Alpha 1:1")
        try await finish(h)
        let verse = try await start(h)
        h.synth.speak((verse.text as NSString).range(of: "God"))
        try await Task.sleep(for: .milliseconds(10))
        let map = ChapterTextMap(document: Self.document("t:AAA:1"))
        let word = try #require(h.controller.focus?.wordRange)
        #expect((map.text as NSString).substring(with: word) == "God")
        #expect(h.controller.focus?.segmentRange == map.entries[0].range)
        #expect(h.controller.focus?.verseID == "t:AAA:1:1")
    }

    @Test func continuesIntoNextChapterAndReaderFollows() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        // The last verse is queued, so the next chapter is prefetched and queued behind it.
        try await until { h.synth.history.count == 3 }
        #expect(h.synth.history.map(\.text) == ["And the earth was.", "Alpha, Chapter 2", "A song."])
        _ = try await start(h)
        try await finish(h)
        _ = try await start(h)
        #expect(h.controller.chapterID == "t:AAA:2")
        #expect(h.recorder.follows.map { "\($0.0)>\($0.1)" } == ["t:AAA:1>t:AAA:2"])
        // Across books the announcement uses the single-chapter wording.
        h.controller.skipChapter(by: 1)
        try await until { h.synth.queue.first?.text == "Beta" && h.synth.queue.count == 3 }
        #expect(h.synth.queue.map(\.text) == ["Beta", "A song.", "In the beginning God created."])
    }

    @Test func stopsAtTheEndOfTheBibleWithoutWrapping() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:BBB:1:2", utf16Offset: 0), in: "t:BBB:1")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        try await finish(h)
        try await until { h.controller.status == .finished(.endOfBible) }
        #expect(h.synth.history.count == 1)
        #expect(h.audio.deactivations == 1)
        #expect(h.controller.focus == nil)
        #expect(h.recorder.positions.last?.1.verseID == "t:BBB:1:2")
    }

    @Test func stopsAtChapterEndWhenContinuationIsOff() async throws {
        let h = harness { $0.continuesToNextChapter = false }
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        try await finish(h)
        try await until { h.controller.status == .finished(.endOfChapter) }
        #expect(h.synth.history.count == 1)
    }

    @Test func continuationLoadFailureReportsAfterTheChapterFinishes() async throws {
        let h = harness()
        h.recorder.failing = ["t:AAA:2"]
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        #expect(h.controller.status == .playing)
        try await finish(h)
        try await until { if case .failed = h.controller.status { true } else { false } }
    }

    @Test func pauseSavesTheSpokenWordAndResumeContinues() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: 9), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        // Starting mid-verse begins at the word ("beginning"), past the omitted pilcrow.
        let verse = try await start(h)
        #expect(verse.text == "beginning God created.")
        h.synth.speak((verse.text as NSString).range(of: "God"))
        try await Task.sleep(for: .milliseconds(10))
        h.controller.pause(.user)
        #expect(h.controller.status == .paused(.user))
        #expect(h.synth.isPaused)
        let saved = try #require(h.recorder.positions.last)
        #expect(saved.0 == "t:AAA:1")
        #expect(saved.1 == VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: ("¶ In the beginning " as NSString).length))
        h.controller.resume()
        #expect(h.controller.status == .playing)
        #expect(!h.synth.isPaused)
    }

    @Test func speedChangeRestartsFromTheLastSpokenWordAndDropsStaleEvents() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:2:1", utf16Offset: 0), in: "t:AAA:2")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        try await finish(h)
        let verse = try await start(h)
        let oldToken = verse.token
        h.synth.speak((verse.text as NSString).range(of: "God"))
        try await Task.sleep(for: .milliseconds(10))
        h.preferences.rate = .fast
        h.controller.speechSettingsChanged()
        try await until { h.synth.history.last?.token.generation != oldToken.generation && h.synth.queue.count == 3 }
        let restarted = try #require(h.synth.queue.first)
        #expect(restarted.text == "God created.")
        #expect(restarted.rate == NarrationRate.fast.utteranceRate)
        #expect(restarted.token.segment == oldToken.segment)
        _ = try await start(h)
        let map = ChapterTextMap(document: Self.document("t:AAA:2"))
        h.synth.speak(NSRange(location: 0, length: 3))
        try await Task.sleep(for: .milliseconds(10))
        #expect(h.controller.focus?.wordRange.map { (map.text as NSString).substring(with: $0) } == "God")
    }

    @Test func verseAndChapterSkipsNeverWrap() async throws {
        let h = harness()
        h.controller.play(from: nil, in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        // Before the first verse: restart verse 1 (with its heading).
        h.controller.skipVerse(by: -1)
        try await until { h.synth.queue.first?.text == "A song." }
        _ = try await start(h)
        h.controller.skipVerse(by: 1)
        try await until { h.synth.queue.first?.text == "And the earth was." }
        _ = try await start(h)
        // Past the last verse: the next chapter.
        h.controller.skipVerse(by: 1)
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 2" }
        _ = try await start(h)
        h.controller.skipChapter(by: -1)
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 1" }
        _ = try await start(h)
        // Before Genesis 1 (here, AAA 1): restart it.
        h.controller.skipChapter(by: -1)
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 1" && h.synth.current == nil }
        #expect(h.controller.status == .preparing)
    }

    @Test func stopCancelsQueueAndKeepsPosition() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        h.controller.stop()
        #expect(h.controller.status == .idle)
        #expect(h.synth.queue.isEmpty)
        #expect(h.audio.deactivations == 1)
        #expect(h.recorder.positions.last?.1 == VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0))
        try await Task.sleep(for: .milliseconds(10))
        #expect(h.controller.focus == nil)
    }

    @Test func pausingBeforeSpeechStartsHoldsTheStartPoint() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        h.controller.pause(.user)
        #expect(h.controller.status == .paused(.user))
        try await Task.sleep(for: .milliseconds(20))
        h.controller.resume()
        try await until { h.synth.queue.first?.text == "And the earth was." }
    }

    @Test func missingChosenVoiceFallsBackWithoutForgettingIt() async throws {
        let h = harness { $0.voiceID = "com.apple.voice.removed" }
        h.controller.play(from: nil, in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        #expect(h.synth.history.first?.voiceID == Self.voice.id)
        #expect(h.controller.notice != nil)
        #expect(h.preferences.voiceID == "com.apple.voice.removed")
    }

    @Test func unavailableVoicesAndAudioFailuresNeverStart() async throws {
        let none = harness(voices: [])
        none.controller.play(from: nil, in: "t:AAA:1")
        guard case .unavailable = none.controller.status else { Issue.record("Expected unavailable"); return }
        let busy = harness()
        busy.audio.failsActivation = true
        busy.controller.play(from: nil, in: "t:AAA:1")
        try await until { if case .failed = busy.controller.status { true } else { false } }
        #expect(busy.synth.history.isEmpty)
    }

    @Test func defaultVoicePrefersRegionAndQualityButNeverPersonalVoice() {
        let catalog = NarrationVoiceCatalog(load: {
            [NarrationVoice(id: "us-default", name: "Ava", language: "en-US", quality: .standard),
             NarrationVoice(id: "gb-premium", name: "Jamie", language: "en-GB", quality: .premium),
             NarrationVoice(id: "personal", name: "Mine", language: "en-GB", quality: .personal),
             NarrationVoice(id: "gb-default", name: "Daniel", language: "en-GB", quality: .standard)]
        }, preferredLanguage: "en-GB")
        #expect(catalog.voices.first?.id == "personal")
        #expect(catalog.defaultVoice?.id == "gb-premium")
        #expect(catalog.resolve(nil).voice == catalog.defaultVoice)
        #expect(!catalog.resolve(nil).isFallback)
        #expect(catalog.resolve("us-default").voice?.id == "us-default")
        #expect(catalog.resolve("gone").isFallback)
    }

    @Test func preferencesPersistAndToleratePartialPayloads() throws {
        let suite = "NarrationPrefs-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let fresh = NarrationPreferences(defaults: defaults)
        #expect(fresh.rate == .normal && fresh.announcesChapters && !fresh.announcesVerseNumbers && fresh.continuesToNextChapter && !fresh.usesVoiceOverSettings)
        fresh.voiceID = "v"
        fresh.rate = .slower
        fresh.announcesVerseNumbers = true
        let reloaded = NarrationPreferences(defaults: defaults)
        #expect(reloaded.voiceID == "v" && reloaded.rate == .slower && reloaded.announcesVerseNumbers)
        defaults.set(Data(#"{"version":1,"rate":"1.5"}"#.utf8), forKey: "reader.narration.v1")
        let partial = NarrationPreferences(defaults: defaults)
        #expect(partial.rate == .fast && partial.voiceID == nil && partial.continuesToNextChapter)
        defaults.set(Data(#"{"version":9,"rate":"2"}"#.utf8), forKey: "reader.narration.v1")
        #expect(NarrationPreferences(defaults: defaults).rate == .normal)
        #expect(NarrationRate.allCases.allSatisfy { (0...1).contains($0.utteranceRate) })
        #expect(NarrationRate.slower.utteranceRate < NarrationRate.normal.utteranceRate)
    }

    @Test func voiceSampleIsGenesisOneOneVerbatim() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let genesis = try await store.chapter("eng-kjv-1769-protestant:GEN:1")
        #expect(genesis.verses.first?.text == NarrationVoiceCatalog.sampleText)
    }

    // MARK: Phase 4: session, Now Playing, sleep timer, background progress

    /// Plays from AAA 1:1 (heading then verse) and returns once the verse is speaking.
    private func playingVerseOne(_ h: Harness) async throws -> SpeechRequest {
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: 0), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        _ = try await start(h)
        try await finish(h)
        return try await start(h)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(20)) }

    @Test func interruptionPausesAndResumesOnlyWhenTheSystemRecommends() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        h.audio.send(.interrupted)
        try await until { h.controller.status == .paused(.interruption) }
        h.audio.send(.interruptionEnded(shouldResume: false))
        try await settle()
        #expect(h.controller.status == .paused(.interruption))

        h.controller.resume()
        #expect(h.controller.status == .playing)
        h.audio.send(.interrupted)
        try await until { h.controller.status == .paused(.interruption) }
        let activations = h.audio.activations
        h.audio.send(.interruptionEnded(shouldResume: true))
        try await until { h.controller.status == .playing }
        // Resuming after an interruption reactivates the session.
        #expect(h.audio.activations == activations + 1)
    }

    @Test func aUserPauseIsNotOverriddenByAResumeRecommendation() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        h.controller.pause(.user)
        h.audio.send(.interrupted)
        h.audio.send(.interruptionEnded(shouldResume: true))
        try await settle()
        #expect(h.controller.status == .paused(.user))
    }

    @Test func losingTheRoutePausesAndNeverResumesByItself() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        h.audio.send(.routeLost)
        try await until { h.controller.status == .paused(.routeLost) }
        h.audio.send(.interruptionEnded(shouldResume: true))
        try await settle()
        #expect(h.controller.status == .paused(.routeLost))
        #expect(h.recorder.positions.last?.1.verseID == "t:AAA:1:1")
    }

    @Test func mediaServicesResetRebuildsTheEngineAndResumesFromTheLastWord() async throws {
        let h = harness()
        let verse = try await playingVerseOne(h)
        h.synth.speak((verse.text as NSString).range(of: "God"))
        try await settle()
        h.audio.send(.mediaServicesReset)
        try await until { h.controller.status == .paused(.mediaReset) }
        #expect(h.synth.resets == 1)
        #expect(h.synth.queue.isEmpty)
        h.controller.resume()
        try await until { h.synth.queue.first?.text == "God created." }
    }

    @Test func nowPlayingShowsTheReferenceAndEditionNeverVerseText() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        #expect(h.nowPlaying.info == NarrationNowPlayingInfo(title: "Alpha 1", edition: "KJV", isPlaying: true))
        h.controller.pause(.user)
        #expect(h.nowPlaying.info?.isPlaying == false)
        h.controller.resume()
        #expect(h.nowPlaying.info?.isPlaying == true)
        h.controller.stop()
        #expect(h.nowPlaying.info == nil)
    }

    @Test func remoteCommandsPauseResumeAndMoveByChapter() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        h.nowPlaying.send(.togglePlayPause)
        try await until { h.controller.status == .paused(.user) }
        h.nowPlaying.send(.play)
        try await until { h.controller.status == .playing }
        h.nowPlaying.send(.pause)
        try await until { h.controller.status == .paused(.user) }
        h.controller.resume()
        h.nowPlaying.send(.nextChapter)
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 2" && h.synth.current == nil }
        _ = try await start(h)
        h.controller.skipVerse(by: 1)
        try await until { h.synth.queue.first?.text == "A song." && h.synth.current == nil }
        _ = try await start(h)
        h.controller.skipVerse(by: 1)
        try await until { h.synth.queue.first?.text == "And the earth was." && h.synth.current == nil }
        _ = try await start(h)
        // Past the first verse, previous track restarts the chapter.
        h.nowPlaying.send(.previousChapter)
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 2" && h.synth.current == nil }
        _ = try await start(h)
        // At the announcement it goes back a chapter.
        h.nowPlaying.send(.previousChapter)
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 1" && h.synth.current == nil }
    }

    @Test func remoteCommandsDoNothingWhenIdle() async throws {
        let h = harness()
        h.nowPlaying.send(.play)
        h.nowPlaying.send(.nextChapter)
        try await settle()
        #expect(h.controller.status == .idle)
        #expect(h.synth.history.isEmpty)
    }

    @Test func minutesSleepTimerPausesAtTheNextSegmentBoundary() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        h.controller.setSleepTimer(.minutes(15))
        #expect(h.controller.sleepDeadline != nil)
        try await until { h.recorder.sleeps.count == 1 }
        h.recorder.elapseSleep()
        // Expired, but the verse finishes first.
        try await until { h.recorder.sleeps.count == 1 }
        #expect(h.controller.status == .playing)
        try await finish(h)
        #expect(h.controller.status == .paused(.sleepTimer))
        #expect(h.controller.sleepTimer == .off)
        #expect(h.synth.queue.isEmpty)
        h.controller.resume()
        try await until { h.synth.queue.first?.text == "And the earth was." }
    }

    @Test func aVerseRunningPastTheSleepGraceIsPausedMidVerse() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        h.controller.setSleepTimer(.minutes(15))
        try await until { h.recorder.sleeps.count == 1 }
        h.recorder.elapseSleep()
        try await until { h.recorder.sleeps.count == 1 }
        h.recorder.elapseSleep()
        try await until { h.controller.status == .paused(.sleepTimer) }
        #expect(h.synth.isPaused)
    }

    @Test func endOfChapterSleepTimerPausesBeforeTheNextChapter() async throws {
        let h = harness()
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        // The next chapter is already queued behind the last verse; setting the timer trims it.
        try await until { h.synth.history.count == 3 }
        _ = try await start(h)
        h.controller.setSleepTimer(.endOfChapter)
        try await until { h.synth.queue.count == 1 && h.synth.queue.first?.text == "And the earth was." }
        _ = try await start(h)
        try await finish(h)
        try await until { h.controller.status == .paused(.sleepTimer) }
        #expect(h.controller.reference == "Alpha 1")
        #expect(h.recorder.follows.isEmpty)
        h.controller.resume()
        try await until { h.synth.queue.first?.text == "Alpha, Chapter 2" }
    }

    @Test func backgroundNarrationSavesProgressAtVerseStarts() async throws {
        let h = harness()
        h.recorder.isAppActive = false
        _ = try await playingVerseOne(h)
        // The heading is not a position; the verse start (past the omitted pilcrow) is.
        #expect(h.recorder.positions.map(\.1) == [VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: 2)])
        try await finish(h)
        _ = try await start(h)
        // At most every five seconds.
        #expect(h.recorder.positions.count == 1)
    }

    @Test func foregroundNarrationLeavesProgressToTheReader() async throws {
        let h = harness()
        _ = try await playingVerseOne(h)
        #expect(h.recorder.positions.isEmpty)
    }

    @Test func aPauseTheSynthesizerIgnoresStillStopsSpeech() async throws {
        let h = harness()
        h.synth.ignoresPause = true
        // Paused right after starting, before any segment began (owner device report, 7 November).
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:2", utf16Offset: 0), in: "t:AAA:1")
        try await until { !h.synth.queue.isEmpty }
        h.controller.pause(.user)
        #expect(h.controller.status == .paused(.user))
        // The synthesizer starts anyway; the controller cancels it and stays paused.
        h.synth.startNext()
        try await until { h.synth.queue.isEmpty }
        #expect(h.controller.status == .paused(.user))
        h.controller.resume()
        try await until { h.synth.queue.first?.text == "And the earth was." && h.synth.current == nil }
    }

    @Test func aPauseIgnoredMidVerseResumesFromTheLastWord() async throws {
        let h = harness()
        let verse = try await playingVerseOne(h)
        h.synth.ignoresPause = true
        h.controller.pause(.user)
        h.synth.speak((verse.text as NSString).range(of: "God"))
        try await until { h.synth.queue.isEmpty }
        #expect(h.controller.status == .paused(.user))
        h.controller.resume()
        try await until { h.synth.queue.first?.text == "God created." }
    }

    // MARK: Phase 5: verse pauses, pronunciation hints, Personal Voice access

    @Test func versesEndWithTheChosenPause() async throws {
        let h = harness { $0.versePause = .long }
        h.controller.play(from: VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: 0), in: "t:AAA:1")
        try await until { h.synth.queue.count == 3 }
        // Heading, verse 1, verse 2.
        #expect(h.synth.queue.map(\.postDelay) == [0.3, NarrationVersePause.long.seconds, NarrationVersePause.long.seconds])
        _ = try await start(h)
        // A change requeues from the last word with the new pause.
        h.preferences.versePause = .none
        h.controller.speechSettingsChanged()
        try await until { h.synth.queue.count == 3 && h.synth.current == nil }
        #expect(h.synth.queue.map(\.postDelay) == [0.3, 0, 0])
    }

    @Test func pronunciationHintsFollowTheSetting() async throws {
        let lexicon = NarrationLexicon(entries: [.init(word: "God", ipa: "ɡɑd", voices: ["v"], reviewed: "test")])
        let on = harness(lexicon: lexicon)
        #expect(on.controller.hasPronunciationHints)
        on.controller.play(from: VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: 0), in: "t:AAA:1")
        try await until { on.synth.queue.count == 3 }
        let verse = try #require(on.synth.queue.dropFirst().first)
        #expect(verse.pronunciations.map { (verse.text as NSString).substring(with: $0.range) } == ["God"])

        let off = harness(lexicon: lexicon) { $0.usesPronunciationHints = false }
        off.controller.play(from: VerseAnchor(verseID: "t:AAA:1:1", utf16Offset: 0), in: "t:AAA:1")
        try await until { off.synth.queue.count == 3 }
        #expect(off.synth.queue.allSatisfy { $0.pronunciations.isEmpty })
        #expect(!harness().controller.hasPronunciationHints)
    }

    @Test func newSettingsDecodeFromOlderPayloads() throws {
        let defaults = try #require(UserDefaults(suiteName: "NarrationPrefs-\(UUID().uuidString)"))
        defaults.set(Data(#"{"version":1,"rate":"1.5"}"#.utf8), forKey: "reader.narration.v1")
        let older = NarrationPreferences(defaults: defaults)
        #expect(older.rate == .fast && older.versePause == .short && older.usesPronunciationHints)
        older.versePause = .none
        older.usesPronunciationHints = false
        let reloaded = NarrationPreferences(defaults: defaults)
        #expect(reloaded.versePause == .none && !reloaded.usesPronunciationHints && reloaded.rate == .fast)
    }

    @Test func personalVoiceAccessIsRequestedOnceAndRefreshesVoices() async throws {
        var access = NarrationVoiceCatalog.PersonalVoiceAccess.notDetermined
        var installed = [Self.voice]
        var requests = 0
        let catalog = NarrationVoiceCatalog(load: { installed }, preferredLanguage: "en-US", personalStatus: { access },
                                            requestPersonal: {
                                                requests += 1
                                                access = .authorized
                                                installed.append(NarrationVoice(id: "personal", name: "My Voice", language: "en-US", quality: .personal))
                                                return access
                                            })
        #expect(catalog.personalVoiceAccess == .notDetermined && !catalog.hasPersonalVoice)
        await catalog.requestPersonalVoice()
        #expect(requests == 1)
        #expect(catalog.personalVoiceAccess == .authorized && catalog.hasPersonalVoice)
        // Personal Voice is never the default; it is used only when chosen.
        #expect(catalog.defaultVoice?.id == Self.voice.id)
        #expect(catalog.hasNaturalVoice)
        let basic = NarrationVoiceCatalog(load: { [NarrationVoice(id: "b", name: "Basic", language: "en-US", quality: .standard)] },
                                          preferredLanguage: "en-US", personalStatus: { .unsupported }, requestPersonal: { .unsupported })
        #expect(!basic.hasNaturalVoice)
    }
}
