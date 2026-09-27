import SwiftUI
import UIKit
import os

/// Chapter-sized native turns. The continuous text view still owns selection and vertical scrolling.
struct PaperChapterView: UIViewControllerRepresentable {
    let document: ChapterDocument
    let state: ReaderState
    let wide: Bool
    var chromeInsets = EdgeInsets()
    var isActive = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicType

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var animated: Bool {
        !reduceMotion && !reduceTransparency && contrast != .increased && !voiceOver
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeUIViewController(context: Context) -> ChapterTurnContainer {
        let host = ChapterTurnContainer()
        let controller = host.pager
        let coordinator = context.coordinator
        controller.delegate = coordinator
        controller.dataSource = coordinator
        coordinator.controller = controller
        // UIKit's own curl recognizers are public; the pan is gated on horizontal intent and
        // taps never turn (owner report: edge taps and ordinary scrolling must not curl).
        for recognizer in controller.gestureRecognizers {
            recognizer.delegate = coordinator
            if recognizer is UITapGestureRecognizer { recognizer.isEnabled = false }
        }
        controller.view.addGestureRecognizer(coordinator.turnGesture)
        controller.willResize = { [weak coordinator] in coordinator?.cancelTurn() }
        return host
    }
    func updateUIViewController(_ host: ChapterTurnContainer, context: Context) {
        host.touchRegion.chromeInsets = chromeInsets
        context.coordinator.update(self)
        host.trackScrollEdges()
    }
    static func dismantleUIViewController(_ host: ChapterTurnContainer, coordinator: Coordinator) {
        let controller = host.pager
        coordinator.turnGesture.isEnabled = false
        coordinator.curlPan?.isEnabled = false
        coordinator.preload?.cancel()
        coordinator.generation = UUID()
        coordinator.active?.textView.capturePosition()
        coordinator.active?.textView.resignFirstResponder()
        controller.delegate = nil
        controller.dataSource = nil
    }

    /// Two ways to turn a chapter:
    /// - With motion allowed, UIKit's interactive curl follows the finger once a drag is clearly
    ///   horizontal, and the chapter commits only when the curl completes.
    /// - With Reduce Motion, Reduce Transparency, Increase Contrast, or VoiceOver, a discrete
    ///   swipe replaces the chapter immediately.
    @MainActor final class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource, UIGestureRecognizerDelegate {
        let state: ReaderState
        weak var controller: UIPageViewController?
        lazy var turnGesture: ChapterSwipeRecognizer = {
            let gesture = ChapterSwipeRecognizer(target: self, action: #selector(turnChapter(_:)))
            gesture.delegate = self
            gesture.cancelsTouchesInView = false
            return gesture
        }()
        var curlPan: UIPanGestureRecognizer? {
            controller?.gestureRecognizers.first { $0 is UIPanGestureRecognizer } as? UIPanGestureRecognizer
        }
        var pages: [String: ChapterPageController] = [:]
        private var backs: [String: PaperBackController] = [:]
        var documents: [String: ChapterDocument] = [:]
        var preload: Task<Void, Never>?
        var generation = UUID()
        var preparedID: String?
        var sourceID: String?
        var turnRevision = 0
        var renderedTypography: ReadingTypography?
        var turning = false
        /// A finger-driven curl owned by UIKit; it ends in `didFinishAnimating`, never in a completion block.
        private var interactive = false
        private var interactiveGeneration = UUID()
        private let haptics = UIImpactFeedbackGenerator(style: .soft)
        private var turnInterval: OSSignpostIntervalState?
        var configuration: PaperChapterView?
        var active: ChapterPageController? { controller?.viewControllers?.first as? ChapterPageController }
        init(state: ReaderState) { self.state = state }

        func update(_ configuration: PaperChapterView) {
            guard let controller else { return }
            let previous = self.configuration
            let typographyChanged = renderedTypography != nil && renderedTypography != state.typography
            renderedTypography = state.typography
            self.configuration = configuration
            controller.view.backgroundColor = UIColor(resource: .readingCanvas)
            if previous?.isActive == true, !configuration.isActive {
                active?.textView.capturePosition()
                active?.textView.resignFirstResponder()
                state.flushPosition()
                cancelTurn()
            }
            if previous?.isActive == false, configuration.isActive { active?.textView.restoreSelectionFocus() }
            guard configuration.isActive else {
                turnGesture.isEnabled = false
                curlPan?.isEnabled = false
                // Compact Saved still mounts its hidden reader after an iPad resize.
                // UIKit requires a page before appearance, even when no reader gestures are active.
                if active == nil, !interactive { show(page(for: configuration.document, live: false), direction: .forward, animated: false) }
                return
            }
            // External navigation/reflow wins over an in-flight gesture; its completion becomes stale.
            let interrupted = turning && (typographyChanged || state.isNavigating || sourceID != state.chapterID || turnRevision != state.navigationRevision ||
                previous?.scheme != configuration.scheme || previous?.dynamicType != configuration.dynamicType ||
                previous?.animated != configuration.animated || previous?.chromeInsets != configuration.chromeInsets ||
                configuration.scenePhase != .active || previous?.wide != configuration.wide)
            if interrupted {
                generation = UUID()
                if interactive {
                    // Never replace pages under UIKit's live curl: cancel it, then reconcile in didFinishAnimating.
                    cancelInteractiveCurl()
                    return
                }
                turning = false
                sourceID = nil
            }
            if !turning {
                // The shared reader is canonical. The representable's captured document can lag one
                // update behind a gesture commit; curling to it would undo the turn on screen.
                let page = page(for: state.document ?? configuration.document, live: true)
                if active !== page || interrupted {
                    active?.textView.capturePosition()
                    let backwards = adjacent(-1, to: active?.document.id) == page.document.id
                    // Verse-targeted navigation must restore its anchor directly.
                    let curl = !interrupted && configuration.animated && state.anchor == nil &&
                        (adjacent(1, to: active?.document.id) == page.document.id || backwards)
                    turning = curl
                    sourceID = state.chapterID
                    turnRevision = state.navigationRevision
                    let token = generation
                    show(page, direction: backwards ? .reverse : .forward, animated: curl) { [weak self] _ in
                        guard let self, self.generation == token else { return }
                        self.turning = false
                        self.sourceID = nil
                        self.reconcileWithReader()
                        self.configurePages()
                        self.prepareNeighbors()
                        (self.controller?.parent as? ChapterTurnContainer)?.trackScrollEdges()
                    }
                }
            }
            configurePages()
            prepareNeighbors()
        }

        /// Double-sided with a leading spine, UIKit requires `[page]` for an immediate change and
        /// `[page, back]` for an animated curl (verified for both directions); gesture curls get
        /// their backs from the data source.
        private func show(_ page: ChapterPageController, direction: UIPageViewController.NavigationDirection,
                          animated: Bool, completion: ((Bool) -> Void)? = nil) {
            guard let controller else { return }
            let pages: [UIViewController] = animated && controller.isDoubleSided ? [page, back(for: page)] : [page]
            controller.setViewControllers(pages, direction: direction, animated: animated, completion: completion)
        }

        private func back(for page: ChapterPageController) -> PaperBackController {
            if let cached = backs[page.document.id], cached.front === page { return cached }
            let back = PaperBackController(front: page)
            backs[page.document.id] = back
            return back
        }

        func page(for document: ChapterDocument, live: Bool) -> ChapterPageController {
            let page: ChapterPageController
            if let cached = pages[document.id] { page = cached }
            else {
                page = ChapterPageController(document: document)
                // Resolve intent first: vertical movement fails immediately into native scrolling.
                page.textView.panGestureRecognizer.require(toFail: turnGesture)
                if let curlPan { page.textView.panGestureRecognizer.require(toFail: curlPan) }
                pages[document.id] = page
            }
            if let configuration {
                page.configure(from: state, live: live, wide: configuration.wide,
                    scheme: configuration.scheme, insets: configuration.chromeInsets)
            }
            page.textView.selectionDidChange = { [weak self] in self?.updateGestures() }
            return page
        }

        func configurePages() {
            guard let configuration else { return }
            for page in pages.values {
                page.configure(from: state, live: page.document.id == state.chapterID,
                    wide: configuration.wide, scheme: configuration.scheme, insets: configuration.chromeInsets)
            }
            updateGestures()
        }

        private var turnsAllowed: Bool {
            guard let configuration else { return false }
            return configuration.isActive && configuration.scenePhase == .active &&
                active?.textView.selectedRange.length == 0 && !state.isSaving && !state.isNavigating
        }

        func updateGestures() {
            guard let configuration, !turning else { return }
            turnGesture.isEnabled = turnsAllowed && !configuration.animated
            curlPan?.isEnabled = turnsAllowed && configuration.animated
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === turnGesture || gestureRecognizer === curlPan, let view = active?.textView,
                  !turning, !view.isDecelerating, !view.isDragging, view.selectedRange.length == 0 else { return false }
            return view.point(inside: touch.location(in: view), with: nil)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === turnGesture { return true }
            guard gestureRecognizer === curlPan, let pan = curlPan, turnsAllowed, !turning else { return false }
            // Begin only on a clearly horizontal drag, so ordinary or diagonal scrolling
            // fails at once into the text view's scroll.
            let travel = pan.translation(in: pan.view), velocity = pan.velocity(in: pan.view)
            guard abs(travel.x) >= abs(travel.y) * 2, abs(velocity.x) >= abs(velocity.y) * 1.5 else { return false }
            // A double-sided curl with no destination (Genesis 1 backward, Revelation 22 forward, or a
            // neighbor still loading) makes UIKit throw from its pan handler. Start only when one is ready.
            let delta = (travel.x != 0 ? travel.x : velocity.x) < 0 ? 1 : -1
            guard let id = active?.document.id, preparedDocument(delta, from: id) != nil else { return false }
            haptics.prepare()
            return true
        }

        // MARK: Interactive curl data source (double-sided: front → back → next front)

        private func preparedDocument(_ delta: Int, from id: String) -> ChapterDocument? {
            guard let target = adjacent(delta, to: id) else { return nil }
            return documents[target] ?? pages[target]?.document
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            if let back = viewController as? PaperBackController { return back.front }
            guard let front = viewController as? ChapterPageController,
                  let document = preparedDocument(-1, from: front.document.id) else { return nil }
            return back(for: page(for: document, live: false))
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            if let front = viewController as? ChapterPageController {
                // The back is only reachable when a following chapter exists (never wrap at Revelation 22).
                guard preparedDocument(1, from: front.document.id) != nil else { return nil }
                return back(for: front)
            }
            guard let back = viewController as? PaperBackController,
                  let document = preparedDocument(1, from: back.front.document.id) else { return nil }
            return page(for: document, live: false)
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            guard let source = state.chapterID else { return }
            active?.textView.capturePosition()
            interactive = true
            turning = true
            interactiveGeneration = generation
            turnInterval = ReaderPerformance.signposter.beginInterval("Chapter turn", id: ReaderPerformance.signposter.makeSignpostID())
            sourceID = source
            turnRevision = state.navigationRevision
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard interactive else { return }
            interactive = false
            turning = false
            if let turnInterval { ReaderPerformance.signposter.endInterval("Chapter turn", turnInterval) }
            turnInterval = nil
            let source = sourceID
            sourceID = nil
            if completed, generation == interactiveGeneration, let source, let page = active, page.document.id != source {
                state.commitTurn(to: page.document, from: source)
                if state.chapterID == page.document.id { haptics.impactOccurred(intensity: 0.7) }
            }
            // A cancelled, stale, or rejected turn returns to the canonical chapter without animation.
            reconcileWithReader()
            configurePages()
            prepareNeighbors()
            (controller?.parent as? ChapterTurnContainer)?.trackScrollEdges()
        }

        /// Show the reader's canonical chapter if the screen drifted during an animation.
        private func reconcileWithReader() {
            guard let document = state.document, active?.document.id != document.id else { return }
            show(page(for: document, live: true), direction: .forward, animated: false)
        }

        private func cancelInteractiveCurl() {
            // Toggling a recognizer cancels its touches; UIKit settles the curl back and reports completed == false.
            curlPan?.isEnabled = false
            curlPan?.isEnabled = true
        }

        @objc private func turnChapter(_ gesture: ChapterSwipeRecognizer) {
            guard gesture.state == .recognized, !turning, let source = state.chapterID,
                  let target = adjacent(gesture.chapterDelta, to: source),
                  let document = documents[target] ?? pages[target]?.document,
                  active?.textView.selectedRange.length == 0, !state.isSaving, !state.isNavigating else { return }
            active?.textView.capturePosition()
            state.commitTurn(to: document, from: source)
            if state.chapterID == document.id { haptics.impactOccurred(intensity: 0.7) }
        }

        func cancelTurn() {
            // Passive reflow preserves the last user-established anchor. Recapturing after
            // each sidebar/rotation step can walk to a preceding, partially visible verse.
            if let text = active?.textView, text.isDragging || text.isDecelerating { text.capturePosition() }
            generation = UUID()
            if interactive { cancelInteractiveCurl(); return }
            turning = false
            sourceID = nil
            guard let document = state.document else { return }
            show(page(for: document, live: true), direction: .forward, animated: false)
            configurePages()
        }

        func adjacent(_ delta: Int, to id: String?) -> String? {
            guard let id, let index = state.catalogIndex[id],
                  state.catalog.indices.contains(index + delta) else { return nil }
            return state.catalog[index + delta].id
        }
        func prepareNeighbors() {
            guard !turning, let current = state.chapterID, preparedID != current else { return }
            preparedID = current
            preload?.cancel()
            let ids = [adjacent(-1, to: current), current, adjacent(1, to: current)].compactMap { $0 }
            pages = pages.filter { ids.contains($0.key) }
            backs = backs.filter { ids.contains($0.key) }
            documents = documents.filter { ids.contains($0.key) }
            preload = Task { [weak self] in
                guard let self else { return }
                do {
                    for id in ids where self.pages[id] == nil && self.documents[id] == nil {
                        let document = try await self.state.chapterForTurn(id)
                        try Task.checkCancellation()
                        guard self.state.chapterID == current else { return }
                        self.documents[id] = document
                    }
                    self.updateGestures()
                    // Build and lay out neighbouring pages ahead of a turn, one per main-actor turn,
                    // so a curl never waits on TextKit layout when the finger starts to move.
                    for id in ids where id != current {
                        await Task.yield()
                        try Task.checkCancellation()
                        guard self.state.chapterID == current, !self.turning, let controller = self.controller,
                              let document = self.documents[id] ?? self.pages[id]?.document else { return }
                        let page = self.page(for: document, live: false)
                        if page.view.bounds.size != controller.view.bounds.size { page.view.frame = controller.view.bounds }
                        page.view.layoutIfNeeded()
                    }
                } catch is CancellationError { } catch {
                    // Explicit chapter navigation still reports load errors and supports another attempt.
                    self.preparedID = nil
                }
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation { .min }
    }
}

@MainActor final class ChapterPageController: UIViewController {
    let document: ChapterDocument
    let textView = ChapterTextView()
    private lazy var preview: ReaderState = {
        let state = ReaderState()
        state.chapters = [document]
        state.chapterID = document.id
        state.annotationEditingEnabled = false
        return state
    }()
    private var previewAnnotationsRevision = -1

    init(document: ChapterDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(document:)") }
    override func loadView() { view = textView }

    func configure(from state: ReaderState, live: Bool, wide: Bool, scheme: ColorScheme, insets: EdgeInsets) {
        if !live {
            if preview.typography != state.typography { preview.typography = state.typography }
            if previewAnnotationsRevision != state.annotationsRevision {
                preview.highlights = state.highlights
                preview.exactAnnotations = state.exactAnnotations(in: document.id)
                preview.bookmarks = state.bookmarkIndicators(in: document)
                previewAnnotationsRevision = state.annotationsRevision
            }
        }
        textView.accessibilityIdentifier = live ? "chapterText" : "adjacentChapter-" + document.id
        textView.chromeInsets = insets
        textView.configure(document: document, state: live ? state : preview, wide: wide, scheme: scheme)
    }
}

@MainActor final class ReaderCurlController: UIPageViewController {
    var willResize: (() -> Void)?
    override init(transitionStyle style: UIPageViewController.TransitionStyle,
                  navigationOrientation: UIPageViewController.NavigationOrientation,
                  options: [UIPageViewController.OptionsKey: Any]? = nil) {
        super.init(transitionStyle: style, navigationOrientation: navigationOrientation, options: options)
        // Each chapter page carries a PaperBackController, so the curl never shows UIKit's pale reverse.
        isDoubleSided = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(transitionStyle:navigationOrientation:options:)") }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        willResize?()
        super.viewWillTransition(to: size, with: coordinator)
    }
}

/// The reverse of a curling chapter: the reading canvas with the page's own print showing
/// faintly through, mirrored like thin Bible paper. Decorative only; hidden from accessibility.
@MainActor final class PaperBackController: UIViewController {
    let front: ChapterPageController
    private var showThrough: UIView?

    init(front: ChapterPageController) {
        self.front = front
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(front:)") }

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        overrideUserInterfaceStyle = front.textView.overrideUserInterfaceStyle
        view.backgroundColor = UIColor(resource: .readingCanvas)
        showThrough?.removeFromSuperview()
        showThrough = nil
        // Only a page already on screen can be mirrored without an extra offscreen render;
        // a page curling in from behind shows plain paper.
        guard front.view.window != nil, !UIAccessibility.isReduceTransparencyEnabled,
              let print = front.view.snapshotView(afterScreenUpdates: false) else { return }
        print.frame = view.bounds
        print.transform = CGAffineTransform(scaleX: -1, y: 1)
        print.alpha = traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.09
        view.addSubview(print)
        showThrough = print
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Release the render surface as soon as the turn ends.
        showThrough?.removeFromSuperview()
        showThrough = nil
    }
}

/// The pager's container must also pass floating-control touches through. Rejecting them
/// only in UITextView leaves UIPageViewController's full-size background intercepting Books.
@MainActor final class ChapterTurnContainer: UIViewController {
    let pager = ReaderCurlController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
        options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
    let touchRegion = ChapterTouchRegion()
    /// The navigation bar cannot discover a scroll view nested in the pager, so the native
    /// top edge effect is requested explicitly for the band behind the floating toolbar.
    private let topEdge = UIView()
    private let topEdgeInteraction = UIScrollEdgeElementContainerInteraction()
    override func loadView() {
        view = touchRegion
        touchRegion.accessibilityIdentifier = "chapterTurnContainer"
        addChild(pager)
        touchRegion.addSubview(pager.view)
        pager.didMove(toParent: self)
        topEdge.isUserInteractionEnabled = false
        topEdge.isAccessibilityElement = false
        topEdgeInteraction.edge = .top
        topEdge.addInteraction(topEdgeInteraction)
        touchRegion.addSubview(topEdge)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pager.view.frame = view.bounds
        trackScrollEdges()
    }
    func trackScrollEdges() {
        let text = (pager.viewControllers?.first as? ChapterPageController)?.textView
        if topEdgeInteraction.scrollView !== text { topEdgeInteraction.scrollView = text }
        let frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: touchRegion.chromeInsets.top)
        if topEdge.frame != frame { topEdge.frame = frame }
    }
}

@MainActor final class ChapterTouchRegion: UIView {
    var chromeInsets = EdgeInsets()
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // The representable is already inset horizontally by the split view. Applying
        // the inherited leading safe area again would block the left side of its text.
        guard point.y >= bounds.minY + chromeInsets.top,
              point.y < bounds.maxY - chromeInsets.bottom else { return false }
        return super.point(inside: point, with: event)
    }
}

/// Discrete gesture: no page preview starts while a finger is scrolling or changing direction.
/// A failure dependency on this recognizer releases vertical drags to UITextView immediately.
@MainActor final class ChapterSwipeRecognizer: UIGestureRecognizer {
    private var origin = CGPoint.zero
    private var beganAt: TimeInterval = 0
    private var intent = ChapterSwipeIntent()
    private(set) var chapterDelta = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, event.allTouches?.count == 1, let touch = touches.first, let view else {
            state = .failed; return
        }
        origin = touch.location(in: view)
        beganAt = touch.timestamp
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view, state == .possible else { return }
        let point = touch.location(in: view)
        intent.update(x: point.x - origin.x, y: point.y - origin.y)
        if intent.rejected || touch.timestamp - beganAt > 1.5 { state = .failed }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view, state == .possible else { return }
        let point = touch.location(in: view)
        intent.update(x: point.x - origin.x, y: point.y - origin.y)
        chapterDelta = intent.completed(width: view.bounds.width, duration: touch.timestamp - beganAt) ?? 0
        state = chapterDelta == 0 ? .failed : .recognized
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func reset() {
        super.reset()
        intent = ChapterSwipeIntent()
        chapterDelta = 0
    }
}

struct ChapterSwipeIntent {
    private(set) var rejected = false
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    mutating func update(x: CGFloat, y: CGFloat) {
        self.x = x; self.y = y
        // Once the finger shows scroll intent, later horizontal drift cannot turn a page.
        if abs(y) >= 10 && abs(x) < abs(y) * 1.8 { rejected = true }
    }
    func completed(width: CGFloat, duration: TimeInterval) -> Int? {
        guard !rejected, duration <= 1.5, abs(x) >= max(36, min(56, width * 0.1)),
              abs(x) >= abs(y) * 2 else { return nil }
        return x < 0 ? 1 : -1
    }
}
