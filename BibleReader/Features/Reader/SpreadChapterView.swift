import SwiftUI
import UIKit

/// Wide landscape "Two Pages": facing book pages on iPad and regular-width phones.
///
/// Each page is an ordinary `ChapterTextView` holding a slice of the chapter's verses, so
/// selection, highlights, bookmarks, notes, copy, and VoiceOver behave as in the scrolling
/// reader, except that a selection stays within one page. Page breaks fall between verses and
/// come from measuring the whole chapter at page size. The spread records the first verse of
/// its left page as the reading anchor, so scroll mode and relaunch resume at the same verse.
struct SpreadChapterView: UIViewControllerRepresentable {
    let document: ChapterDocument
    let state: ReaderState
    var chromeInsets = EdgeInsets()
    var innerPageInset: CGFloat = 0
    var isActive = true
    @Environment(\.colorScheme) fileprivate var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) fileprivate var scenePhase

    /// Same policy as the scrolling reader: assistive settings turn pages without the curl.
    fileprivate var animated: Bool {
        !reduceMotion && !reduceTransparency && contrast != .increased && !voiceOver
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIViewController(context: Context) -> SpreadContainer {
        let container = SpreadContainer()
        context.coordinator.attach(container)
        return container
    }

    func updateUIViewController(_ container: SpreadContainer, context: Context) {
        container.touchRegion.chromeInsets = chromeInsets
        context.coordinator.update(self)
    }

    static func dismantleUIViewController(_ container: SpreadContainer, coordinator: Coordinator) {
        coordinator.detach()
    }

    struct PageKey: Hashable {
        let chapterID: String
        let index: Int
    }

    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        let state: ReaderState
        private weak var container: SpreadContainer?
        private var configuration: SpreadChapterView?
        private var layoutKey: LayoutKey?
        private var paginations: [String: ChapterPagination] = [:]
        /// Full chapters for the current chapter and its neighbors.
        private var documents: [String: ChapterDocument] = [:]
        private var controllers: [PageKey: SpreadPageController] = [:]
        /// The left page of the spread on screen.
        private var displayed: PageKey?
        private var shownRevision = -1
        private var turning = false
        private var turnSource: String?
        private var preload: Task<Void, Never>?
        private var preparedID: String?
        /// Typography-only state for measuring; never the live reader.
        private let measuringState: ReaderState = {
            let state = ReaderState()
            state.annotationEditingEnabled = false
            return state
        }()
        private let haptics = UIImpactFeedbackGenerator(style: .soft)
        private lazy var swipe: ChapterSwipeRecognizer = {
            let gesture = ChapterSwipeRecognizer(target: self, action: #selector(swiped(_:)))
            gesture.delegate = self
            gesture.cancelsTouchesInView = false
            return gesture
        }()

        private struct LayoutKey: Equatable {
            let size: CGSize
            let insets: EdgeInsets
            let typography: ReadingTypography
            let category: UIContentSizeCategory
            let scheme: ColorScheme
            let innerPageInset: CGFloat
        }

        init(state: ReaderState) { self.state = state }

        private var pager: UIPageViewController? { container?.pager }
        private var curlPan: UIPanGestureRecognizer? {
            pager?.gestureRecognizers.first { $0 is UIPanGestureRecognizer } as? UIPanGestureRecognizer
        }
        private var visiblePages: [SpreadPageController] {
            pager?.viewControllers?.compactMap { $0 as? SpreadPageController } ?? []
        }

        func attach(_ container: SpreadContainer) {
            self.container = container
            let pager = container.pager
            pager.dataSource = self
            pager.delegate = self
            for recognizer in pager.gestureRecognizers {
                recognizer.delegate = self
                // Taps select words and open notes; only a deliberate drag turns a page.
                if recognizer is UITapGestureRecognizer { recognizer.isEnabled = false }
            }
            // A mid-spine pager must hold two pages before it appears, which can precede the
            // first sized layout. Blank paper stands in until pagination has a page size.
            pager.setViewControllers([SpreadPageController(key: PageKey(chapterID: "", index: 0), page: nil),
                                      SpreadPageController(key: PageKey(chapterID: "", index: 1), page: nil)],
                                     direction: .forward, animated: false)
            container.view.addGestureRecognizer(swipe)
            container.didLayout = { [weak self] in self?.refresh() }
            container.turn = { [weak self] delta in self?.turn(by: delta) ?? false }
        }

        func detach() {
            preload?.cancel()
            swipe.isEnabled = false
            curlPan?.isEnabled = false
            pager?.dataSource = nil
            pager?.delegate = nil
            state.flushPosition()
        }

        private func refresh() {
            if let configuration { update(configuration) }
        }

        func update(_ configuration: SpreadChapterView) {
            self.configuration = configuration
            guard let container else { return }
            container.view.backgroundColor = UIColor(resource: .readingCanvas)
            let size = container.view.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let key = LayoutKey(size: size, insets: configuration.chromeInsets, typography: state.typography,
                                category: container.traitCollection.preferredContentSizeCategory, scheme: configuration.scheme,
                                innerPageInset: configuration.innerPageInset)
            // Never replace pages under a live curl; the turn's completion refreshes.
            guard !curling else { return }
            let relayout = key != layoutKey
            if relayout {
                layoutKey = key
                paginations = [:]
                controllers = [:]
            }
            let document = state.document ?? configuration.document
            documents[document.id] = document
            let target: PageKey
            if let displayed, displayed.chapterID == document.id, state.navigationRevision == shownRevision, !relayout {
                target = displayed
            } else {
                target = spreadStart(for: document)
            }
            if target != displayed || relayout || visiblePages.first?.key.chapterID != target.chapterID { show(target, direction: .forward, animated: false) }
            shownRevision = state.navigationRevision
            configurePages()
            prepareNeighbors()
            updateGestures()
        }

        // MARK: Pagination

        private var pageSize: CGSize {
            guard let bounds = container?.view.bounds.size else { return .zero }
            return CGSize(width: floor(bounds.width / 2), height: bounds.height)
        }

        private func pagination(for document: ChapterDocument) -> ChapterPagination {
            if let cached = paginations[document.id] { return cached }
            guard let container, let configuration else {
                return ChapterPagination(verseEnds: [], contentEnd: 0, firstPageHeight: 1, pageHeight: 1)
            }
            let measurer = container.measurer
            measurer.frame = CGRect(origin: .zero, size: pageSize)
            measurer.paged = true
            measurer.pageInnerInset = configuration.innerPageInset
            measurer.showsHeader = true
            measurer.chromeInsets = configuration.chromeInsets
            measuringState.typography = state.typography
            measuringState.chapters = [document]
            measuringState.chapterID = document.id
            measurer.configure(document: document, state: measuringState, wide: true, scheme: configuration.scheme)
            measurer.layoutIfNeeded()
            let firstHeight = measurer.pageTextHeight
            let ends = measurer.measuredVerseEnds() ?? (verses: [], content: 0)
            measurer.showsHeader = false
            measurer.layoutIfNeeded()
            let laterHeight = measurer.pageTextHeight
            measurer.showsHeader = true
            // A few points of slack absorb paragraph spacing at a page's foot.
            let pagination = ChapterPagination(verseEnds: ends.verses, contentEnd: ends.content,
                                               firstPageHeight: firstHeight - 4, pageHeight: laterHeight - 4)
            paginations[document.id] = pagination
            return pagination
        }

        /// Chapters always open on a left page, so odd page counts end with a blank right page.
        private func pageCount(_ chapterID: String) -> Int? {
            guard let document = documents[chapterID] else { return nil }
            let count = pagination(for: document).pages.count
            return count + count % 2
        }

        private func spreadStart(for document: ChapterDocument) -> PageKey {
            let pagination = pagination(for: document)
            let verse = state.anchor.flatMap { anchor in document.verses.firstIndex { $0.id == anchor.text.verseID } }
            let page = verse.map { pagination.page(containingVerse: $0) } ?? 0
            return PageKey(chapterID: document.id, index: page - page % 2)
        }

        // MARK: Page sequence (never wraps at Genesis 1 or Revelation 22)

        private func key(after key: PageKey) -> PageKey? {
            guard let count = pageCount(key.chapterID) else { return nil }
            if key.index + 1 < count { return PageKey(chapterID: key.chapterID, index: key.index + 1) }
            guard let next = adjacent(1, to: key.chapterID), pageCount(next) != nil else { return nil }
            return PageKey(chapterID: next, index: 0)
        }

        private func key(before key: PageKey) -> PageKey? {
            if key.index > 0 { return PageKey(chapterID: key.chapterID, index: key.index - 1) }
            guard let previous = adjacent(-1, to: key.chapterID), let count = pageCount(previous) else { return nil }
            return PageKey(chapterID: previous, index: count - 1)
        }

        private func adjacent(_ delta: Int, to id: String) -> String? {
            guard let index = state.catalogIndex[id], state.catalog.indices.contains(index + delta) else { return nil }
            return state.catalog[index + delta].id
        }

        /// Load and paginate the neighboring chapters before a turn reaches them, one per
        /// main-actor turn, so a curl never waits on TextKit layout of the next chapter.
        private func prepareNeighbors() {
            guard !turning, let current = state.chapterID, preparedID != current else { return }
            preparedID = current
            preload?.cancel()
            let ids = [adjacent(-1, to: current), current, adjacent(1, to: current)].compactMap { $0 }
            controllers = controllers.filter { ids.contains($0.key.chapterID) }
            documents = documents.filter { ids.contains($0.key) }
            paginations = paginations.filter { ids.contains($0.key) }
            preload = Task { [weak self] in
                guard let self else { return }
                do {
                    for id in ids where self.documents[id] == nil {
                        let document = try await self.state.chapterForTurn(id)
                        try Task.checkCancellation()
                        guard self.state.chapterID == current else { return }
                        self.documents[id] = document
                    }
                    for id in ids where id != current {
                        await Task.yield()
                        try Task.checkCancellation()
                        guard self.state.chapterID == current, !self.turning, let document = self.documents[id] else { return }
                        _ = self.pagination(for: document)
                    }
                    self.updateGestures()
                } catch is CancellationError { } catch {
                    // Turning simply stops at this chapter; explicit navigation still reports errors.
                    self.preparedID = nil
                }
            }
        }

        private func controller(for key: PageKey) -> SpreadPageController {
            if let cached = controllers[key] { return cached }
            let controller: SpreadPageController
            if let document = documents[key.chapterID] {
                let pagination = pagination(for: document)
                if pagination.pages.indices.contains(key.index) {
                    let last = key.index == pagination.pages.count - 1
                    let page = ChapterPageController(document: document.page(pagination.pages[key.index],
                        includesTrailingBlocks: last && pagination.trailingOnLastPage))
                    page.textView.paged = true
                    page.textView.showsHeader = key.index == 0
                    page.textView.selectionDidChange = { [weak self] in self?.updateGestures() }
                    controller = SpreadPageController(key: key, page: page)
                } else {
                    controller = SpreadPageController(key: key, page: nil)
                }
            } else {
                controller = SpreadPageController(key: key, page: nil)
            }
            controllers[key] = controller
            configure(controller)
            return controller
        }

        private func configure(_ controller: SpreadPageController) {
            guard let configuration, let page = controller.page else { return }
            page.textView.pageInnerInset = configuration.innerPageInset
            page.textView.isLeftSpreadPage = controller.key.index % 2 == 0
            let live = controller.key.chapterID == state.chapterID
            page.configure(from: state, live: live, wide: true, scheme: configuration.scheme, insets: configuration.chromeInsets)
            let side = controller.key.index % 2 == 0 ? "Left" : "Right"
            page.textView.accessibilityIdentifier = live ? "spreadPage\(side)" : "adjacentSpreadPage"
        }

        private func configurePages() {
            controllers.values.forEach(configure)
        }

        // MARK: Turning

        private func show(_ key: PageKey, direction: UIPageViewController.NavigationDirection, animated: Bool,
                          completion: ((Bool) -> Void)? = nil) {
            guard let pager, !curling || animated else { return }
            let left = controller(for: key)
            let right = controller(for: PageKey(chapterID: key.chapterID, index: key.index + 1))
            pager.setViewControllers([left, right], direction: direction, animated: animated, completion: completion)
            displayed = key
        }

        /// Adopt the spread on screen: commit a chapter change and record the reading anchor.
        private func didShow(_ key: PageKey, from source: String?) {
            displayed = key
            if key.chapterID != state.chapterID {
                guard let source, let document = documents[key.chapterID] else { return }
                state.commitTurn(to: document, from: source)
                guard state.chapterID == document.id else {
                    // A rejected turn returns to the reader's canonical chapter.
                    if let current = state.document { show(spreadStart(for: current), direction: .forward, animated: false) }
                    return
                }
                haptics.impactOccurred(intensity: 0.7)
            }
            if let document = documents[key.chapterID] {
                let pagination = pagination(for: document)
                let range = pagination.pages.indices.contains(key.index) ? pagination.pages[key.index] : nil
                let verse = range.flatMap { $0.isEmpty ? nil : document.verses[$0.lowerBound] } ?? document.verses.last
                if let verse { state.anchor = ReadingAnchor(text: VerseAnchor(verseID: verse.id, utf16Offset: 0), viewportY: 0.1) }
            }
            shownRevision = state.navigationRevision
            announcePage()
        }

        /// The left page of the neighboring spread, when both of its pages are ready.
        /// A neighbor chapter still loading counts as not ready.
        private func spread(_ delta: Int) -> PageKey? {
            guard let displayed else { return nil }
            if delta > 0 {
                // Page counts are even, so a left page always has its right page.
                return key(after: PageKey(chapterID: displayed.chapterID, index: displayed.index + 1))
            }
            guard let right = key(before: displayed), let left = key(before: right) else { return nil }
            return left
        }

        /// A finger-driven curl counts from the moment its pan begins, before UIKit reports a
        /// transition: pages must not change and the pan must not be toggled underneath it.
        private var curling: Bool {
            guard !turning else { return true }
            guard let state = curlPan?.state else { return false }
            return state == .began || state == .changed
        }

        @discardableResult
        private func turn(by delta: Int) -> Bool {
            guard turnsAllowed, let configuration, let target = spread(delta) else { return false }
            let source = state.chapterID
            let direction: UIPageViewController.NavigationDirection = delta > 0 ? .forward : .reverse
            if configuration.animated {
                turning = true
                show(target, direction: direction, animated: true) { [weak self] _ in
                    guard let self else { return }
                    self.turning = false
                    self.didShow(target, from: source)
                    self.settle()
                }
            } else {
                show(target, direction: direction, animated: false)
                didShow(target, from: source)
                settle()
            }
            return true
        }

        private func settle() {
            configurePages()
            prepareNeighbors()
            updateGestures()
            refresh()
        }

        @objc private func swiped(_ gesture: ChapterSwipeRecognizer) {
            guard gesture.state == .recognized else { return }
            turn(by: gesture.chapterDelta)
        }

        private func announcePage() {
            guard UIAccessibility.isVoiceOverRunning, let displayed, let count = pageCount(displayed.chapterID),
                  let document = documents[displayed.chapterID] else { return }
            let message = String(localized: "\(document.reference), pages \(displayed.index + 1) and \(displayed.index + 2) of \(count)")
            UIAccessibility.post(notification: .pageScrolled, argument: message)
        }

        // MARK: UIPageViewController (spine in the middle: left, right, next left, …)

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? SpreadPageController, let key = key(before: page.key) else { return nil }
            return controller(for: key)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? SpreadPageController, let key = key(after: page.key) else { return nil }
            return controller(for: key)
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            turning = true
            turnSource = state.chapterID
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            turning = false
            let source = turnSource
            turnSource = nil
            if completed, let left = visiblePages.first { didShow(left.key, from: source) }
            settle()
        }

        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            .mid
        }

        // MARK: Gestures

        private var turnsAllowed: Bool {
            guard let configuration, configuration.isActive, configuration.scenePhase == .active, !curling,
                  !state.isSaving, !state.isNavigating else { return false }
            return visiblePages.allSatisfy { ($0.page?.textView.selectedRange.length ?? 0) == 0 }
        }

        private func updateGestures() {
            // Disabling the pan mid-drag makes UIKit cancel the curl with no pages (a crash).
            guard let configuration, !curling else { return }
            swipe.isEnabled = turnsAllowed && !configuration.animated
            curlPan?.isEnabled = turnsAllowed && configuration.animated
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard turnsAllowed, let view = container?.touchRegion else { return false }
            return view.point(inside: touch.location(in: view), with: nil)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard turnsAllowed else { return false }
            guard gestureRecognizer === curlPan, let pan = curlPan else { return true }
            // Begin only on a clearly horizontal drag; selection drags and vertical scrolls stay native.
            let travel = pan.translation(in: pan.view), velocity = pan.velocity(in: pan.view)
            guard abs(travel.x) >= abs(travel.y) * 2, abs(velocity.x) >= abs(velocity.y) * 1.5 else { return false }
            // UIKit needs both pages of the destination spread for a middle-spine curl; a curl it
            // cannot complete would later be cancelled with none. Start only when they exist.
            guard spread(travel.x < 0 ? 1 : -1) != nil else { return false }
            haptics.prepare()
            return true
        }
    }
}

