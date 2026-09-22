import Observation
import Foundation

@MainActor
@Observable
final class ReaderState {
    // Only the active chapter is retained; the lightweight catalog contains no Scripture text.
    var typography = ReadingTypography()
    var editionNotice = ""
    var chapters: [ChapterDocument] = []
    var catalog: [ChapterSummary] = []
    var books: [BookSummary] = []
    var chapterID: String?
    var highlights: [String: HighlightColor] = [:]
    var bookmarks: Set<String> = []
    var exactAnnotations: [ExactAnnotation] = []
    var bookmarkRanges: [BookmarkRecord] = []
    var savedItems: [SavedItem] = []
    var loadFailed = false
    var isLoading = true
    var isSaving = false
    var annotationEditingEnabled = true
    var errorMessage: String?
    private enum AnnotationRetry {
        case save(ExactPassage, HighlightColor?, Bool?)
        case refresh
        case undo
    }
    @ObservationIgnored private var annotationRetry: AnnotationRetry?
    var canRetry: Bool { annotationRetry != nil || store == nil }
    var navigationRevision = 0
    var navigationCollapsed = false
    var navigationCue: Set<String> = []
    @ObservationIgnored private var cueTask: Task<Void, Never>?
    var canUndo = false
    @ObservationIgnored var selection: PassageSelection?
    @ObservationIgnored var anchor: ReadingAnchor? { didSet { schedulePositionSave() } }
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

    var document: ChapterDocument? { chapters.first { $0.id == chapterID } }

    func load() async {
        guard store == nil else { return }
        isLoading = true
        do {
            let opened = try await makeStore()
            let books = try await opened.books()
            let catalog = try await opened.chapters()
            let position = try await opened.position()
            try Task.checkCancellation()
            editionNotice = try await opened.editionNotice()
            store = opened
            self.books = books
            self.catalog = catalog
            var initial = position?.chapterID ?? catalog.first?.id
            #if DEBUG
            if let requested = ProcessInfo.processInfo.environment["BIBLE_TEST_CHAPTER"], position == nil {
                initial = catalog.first { "\($0.bookID):\($0.label)" == requested }?.id ?? initial
            }
            #endif
            if let proposed = initial, !catalog.contains(where: { $0.id == proposed }) {
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
        navigationTask = Task {
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
        guard let chapter = catalog.first(where: { $0.id == passage.chapterID }) else { return }
        navigate(to: chapter, verseID: passage.verseIDs.first, cueVerseIDs: passage.verseIDs)
    }

    #if DEBUG
    func chapterForExperiment(_ id: String) async throws -> ChapterDocument {
        guard let store else { throw StorageIssue.incompatibleCorpus }
        return try await store.chapter(id)
    }
    #endif

    func moveChapter(by amount: Int) {
        guard let index = catalog.firstIndex(where: { $0.id == chapterID }), catalog.indices.contains(index + amount) else { return }
        navigate(to: catalog[index + amount])
    }

    func hasAdjacentChapter(_ amount: Int) -> Bool {
        guard let index = catalog.firstIndex(where: { $0.id == chapterID }) else { return false }
        return catalog.indices.contains(index + amount)
    }

    func saveExact(_ passage: ExactPassage, color: HighlightColor?, bookmarkAction: Bool? = nil) async {
        guard annotationEditingEnabled, let store, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let change = try await store.editExact(passage, color: color, bookmarkAction: bookmarkAction)
            undoHistory.append(.exact(change))
            canUndo = true
        } catch {
            annotationRetry = .save(passage, color, bookmarkAction)
            errorMessage = "The selected words in \(passage.reference) could not be saved. Your existing annotations have been kept. Retry to save this selection."
            return
        }
        do {
            try await refreshAnnotations()
            annotationRetry = nil
        } catch {
            annotationRetry = .refresh
            errorMessage = "Your annotation was saved, but the display could not refresh. Retry to show the saved change."
        }
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
        if exactAnnotations.contains(where: { $0.isBookmark && $0.passage.parts == passage.parts }) { return true }
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
            case .exact(let change): try await store.undoExact(change)
            }
            undoHistory.removeLast()
            canUndo = !undoHistory.isEmpty
        } catch {
            annotationRetry = .undo
            errorMessage = "Undo could not complete. Later changes and saved data have been kept."
            return
        }
        do {
            try await refreshAnnotations()
            annotationRetry = nil
        } catch {
            annotationRetry = .refresh
            errorMessage = "Undo was saved, but the display could not refresh. Please try again."
        }
    }

    private func refreshAnnotations() async throws {
        guard let store else { return }
        let snapshot = try await store.annotations()
        exactAnnotations = try await store.exactAnnotations()
        highlights = Dictionary(uniqueKeysWithValues: snapshot.highlights.map { ($0.verseID,$0.color) })
        bookmarkRanges = snapshot.bookmarks
        updateBookmarkIndicators()
        savedItems = try await store.savedItems()
    }

    private func updateBookmarkIndicators() {
        let verses = document?.verses.map(\.id) ?? []
        var marked = Set<String>()
        for bookmark in bookmarkRanges {
            if let start = verses.firstIndex(of: bookmark.startID), let end = verses.firstIndex(of: bookmark.endID), start <= end {
                marked.formUnion(verses[start...end])
            }
        }
        for record in exactAnnotations where record.isBookmark {
            marked.formUnion(record.passage.verseIDs.filter { verses.contains($0) })
        }
        bookmarks = marked
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
            catch { errorMessage = "Your reading position could not be saved. Please try again." }
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow, sage, blue, rose
    var id: Self { self }
    var assetName: String { "Highlight" + rawValue.capitalized }
}
