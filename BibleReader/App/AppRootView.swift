import SwiftUI

struct AppRootView: View {
    @State private var state = AppState()
    #if DEBUG
    @State private var paperExperiment: PaperTurnModel?
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--native-tabs-probe") {
                NativeTabsProbe()
            } else if ProcessInfo.processInfo.arguments.contains("--missing-corpus") {
                NavigationStack { ReaderUnavailableView() }
            } else {
                prototype
            }
            #else
            prototype
            #endif
        }
        .preferredColorScheme(state.appearance.colorScheme)
        .onChange(of: state.preferences.typography, initial: true) { _, typography in state.reader.typography = typography }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { state.reader.flushPosition() }
        }
    }

    private var prototype: some View {
        GeometryReader { geometry in
            // Space for a 320-point sidebar plus a useful reading column and safe margins.
            let wide = geometry.size.width >= 920
            Group {
                if wide {
                    NavigationSplitView(columnVisibility: $state.sidebarVisibility) {
                        sidebar
                            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 320)
                    } detail: {
                        reader(wide: true)
                    }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    NavigationStack {
                        compactDestination
                            .background(Color(.readingCanvas).ignoresSafeArea())
                            .toolbarBackground(.hidden, for: .navigationBar)
                            .toolbar { readerToolbar(wide: false) }
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                CompactReaderNavigation(state: state)
                            }
                    }
                }
            }
            .background(Color(.readingCanvas))
            .sheet(isPresented: $state.isAppearancePresented) {
                AppearanceView(preferences: state.preferences)
            }
            .sheet(isPresented: $state.isBooksPresented) {
                PrototypeChapterPicker(state: state.reader, startsWithBooks: true) { state.destination = .read }
            }
            .sheet(item: $state.summary) { ChapterSummaryView(state: $0) }
            #if DEBUG
            .sheet(item: $paperExperiment) { PaperTurnExperimentView(model: $0) }
            #endif
            .sheet(isPresented: $state.isPrototypeInfoPresented) { prototypeInfo }

        }
        .task { await state.reader.load() }
        .alert("Local reading data", isPresented: Binding(get: { state.reader.errorMessage != nil }, set: { if !$0 { state.reader.errorMessage = nil } })) {
            if state.reader.canRetry {
                Button("Retry") { Task { await state.reader.retry() } }
            }
            Button("OK", role: .cancel) { state.reader.dismissError() }
        } message: { Text(state.reader.errorMessage ?? "") }
    }

    @ViewBuilder private var compactDestination: some View {
        switch state.destination {
        case .read:
            chapter(wide: false)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        case .saved: saved
        case .search:
            SearchView(state: state.search) { passage in
                state.reader.openPassage(passage)
                state.destination = .read
            }
        }
    }

    @ViewBuilder private func chapter(wide: Bool) -> some View {
        if let document = state.reader.document {
            GeometryReader { geometry in
                NativeChapterView(document: document, state: state.reader, wide: wide,
                                  chromeInsets: geometry.safeAreaInsets)
                    .ignoresSafeArea(.container, edges: .vertical)
            }
        } else if state.reader.isLoading {
            ProgressView("Opening Bible…")
        } else {
            ReaderUnavailableView()
        }
    }

    private func reader(wide: Bool) -> some View {
        chapter(wide: wide)
            .background(Color(.readingCanvas).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { readerToolbar(wide: wide) }
    }

    @ToolbarContentBuilder private func readerToolbar(wide: Bool) -> some ToolbarContent {
        if wide {
            ToolbarItem(placement: .topBarLeading) {
                Button("About") { state.isPrototypeInfoPresented = true }
                    .font(.caption)
                    .accessibilityIdentifier("prototypeInfoButton")
            }
        }
        if wide {
            ToolbarItem(placement: .principal) { PassageButton(state: state, compact: false) }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Appearance", systemImage: "textformat.size") { state.isAppearancePresented = true }
                .accessibilityIdentifier("appearanceButton")
            Button {
                if let chapter = state.reader.document { state.summary = ChapterSummaryState(chapter: chapter) }
            } label: {
                Image(systemName: "apple.intelligence")
            }
            .accessibilityLabel("Summarize current chapter")
            .accessibilityIdentifier("chapterSummaryButton")
            .disabled(state.reader.document == nil || state.reader.isLoading)
            Menu("More", systemImage: "ellipsis") {
                #if DEBUG
                Button("Paper turn experiment") { paperExperiment = PaperTurnModel(reader: state.reader) }
                    .disabled(state.reader.document == nil)
                #endif
                Button("About this edition") { state.isPrototypeInfoPresented = true }
                Button("Search", systemImage: "magnifyingglass") {
                    state.destination = .search
                    state.search.focusRequest += 1
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Previous chapter", systemImage: "chevron.left") { state.reader.moveChapter(by: -1) }
                    .disabled(!state.reader.hasAdjacentChapter(-1))
                    .keyboardShortcut("[", modifiers: .command)
                Button("Next chapter", systemImage: "chevron.right") { state.reader.moveChapter(by: 1) }
                    .disabled(!state.reader.hasAdjacentChapter(1))
                    .keyboardShortcut("]", modifiers: .command)
                Button("Undo annotation", systemImage: "arrow.uturn.backward") { Task { await state.reader.undo() } }
                    .disabled(!state.reader.canUndo || state.reader.isSaving)
                if let document = state.reader.document {
                    ShareLink(item: "\(document.reference) — \(document.editionLabel)") {
                        Label("Share reference", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(AppDestination.allCases) { destination in
                    Button {
                        state.destination = destination
                    } label: {
                        Label(destination.title, systemImage: destination.symbol)
                            .font(.subheadline)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(state.destination == destination ? Color(.accent) : Color(.readingSecondary))
                    .background(state.destination == destination ? Color(.accent).opacity(0.12) : .clear, in: .capsule)
                    .accessibilityAddTraits(state.destination == destination ? .isSelected : [])
                    .accessibilityIdentifier("sidebar-\(destination.rawValue)")
                }
            }
            .padding(12)
            Divider()
            if state.destination == .search {
                SearchView(state: state.search) { state.reader.openPassage($0) }
            } else if state.destination == .saved {
                List { savedRows(wide: true) }.scrollContentBackground(.hidden)
            } else {
                TestamentPicker(newTestament: $state.newTestament).padding(12)
                List(state.reader.books.filter { ($0.ordinal >= 39) == state.newTestament }) { book in
                    NavigationLink {
                        ChapterChoices(state: state.reader, bookID: book.id) { }
                            .navigationTitle(book.name)
                    } label: {
                        BookRow(book: book, selected: state.reader.document?.bookID == book.id)
                    }
                    .accessibilityIdentifier("book-\(book.id)")
                    .listRowBackground(Color(.readingCanvas))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.readingCanvas))
        .navigationTitle("Library")
    }

    private var saved: some View {
        List { savedRows(wide: false) }
            .navigationTitle("Saved")
            .scrollContentBackground(.hidden)
            .background(Color(.readingCanvas))
    }

    @ViewBuilder private func savedRows(wide: Bool) -> some View {
        Section("Saved on this device") {
            if state.reader.savedItems.isEmpty {
                Text("Your highlights and bookmarks will appear here.").foregroundStyle(.secondary)
            }
            ForEach(state.reader.savedItems) { item in
                Button {
                    state.savedSelection = item.id
                    if let chapter = state.reader.catalog.first(where: { $0.id == item.chapterID }) {
                        state.reader.navigate(to: chapter, verseID: item.verseID, utf16Offset: item.passage?.parts.first?.start ?? 0)
                        if !wide { state.destination = .read }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.reference).font(.headline)
                        Text(item.text).font(.body).lineLimit(3)
                        if let color = item.color {
                            Label(color.rawValue.capitalized, systemImage: "highlighter").font(.caption)
                        }
                        if item.bookmark { Label("Bookmarked", systemImage: "bookmark.fill").font(.caption) }
                        if item.unavailable {
                            Text("Saved words could not be located. Opens the chapter when available.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(wide && state.savedSelection == item.id ? Color(.accent).opacity(0.12) : Color.clear)
                .accessibilityAddTraits(state.savedSelection == item.id ? .isSelected : [])
            }
        }
    }

    private var prototypeInfo: some View {
        NavigationStack {
            Form {
                Section("Development build") {
                    Text("King James Version, 66-book edition. All chapters are bundled for offline reading.")
                    Text("Highlights, bookmarks, and reading position are saved on this device. No accounts, tracking, or app-operated sync. Device backups may include your saved data.")
                }
                Section("Source and notices") {
                    Text(state.reader.editionNotice).font(.footnote)
                    Text("Provider: eBible.org / Crosswire Bible Society. Source ID: eng-kjv. Downloaded 21 September 2026. Release rights and canon review remain open.")
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { state.isPrototypeInfoPresented = false }
                }
            }
        }
    }
}

#Preview { AppRootView() }
