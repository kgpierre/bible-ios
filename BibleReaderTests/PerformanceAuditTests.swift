import XCTest
import Foundation
import SQLite3
import SwiftUI
import UIKit
@testable import BibleReader

/// Diagnostic benchmarks, not device acceptance thresholds. Run this class alone, serially.
/// Only synthetic annotations in a fresh temporary database are used.
final class PerformanceAuditTests: XCTestCase {
    @MainActor func testRendererStress() async throws {
        let corpus = try XCTUnwrap(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        let document = try await store.chapter("eng-kjv-1769-protestant:PSA:119")
        let state = ReaderState(); state.chapters = [document]; state.chapterID = document.id
        var samples: [String: [Double]] = [:]
        func record(_ name: String, _ start: CFTimeInterval) {
            samples[name, default: []].append((CACurrentMediaTime() - start) * 1000)
        }
        for _ in 0..<5 {
            let page = ChapterPageController(document: document)
            var start = CACurrentMediaTime()
            page.configure(from: state, live: false, wide: false, scheme: .light, insets: .init())
            page.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            page.view.layoutIfNeeded()
            record("adjacent_page_create_configure_layout", start)
            let view = page.textView
            start = CACurrentMediaTime()
            view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            view.updateTraitsIfNeeded()
            view.configure(document: document, state: state, wide: false, scheme: .dark)
            view.layoutIfNeeded()
            record("largest_type_dark_reflow", start)
            start = CACurrentMediaTime()
            state.highlights = Dictionary(uniqueKeysWithValues: document.verses.map { ($0.id, .sage) })
            view.configure(document: document, state: state, wide: false, scheme: .dark)
            view.layoutIfNeeded()
            record("highlight_all_176_verses", start)
            state.highlights = [:]
            start = CACurrentMediaTime()
            _ = try await store.summarySources(bookID: "PSA", chapterID: document.id, question: "law truth mercy")
            record("summary_retrieve_psalms", start)
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "RendererStress.json"; attachment.lifetime = .keepAlways; add(attachment)
        print("RENDERER_STRESS " + String(decoding: data, as: UTF8.self))
    }

    @MainActor func testAudit() async throws {
        var samples: [String: [Double]] = [:]
        func record(_ name: String, _ start: CFTimeInterval) {
            samples[name, default: []].append((CACurrentMediaTime() - start) * 1000)
        }
        let corpus = try XCTUnwrap(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PerformanceAudit-" + UUID().uuidString)
        let url = directory.appendingPathComponent("User.sqlite")
        var t = CACurrentMediaTime()
        let store = try BibleStore(corpusURL: corpus, userURL: url)
        record("store_open_fresh", t)
        t = CACurrentMediaTime()
        let bootstrap = try await store.readerBootstrap()
        record("bootstrap", t)
        let psalmID = try XCTUnwrap(bootstrap.catalog.first { $0.bookID == "PSA" && $0.label == "119" }?.id)
        t = CACurrentMediaTime()
        let psalm = try await store.chapter(psalmID)
        record("psalm119_decode_first", t)
        XCTAssertEqual(psalm.verses.count, 176)
        for _ in 0..<10 {
            t = CACurrentMediaTime(); _ = try await store.chapter(psalmID); record("psalm119_cached", t)
        }
        for query in ["the", "and", "love", "\"in the beginning\""] {
            for _ in 0..<5 {
                t = CACurrentMediaTime()
                guard case .results(let page) = try await store.search(query) else { return XCTFail("Expected results") }
                XCTAssertFalse(page.hits.isEmpty)
                record("search_" + query, t)
            }
        }
        for offset in [50, 1000, 10000] {
            t = CACurrentMediaTime(); _ = try await store.search("the", offset: offset); record("search_offset_\(offset)", t)
        }
        for _ in 0..<10 {
            t = CACurrentMediaTime(); try await store.savePosition(chapterID: psalmID, anchor: nil); record("position_write", t)
        }
        let state = ReaderState()
        state.chapters = [psalm]; state.chapterID = psalm.id
        for width in [390.0, 640.0] {
            for _ in 0..<5 {
                let view = ChapterTextView()
                view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
                t = CACurrentMediaTime()
                view.configure(document: psalm, state: state, wide: width > 400, scheme: .light)
                record("configure_\(Int(width))", t)
                t = CACurrentMediaTime(); view.layoutIfNeeded(); record("layout_\(Int(width))", t)
                t = CACurrentMediaTime()
                for _ in 0..<100 { view.configure(document: psalm, state: state, wide: width > 400, scheme: .light) }
                record("unchanged_configure_100_\(Int(width))", t)
                t = CACurrentMediaTime()
                for step in 0..<50 {
                    view.setContentOffset(CGPoint(x: 0, y: Double(step) * 80), animated: false)
                    view.layoutIfNeeded()
                }
                record("scroll_layout_50_\(Int(width))", t)
            }
        }
        // Seed genuine corpus excerpts, one per verse, across chapters; no generated Scripture.
        var records: [ExactAnnotation] = []
        let edition = await store.editionID, revision = await store.revision
        for chapter in bootstrap.catalog {
            let doc = try await store.chapter(chapter.id)
            for verse in doc.verses {
                let part = try XCTUnwrap(SavedTextPart(verseID: verse.id, text: verse.text,
                    range: NSRange(location: 0, length: verse.text.utf16.count)))
                records.append(ExactAnnotation(id: UUID().uuidString, editionID: edition, revision: revision,
                    passage: ExactPassage(chapterID: doc.id, reference: doc.reference, parts: [part]),
                    color: .sage, created: Double(records.count), updated: Double(records.count)))
                if records.count == 10000 { break }
            }
            if records.count == 10000 { break }
        }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "BEGIN", nil, nil, nil), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO exact_annotation VALUES(?,?,?)", -1, &statement, nil), SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for annotation in records {
            let payload = try JSONEncoder().encode(annotation)
            sqlite3_bind_text(statement, 1, annotation.id, -1, transient)
            sqlite3_bind_text(statement, 2, annotation.editionID, -1, transient)
            _ = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), transient) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_reset(statement)
        }
        sqlite3_finalize(statement)
        XCTAssertEqual(sqlite3_exec(db, "COMMIT", nil, nil, nil), SQLITE_OK)
        t = CACurrentMediaTime()
        let annotations = try await store.readerAnnotations()
        record("annotations_load_10000", t)
        XCTAssertEqual(annotations.1.count, 10000)
        t = CACurrentMediaTime(); state.exactAnnotations = annotations.1; record("annotations_main_assignment_10000", t)
        t = CACurrentMediaTime(); let items = try await store.savedItems(); record("saved_first_10000", t)
        XCTAssertEqual(items.count, 10000)
        for _ in 0..<5 {
            t = CACurrentMediaTime(); _ = try await store.savedItems(); record("saved_cached_10000", t)
            t = CACurrentMediaTime()
            _ = SavedOrdering.items(items, filter: .all, sort: .bible, chapters: Dictionary(uniqueKeysWithValues: bootstrap.catalog.enumerated().map { ($0.element.id, $0.offset) }))
            record("saved_main_sort_10000", t)
        }
        let output = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("PerformanceAudit.json"))
        let attachment = XCTAttachment(data: output, uniformTypeIdentifier: "public.json")
        attachment.name = "PerformanceAudit.json"; attachment.lifetime = .keepAlways; add(attachment)
        print("PERFORMANCE_AUDIT " + String(decoding: output, as: UTF8.self))
    }
}
