import SwiftUI

struct AppRootView: View {
    @State private var state = AppState()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumPageWidth = ReaderLayout.minimumPageWidth
    @ScaledMetric(relativeTo: .body) private var minimumBookPageWidth = ReaderLayout.minimumBookPageWidth
    #if DEBUG
    @State private var lockProbe: LockProbe?
    @State private var lockProbeReport: String?
    #endif

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
        .background { HingeProbe { state.hasHinge = $0 }.frame(width: 0, height: 0).accessibilityHidden(true) }
        .onChange(of: undoManager, initial: true) { _, manager in state.reader.connectUndoManager(manager) }
        .preferredColorScheme(state.appearance.colorScheme)
        .onChange(of: state.preferences.typography, initial: true) { _, typography in state.reader.typography = typography }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { state.reader.flushPosition(protectInBackground: true) }
        }
        #if DEBUG
        .onAppear {
            if LockProbe.enabled, lockProbe == nil {
                lockProbe = LockProbe(reader: state.reader) { lockProbeReport = $0 }
            }
        }
        .alert("Lock probe", isPresented: Binding(get: { lockProbeReport != nil }, set: { if !$0 { lockProbeReport = nil } })) {
            Button("OK", role: .cancel) { lockProbeReport = nil }
        } message: { Text(lockProbeReport ?? "") }
        #endif
    }

    private var prototype: some View {
        Group {
            // Regular width uses the system top tab bar without a sidebar (owner choice); books stay
            // in the passage picker. Compact width, including narrow iPad windows, keeps 2a's bottom chrome.
            if horizontalSizeClass == .regular { regularLayout } else { compactLayout }
        }
        .background(Color(.readingCanvas))
        .sheet(isPresented: $state.isAppearancePresented) {
            // Only offer page layouts a device can show: Two Pages needs an iPad-class or foldable
            // display; the folded book layout needs a hinge.
            AppearanceView(preferences: state.preferences,
                           showsPageLayout: UIDevice.current.userInterfaceIdiom == .pad || state.hasHinge,
                           showsFoldOptions: state.hasHinge)
        }
        .sheet(item: $state.summary) { summary in
            ChapterSummaryView(state: summary) { source in
                if let chapter = state.reader.catalogChapter(source.chapterID) {
                    state.reader.navigate(to: chapter, verseID: source.id, cueVerseIDs: [source.id])
                    state.destination = .read
                }
            }
        }
        .sheet(item: Binding(get: { state.reader.notesRequest }, set: { state.reader.notesRequest = $0 })) { request in
            SourceNotesView(request: request)
                .preferredColorScheme(state.preferences.theme.colorScheme)
        }
        .sheet(isPresented: $state.isAboutPresented) {
            AboutView(editionNotice: state.reader.editionNotice) { state.isAboutPresented = false }
        }
        .task { await state.reader.load() }
        .onChange(of: state.destination) { _, destination in
            if destination == .search { state.reader.prewarmSearch() }
        }
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

    private var compactLayout: some View {
        NavigationStack {
            destinationContent
                .background(Color(.readingCanvas).ignoresSafeArea())
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar { readerToolbar }
                .safeAreaInset(edge: .bottom, spacing: 0) { CompactReaderNavigation(state: state) }
        }
    }

    private var regularLayout: some View {
        TabView(selection: $state.destination) {
            Tab(AppDestination.read.title, systemImage: AppDestination.read.symbol, value: AppDestination.read) {
                NavigationStack {
                    chapter(wide: true, active: state.destination == .read)
                        .background(Color(.readingCanvas).ignoresSafeArea())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .toolbar { readerToolbar }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            // The passage selector floats at the bottom trailing corner, clear of
                            // the bounded reading column's start; text scrolls clear of it.
                            PassageButton(state: state)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }
                }
            }
            Tab(AppDestination.saved.title, systemImage: AppDestination.saved.symbol, value: AppDestination.saved) {
                NavigationStack {
                    SavedView(state: state)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                        .background(Color(.readingCanvas).ignoresSafeArea())
                        .toolbarBackground(.hidden, for: .navigationBar)
                }
            }
            Tab(AppDestination.search.title, systemImage: AppDestination.search.symbol, value: AppDestination.search, role: .search) {
                NavigationStack {
                    SearchView(state: state.search, active: state.destination == .search) { passage in
                        state.reader.openPassage(passage)
                        state.destination = .read
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background(Color(.readingCanvas).ignoresSafeArea())
                    .toolbarBackground(.hidden, for: .navigationBar)
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(Color(.accent))
    }

    private var destinationContent: some View {
        ZStack {
            chapter(wide: false, active: state.destination == .read)
                .opacity(state.destination == .read ? 1 : 0)
                .allowsHitTesting(state.destination == .read)
                .accessibilityHidden(state.destination != .read)
            SavedView(state: state)
                .opacity(state.destination == .saved ? 1 : 0)
                .allowsHitTesting(state.destination == .saved)
                .accessibilityHidden(state.destination != .saved)
            SearchView(state: state.search, active: state.destination == .search) { passage in
                state.reader.openPassage(passage)
                state.destination = .read
            }
            .opacity(state.destination == .search ? 1 : 0)
            .allowsHitTesting(state.destination == .search)
            .accessibilityHidden(state.destination != .search)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func chapter(wide: Bool, active: Bool) -> some View {
        if let document = state.reader.document {
            GeometryReader { geometry in
                let fold = foldLayout(in: geometry)
                // Regular-width phones (including Duo's inner display) get the same reader as
                // iPad. Use the actual safe content area, never the device name or screen bounds.
                if wide, state.preferences.automaticBookLayout, let fold, fold.supportsBookPages(minimumPageWidth: minimumBookPageWidth,
                                                         accessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                    // Book pose automatically opens facing pages without overwriting the flat-screen preference.
                    SpreadChapterView(document: document, state: state.reader,
                                      innerPageInset: fold.innerPageInset, isActive: active)
                        .frame(width: fold.spreadFrame.width, height: fold.spreadFrame.height)
                        .position(x: fold.spreadFrame.midX, y: fold.spreadFrame.midY)
                } else if wide, let fold, fold.kind == .tabletop,
                          fold.division.minY >= 200, geometry.size.height - fold.division.maxY >= 120,
                          !dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        PaperChapterView(document: document, state: state.reader, wide: true, isActive: active)
                            .frame(height: fold.division.minY)
                        Color.clear.frame(height: fold.division.height)
                        tabletopControls
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if fold == nil, state.preferences.pageLayout == .twoPages,
                   ReaderLayout.supportsTwoPages(in: geometry.size, regularWidth: wide,
                       minimumPageWidth: minimumPageWidth, accessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                    SpreadChapterView(document: document, state: state.reader,
                                      chromeInsets: geometry.safeAreaInsets, isActive: active)
                        .ignoresSafeArea(.container, edges: .vertical)
                } else if let pane = fold?.clearPane {
                    // Scrolling fallback with an active fold (book layout off, accessibility text, or
                    // pages too narrow): keep text out of the division rather than spanning it.
                    PaperChapterView(document: document, state: state.reader, wide: wide, isActive: active)
                        .frame(width: pane.width, height: pane.height)
                        .position(x: pane.midX, y: pane.midY)
                } else {
                    PaperChapterView(document: document, state: state.reader, wide: wide,
                                      chromeInsets: geometry.safeAreaInsets, isActive: active)
                        .ignoresSafeArea(.container, edges: .vertical)
                }
            }
        } else if state.reader.isLoading {
            ProgressView("Opening Bible…")
        } else {
            ReaderUnavailableView()
        }
    }

    private func foldLayout(in geometry: GeometryProxy) -> ReaderFoldLayout? {
        if #available(iOS 27.1, *) {
            let divisions = geometry.reservedRegions(kind: .division).filter(\.isActive).map { region in
                let frame = region.frame, margins = region.margins
                return CGRect(x: frame.minX - margins.leading, y: frame.minY - margins.top,
                              width: frame.width + margins.leading + margins.trailing,
                              height: frame.height + margins.top + margins.bottom)
            }
            return ReaderFoldLayout(size: geometry.size, divisions: divisions)
        }
        return nil
    }

    private var tabletopControls: some View {
        VStack(spacing: 20) {
            Text(state.reader.document?.reference ?? "")
                .font(.title2.weight(.semibold)).fontDesign(.serif)
            HStack(spacing: 24) {
                Button("Previous chapter", systemImage: "chevron.left") { state.reader.moveChapter(by: -1) }
                    .disabled(!state.reader.hasAdjacentChapter(-1))
                Button("Next chapter", systemImage: "chevron.right") { state.reader.moveChapter(by: 1) }
                    .disabled(!state.reader.hasAdjacentChapter(1))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .accessibilityIdentifier("tabletopReadingControls")
    }

    @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
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
                Section {
                    Button("Search", systemImage: "magnifyingglass") {
                        state.destination = .search
                        state.search.focusRequest += 1
                    }
                    Button("Previous chapter", systemImage: "chevron.left") { state.reader.moveChapter(by: -1) }
                        .disabled(!state.reader.hasAdjacentChapter(-1))
                    Button("Next chapter", systemImage: "chevron.right") { state.reader.moveChapter(by: 1) }
                        .disabled(!state.reader.hasAdjacentChapter(1))
                }
                Section {
                    Button("Undo annotation", systemImage: "arrow.uturn.backward") { Task { await state.reader.undo() } }
                        .disabled(!state.reader.canUndo || state.reader.isSaving)
                    if let document = state.reader.document {
                        Button("Chapter notes", systemImage: "note.text") {
                            state.reader.notesRequest = .chapter(document)
                        }
                        .disabled(!document.verses.contains { !$0.notes.isEmpty })
                        ShareLink(item: "\(document.reference) — \(document.editionLabel)") {
                            Label("Share reference", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                Button("About \(AppInfo.name)", systemImage: "info.circle") { state.isAboutPresented = true }
            }
        }
    }

}

#Preview { AppRootView() }
