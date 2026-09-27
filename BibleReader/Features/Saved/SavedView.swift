import SwiftUI

struct SavedView: View {
    @Bindable var state: AppState
    var wide = false
    @Environment(\.dynamicTypeSize) private var dynamicType

    @State private var items: [SavedItem] = []
    /// Row order of `items`, so finding the first visible row stays cheap in large libraries.
    @State private var itemIndex: [String: Int] = [:]
    @State private var scroll = SavedScrollTracker()
    @State private var pendingScroll: String?
    private static let listSpace = "savedList"
    private var listRevision: String {
        "\(state.reader.savedRevision):\(state.reader.savedLoadedRevision):\(state.savedFilter.rawValue):\(state.savedSort.rawValue):\(state.reader.catalog.count)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onChange(of: pendingScroll) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .top) }
                }
                .task(id: listRevision) {
                    let source = state.reader.savedItems, filter = state.savedFilter
                    let sort = state.savedSort, chapters = state.reader.catalogIndex
                    // Ordinary libraries sort inline (no empty-state flash). Large ones sort off the main
                    // actor; a newer revision cancels this task and its stale result is discarded.
                    let ordered: [SavedItem]
                    if source.count > 1_000 {
                        ordered = await Task.detached(priority: .userInitiated) {
                            SavedOrdering.items(source, filter: filter, sort: sort, chapters: chapters)
                        }.value
                        guard !Task.isCancelled else { return }
                    } else {
                        ordered = SavedOrdering.items(source, filter: filter, sort: sort, chapters: chapters)
                    }
                    items = ordered
                    itemIndex = Dictionary(ordered.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
                    await restoreScroll()
                }
        }
    }

    /// Once per list instance, return to the row that was first visible in the other layout.
    private func restoreScroll() async {
        guard !scroll.restored, state.reader.savedLoadedRevision >= 0 else { return }
        scroll.restored = true
        guard let id = state.savedScrollID, id != items.first?.id, itemIndex[id] != nil else { return }
        // A new list (after a size-class change) ignores scrolling until its rows have laid out.
        for _ in 0..<40 {
            if !scroll.visibleIDs.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        pendingScroll = id
    }

    /// Rows moving because the list itself resized (rotation, fold, window) are not a user scroll
    /// and must not move the anchor. List reports no scroll phases, so settle before committing.
    private func trackVisibility(of id: String, visible: Bool) {
        if visible { scroll.visibleIDs.insert(id) } else { scroll.visibleIDs.remove(id) }
        scroll.commit?.cancel()
        guard scroll.restored, ContinuousClock.now - scroll.resizedAt > .seconds(1) else { return }
        scroll.commit = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled,
                  let first = scroll.visibleIDs.min(by: { (itemIndex[$0] ?? .max) < (itemIndex[$1] ?? .max) }),
                  itemIndex[first] != nil else { return }
            state.savedScrollID = first
        }
    }

    private var list: some View {
        List {
            Section {
                if dynamicType.isAccessibilitySize {
                    // Segments truncate at accessibility sizes; full-width menus keep every label readable.
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
                } else {
                    HStack(spacing: 12) {
                        Picker("Show", selection: $state.savedFilter) {
                            ForEach(SavedFilter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("savedFilterSegments")
                        Menu {
                            Picker("Sort", selection: $state.savedSort) {
                                ForEach(SavedSort.allCases) { Text($0.title).tag($0) }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Sort")
                        .accessibilityValue(state.savedSort.title)
                        .accessibilityIdentifier("savedSort")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8))
                }
                if state.reader.canUndo {
                    Button("Undo last annotation change", systemImage: "arrow.uturn.backward") {
                        Task { await state.reader.undo() }
                    }
                    .disabled(state.reader.isSaving)
                    .accessibilityIdentifier("savedUndo")
                }
            } header: {
                DestinationTitle("Saved")
                    .padding(.bottom, 8)
            }
            Section("Saved on this device") {
                if let error = state.reader.savedError {
                    Text(error).foregroundStyle(Color(.readingSecondary))
                    Button("Retry saved passages") { Task { await state.reader.loadSavedItems() } }
                } else if state.reader.savedLoadedRevision < 0 {
                    ProgressView("Loading saved passages…")
                } else if items.isEmpty {
                    Text(state.reader.savedItems.isEmpty
                         ? "Your highlights and bookmarks will appear here."
                         : state.savedFilter == .highlights ? "No saved highlights." : "No saved bookmarks.")
                        .foregroundStyle(Color(.readingSecondary))
                }
                ForEach(items) { item in
                    row(item)
                        .id(item.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { deleteButton(item) }
                        .contextMenu { deleteButton(item) }
                        .accessibilityAction(named: Text("Delete saved item")) { delete(item) }
                        .listRowBackground(wide && state.savedSelection == item.id ? Color(.accent).opacity(0.12) : nil)
                        .onGeometryChange(for: Bool.self) { [scroll] proxy in
                            // List exposes no scroll-view bounds to its rows; measure against the list's own frame.
                            let midY = proxy.frame(in: .named(Self.listSpace)).midY
                            return midY >= 0 && midY <= scroll.listHeight
                        } action: { trackVisibility(of: item.id, visible: $0) }
                }
            }
        }
        .coordinateSpace(.named(Self.listSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            scroll.listHeight = size.height
            scroll.resizedAt = .now
            scroll.commit?.cancel()
        }
        .onDisappear { scroll.commit?.cancel() }
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
            // Matches Search results: accent reference, serif Scripture excerpt, labeled annotation kind.
            VStack(alignment: .leading, spacing: 6) {
                Text(item.reference).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.accent))
                Text(item.text).font(.system(.body, design: .serif)).foregroundStyle(Color(.readingPrimary))
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : 3)
                if item.color != nil || item.bookmark {
                    HStack(spacing: 14) {
                        if let color = item.color {
                            Label {
                                Text(color.title)
                            } icon: {
                                Circle().fill(Color(color.assetName))
                                    .overlay { Circle().strokeBorder(Color(.readingSecondary).opacity(0.45), lineWidth: 1) }
                                    .frame(width: 12, height: 12)
                            }
                        }
                        if item.bookmark { Label("Bookmarked", systemImage: "bookmark.fill") }
                    }
                    .font(.caption).foregroundStyle(Color(.readingSecondary))
                }
                if item.unavailable {
                    Text("Saved words could not be located. Opens the chapter when available.")
                        .font(.caption).foregroundStyle(Color(.readingSecondary))
                }
            }
            .padding(.vertical, 4)
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

/// Scroll bookkeeping for one Saved list. A plain reference, not observed: row visibility changes
/// on every scrolled frame, and re-rendering the List for it cancels programmatic scrolling.
@MainActor private final class SavedScrollTracker {
    var visibleIDs: Set<String> = []
    var restored = false
    var listHeight: CGFloat = 0
    var resizedAt = ContinuousClock.now
    var commit: Task<Void, Never>?
}
