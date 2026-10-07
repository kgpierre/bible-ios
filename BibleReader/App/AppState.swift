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
    /// The Widgets sheet: the card list, or a new card's editor from Saved.
    var cardsRequest: CardsRequest?
    let cards = CardsModel()
    /// A widget link received before the catalog loaded; opened once it can be validated.
    var pendingLink: (chapterID: String, verseID: String?)?
    /// Whether this device reports a hinge (a foldable); fold-only settings appear only then.
    var hasHinge = false
    var savedSelection: String?
    var savedFilter: SavedFilter = .all
    var savedSort: SavedSort = .recent
    /// First visible Saved row. Compact and regular layouts build separate lists, so resizing
    /// across the size-class boundary restores from this instead of returning to the top.
    @ObservationIgnored var savedScrollID: String?
    var destination: AppDestination = .read
    let reader: ReaderState
    let search: SearchState

    init(reader: ReaderState = ReaderState()) {
        self.reader = reader
        search = SearchState { input, offset in try await reader.search(input, offset: offset) }
    }

    /// Opens a widget link only for a chapter (and verse) in the installed catalog.
    func open(_ url: URL) {
        guard let link = CardLink.parse(url) else { return }
        guard !reader.catalog.isEmpty else { pendingLink = link; return }
        pendingLink = nil
        guard let chapter = reader.catalogChapter(link.chapterID) else { return }
        summary = nil
        cardsRequest = nil
        isAppearancePresented = false
        isChapterPickerPresented = false
        isAboutPresented = false
        reader.navigate(to: chapter, verseID: link.verseID, cueVerseIDs: link.verseID.map { [$0] } ?? [])
        destination = .read
    }

    /// Opens the on-device overview for the chapter on screen.
    func summarizeCurrentChapter() {
        guard let chapter = reader.document, !reader.isLoading else { return }
        summary = reader.summaryState(for: chapter)
    }

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
