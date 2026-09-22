#if DEBUG
import SwiftUI
import UIKit
import Observation

/// Isolated geometry experiment. Only completed turns change this in-memory chapter.
@MainActor @Observable
final class PaperTurnModel: Identifiable {
    let id = UUID()
    let catalog: [ChapterSummary]
    var currentID: String
    var documents: [String: ChapterDocument] = [:]
    var requestedID: String?
    var errorMessage: String?
    var preparing = false
    let typography: ReadingTypography
    @ObservationIgnored let loadChapter: @MainActor (String) async throws -> ChapterDocument

    init(reader: ReaderState) {
        catalog = reader.catalog
        currentID = reader.chapterID ?? ""
        typography = reader.typography
        loadChapter = { try await reader.chapterForExperiment($0) }
        if let document = reader.document { documents[document.id] = document }
    }

    func adjacent(_ delta: Int, to id: String? = nil) -> String? {
        guard let index = catalog.firstIndex(where: { $0.id == (id ?? currentID) }), catalog.indices.contains(index + delta) else { return nil }
        return catalog[index + delta].id
    }

    func prepare() async {
        let current = currentID
        preparing = true
        defer { preparing = false }
        do {
            let ids = [adjacent(-1), current, adjacent(1)].compactMap { $0 }
            var next: [String: ChapterDocument] = [:]
            for id in ids {
                if let cached = documents[id] { next[id] = cached }
                else { next[id] = try await loadChapter(id) }
            }
            try Task.checkCancellation()
            guard currentID == current else { return }
            documents = next
            errorMessage = nil
        } catch is CancellationError { }
        catch { errorMessage = "The adjacent chapter could not be loaded. Try again." }
    }
}

struct PaperTurnExperimentView: View {
    @State var model: PaperTurnModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var retry = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Chapter-turn experiment · Selection and scrolling remain native. Annotation editing is disabled here.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
                PaperCurlHost(model: model, scheme: scheme,
                    animate: !reduceMotion && !reduceTransparency && contrast != .increased)
                if let error = model.errorMessage {
                    Text(error).font(.footnote)
                    Button("Try again") { retry += 1 }
                }
            }
            .background(Color(.readingCanvas))
            .navigationTitle("Paper turn experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("paperTurnDone")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Previous", systemImage: "chevron.left") { model.requestedID = model.adjacent(-1) }
                        .disabled(model.preparing || model.adjacent(-1) == nil)
                        .accessibilityIdentifier("paperPrevious")
                    Spacer()
                    Text(model.documents[model.currentID]?.reference ?? "Opening chapter…")
                        .font(.subheadline).accessibilityIdentifier("paperReference")
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { model.requestedID = model.adjacent(1) }
                        .disabled(model.preparing || model.adjacent(1) == nil)
                        .accessibilityIdentifier("paperNext")
                }
            }
        }
        .task(id: model.currentID) { await model.prepare() }
        .task(id: retry) { if retry > 0 { await model.prepare() } }
    }
}

private struct PaperCurlHost: UIViewControllerRepresentable {
    let model: PaperTurnModel
    let scheme: ColorScheme
    let animate: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        controller.isDoubleSided = false
        controller.delegate = context.coordinator
        context.coordinator.scheme = scheme
        if let page = context.coordinator.page(model.currentID) {
            controller.setViewControllers([page], direction: .forward, animated: false)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.scheme = scheme
        coordinator.pages = coordinator.pages.filter { model.documents[$0.key] != nil }
        coordinator.pages.values.forEach { $0.scheme = scheme; $0.view.setNeedsLayout() }
        controller.view.backgroundColor = UIColor(resource: .readingCanvas)
        controller.dataSource = animate && !UIAccessibility.isVoiceOverRunning ? coordinator : nil
        guard let target = model.requestedID, !coordinator.turning, let page = coordinator.page(target) else { return }
        coordinator.turning = true
        let direction: UIPageViewController.NavigationDirection = target == model.adjacent(-1) ? .reverse : .forward
        controller.setViewControllers([page], direction: direction, animated: animate && !UIAccessibility.isVoiceOverRunning) { completed in
            coordinator.turning = false
            if completed { model.currentID = target }
            model.requestedID = nil
        }
    }

    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let model: PaperTurnModel
        var pages: [String: PaperChapterController] = [:]
        var scheme: ColorScheme = .light
        var turning = false
        init(model: PaperTurnModel) { self.model = model }

        func page(_ id: String) -> PaperChapterController? {
            if let page = pages[id] { return page }
            guard let document = model.documents[id] else { return nil }
            let page = PaperChapterController(document: document, typography: model.typography, scheme: scheme)
            pages[id] = page
            return page
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(-1, from: viewController)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(1, from: viewController)
        }
        private func neighbor(_ delta: Int, from controller: UIViewController) -> UIViewController? {
            guard let current = controller as? PaperChapterController, current.textView.selectedRange.length == 0,
                  let id = model.adjacent(delta, to: current.document.id) else { return nil }
            return page(id)
        }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            turning = true
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            turning = false
            if completed, let page = pageViewController.viewControllers?.first as? PaperChapterController {
                model.currentID = page.document.id
            }
        }
        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation { .min }
    }
}

@MainActor private final class PaperChapterController: UIViewController {
    let document: ChapterDocument
    let state = ReaderState()
    let textView = ChapterTextView()
    var scheme: ColorScheme

    init(document: ChapterDocument, typography: ReadingTypography, scheme: ColorScheme) {
        self.document = document
        self.scheme = scheme
        super.init(nibName: nil, bundle: nil)
        state.chapters = [document]
        state.chapterID = document.id
        state.typography = typography
        state.annotationEditingEnabled = false
        textView.accessibilityIdentifier = "paperChapter-" + document.id
    }
    required init?(coder: NSCoder) { fatalError("Use the experiment initializer") }
    override func loadView() { view = textView }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        textView.configure(document: document, state: state, wide: view.bounds.width >= 920, scheme: scheme)
    }
}
#endif
