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
    var isBooksPresented = false
    var newTestament = false
    var isPrototypeInfoPresented = false
    var savedSelection: String?
    var savedFilter: SavedFilter = .all
    var savedSort: SavedSort = .recent
    var destination: AppDestination = .read
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    let reader: ReaderState
    let search: SearchState

    init(reader: ReaderState = ReaderState()) {
        self.reader = reader
        search = SearchState { input, offset in try await reader.search(input, offset: offset) }
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
