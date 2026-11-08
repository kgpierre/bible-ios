import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    let preferences = ReaderPreferences()
    var appearance: AppAppearance { preferences.theme }
    var summary: ChapterSummaryState?
    var isAppearancePresented = false
    var isChapterPickerPresented = false
    var isAboutPresented = false
    var isReadAloudSettingsPresented = false
    /// The Widgets sheet: the card list, or a new card's editor from Saved.
    var cardsRequest: CardsRequest?
    let cards = CardsModel()
    /// A widget link received before the catalog loaded; opened once it can be validated.
    var pendingLink: (chapterID: String, verseID: String?)?
    /// Whether this device reports a hinge (a foldable); fold-only settings appear only then.
    var hasHinge = false
    /// Whether the system currently offers the outer display for the chapter card (iOS 27 scene
    /// accessory); nil until it reports.
    var outerDisplayAvailable: Bool?
    var savedSelection: String?
    var savedFilter: SavedFilter = .all
    var savedSort: SavedSort = .recent
    /// First visible Saved row. Compact and regular layouts build separate lists, so resizing
    /// across the size-class boundary restores from this instead of returning to the top.
    @ObservationIgnored var savedScrollID: String?
    var destination: AppDestination = .read
    let reader: ReaderState
    let search: SearchState
    let narration: NarrationController

    init(reader: ReaderState = ReaderState(), narration: NarrationController? = nil) {
        self.reader = reader
        search = SearchState { input, offset in try await reader.search(input, offset: offset) }
        self.narration = narration ?? Self.makeNarration(source: reader.narrationSource())
    }

    private static func makeNarration(source: NarrationSource) -> NarrationController {
        var synthesizer: any SpeechSynthesizing = SystemSpeechSynthesizer()
        var audio: any NarrationAudioSession = SystemNarrationAudioSession()
        let nowPlaying: any NarrationNowPlaying = SystemNarrationNowPlaying()
        #if DEBUG
        // UI tests use deterministic speech instead of Simulator audio; "fast" exercises follow-along.
        if let mode = ProcessInfo.processInfo.environment["BIBLE_TEST_FAKE_SPEECH"], mode == "1" || mode == "fast" {
            synthesizer = ScriptedSpeechSynthesizer(pacing: mode == "fast" ? .milliseconds(700) : .seconds(3))
            audio = SilentNarrationAudioSession()
        }
        #endif
        return NarrationController(source: source, synthesizer: synthesizer, audio: audio, nowPlaying: nowPlaying,
                                   preferences: NarrationPreferences(), voices: NarrationVoiceCatalog())
    }

    /// The latest widget link; an older link's late validation never navigates.
    @ObservationIgnored private var linkRequest = UUID()

    /// Opens a widget link only for a chapter (and verse) in the installed catalog. Links that
    /// arrive before initial restoration finishes wait, so restoration cannot replace them.
    func open(_ url: URL) {
        guard let link = CardLink.parse(url) else { return }
        guard !reader.catalog.isEmpty, !reader.isLoading else { pendingLink = link; return }
        pendingLink = nil
        let request = UUID()
        linkRequest = request
        guard let chapter = reader.catalogChapter(link.chapterID) else { return }
        guard let verseID = link.verseID else { show(chapter, verseID: nil); return }
        Task {
            guard await reader.containsVerse(verseID, inChapter: chapter.id), request == linkRequest else { return }
            show(chapter, verseID: verseID)
        }
    }

    /// Opens a pending link once initial restoration has finished.
    func openPendingLink() {
        guard let link = pendingLink, let url = CardLink.url(chapterID: link.chapterID, verseID: link.verseID) else { return }
        open(url)
    }

    private func show(_ chapter: ChapterSummary, verseID: String?) {
        summary = nil
        cardsRequest = nil
        isAppearancePresented = false
        isChapterPickerPresented = false
        isAboutPresented = false
        reader.navigate(to: chapter, verseID: verseID, cueVerseIDs: verseID.map { [$0] } ?? [])
        destination = .read
    }

    /// Opens the on-device overview for the chapter on screen.
    func summarizeCurrentChapter() {
        guard let chapter = reader.document, !reader.isLoading else { return }
        summary = reader.summaryState(for: chapter)
    }

    /// Read Chapter Aloud starts at the first visible verse, or at the chapter's beginning (with
    /// its announcement) when the reader is at the top.
    func readCurrentChapterAloud() {
        guard let document = reader.document, !reader.isLoading else { return }
        let verseID = reader.anchor?.text.verseID
        let anchor = verseID.flatMap { $0 == document.verses.first?.id ? nil : VerseAnchor(verseID: $0, utf16Offset: 0) }
        narration.play(from: anchor, in: document.id)
    }

    /// The Read Aloud keyboard command and Magic Tap.
    func toggleReadAloud() {
        if narration.status.isActive { narration.togglePlayPause() } else { readCurrentChapterAloud() }
    }

    /// Shows the verse being read aloud.
    func showNarratedVerse() {
        guard let chapterID = narration.chapterID, let chapter = reader.catalogChapter(chapterID) else { return }
        let verseID = narration.focus?.verseID
        if reader.chapterID != chapterID || verseID != nil {
            reader.navigate(to: chapter, verseID: verseID, cueVerseIDs: verseID.map { [$0] } ?? [])
        }
        destination = .read
    }

    var isNarrationElsewhere: Bool { narration.chapterID != nil && narration.chapterID != reader.chapterID }

    func makeWidget(from item: SavedItem) {
        guard let card = CardsModel.draft(from: item, editionLabel: reader.document?.editionLabel ?? "KJV") else { return }
        cardsRequest = .new(card)
    }
}

enum AppDestination: String, CaseIterable, Identifiable {
    case read, saved, search
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self { case .read: "Read"; case .saved: "Saved"; case .search: "Search" }
    }
    var localizedTitle: String {
        switch self {
        case .read: String(localized: "Read")
        case .saved: String(localized: "Saved")
        case .search: String(localized: "Search")
        }
    }
    var symbol: String {
        switch self { case .read: "book"; case .saved: "bookmark"; case .search: "magnifyingglass" }
    }
}
