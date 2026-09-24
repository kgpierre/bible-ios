import SwiftUI

struct SavedView: View {
    @Bindable var state: AppState
    var wide = false
    @Environment(\.dynamicTypeSize) private var dynamicType

    @State private var items: [SavedItem] = []
    private var listRevision: String {
        "\(state.reader.savedRevision):\(state.reader.savedLoadedRevision):\(state.savedFilter.rawValue):\(state.savedSort.rawValue):\(state.reader.catalog.count)"
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $state.savedFilter) {
                    ForEach(SavedFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("savedFilter")
                Picker("Sort", selection: $state.savedSort) {
                    ForEach(SavedSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("savedSort")
                if state.reader.canUndo {
                    Button("Undo last annotation change", systemImage: "arrow.uturn.backward") {
                        Task { await state.reader.undo() }
                    }
                    .disabled(state.reader.isSaving)
                    .accessibilityIdentifier("savedUndo")
                }
            }
            Section("Saved on this device") {
                if let error = state.reader.savedError {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry saved passages") { Task { await state.reader.loadSavedItems() } }
                } else if state.reader.savedLoadedRevision < 0 {
                    ProgressView("Loading saved passages…")
                } else if items.isEmpty {
                    Text(state.reader.savedItems.isEmpty
                         ? "Your highlights and bookmarks will appear here."
                         : state.savedFilter == .highlights ? "No saved highlights." : "No saved bookmarks.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    row(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { deleteButton(item) }
                        .contextMenu { deleteButton(item) }
                        .accessibilityAction(named: Text("Delete saved item")) { delete(item) }
                        .listRowBackground(wide && state.savedSelection == item.id ? Color(.accent).opacity(0.12) : Color.clear)
                }
            }
        }
        .onChange(of: listRevision, initial: true) { _, _ in
            items = SavedOrdering.items(state.reader.savedItems, filter: state.savedFilter,
                                        sort: state.savedSort, chapters: state.reader.catalogIndex)
        }
        .refreshable { await state.reader.loadSavedItems(force: true) }
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
    }

    private func row(_ item: SavedItem) -> some View {
        Button {
            state.savedSelection = item.id
            if let chapter = state.reader.catalogChapter(item.chapterID) {
                state.reader.navigate(to: chapter, verseID: item.verseID, utf16Offset: item.passage?.parts.first?.start ?? 0)
                if !wide { state.destination = .read }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.reference).font(.headline)
                Text(item.text).font(.body).lineLimit(dynamicType.isAccessibilitySize ? nil : 3)
                if let color = item.color {
                    Label(color.title, systemImage: "highlighter").font(.caption)
                }
                if item.bookmark { Label("Bookmarked", systemImage: "bookmark.fill").font(.caption) }
                if item.unavailable {
                    Text("Saved words could not be located. Opens the chapter when available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("savedItem-" + item.id)
        .accessibilityAddTraits(state.savedSelection == item.id ? .isSelected : [])
    }

    private func deleteButton(_ item: SavedItem) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
            .disabled(state.reader.isSaving)
    }

    private func delete(_ item: SavedItem) {
        Task { await state.reader.deleteSaved(item) }
    }
}
