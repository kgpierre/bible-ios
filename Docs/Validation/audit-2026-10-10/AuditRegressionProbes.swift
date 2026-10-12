// Audit-only regression probes. Intentionally assert the desired behavior.
// Copy into BibleReaderTests to reproduce; these are not in the shipping test target.
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BibleReader

final class AuditRegressionProbes: XCTestCase {
    @MainActor private func reader() async throws -> ReaderState {
        let corpus = try XCTUnwrap(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let state = ReaderState(makeStore: { store })
        await state.load()
        return state
    }

    @MainActor func testSourceHeadingsAreAccessible() async throws {
        let corpus = try XCTUnwrap(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let store = try BibleStore(corpusURL: corpus, userURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite"))
        let document = try await store.chapter("eng-kjv-1769-protestant:PSA:23")
        let heading = try XCTUnwrap(document.verses.first?.headings.first)
        let state = ReaderState()
        state.chapters = [document]; state.chapterID = document.id
        let text = ChapterTextView()
        text.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        text.configure(document: document, state: state, wide: false, scheme: .light)
        text.layoutIfNeeded(); text.prepareVerseAccessibility()
        XCTAssertTrue(text.map?.text.contains(heading) == true)
        let labels = (text.accessibilityElements ?? []).compactMap { ($0 as? NSObject)?.accessibilityLabel }
        XCTAssertTrue(labels.contains { $0.contains(heading) }, "Source heading is rendered but absent from the explicit accessibility elements: \(heading)")
    }

    @MainActor func testLateSpreadCompletionPreservesNewSameChapterNavigation() async throws {
        let state = try await reader()
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
        defer { coordinator.detach(); window.isHidden = true; original?.makeKey() }
        container.view.frame = window.bounds
        container.view.layoutIfNeeded()
        coordinator.update(configuration)
        let previous = try XCTUnwrap(container.pager.viewControllers)
        let right = try XCTUnwrap(previous.last)
        let nextLeft = try XCTUnwrap(coordinator.pageViewController(container.pager, viewControllerAfter: right))
        let nextRight = try XCTUnwrap(coordinator.pageViewController(container.pager, viewControllerAfter: nextLeft))
        coordinator.pageViewController(container.pager, willTransitionTo: [nextLeft, nextRight])
        let targetVerse = try XCTUnwrap(document.verses.last)
        let targetChapter = try XCTUnwrap(state.catalogChapter(document.id))
        state.navigate(to: targetChapter, verseID: targetVerse.id)
        for _ in 0..<100 where state.isNavigating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(state.anchor?.text.verseID, targetVerse.id)
        coordinator.update(configuration)
        container.pager.setViewControllers([nextLeft, nextRight], direction: .forward, animated: false)
        coordinator.pageViewController(container.pager, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: true)
        XCTAssertEqual(state.anchor?.text.verseID, targetVerse.id, "An old turn must not overwrite the newer reference navigation")
    }

    @MainActor func testWidgetLinkRejectsNonexistentVerse() async throws {
        let reader = try await reader()
        let state = AppState(reader: reader)
        let before = reader.chapterID
        let url = try XCTUnwrap(CardLink.url(chapterID: "eng-kjv-1769-protestant:JHN:3", verseID: "eng-kjv-1769-protestant:JHN:3:999"))
        state.open(url)
        for _ in 0..<100 where reader.isNavigating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.chapterID, before, "Unknown verse links should be ignored, not navigate with an invalid persistence anchor")
    }

    @MainActor func testCommittedCardSaveDoesNotReportFailureWhenCleanupFails() throws {
        let library = CardLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let oldImage = try library.storeBackground(Data([1, 2, 3]))
        let card = ScriptureCard(id: UUID(), kind: .passage, chapterID: "test:BOOK:1", verseID: "test:BOOK:1:1", reference: "Synthetic test", text: "Synthetic non-Scripture test content", isExcerpt: false, editionLabel: "Test", verseCount: nil, style: CardStyle(background: .image(file: oldImage, source: .photo, luminance: 0.5)), created: .now, updated: .now)
        try library.upsert(card)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: library.backgroundsURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: library.backgroundsURL.path) }
        var edited = card
        edited.style.background = .preset(.sage)
        var reloads = 0
        let model = CardsModel(library: library) { reloads += 1 }
        model.load()
        let reportedSuccess = model.save(edited)
        XCTAssertEqual(try library.load().first?.style.background, .preset(.sage), "Card commit itself succeeded")
        XCTAssertTrue(reportedSuccess, "Background garbage collection must not turn a committed save into an error")
        XCTAssertEqual(reloads, 1, "A committed card must reload its widgets")
    }
}
