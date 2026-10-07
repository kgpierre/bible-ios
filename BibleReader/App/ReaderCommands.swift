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
            Section {
                ForEach(Array(AppDestination.allCases.enumerated()), id: \.element) { index, destination in
                    Button(destination.title) { state?.destination = destination }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            Section {
                Button("Search") {
                    state?.destination = .search
                    state?.search.focusRequest += 1
                }.keyboardShortcut("f", modifiers: .command)
                Button("Appearance") {
                    state?.destination = .read
                    state?.isAppearancePresented = true
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(state == nil)
                Button("Summarize Chapter") {
                    state?.destination = .read
                    state?.summarizeCurrentChapter()
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(state?.reader.document == nil || state?.reader.isLoading == true)
            }
            Section {
                Button(state?.reader.isCurrentChapterSaved == true ? "Remove Saved Chapter" : "Save Chapter") {
                    guard let reader = state?.reader else { return }
                    Task { await reader.setCurrentChapterSaved(!reader.isCurrentChapterSaved) }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(state?.reader.document == nil || state?.reader.isSaving == true)
                Button("Previous Chapter") { state?.reader.moveChapter(by: -1) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(state?.reader.hasAdjacentChapter(-1) != true)
                Button("Next Chapter") { state?.reader.moveChapter(by: 1) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(state?.reader.hasAdjacentChapter(1) != true)
            }
        }
    }
}
