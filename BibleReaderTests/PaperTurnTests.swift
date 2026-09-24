import Foundation
import Testing
import UIKit
@testable import BibleReader

struct PaperTurnTests {
    @Test @MainActor func inactiveReaderStillSuppliesAPageForUIKitAppearance() async throws {
        let document = try #require(await PrototypeLibrary.load().first)
        let state = ReaderState()
        state.chapters = [document]
        state.chapterID = document.id
        let view = PaperChapterView(document: document, state: state, wide: false, isActive: false)
        let coordinator = view.makeCoordinator()
        let controller = ReaderCurlController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        coordinator.controller = controller
        coordinator.update(view)
        #expect(controller.viewControllers?.count == 1)
        #expect(!coordinator.turnGesture.isEnabled)
        #expect(state.document?.id == document.id)
    }

    @Test @MainActor func preparedCancelledAndStaleTurnsPreserveReaderAndAnnotations() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let state = ReaderState(makeStore: { store })
        await state.load()
        let original = try #require(state.document)
        let first = try #require(original.verses.first)
        let part = try #require(SavedTextPart(verseID: first.id, text: first.text, range: NSRange(location: 0, length: 2)))
        let passage = ExactPassage(chapterID: original.id, reference: original.reference, parts: [part])
        await state.saveExact(passage, color: .sage)
        let originalAnnotations = state.exactAnnotations
        // Repeated lifecycle flushes and a following turn cancel obsolete writes without alerts.
        state.flushPosition()
        state.flushPosition()
        let index = try #require(state.catalog.firstIndex(where: { $0.id == original.id }))
        let next = try await state.chapterForTurn(state.catalog[index + 1].id)
        // Preparing a page and cancelling its gesture does not navigate or edit annotations.
        #expect(state.document?.id == original.id)
        #expect(state.exactAnnotations == originalAnnotations)
        state.commitTurn(to: next, from: "stale-source")
        #expect(state.document?.id == original.id)
        let skipped = try await state.chapterForTurn(state.catalog[index + 2].id)
        state.commitTurn(to: skipped, from: original.id)
        #expect(state.document?.id == original.id)
        state.commitTurn(to: next, from: original.id)
        #expect(state.document?.id == next.id)
        #expect(state.exactAnnotations == originalAnnotations)
        #expect(state.selection == nil)
        for _ in 0..<50 {
            if try await store.position()?.chapterID == next.id { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let reopened = ReaderState(makeStore: { store })
        await reopened.load()
        #expect(state.errorMessage == nil)
        #expect(reopened.document?.id == next.id)
        #expect(reopened.exactAnnotations == originalAnnotations)
    }
}

struct ChapterSwipeIntentTests {
    @Test func verticalOrDiagonalStartCannotBecomeATurnLater() {
        for initial in [CGPoint(x: 0, y: 12), CGPoint(x: 15, y: -12), CGPoint(x: 50, y: 30)] {
            var intent = ChapterSwipeIntent()
            intent.update(x: initial.x, y: initial.y)
            intent.update(x: -220, y: 2)
            #expect(intent.completed(width: 400, duration: 0.4) == nil)
        }
    }
    @Test func shorterSlowerSwipesAllowNaturalVerticalDrift() {
        var intent = ChapterSwipeIntent()
        intent.update(x: -25, y: 8)
        intent.update(x: -60, y: 25)
        #expect(intent.completed(width: 400, duration: 1.2) == 1)
    }
    @Test func deliberateHorizontalTurnsButShortHeldAndCurvedDragsDoNot() {
        var intent = ChapterSwipeIntent()
        intent.update(x: -160, y: 8)
        #expect(intent.completed(width: 400, duration: 0.4) == 1)
        #expect(intent.completed(width: 400, duration: 1.6) == nil)
        intent.update(x: 160, y: 4)
        #expect(intent.completed(width: 400, duration: 0.4) == -1)
        intent.update(x: 20, y: 1)
        #expect(intent.completed(width: 400, duration: 0.4) == nil)
        intent.update(x: -30, y: 40)
        #expect(intent.completed(width: 400, duration: 0.4) == nil)
    }
}
