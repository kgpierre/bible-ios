import SwiftUI

struct AppRootView: View {
    @State private var state = AppState()
    @State private var sideSafeArea = EdgeInsets()
    @State private var sideUsableSize = CGSize.zero
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
                NavigationStack { ReaderUnavailableView(failure: ReaderOpenFailure(kind: .corpusUnavailable)) }
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
            // Read Aloud keeps playing in the background (audio background mode, plan §9.4).
            if phase != .active { state.reader.flushPosition(protectInBackground: true) }
            // A store that failed because the device was locked can open once the scene is active again.
            else if state.reader.openFailure?.kind == .locked, !state.reader.isLoading {
                Task { await state.reader.retry() }
            } else {
                // Narration that moved on while in the background brings the reader with it.
                state.reader.applyPendingNarrationFollow()
            }
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
            // A phone in landscape can be regular width but is compact in height: the system tab bar would
            // float over the text with the passage capsule stranded above it. Use the 2a bottom row there.
            if ReaderLayout.usesTopTabLayout(horizontalCompact: horizontalSizeClass != .regular,
                                             verticalCompact: verticalSizeClass == .compact) { regularLayout } else { compactLayout }
        }
        .background(Color(.readingCanvas))
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
        .sheet(item: $state.cardsRequest) { request in
            CardsSheet(request: request, model: state.cards) { state.cardsRequest = nil }
        }
        .onOpenURL { state.open($0) }
        .onChange(of: state.reader.isLoading) { _, loading in
            if !loading { state.openPendingLink() }
        }
        .sheet(isPresented: $state.isReadAloudSettingsPresented) {
            NavigationStack { NarrationSettingsView(narration: state.narration, showsCloseButton: true) }
                .presentationDetents([.medium, .large])
        }
        .alert("Read Aloud", isPresented: Binding(get: { narrationMessage != nil }, set: { if !$0 { dismissNarrationMessage() } })) {
            Button("OK", role: .cancel) { dismissNarrationMessage() }
        } message: { Text(narrationMessage ?? "") }
        // Magic Tap toggles Read Aloud only while it is active, so it never starts audio unexpectedly.
        .accessibilityAction(.magicTap) { if state.narration.status.isActive { state.narration.togglePlayPause() } }
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
        .alert(state.reader.errorTitle, isPresented: Binding(get: { state.reader.errorMessage != nil }, set: { if !$0 { state.reader.errorMessage = nil } })) {
            if state.reader.canRetry {
                Button("Retry") { Task { await state.reader.retry() } }
            }
            Button("OK", role: .cancel) { state.reader.dismissError() }
        } message: { Text(state.reader.errorMessage ?? "") }
    }

    /// Each destination keeps its own navigation stack and toolbar; reader actions appear only on Read.
    private var compactLayout: some View {
        ZStack {
            NavigationStack {
                chapter(wide: false, active: state.destination == .read)
                    .environment(state.narration)
                    .background(Color(.readingCanvas).ignoresSafeArea())
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar { readerToolbar }
            }
            .destination(.read, selected: state.destination)
            NavigationStack {
                SavedView(state: state)
            }
            .destination(.saved, selected: state.destination)
            NavigationStack {
                SearchView(state: state.search, active: state.destination == .search) { passage in
                    state.reader.openPassage(passage)
                    state.destination = .read
                }
            }
            .destination(.search, selected: state.destination)
        }
        .background(Color(.readingCanvas).ignoresSafeArea())
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { sideSafeArea = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { sideUsableSize = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sideRailWidth != nil {
                // Duo outer display: destinations and the passage control live in the side column,
                // so only Read Aloud's mini player needs a bottom band.
                SideNarrationInset(state: state)
            } else {
                CompactReaderNavigation(state: state)
                    // Landscape phones are short: let the text stop at the controls' top edge rather than
                    // scroll under them, so nothing is read through the glass at rest.
                    .background {
                        if verticalSizeClass == .compact { Color(.readingCanvas).ignoresSafeArea(.container, edges: .bottom) }
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let width = sideRailWidth {
                SideReaderNavigation(state: state, columnWidth: width)
                    .ignoresSafeArea(.container, edges: .trailing)
            }
        }
    }

    /// The trailing system column's width when the compact reader is on a presentation that stacks
    /// the status and toolbar at the side; nil for ordinary phones.
    private var sideRailWidth: CGFloat? {
        ReaderLayout.sideRailWidth(safeLeading: sideSafeArea.leading, safeTrailing: sideSafeArea.trailing,
                                   accessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                   verticalCompact: verticalSizeClass == .compact, usableSize: sideUsableSize)
    }

    private var regularLayout: some View {
        TabView(selection: $state.destination) {
            Tab(AppDestination.read.title, systemImage: AppDestination.read.symbol, value: AppDestination.read) {
                NavigationStack {
                    chapter(wide: true, active: state.destination == .read)
                        .environment(state.narration)
                        .background(Color(.readingCanvas).ignoresSafeArea())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.hidden, for: .navigationBar)
                        .toolbar { readerToolbar }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            // The passage selector floats at the bottom trailing corner, clear of
                            // the bounded reading column's start; text scrolls clear of it.
                            VStack(alignment: .trailing, spacing: 10) {
                                regularMiniPlayer
                                PassageButton(state: state)
                            }
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
                        .safeAreaInset(edge: .bottom, spacing: 0) { regularMiniPlayerInset }
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
                    .safeAreaInset(edge: .bottom, spacing: 0) { regularMiniPlayerInset }
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(Color(.accent))
    }

    /// Bottom trailing above the passage selector, like 0017's floating capsule. A Duo book or
    /// tabletop pose keeps it at the bottom: the right page and below the division.
    @ViewBuilder private var regularMiniPlayer: some View {
        if state.narration.status.isActive {
            NarrationMiniPlayer(narration: state.narration, isElsewhere: state.isNarrationElsewhere,
                                showReference: { state.showNarratedVerse() },
                                openSettings: { state.isReadAloudSettingsPresented = true })
                .frame(maxWidth: 440)
        }
    }

    @ViewBuilder private var regularMiniPlayerInset: some View {
        if state.narration.status.isActive {
            regularMiniPlayer
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    private var narrationMessage: String? {
        switch state.narration.status {
        case .failed(let message), .unavailable(let message): message
        default: state.narration.notice
        }
    }

    private func dismissNarrationMessage() {
        switch state.narration.status {
        case .failed, .unavailable: state.narration.stop()
        default: state.narration.notice = nil
        }
    }

    @ViewBuilder private func chapter(wide: Bool, active: Bool) -> some View {
        if let document = state.reader.document {
            GeometryReader { geometry in
                let fold = foldLayout(in: geometry)
                // Regular-width phones (including Duo's inner display) get the same reader as
                // iPad. Use the actual safe content area, never the device name or screen bounds.
                if wide, let fold, fold.supportsBookPages(minimumPageWidth: minimumBookPageWidth,
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
                    // Scrolling fallback with an active fold (accessibility text or
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ReaderUnavailableView(failure: state.reader.openFailure, retry: state.reader.canRetry ? { Task { await state.reader.retry() } } : nil)
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
                Button("Previous Chapter", systemImage: "chevron.left") { state.reader.moveChapter(by: -1) }
                    .disabled(!state.reader.hasAdjacentChapter(-1))
                Button("Next Chapter", systemImage: "chevron.right") { state.reader.moveChapter(by: 1) }
                    .disabled(!state.reader.hasAdjacentChapter(1))
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            // Read Aloud below the division with the chapter controls (plan §6.5).
            Button(tabletopReadAloudTitle, systemImage: tabletopReadAloudSymbol) { state.toggleReadAloud() }
                .accessibilityIdentifier("tabletopReadAloud")
                .buttonStyle(.glass)
            .controlSize(.large)
        }
        .accessibilityIdentifier("tabletopReadingControls")
    }

    private var tabletopReadAloudTitle: LocalizedStringKey {
        switch state.narration.status {
        case .playing, .preparing: "Pause"
        case .paused: "Resume"
        default: "Read Chapter Aloud"
        }
    }

    private var tabletopReadAloudSymbol: String {
        switch state.narration.status {
        case .playing, .preparing: "pause.fill"
        case .paused: "play.fill"
        default: "speaker.wave.2"
        }
    }

    @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { state.isAppearancePresented = true } label: { ToolbarGlyph(systemName: "textformat.size") }
                .accessibilityLabel("Appearance")
                .accessibilityIdentifier("appearanceButton")
                .popover(isPresented: $state.isAppearancePresented) {
                    // Offer the page layout from the live window, never the device idiom: regular width
                    // can fit facing pages (iPad, Duo inner display, large phones in landscape), and a
                    // foldable keeps it while closed. Book-pose facing pages need a hinge and are always on.
                    AppearanceView(preferences: state.preferences,
                                   showsPageLayout: AppearanceView.offersPageLayout(
                                       horizontalSizeClass: horizontalSizeClass, hasHinge: state.hasHinge),
                                   showsFoldOptions: state.hasHinge,
                                   narration: state.narration)
                        .frame(idealWidth: 400, idealHeight: 560)
                        .presentationCompactAdaptation(.sheet)
                        // Leave the reader visible above the sheet so changes show as they are made.
                        .presentationDetents([.medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
            Button {
                state.summarizeCurrentChapter()
            } label: {
                ToolbarGlyph(systemName: "apple.intelligence")
            }
            .accessibilityLabel("Summarize current chapter")
            .accessibilityIdentifier("chapterSummaryButton")
            .disabled(state.reader.document == nil || state.reader.isLoading)
            let saved = state.reader.isCurrentChapterSaved
            Button {
                Task { await state.reader.setCurrentChapterSaved(!saved) }
            } label: {
                ToolbarGlyph(systemName: saved ? "bookmark.fill" : "bookmark")
            }
            .accessibilityLabel(saved ? "Remove Saved Chapter" : "Save Chapter")
            .accessibilityIdentifier("saveChapterButton")
            .disabled(state.reader.document == nil || state.reader.isLoading || state.reader.isSaving)
            Menu {
                Section {
                    Button("Previous Chapter", systemImage: "chevron.left") { state.reader.moveChapter(by: -1) }
                        .disabled(!state.reader.hasAdjacentChapter(-1))
                    Button("Next Chapter", systemImage: "chevron.right") { state.reader.moveChapter(by: 1) }
                        .disabled(!state.reader.hasAdjacentChapter(1))
                    if state.narration.status.isActive {
                        Button("Stop Reading Aloud", systemImage: "stop.fill") { state.narration.stop() }
                            .accessibilityIdentifier("stopReadAloud")
                    } else {
                        Button("Read Chapter Aloud", systemImage: "speaker.wave.2") { state.readCurrentChapterAloud() }
                            .disabled(state.reader.document == nil || state.reader.isLoading)
                            .accessibilityIdentifier("readChapterAloud")
                    }
                }
                Section {
                    Button(state.reader.undoActionName.map { String(localized: "Undo \($0)") } ?? String(localized: "Undo"),
                           systemImage: "arrow.uturn.backward") { Task { await state.reader.undo() } }
                        .disabled(!state.reader.canUndo || state.reader.isSaving)
                        .accessibilityIdentifier("undoAnnotation")
                    if let document = state.reader.document {
                        Button("Chapter Notes", systemImage: "note.text") {
                            state.reader.notesRequest = .chapter(document)
                        }
                        .disabled(!document.verses.contains { !$0.notes.isEmpty })
                        ShareLink(item: "\(document.reference) — \(document.editionLabel)") {
                            Label("Share Reference", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                Button("About \(AppInfo.name)", systemImage: "info.circle") { state.isAboutPresented = true }
            } label: {
                ToolbarGlyph(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

}

/// A reader toolbar icon in a fixed slot. Glyphs differ in width (the ribbon is narrow, "AA" is
/// wide), so equal slots space the group's icons evenly instead of by each glyph's own width.
private struct ToolbarGlyph: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .frame(width: 30, height: 24)
    }
}

private extension View {
    /// Shows one compact destination; hidden ones keep their state but leave touch and VoiceOver.
    func destination(_ destination: AppDestination, selected: AppDestination) -> some View {
        opacity(selected == destination ? 1 : 0)
            // Hidden stacks host UIKit navigation controllers; keep the selected one frontmost
            // so their transparent bars can never intercept its touches.
            .zIndex(selected == destination ? 1 : 0)
            .allowsHitTesting(selected == destination)
            .accessibilityHidden(selected != destination)
    }
}

#Preview {
    // About reads the app-owned TipStore; a non-observing store keeps the preview off StoreKit.
    AppRootView().environment(TipStore(observeTransactions: false))
}
