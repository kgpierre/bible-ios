// Regressions for the 10–11 October 2026 audit (Docs/Validation/audit-2026-10-10), adapted from
// its desired-behavior probes. Each test failed on the audited commit 57e5eff.
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BibleReader

final class AuditRegressionTests: XCTestCase {
    private let edition = "eng-kjv-1769-protestant"

    @MainActor private func store() throws -> BibleStore {
        let corpus = try XCTUnwrap(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        return try BibleStore(corpusURL: corpus, userURL: user)
    }

    @MainActor private func reader() async throws -> ReaderState {
        let store = try store()
        let state = ReaderState(makeStore: { store })
        await state.load()
        return state
    }

    @MainActor private func wait(timeout: Duration = .seconds(2), until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: F1 · spread turns

    /// A spread coordinator in a window, showing the reader's current chapter.
    @MainActor private func spread(_ state: ReaderState) throws -> (SpreadChapterView.Coordinator, SpreadContainer, SpreadChapterView, () -> Void) {
        let document = try XCTUnwrap(state.document)
        let configuration = SpreadChapterView(document: document, state: state)
        let coordinator = configuration.makeCoordinator()
        let container = SpreadContainer()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1000, height: 650)
        window.rootViewController = container
        coordinator.attach(container)
        window.makeKeyAndVisible()
        container.view.frame = window.bounds
        container.view.layoutIfNeeded()
        coordinator.update(configuration)
        return (coordinator, container, configuration, { coordinator.detach(); window.isHidden = true; original?.makeKey() })
    }

    @MainActor func testLateSpreadCompletionPreservesNewSameChapterNavigation() async throws {
        let state = try await reader()
        let document = try XCTUnwrap(state.document)
        let (coordinator, container, configuration, cleanUp) = try spread(state)
        defer { cleanUp() }
        let previous = try XCTUnwrap(container.pager.viewControllers)
        let right = try XCTUnwrap(previous.last)
        let nextLeft = try XCTUnwrap(coordinator.pageViewController(container.pager, viewControllerAfter: right))
        let nextRight = try XCTUnwrap(coordinator.pageViewController(container.pager, viewControllerAfter: nextLeft))
        coordinator.pageViewController(container.pager, willTransitionTo: [nextLeft, nextRight])
        let targetVerse = try XCTUnwrap(document.verses.last)
        let targetChapter = try XCTUnwrap(state.catalogChapter(document.id))
        state.navigate(to: targetChapter, verseID: targetVerse.id)
        try await wait { !state.isNavigating }
        XCTAssertEqual(state.anchor?.text.verseID, targetVerse.id)
        coordinator.update(configuration)
        container.pager.setViewControllers([nextLeft, nextRight], direction: .forward, animated: false)
        coordinator.pageViewController(container.pager, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: true)
        XCTAssertEqual(state.anchor?.text.verseID, targetVerse.id, "An old turn must not overwrite the newer reference navigation")
        // The pager returns to the spread holding the newer destination.
        let shown = try XCTUnwrap((container.pager.viewControllers?.first as? SpreadPageController)?.key)
        XCTAssertEqual(shown.chapterID, document.id)
        XCTAssertNotEqual(shown, (nextLeft as? SpreadPageController)?.key)
    }

    @MainActor func testCancelledSpreadTurnKeepsTheAnchor() async throws {
        let state = try await reader()
        let document = try XCTUnwrap(state.document)
        let (coordinator, container, _, cleanUp) = try spread(state)
        defer { cleanUp() }
        let anchor = state.anchor
        let previous = try XCTUnwrap(container.pager.viewControllers)
        let nextLeft = try XCTUnwrap(coordinator.pageViewController(container.pager, viewControllerAfter: try XCTUnwrap(previous.last)))
        let nextRight = try XCTUnwrap(coordinator.pageViewController(container.pager, viewControllerAfter: nextLeft))
        coordinator.pageViewController(container.pager, willTransitionTo: [nextLeft, nextRight])
        coordinator.pageViewController(container.pager, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: false)
        XCTAssertEqual(state.anchor, anchor)
        XCTAssertEqual(state.chapterID, document.id)
    }

    // MARK: F2 · accessibility

    @MainActor func testSourceHeadingsAreAccessibleInReadingOrder() async throws {
        let store = try store()
        let document = try await store.chapter("\(edition):PSA:23")
        let heading = try XCTUnwrap(document.verses.first?.headings.first)
        let state = ReaderState()
        state.chapters = [document]; state.chapterID = document.id
        let text = ChapterTextView()
        text.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        text.configure(document: document, state: state, wide: false, scheme: .light)
        text.layoutIfNeeded(); text.prepareVerseAccessibility()
        let labels = (text.accessibilityElements ?? []).compactMap { ($0 as? NSObject)?.accessibilityLabel }
        let headingIndex = try XCTUnwrap(labels.firstIndex { $0.contains(heading) }, "Source heading missing: \(heading)")
        let firstVerseIndex = try XCTUnwrap(labels.firstIndex { $0.hasPrefix("\(document.reference):1.") })
        XCTAssertLessThan(headingIndex, firstVerseIndex, "The superscription is read before verse 1")
    }

    // MARK: F3 · card cleanup

    @MainActor private func cardWithImage(_ library: CardLibrary) throws -> ScriptureCard {
        let oldImage = try library.storeBackground(Data([1, 2, 3]))
        let card = ScriptureCard(id: UUID(), kind: .passage, chapterID: "test:BOOK:1", verseID: "test:BOOK:1:1", reference: "Synthetic test",
                                 text: "Synthetic non-Scripture test content", isExcerpt: false, editionLabel: "Test", verseCount: nil,
                                 style: CardStyle(background: .image(file: oldImage, source: .photo, luminance: 0.5)), created: .now, updated: .now)
        try library.upsert(card)
        return card
    }

    @MainActor func testCommittedCardSaveAndDeleteSurviveCleanupFailure() async throws {
        let library = CardLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let card = try cardWithImage(library)
        let other = try cardWithImage(library)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: library.backgroundsURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: library.backgroundsURL.path) }
        var edited = card
        edited.style.background = .preset(.sage)
        var reloads = 0
        let model = CardsModel(library: library) { reloads += 1 }
        await model.load()
        let saved = await model.save(edited)
        XCTAssertTrue(saved, "Background cleanup must not turn a committed save into an error")
        XCTAssertEqual(try library.load().first { $0.id == card.id }?.style.background, .preset(.sage))
        XCTAssertEqual(model.cards.first { $0.id == card.id }?.style.background, .preset(.sage))
        XCTAssertEqual(reloads, 1)
        await model.delete(other)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try library.load().map(\.id), [card.id])
        XCTAssertEqual(reloads, 2)
        // Cleanup is retried once the folder is writable again.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: library.backgroundsURL.path)
        try library.removeUnreferencedBackgrounds()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.backgroundsURL.path), [])
    }

    // MARK: F4 · widget links

    @MainActor func testWidgetLinkRejectsNonexistentVerse() async throws {
        let reader = try await reader()
        let state = AppState(reader: reader)
        let before = reader.chapterID
        state.open(try XCTUnwrap(CardLink.url(chapterID: "\(edition):JHN:3", verseID: "\(edition):JHN:3:999")))
        try await Task.sleep(for: .milliseconds(300))
        try await wait { !reader.isNavigating }
        XCTAssertEqual(reader.chapterID, before, "Unknown verse links are ignored, not opened with an invalid anchor")
    }

    @MainActor func testWidgetLinkOpensAValidVerse() async throws {
        let reader = try await reader()
        let state = AppState(reader: reader)
        state.destination = .saved
        state.open(try XCTUnwrap(CardLink.url(chapterID: "\(edition):JHN:3", verseID: "\(edition):JHN:3:16")))
        try await wait { reader.chapterID == "\(edition):JHN:3" && !reader.isNavigating }
        XCTAssertEqual(reader.chapterID, "\(edition):JHN:3")
        XCTAssertEqual(reader.anchor?.text.verseID, "\(edition):JHN:3:16")
        XCTAssertEqual(state.destination, .read)
    }

    @MainActor func testWidgetLinkWaitsForRestoration() async throws {
        let store = try store()
        let reader = ReaderState(makeStore: { store })
        let state = AppState(reader: reader)
        state.open(try XCTUnwrap(CardLink.url(chapterID: "\(edition):JHN:3", verseID: nil)))
        XCTAssertNotNil(state.pendingLink, "A link before restoration is held")
        await reader.load()
        XCTAssertNotEqual(reader.chapterID, "\(edition):JHN:3")
        state.openPendingLink()
        try await wait { reader.chapterID == "\(edition):JHN:3" && !reader.isNavigating }
        XCTAssertEqual(reader.chapterID, "\(edition):JHN:3")
        XCTAssertNil(state.pendingLink)
    }

    func testWidgetLinksRejectRepeatedParameters() throws {
        let chapter = "\(edition):JHN:3"
        XCTAssertNil(CardLink.parse(try XCTUnwrap(URL(string: "\(CardLink.scheme)://open?chapter=\(chapter)&chapter=\(edition):GEN:1"))))
        XCTAssertNil(CardLink.parse(try XCTUnwrap(URL(string: "\(CardLink.scheme)://open?chapter=\(chapter)&verse=\(chapter):1&verse=\(chapter):2"))))
        XCTAssertNil(CardLink.parse(try XCTUnwrap(URL(string: "\(CardLink.scheme)://open?verse=\(chapter):1"))))
        XCTAssertNotNil(CardLink.parse(try XCTUnwrap(URL(string: "\(CardLink.scheme)://open?chapter=\(chapter)&verse=\(chapter):1"))))
    }

    // MARK: F7 · generated backgrounds

    func testOnlyImagePlaygroundBackgroundsAreLabeledGenerated() {
        XCTAssertTrue(CardStyle(background: .image(file: "A.jpg", source: .imagePlayground, luminance: 0.5)).hasGeneratedBackground)
        XCTAssertFalse(CardStyle(background: .image(file: "A.jpg", source: .photo, luminance: 0.5)).hasGeneratedBackground)
        XCTAssertFalse(CardStyle(background: .preset(.sage)).hasGeneratedBackground)
    }

    // MARK: F8 · Saved share text

    @MainActor func testSavedExcerptShareTextMarksExcerptOnce() async throws {
        let store = try store()
        let document = try await store.chapter("\(edition):JHN:3")
        let verse = try XCTUnwrap(document.verses.first)
        let part = try XCTUnwrap(SavedTextPart(verseID: verse.id, text: verse.text, range: NSRange(location: 0, length: 5)))
        let passage = ExactPassage(chapterID: document.id, reference: "\(document.reference):\(verse.label)", parts: [part])
        _ = try await store.editExact(passage, color: .yellow)
        let items = try await store.savedItems()
        let item = try XCTUnwrap(items.first)
        let text = try XCTUnwrap(item.shareText(editionLabel: "KJV"))
        XCTAssertEqual(text, "\(passage.text)\n— \(passage.reference), KJV (excerpt)")
        XCTAssertEqual(text.components(separatedBy: "(excerpt)").count, 2)
    }

    // MARK: Improvements · widget states, thumbnails, note markers

    func testUnreadableLibraryIsNeverReportedAsRemovedOrEmpty() {
        let card = ScriptureCard(id: UUID(), kind: .passage, chapterID: "test:BOOK:1", verseID: nil, reference: "Synthetic test",
                                 text: "Synthetic non-Scripture test content", isExcerpt: false, editionLabel: "Test", verseCount: nil,
                                 style: CardStyle(), created: .now, updated: .now)
        XCTAssertEqual(CardSelection.resolve(cards: nil, chosen: card.id, rotate: false, on: .now), .unavailable)
        XCTAssertEqual(CardSelection.resolve(cards: nil, chosen: nil, rotate: true, on: .now), .unavailable)
        XCTAssertEqual(CardSelection.resolve(cards: [], chosen: card.id, rotate: false, on: .now), .removed)
        XCTAssertEqual(CardSelection.resolve(cards: [], chosen: nil, rotate: false, on: .now), .noCards)
        XCTAssertEqual(CardSelection.resolve(cards: [], chosen: nil, rotate: true, on: .now), .noCards)
        XCTAssertEqual(CardSelection.resolve(cards: [card], chosen: card.id, rotate: false, on: .now), .card(card))
    }

    func testCardThumbnailsAreDownsampledToTheRequestedSize() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .jpegData(withCompressionQuality: 0.8) { context in UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800)) }
        try jpeg.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let thumbnail = await CardThumbnails.shared.image(at: url, maxPixelSize: 300)
        let image = try XCTUnwrap(thumbnail)
        XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 300)
        let missing = await CardThumbnails.shared.image(at: url.deletingLastPathComponent().appendingPathComponent("missing.jpg"), maxPixelSize: 300)
        XCTAssertNil(missing)
    }

    @MainActor func testNoteMarkerToggleKeepsTextAndSelection() async throws {
        let store = try store()
        let document = try await store.chapter("\(edition):GEN:1")
        let state = ReaderState()
        state.chapters = [document]; state.chapterID = document.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let selection = NSRange(location: try XCTUnwrap(view.map?.entries.first).range.location, length: 10)
        view.selectedRange = selection
        #if DEBUG
        let builds = view.documentBuildCount
        #endif
        state.typography.showsNotes.toggle()
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        state.typography.showsNotes.toggle()
        view.configure(document: document, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        XCTAssertEqual(view.selectedRange, selection)
        #if DEBUG
        XCTAssertEqual(view.documentBuildCount, builds, "Toggling note markers must not rebuild the chapter text")
        #endif
        state.typography.sizeAdjustment += 1
        view.configure(document: document, state: state, wide: false, scheme: .light)
        #if DEBUG
        XCTAssertEqual(view.documentBuildCount, builds + 1, "Layout-affecting typography still rebuilds")
        #endif
    }
}
