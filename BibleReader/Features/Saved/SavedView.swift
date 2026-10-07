import SwiftUI
import UIKit

struct SavedView: View {
    @Bindable var state: AppState
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
                if let error = state.reader.savedError {
                    ContentUnavailableView {
                        Label("Saved Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await state.reader.loadSavedItems() } }
                            .accessibilityIdentifier("savedRetry")
                    }
                    .listRowBackground(Color.clear)
                } else if state.reader.savedLoadedRevision < 0 {
                    ProgressView("Loading saved passages…")
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if items.isEmpty {
                    emptyState.listRowBackground(Color.clear)
                }
                ForEach(items) { item in
                    row(item)
                        .id(item.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) { deleteButton(item) }
                        .swipeActions(edge: .leading) { if !item.unavailable { widgetButton(item).tint(Color(.accent)) } }
                        .contextMenu {
                            contextActions(item)
                        } preview: {
                            SavedItemPreview(item: item)
                        }
                        .accessibilityAction(named: Text("Make Widget")) { state.makeWidget(from: item) }
                        .accessibilityAction(named: Text("Delete Saved Item")) { delete(item) }
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
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
        .safeAreaBar(edge: .top) {
            if !dynamicType.isAccessibilitySize {
                Picker("Show", selection: $state.savedFilter) {
                    ForEach(SavedFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("savedFilterSegments")
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if state.reader.canUndo {
            ToolbarItem(placement: .topBarLeading) {
                Button(state.reader.undoActionName.map { String(localized: "Undo \($0)") } ?? String(localized: "Undo"),
                       systemImage: "arrow.uturn.backward") {
                    Task { await state.reader.undo() }
                }
                .disabled(state.reader.isSaving)
                .accessibilityIdentifier("savedUndo")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Widgets", systemImage: "widget.small") { state.cardsRequest = .library }
                .accessibilityHint("Design widget cards from your saved passages")
                .accessibilityIdentifier("savedWidgets")
            Menu {
                if dynamicType.isAccessibilitySize {
                    // Segments truncate at accessibility sizes; the menu keeps every label readable.
                    Picker("Show", selection: $state.savedFilter) {
                        ForEach(SavedFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("savedFilter")
                }
                Picker("Sort", selection: $state.savedSort) {
                    ForEach(SavedSort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label(dynamicType.isAccessibilitySize ? "Show and Sort" : "Sort",
                      systemImage: dynamicType.isAccessibilitySize ? "line.3.horizontal.decrease" : "arrow.up.arrow.down")
            }
            .accessibilityValue(dynamicType.isAccessibilitySize
                                ? "\(state.savedFilter.title), \(state.savedSort.title)" : state.savedSort.title)
            .accessibilityIdentifier("savedSort")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if state.reader.savedItems.isEmpty {
            ContentUnavailableView {
                Label("No Saved Passages", systemImage: "bookmark")
            } description: {
                Text("Your highlights and bookmarks will appear here.")
            }
        } else {
            ContentUnavailableView {
                Label(state.savedFilter == .highlights ? "No Highlights" : "No Bookmarks",
                      systemImage: state.savedFilter == .highlights ? "highlighter" : "bookmark")
            } description: {
                Text(state.savedFilter == .highlights ? "No saved highlights." : "No saved bookmarks.")
            }
        }
    }

    @ViewBuilder private func contextActions(_ item: SavedItem) -> some View {
        Section {
            Button("Open", systemImage: "book") { open(item) }
            if let text = shareText(item) {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if !item.unavailable { widgetButton(item) }
        }
        deleteButton(item)
    }

    /// Exact saved text with its reference and edition, as Copy and Share do in the reader.
    /// Saved chapters hold only their opening verse, so they offer no text to copy.
    private func shareText(_ item: SavedItem) -> String? {
        guard !item.unavailable, !item.savedChapter else { return nil }
        let edition = state.reader.document?.editionLabel ?? "KJV"
        let excerpt = item.records.exact.isEmpty ? "" : String(localized: " (excerpt)")
        return "\(item.text)\n— \(item.reference), \(edition)\(excerpt)"
    }

    private func open(_ item: SavedItem) {
        state.savedSelection = item.id
        if let chapter = state.reader.catalogChapter(item.chapterID) {
            state.reader.navigate(to: chapter, verseID: item.savedChapter ? nil : item.verseID,
                                 utf16Offset: item.passage?.parts.first?.start ?? 0)
            state.destination = .read
        }
    }

    private func row(_ item: SavedItem) -> some View {
        Button {
            open(item)
        } label: {
            // Matches Search results: accent reference, serif Scripture excerpt, labeled annotation kind.
            VStack(alignment: .leading, spacing: 6) {
                Text(item.reference).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.accent))
                Text(item.text).font(.system(.body, design: .serif)).foregroundStyle(Color(.readingPrimary))
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : 3)
                if item.savedChapter {
                    Label {
                    if let count = item.verseCount {
                        Text("Saved chapter · ^[\(count) verse](inflect: true)")
                    } else {
                        Text("Saved chapter")
                    }
                } icon: {
                    Image(systemName: "book.closed.fill")
                }
                        .font(.caption).foregroundStyle(Color(.readingSecondary))
                }
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
                    Text(item.savedChapter ? "This chapter is not in the installed edition. Its reference has been kept."
                                           : "Saved words could not be located. Opens the chapter when available.")
                        .font(.caption).foregroundStyle(Color(.readingSecondary))
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("savedItem-" + item.id)
    }

    private func widgetButton(_ item: SavedItem) -> some View {
        Button("Make Widget", systemImage: "widget.small") { state.makeWidget(from: item) }
    }

    private func deleteButton(_ item: SavedItem) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
            .disabled(state.reader.isSaving)
    }

    private func delete(_ item: SavedItem) {
        Task { await state.reader.deleteSaved(item) }
    }
}

/// The context menu preview: the saved text at a readable size, with its reference.
private struct SavedItemPreview: View {
    let item: SavedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.reference).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.accent))
            Text(item.text).font(.system(.body, design: .serif)).foregroundStyle(Color(.readingPrimary))
                .lineLimit(12)
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(Color(.readingCanvas))
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
