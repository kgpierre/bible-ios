import SwiftUI

struct AppRootView: View {
    @State private var state = AppState()
    @Environment(\.undoManager) private var undoManager
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
        .focusedSceneValue(\.readerCommandState, state)
        .onChange(of: undoManager, initial: true) { _, manager in state.reader.connectUndoManager(manager) }
        .preferredColorScheme(state.appearance.colorScheme)
        .onChange(of: state.preferences.typography, initial: true) { _, typography in state.reader.typography = typography }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { state.reader.flushPosition(protectInBackground: true) }
        }
    }

    private var prototype: some View {
        GeometryReader { geometry in
            // Space for a 320-point sidebar plus a useful reading column and safe margins.
            let wide = geometry.size.width >= 920
            NavigationSplitView(columnVisibility: Binding(
                get: { wide ? state.sidebarVisibility : .detailOnly },
                set: { if wide { state.sidebarVisibility = $0 } }), preferredCompactColumn: .constant(.detail)) {
                sidebar(wide: wide)
                    .accessibilityHidden(!wide)
                    .allowsHitTesting(wide)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 320)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                destinationContent(wide: wide)
                    .background(Color(.readingCanvas).ignoresSafeArea())
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar(removing: .sidebarToggle)
                    .toolbar { readerToolbar(wide: wide) }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !wide { CompactReaderNavigation(state: state) }
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .background(Color(.readingCanvas))
            .sheet(isPresented: $state.isAppearancePresented) {
                AppearanceView(preferences: state.preferences)
            }
            .sheet(isPresented: $state.isBooksPresented) {
                PrototypeChapterPicker(state: state.reader, startsWithBooks: true) { state.destination = .read }
            }
            .sheet(item: $state.summary) { summary in
                ChapterSummaryView(state: summary) { source in
                    if let chapter = state.reader.catalogChapter(source.chapterID) {
                        state.reader.navigate(to: chapter, verseID: source.id, cueVerseIDs: [source.id])
                        state.destination = .read
                    }
                }
            }
            .sheet(isPresented: $state.isPrototypeInfoPresented) { prototypeInfo }

        }
        .task { await state.reader.load() }
        .task(id: "\(state.destination.rawValue):\(state.reader.savedRevision)") {
            if state.destination == .saved { await state.reader.loadSavedItems() }
        }
        .alert("Local reading data", isPresented: Binding(get: { state.reader.errorMessage != nil }, set: { if !$0 { state.reader.errorMessage = nil } })) {
            if state.reader.canRetry {
                Button("Retry") { Task { await state.reader.retry() } }
            }
            Button("OK", role: .cancel) { state.reader.dismissError() }
        } message: { Text(state.reader.errorMessage ?? "") }
    }

    private func destinationContent(wide: Bool) -> some View {
        ZStack {
            chapter(wide: wide)
                .opacity(wide || state.destination == .read ? 1 : 0)
                .allowsHitTesting(wide || state.destination == .read)
                .accessibilityHidden(!wide && state.destination != .read)
            saved
                .opacity(!wide && state.destination == .saved ? 1 : 0)
                .allowsHitTesting(!wide && state.destination == .saved)
                .accessibilityHidden(wide || state.destination != .saved)
            if !wide {
                SearchView(state: state.search, active: state.destination == .search) { passage in
                    state.reader.openPassage(passage)
                    state.destination = .read
                }
                .opacity(state.destination == .search ? 1 : 0)
                .allowsHitTesting(state.destination == .search)
                .accessibilityHidden(state.destination != .search)
            }
        }
        .navigationTitle(!wide && state.destination == .saved ? String(localized: "Saved") : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!wide)
    }

    @ViewBuilder private func chapter(wide: Bool) -> some View {
        if let document = state.reader.document {
            GeometryReader { geometry in
                PaperChapterView(document: document, state: state.reader, wide: wide,
                                  chromeInsets: geometry.safeAreaInsets, isActive: wide || state.destination == .read)
                    .ignoresSafeArea(.container, edges: .vertical)
            }
        } else if state.reader.isLoading {
            ProgressView("Opening Bible…")
        } else {
            ReaderUnavailableView()
        }
    }

    @ToolbarContentBuilder private func readerToolbar(wide: Bool) -> some ToolbarContent {
        if wide {
            ToolbarItem(placement: .topBarLeading) {
                Button("Toggle sidebar", systemImage: "sidebar.left") {
                    state.sidebarVisibility = state.sidebarVisibility == .detailOnly ? .all : .detailOnly
                }
            }
            ToolbarItem(placement: .principal) { PassageButton(state: state, compact: false) }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Appearance", systemImage: "textformat.size") { state.isAppearancePresented = true }
                .accessibilityIdentifier("appearanceButton")
            Button {
                if let chapter = state.reader.document { state.summary = state.reader.summaryState(for: chapter) }
            } label: {
                Image(systemName: "apple.intelligence")
            }
            .accessibilityLabel("Summarize current chapter")
            .accessibilityIdentifier("chapterSummaryButton")
            .disabled(state.reader.document == nil || state.reader.isLoading)
            Menu("More", systemImage: "ellipsis") {
                Button("About this edition") { state.isPrototypeInfoPresented = true }
                Button("Search", systemImage: "magnifyingglass") {
                    state.destination = .search
                    state.search.focusRequest += 1
                }

                Button("Previous chapter", systemImage: "chevron.left") { state.reader.moveChapter(by: -1) }
                    .disabled(!state.reader.hasAdjacentChapter(-1))

                Button("Next chapter", systemImage: "chevron.right") { state.reader.moveChapter(by: 1) }
                    .disabled(!state.reader.hasAdjacentChapter(1))

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

    private func sidebar(wide: Bool) -> some View {
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
                            .contentShape(Rectangle())
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
                SearchView(state: state.search, active: wide) { state.reader.openPassage($0) }
            } else if state.destination == .saved {
                SavedView(state: state, wide: true)
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

    private var saved: some View { SavedView(state: state) }

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
