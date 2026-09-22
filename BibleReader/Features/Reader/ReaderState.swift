import Observation
import Foundation

@MainActor
@Observable
final class ReaderState {
    // Only the active chapter is retained; the lightweight catalog contains no Scripture text.
    var typography = ReadingTypography()
    var editionNotice = ""
    var chapters: [ChapterDocument] = []
    var catalog: [ChapterSummary] = [] {
        didSet { catalogIndex = Dictionary(uniqueKeysWithValues: catalog.enumerated().map { ($0.element.id, $0.offset) }) }
    }
    private(set) var catalogIndex: [String: Int] = [:]
    func catalogChapter(_ id: String) -> ChapterSummary? { catalogIndex[id].map { catalog[$0] } }
    var books: [BookSummary] = []
    var chapterID: String?
    var highlights: [String: HighlightColor] = [:] { didSet { annotationsRevision += 1 } }
    var bookmarks: Set<String> = [] { didSet { annotationsRevision += 1 } }
    var exactAnnotations: [ExactAnnotation] {
        get {
            _ = annotationsRevision
            return exactByChapter.values.flatMap { $0 }.sorted { $0.id < $1.id }
        }
        set {
            exactByChapter = Dictionary(grouping: newValue, by: { $0.passage.chapterID })
            annotationsRevision += 1
        }
    }
    private(set) var annotationsRevision = 0
    @ObservationIgnored private var exactByChapter: [String: [ExactAnnotation]] = [:]
    @ObservationIgnored private var legacyHighlights: [HighlightRecord] = []
    @ObservationIgnored private var bookmarkCache: [String: (Int, Set<String>)] = [:]

    func exactAnnotations(in chapterID: String) -> [ExactAnnotation] {
        _ = annotationsRevision
        return exactByChapter[chapterID] ?? []
    }

