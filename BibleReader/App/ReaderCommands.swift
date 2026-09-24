import SwiftUI

private struct ReaderCommandStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var readerCommandState: AppState? {
        get { self[ReaderCommandStateKey.self] }
        set { self[ReaderCommandStateKey.self] = newValue }
    }
}

struct ReaderCommands: Commands {
    @FocusedValue(\.readerCommandState) private var state
    var body: some Commands {
        CommandMenu("Reader") {
            Button("Search") {
                state?.destination = .search
                state?.search.focusRequest += 1
            }.keyboardShortcut("f", modifiers: .command)
            Button("Previous chapter") { state?.reader.moveChapter(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(state?.reader.hasAdjacentChapter(-1) != true)
            Button("Next chapter") { state?.reader.moveChapter(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(state?.reader.hasAdjacentChapter(1) != true)
            Button("Toggle sidebar") {
                guard let state else { return }
                state.sidebarVisibility = state.sidebarVisibility == .detailOnly ? .all : .detailOnly
            }.keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
