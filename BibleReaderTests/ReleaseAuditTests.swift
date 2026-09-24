import Foundation
import SwiftUI
import Testing
import UIKit
@testable import BibleReader

struct ReleaseAuditTests {
    @Test func packagedPrivacyManifestDeclaresAppPreferences() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        let types = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(types.contains { ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults" && ($0["NSPrivacyAccessedAPITypeReasons"] as? [String]) == ["CA92.1"] })
    }

    @Test @MainActor func wrappedVerseAccessibilityIncludesLastLineWithoutVoiceOver() async throws {
        let doc = try #require(await PrototypeLibrary.load().first)
        let state = ReaderState()
        state.chapters = [doc]; state.chapterID = doc.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 260, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        let entry = try #require(map.entries.first)
        let start = try #require(view.position(from: view.beginningOfDocument, offset: entry.range.location))
        let end = try #require(view.position(from: start, offset: entry.range.length))
        let range = try #require(view.textRange(from: start, to: end))
        let element = try #require(view.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }.first)
        #expect(element.accessibilityCustomActions?.isEmpty == false)
        let rectangles = view.selectionRects(for: range).filter { !$0.rect.isEmpty }
        #expect(rectangles.count > 1)
        #expect(rectangles.allSatisfy { element.accessibilityFrameInContainerSpace.contains($0.rect) })
        #expect(element.accessibilityFrameInContainerSpace.height > view.firstRect(for: range).height)
    }

    @Test @MainActor func systemUndoRestoresPersistedAnnotation() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        let reader = ReaderState(makeStore: { store })
        await reader.load()
        let manager = UndoManager()
        manager.groupsByEvent = false
        reader.connectUndoManager(manager)
        let doc = try #require(reader.document), verse = try #require(doc.verses.first)
        let part = try #require(SavedTextPart(verseID: verse.id, text: verse.text, range: NSRange(location: 0, length: 2)))
        manager.beginUndoGrouping()
        await reader.saveExact(ExactPassage(chapterID: doc.id, reference: doc.reference, parts: [part]), color: .sage)
        manager.endUndoGrouping()
        #expect(manager.canUndo)
        manager.undo()
        for _ in 0..<100 where reader.canUndo { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!reader.canUndo)
        #expect(try await store.exactAnnotations().isEmpty)
    }

}