    func bookmarkIndicators(in document: ChapterDocument) -> Set<String> {
        if let cached = bookmarkCache[document.id], cached.0 == annotationsRevision { return cached.1 }
        let verses = document.verses.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: verses.enumerated().map { ($0.element, $0.offset) })
        var marked = Set<String>()
        for bookmark in bookmarkRanges {
            if let start = index[bookmark.startID], let end = index[bookmark.endID], start <= end {
                marked.formUnion(verses[start...end])
            }
        }
        for record in exactAnnotations(in: document.id) where record.isBookmark {
            marked.formUnion(record.passage.verseIDs.filter { index[$0] != nil })
        }
        if bookmarkCache.count >= 6 { bookmarkCache.removeAll() }
        bookmarkCache[document.id] = (annotationsRevision, marked)
        return marked
    }
    var bookmarkRanges: [BookmarkRecord] = [] { didSet { annotationsRevision += 1 } }
    var savedItems: [SavedItem] = []
    var savedRevision = 0
    var savedLoadedRevision = -1
    var savedError: String?
    var isLoadingSaved = false
    var loadFailed = false
    var isLoading = true
    var isNavigating = false
    var isSaving = false
    var annotationEditingEnabled = true
    var errorMessage: String?
    private enum AnnotationRetry {
        case save(ExactPassage, HighlightColor?, Bool?)
        case refresh
        case undo
    }
    @ObservationIgnored private var savedRequest = UUID()
    @ObservationIgnored private var annotationRetry: AnnotationRetry?
    var canRetry: Bool { annotationRetry != nil || store == nil }
    var navigationRevision = 0
    var navigationCollapsed = false
    var navigationCue: Set<String> = []
    @ObservationIgnored private var cueTask: Task<Void, Never>?
    var canUndo = false
    @ObservationIgnored var selection: PassageSelection?
    @ObservationIgnored var anchor: ReadingAnchor? { didSet { if anchor != oldValue { schedulePositionSave() } } }
    @ObservationIgnored private var store: BibleStore?
    @ObservationIgnored private var positionTask: Task<Void, Never>?
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var navigationRequest = UUID()
    @ObservationIgnored private var holdUnresolvedPosition = false
    @ObservationIgnored private var undoHistory: [ReaderAnnotationChange] = []
    @ObservationIgnored private let makeStore: @Sendable () async throws -> BibleStore

    init(makeStore: @escaping @Sendable () async throws -> BibleStore = StoreLocation.open) {
        self.makeStore = makeStore
    }

    var highlightedChapterIDs: Set<String> {
        _ = annotationsRevision
        var ids = Set(exactByChapter.compactMap { key, records in records.contains { $0.color != nil } ? key : nil })
        // Legacy verse IDs follow the edition:book:chapter:verse identity contract.
        for verseID in highlights.keys {
            if let separator = verseID.lastIndex(of: ":") { ids.insert(String(verseID[..<separator])) }
        }
        return ids
    }

    var document: ChapterDocument? { chapters.first { $0.id == chapterID } }

    func summaryState(for chapter: ChapterDocument) -> ChapterSummaryState {
        let capturedStore = store
        return ChapterSummaryState(chapter: chapter, sources: { question in
            guard let capturedStore else { throw StorageIssue.invalidPassage }
            return try await capturedStore.summarySources(bookID: chapter.bookID, chapterID: chapter.id, question: question.question, preferred: question.preferred, preferredOnly: question.preferredOnly)
        })
    }

    func load() async {
        guard store == nil else { return }
        isLoading = true
        do {
            let opened = try await makeStore()
            let initialData = try await opened.readerBootstrap()
            let books = initialData.books, catalog = initialData.catalog, position = initialData.position
            try Task.checkCancellation()
            editionNotice = initialData.notice
            store = opened
            self.books = books
            self.catalog = catalog
            var initial = position?.chapterID ?? catalog.first?.id
            #if DEBUG
            if let requested = ProcessInfo.processInfo.environment["BIBLE_TEST_CHAPTER"], position == nil {
                initial = catalog.first { "\($0.bookID):\($0.label)" == requested }?.id ?? initial
            }
            #endif
            if let proposed = initial, catalogIndex[proposed] == nil {
                holdUnresolvedPosition = true
                initial = catalog.first?.id
                errorMessage = "Your saved chapter is unavailable in this edition. Its reference has been kept. Choose a chapter to continue."
            }
            guard let initial else { throw StorageIssue.incompatibleCorpus }
            let chapter = try await opened.chapter(initial)
            chapters = [chapter]
            chapterID = chapter.id
            anchor = holdUnresolvedPosition ? nil : position?.anchor
            try await refreshAnnotations()
            loadFailed = false
        } catch {
            loadFailed = true
            errorMessage = "Local reading data could not open. Your saved data has been kept. Unlock the device and try again."
            store = nil
        }
        isLoading = false
    }

    func navigate(to chapter: ChapterSummary, verseID: String? = nil, utf16Offset: Int = 0, cueVerseIDs: [String] = []) {
        guard let store else { return }
        flushPosition()
        navigationTask?.cancel()
        let request = UUID()
        navigationRequest = request
        isNavigating = true
        navigationTask = Task {
            defer { if request == navigationRequest { isNavigating = false } }
            do {
                let document = try await store.chapter(chapter.id)
                try Task.checkCancellation()
                guard request == navigationRequest else { return }
                holdUnresolvedPosition = false
                chapters = [document]
                chapterID = document.id
                selection = nil
                anchor = verseID.map { ReadingAnchor(text: VerseAnchor(verseID: $0, utf16Offset: utf16Offset), viewportY: 0.2) }
                navigationRevision += 1
                navigationCollapsed = false
                updateBookmarkIndicators()
                flushPosition()
                cueTask?.cancel()
                navigationCue = Set(cueVerseIDs)
                if !navigationCue.isEmpty {
                    cueTask = Task {
                        do {
                            try await Task.sleep(for: .seconds(2))
                            guard request == navigationRequest else { return }
                            navigationCue = []
                        } catch { }
                    }
                }
            } catch is CancellationError { } catch {
                errorMessage = "This chapter could not load. Your current passage and saved data have been kept."
            }
        }
    }

    func search(_ input: String, offset: Int = 0) async throws -> SearchResponse {
        guard let store else { throw StorageIssue.incompatibleCorpus }
        return try await store.search(input, offset: offset)
    }

    func lookupReference(_ input: String) async throws -> SearchResponse {
        guard let store else { throw StorageIssue.incompatibleCorpus }
        return try await store.lookupReference(input)
    }

    func openPassage(_ passage: ResolvedPassage) {
        guard let chapter = catalogChapter(passage.chapterID) else { return }
        navigate(to: chapter, verseID: passage.verseIDs.first, cueVerseIDs: passage.verseIDs)
    }

    func chapterForTurn(_ id: String) async throws -> ChapterDocument {
        guard let store else { throw StorageIssue.incompatibleCorpus }
        return try await store.chapter(id)
    }

    /// Commit only a completed native turn; a cancelled or stale turn never changes the store.
    func commitTurn(to document: ChapterDocument, from sourceID: String) {
        guard !isNavigating, chapterID == sourceID,
              let source = catalogIndex[sourceID],
              let target = catalogIndex[document.id], abs(target - source) == 1 else { return }
        flushPosition()
        navigationTask?.cancel()
        navigationRequest = UUID()
        cueTask?.cancel()
        holdUnresolvedPosition = false
        chapters = [document]
        chapterID = document.id
        selection = nil
        anchor = nil
        navigationRevision += 1
        navigationCue = []
        navigationCollapsed = false
        updateBookmarkIndicators()
        flushPosition()
    }

    func moveChapter(by amount: Int) {
        guard let index = chapterID.flatMap({ catalogIndex[$0] }), catalog.indices.contains(index + amount) else { return }
        navigate(to: catalog[index + amount])
    }

    func hasAdjacentChapter(_ amount: Int) -> Bool {
        guard let index = chapterID.flatMap({ catalogIndex[$0] }) else { return false }
        return catalog.indices.contains(index + amount)
    }

    func saveExact(_ passage: ExactPassage, color: HighlightColor?, bookmarkAction: Bool? = nil) async {
        guard annotationEditingEnabled, let store, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        // Preview uses the transaction's reducer; completed success/Undo/Saved wait for commit.
        var pending: ExactAnnotationChange?
        if let document, document.id == passage.chapterID {
            let ids = Set(passage.verseIDs)
            let before = exactAnnotations(in: passage.chapterID).filter { !$0.passage.parts.allSatisfy { !ids.contains($0.verseID) } }.sorted { $0.id < $1.id }
            let legacy = AnnotationSnapshot(highlights: legacyHighlights.filter { ids.contains($0.verseID) },
                bookmarks: bookmarkRanges.filter { $0.startID == passage.verseIDs.first && $0.endID == passage.verseIDs.last })
            pending = try? ExactAnnotationEditor.change(passage: passage, document: document, before: before,
                legacyBefore: legacy, color: color, bookmarkAction: bookmarkAction,
                edition: store.editionID, revision: store.revision, now: Date().timeIntervalSince1970, newID: UUID().uuidString)
            if let pending { apply(pending) }
        }
        do {
            let change = try await store.editExact(passage, color: color, bookmarkAction: bookmarkAction)
            if let pending { apply(pending, reversed: true) }
            apply(change)
            undoHistory.append(.exact(change))
            canUndo = true
            savedRevision += 1
            annotationRetry = nil
        } catch {
            if let pending { apply(pending, reversed: true) }
            annotationRetry = .save(passage, color, bookmarkAction)
            errorMessage = "The selected words in \(passage.reference) could not be saved. Your existing annotations have been kept. Retry to save this selection."
        }
    }

    private func apply(_ change: ExactAnnotationChange, reversed: Bool = false) {
        let removing = reversed ? change.after : change.before
        let inserting = reversed ? change.before : change.after
        let removed = Set(removing.map(\.id))
        let chapterID = change.verseIDs[0].split(separator: ":").dropLast().joined(separator: ":")
        var records = exactByChapter[chapterID] ?? []
        records.removeAll { removed.contains($0.id) }
        records.append(contentsOf: inserting)
        exactByChapter[chapterID] = records.sorted { $0.id < $1.id }
        annotationsRevision += 1
        let legacy = reversed ? change.legacyBefore : change.legacyAfter
        let ids = Set(change.verseIDs)
        legacyHighlights.removeAll { ids.contains($0.verseID) }
        legacyHighlights.append(contentsOf: legacy.highlights)
        for id in ids { highlights.removeValue(forKey: id) }
        for record in legacy.highlights { highlights[record.verseID] = record.color }
        bookmarkRanges.removeAll { $0.startID == change.verseIDs.first && $0.endID == change.verseIDs.last }
        bookmarkRanges.append(contentsOf: legacy.bookmarks)
        updateBookmarkIndicators()
    }

    func retry() async {
        let pending = annotationRetry
        errorMessage = nil
        switch pending {
        case .save(let passage, let color, let bookmark):
            await saveExact(passage, color: color, bookmarkAction: bookmark)
        case .refresh:
            guard !isSaving else { return }
            isSaving = true
            defer { isSaving = false }
            do { try await refreshAnnotations(); annotationRetry = nil }
            catch { errorMessage = "Your saved annotations could not refresh. Please try again." }
        case .undo: await undo()
        case nil: await load()
        }
    }

    func dismissError() {
        errorMessage = nil
        annotationRetry = nil
    }

    func isExactlyBookmarked(_ passage: ExactPassage) -> Bool {
        if exactAnnotations(in: passage.chapterID).contains(where: { $0.isBookmark && $0.passage.parts == passage.parts }) { return true }
        guard let document, passage.chapterID == document.id,
              passage.parts.allSatisfy({ part in
                  part.start == 0 && part.end == document.verses.first(where: { $0.id == part.verseID })?.text.utf16.count
              }) else { return false }
        return bookmarkRanges.contains { $0.startID == passage.verseIDs.first && $0.endID == passage.verseIDs.last }
    }

    func undo() async {
        guard let store, let lastChange = undoHistory.last, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch lastChange {
            case .legacy(let change): try await store.undo(change)
            case .exact(let change):
                try await store.undoExact(change)
                apply(change, reversed: true)
            }
            undoHistory.removeLast()
            canUndo = !undoHistory.isEmpty
        } catch {
            annotationRetry = .undo
            errorMessage = "Undo could not complete. Later changes and saved data have been kept."
            return
        }
        do {
            if case .legacy = lastChange { try await refreshAnnotations() }
            else { savedRevision += 1 }
            annotationRetry = nil
        } catch {
            annotationRetry = .refresh
            errorMessage = "Undo was saved, but the display could not refresh. Please try again."
        }
    }

    private func refreshAnnotations() async throws {
        guard let store else { return }
        let (snapshot, exact) = try await store.readerAnnotations()
        exactAnnotations = exact
        legacyHighlights = snapshot.highlights
        highlights = Dictionary(uniqueKeysWithValues: snapshot.highlights.map { ($0.verseID,$0.color) })
        bookmarkRanges = snapshot.bookmarks
        updateBookmarkIndicators()
        savedRevision += 1
    }

    func loadSavedItems() async {
        guard let store, savedLoadedRevision != savedRevision else { return }
        let revision = savedRevision
        let request = UUID()
        savedRequest = request
        isLoadingSaved = true
        savedError = nil
        defer { if request == savedRequest { isLoadingSaved = false } }
        do {
            let items = try await store.savedItems()
            try Task.checkCancellation()
            guard revision == savedRevision, request == savedRequest else { return }
            savedItems = items
            savedLoadedRevision = revision
        } catch is CancellationError { } catch {
            savedError = "Saved passages could not load. Your annotations have been kept. Try again."
        }
    }

    private func updateBookmarkIndicators() {
        bookmarks = document.map { bookmarkIndicators(in: $0) } ?? []
    }

    private func schedulePositionSave() {
        positionTask?.cancel()
        guard !holdUnresolvedPosition, let store, let chapterID else { return }
        let anchor = anchor
        positionTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                try await store.savePosition(chapterID: chapterID, anchor: anchor)
            } catch is CancellationError { } catch {
                errorMessage = "Your reading position could not be saved. Your annotations have been kept."
            }
        }
    }

    func flushPosition() {
        positionTask?.cancel()
        guard !holdUnresolvedPosition, let store, let chapterID else { return }
        let anchor = anchor
        positionTask = Task {
            do { try await store.savePosition(chapterID: chapterID, anchor: anchor) }
            catch is CancellationError { }
            catch { errorMessage = "Your reading position could not be saved. Please try again." }
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow, sage, blue, rose
    var id: Self { self }
    var assetName: String { "Highlight" + rawValue.capitalized }
}
