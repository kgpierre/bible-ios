import Foundation
import FoundationModels
import Testing
@testable import BibleReader

/// Diagnostic probe against the real on-device model. It runs only when `BIBLE_MODEL_PROBE` is set
/// (for xcodebuild: `TEST_RUNNER_BIBLE_MODEL_PROBE=1`), because results depend on model availability.
/// It prints stage outcomes per chapter; it asserts nothing about model quality.
struct SummaryRefusalProbeTests {
    static let enabled = ProcessInfo.processInfo.environment["BIBLE_MODEL_PROBE"] != nil
    static let chapters = ["GEN:1", "GEN:19", "GEN:34", "GEN:38", "LEV:18", "NUM:31", "JOS:6", "JDG:3", "JDG:19",
                           "1SA:15", "2SA:11", "2SA:13", "EST:9", "PSA:137", "SNG:7", "EZK:16", "EZK:23",
                           "MAT:27", "JHN:3", "REV:19"]

    @Test(.enabled(if: enabled)) func stageOutcomesForDifficultChapters() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let model = OnDeviceChapterModel()
        if let reason = await model.unavailableReason() {
            print("MODEL_PROBE unavailable: \(reason)")
            return
        }
        for code in Self.chapters {
            let document = try await store.chapter("eng-kjv-1769-protestant:\(code)")
            let start = ContinuousClock.now
            var line = "MODEL_PROBE \(document.reference):"
            do {
                let text = try await ChapterSummarizer(model: model).summarize(document)
                line += " ok words=\(text.split(separator: " ").count)"
            } catch {
                line += " failed=\(error)"
            }
            line += " diagnostics=\(await SummaryDiagnostics.shared.drain()) elapsed=\(ContinuousClock.now - start)"
            print(line)
        }
    }

    @Test(.enabled(if: enabled)) func questionOutcomesForDifficultChapters() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let model = OnDeviceChapterModel()
        guard await model.unavailableReason() == nil else { return }
        let cases = [("GEN:19", "What happens to Lot and his family in this chapter?"),
                     ("JDG:19", "Why did the Levite go to Bethlehem?"),
                     ("MAT:27", "Who condemned Jesus in this chapter?"),
                     ("2SA:11", "What did David do to Uriah?"),
                     ("JHN:3", "What does Jesus tell Nicodemus?")]
        for (code, question) in cases {
            let document = try await store.chapter("eng-kjv-1769-protestant:\(code)")
            let answerer = BookQuestionAnswerer(model: model, chapter: document, sources: { query in
                try await store.summarySources(bookID: document.bookID, chapterID: document.id, question: query.question,
                                               preferred: query.preferred, preferredOnly: query.preferredOnly)
            })
            var line = "MODEL_PROBE_Q \(document.reference):"
            do {
                let answer = try await answerer.answer(question)
                line += " ok sources=\(answer.sources.count)"
            } catch {
                line += " failed=\(error)"
            }
            print(line + " diagnostics=\(await SummaryDiagnostics.shared.drain())")
        }
    }
}
