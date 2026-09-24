import SwiftUI
import UIKit

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
        controller.isDoubleSided = false
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        controller.view.addGestureRecognizer(context.coordinator.turnGesture)
        controller.willResize = { [weak coordinator = context.coordinator] in coordinator?.cancelTurn() }
        return host
    }
    func updateUIViewController(_ host: ChapterTurnContainer, context: Context) {
        host.touchRegion.chromeInsets = chromeInsets
        context.coordinator.update(self)
    }
    static func dismantleUIViewController(_ host: ChapterTurnContainer, coordinator: Coordinator) {
        let controller = host.pager
        coordinator.turnGesture.isEnabled = false
        coordinator.preload?.cancel()
        coordinator.generation = UUID()
        coordinator.active?.textView.capturePosition()
        coordinator.active?.textView.resignFirstResponder()
        controller.delegate = nil
        controller.dataSource = nil
    }

    @MainActor final class Coordinator: NSObject, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        let state: ReaderState
        weak var controller: UIPageViewController?
        lazy var turnGesture: ChapterSwipeRecognizer = {
            let gesture = ChapterSwipeRecognizer(target: self, action: #selector(turnChapter(_:)))
            gesture.delegate = self
            gesture.cancelsTouchesInView = false
            return gesture
        }()
        var pages: [String: ChapterPageController] = [:]
        var documents: [String: ChapterDocument] = [:]
        var preload: Task<Void, Never>?
        var generation = UUID()
        var preparedID: String?
        var sourceID: String?
        var turnRevision = 0
        var renderedTypography: ReadingTypography?
        var turning = false
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
                // Compact Saved still mounts its hidden reader after an iPad resize.
                // UIKit requires a page before appearance, even when no reader gestures are active.
                if active == nil {
                    controller.setViewControllers([page(for: configuration.document, live: false)],
                                                  direction: .forward, animated: false)
                }
                return
            }
            // External navigation/reflow wins over an in-flight gesture; its completion becomes stale.
            let interrupted = turning && (typographyChanged || state.isNavigating || sourceID != state.chapterID || turnRevision != state.navigationRevision ||
                previous?.scheme != configuration.scheme || previous?.dynamicType != configuration.dynamicType ||
                previous?.animated != configuration.animated || previous?.chromeInsets != configuration.chromeInsets ||
                configuration.scenePhase != .active || previous?.wide != configuration.wide)
            if interrupted {
                generation = UUID()
                turning = false
                sourceID = nil
            }
            if !turning {
                let page = page(for: configuration.document, live: true)
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
                    controller.setViewControllers([page], direction: backwards ? .reverse : .forward, animated: curl) { [weak self] _ in
                        guard let self, self.generation == token else { return }
                        self.turning = false
                        self.sourceID = nil
                        self.configurePages()
                        self.prepareNeighbors()
                    }
                }
            }
            configurePages()
            prepareNeighbors()
        }

        func page(for document: ChapterDocument, live: Bool) -> ChapterPageController {
            let page: ChapterPageController
            if let cached = pages[document.id] { page = cached }
            else {
                page = ChapterPageController(document: document)
                // Resolve intent first: vertical movement fails immediately into native scrolling.
                page.textView.panGestureRecognizer.require(toFail: turnGesture)
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

        func updateGestures() {
            guard let controller, let configuration else { return }
            guard !turning else { return }
            // A nil data source disables UIKit's eager curl/tap navigation. Only our discrete
            // horizontal gesture can request a turn; the native curl remains the transition.
            controller.dataSource = nil
            turnGesture.isEnabled = configuration.isActive && configuration.scenePhase == .active &&
                active?.textView.selectedRange.length == 0 && !state.isSaving && !state.isNavigating
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === turnGesture, let view = active?.textView,
                  !turning, !view.isDecelerating, !view.isDragging, view.selectedRange.length == 0 else { return false }
            return view.point(inside: touch.location(in: view), with: nil)
        }

        @objc private func turnChapter(_ gesture: ChapterSwipeRecognizer) {
            guard gesture.state == .recognized, !turning, let source = state.chapterID,
                  let target = adjacent(gesture.chapterDelta, to: source),
                  let document = documents[target] ?? pages[target]?.document,
                  active?.textView.selectedRange.length == 0, !state.isSaving, !state.isNavigating else { return }
            active?.textView.capturePosition()
            state.commitTurn(to: document, from: source)
        }

        func cancelTurn() {
            // Passive reflow preserves the last user-established anchor. Recapturing after
            // each sidebar/rotation step can walk to a preceding, partially visible verse.
            if let text = active?.textView, text.isDragging || text.isDecelerating { text.capturePosition() }
            generation = UUID()
            turning = false
            sourceID = nil
            guard let document = state.document else { return }
            controller?.setViewControllers([page(for: document, live: true)], direction: .forward, animated: false)
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
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        willResize?()
        super.viewWillTransition(to: size, with: coordinator)
    }
}

/// The pager's container must also pass floating-control touches through. Rejecting them
/// only in UITextView leaves UIPageViewController's full-size background intercepting Books.
@MainActor final class ChapterTurnContainer: UIViewController {
    let pager = ReaderCurlController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
        options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
    let touchRegion = ChapterTouchRegion()
    override func loadView() {
        view = touchRegion
        touchRegion.accessibilityIdentifier = "chapterTurnContainer"
        addChild(pager)
        touchRegion.addSubview(pager.view)
        pager.didMove(toParent: self)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pager.view.frame = view.bounds
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
        guard !rejected, duration <= 1.5, abs(x) >= max(44, min(64, width * 0.12)),
              abs(x) >= abs(y) * 2 else { return nil }
        return x < 0 ? 1 : -1
    }
}