/// One page of the spread: a chapter slice, or blank paper after a chapter's last page.
@MainActor final class SpreadPageController: UIViewController {
    let key: SpreadChapterView.PageKey
    let page: ChapterPageController?

    init(key: SpreadChapterView.PageKey, page: ChapterPageController?) {
        self.key = key
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(key:page:)") }

    override func loadView() {
        view = UIView()
        view.backgroundColor = UIColor(resource: .readingCanvas)
        guard let page else {
            view.isAccessibilityElement = false
            return
        }
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(page.view)
        page.didMove(toParent: self)
    }
}

@MainActor final class SpreadContainer: UIViewController {
    let pager: UIPageViewController = {
        let pager = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue])
        pager.isDoubleSided = true
        return pager
    }()
    let touchRegion = SpreadTouchRegion()
    /// Lays out whole chapters at page size to find page breaks. It lives in the hierarchy,
    /// hidden, so its fonts resolve with the same Dynamic Type traits as the visible pages.
    let measurer = ChapterTextView()
    var didLayout: (() -> Void)?
    var turn: ((Int) -> Bool)?
    private var lastSize = CGSize.zero

    override func loadView() {
        view = touchRegion
        touchRegion.accessibilityIdentifier = "spreadContainer"
        touchRegion.onScroll = { [weak self] delta in self?.turn?(delta) ?? false }
        measurer.isHidden = true
        measurer.isUserInteractionEnabled = false
        measurer.accessibilityElementsHidden = true
        measurer.accessibilityIdentifier = "spreadMeasurer"
        touchRegion.addSubview(measurer)
        addChild(pager)
        touchRegion.addSubview(pager.view)
        pager.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pager.view.frame = view.bounds
        if view.bounds.size != lastSize {
            lastSize = view.bounds.size
            didLayout?()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        let next = UIKeyCommand(title: String(localized: "Next Page"), action: #selector(nextPage), input: UIKeyCommand.inputRightArrow)
        let previous = UIKeyCommand(title: String(localized: "Previous Page"), action: #selector(previousPage), input: UIKeyCommand.inputLeftArrow)
        next.wantsPriorityOverSystemBehavior = true
        previous.wantsPriorityOverSystemBehavior = true
        return [previous, next]
    }
    @objc private func nextPage() { _ = turn?(1) }
    @objc private func previousPage() { _ = turn?(-1) }
}

/// Passes touches in the floating-chrome bands through to the controls above, and turns
/// pages for VoiceOver's three-finger scroll.
@MainActor final class SpreadTouchRegion: UIView {
    var chromeInsets = EdgeInsets()
    var onScroll: ((Int) -> Bool)?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard point.y >= bounds.minY + chromeInsets.top, point.y < bounds.maxY - chromeInsets.bottom else { return false }
        return super.point(inside: point, with: event)
    }
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .left, .next: onScroll?(1) ?? false
        case .right, .previous: onScroll?(-1) ?? false
        default: false
        }
    }
}
