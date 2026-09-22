import Foundation
import Testing
import UIKit
@testable import BibleReader

private actor SummaryFake: ChapterSummaryModel {
    let unavailable: String?
    var prompts: [String] = []
    var contextFailures: Int
    init(unavailable: String? = nil, contextFailures: Int = 0) {
        self.unavailable = unavailable
        self.contextFailures = contextFailures
    }
    func unavailableReason() -> String? { unavailable }
    func generate(instructions: String, prompt: String) async throws -> String {
        prompts.append(prompt)
        if contextFailures > 0 { contextFailures -= 1; throw ChapterSummaryError.contextLimit }
        return "Synthetic test overview."
    }
}

private actor DelayedSummaryFake: ChapterSummaryModel {
    var pending: CheckedContinuation<String, Never>?
    func unavailableReason() -> String? { nil }
    func generate(instructions: String, prompt: String) async throws -> String {
        await withCheckedContinuation { pending = $0 }
    }
    func isPending() -> Bool { pending != nil }
    func finish() { pending?.resume(returning: "Synthetic late response."); pending = nil }
}

struct ChapterSummaryTests {
    private func chapter(_ text: String) -> ChapterDocument {
        ChapterDocument(id: "synthetic:1", bookID: "synthetic", bookName: "Synthetic", eyebrow: "TEST", label: "1",
                        editionLabel: "Test", verses: [.init(id: "synthetic:1:1", label: "1", runs: [.init(text: text, italic: false)], structure: "p", headings: [], notes: [])])
    }

    @Test @MainActor func supportedSymbolExists() {
        #expect(UIImage(systemName: "apple.intelligence") != nil)
    }

    @Test @MainActor func unavailableNeverStartsGeneration() async {
        let model = SummaryFake(unavailable: "Model is not ready.")
        let state = ChapterSummaryState(chapter: chapter("Synthetic content"), model: model)
        await state.run()
        #expect(state.status == .unavailable("Model is not ready."))
        #expect(await model.prompts.isEmpty)
    }

    @Test func longInputIsLosslesslyChunkedAndContextFailuresRetrySmaller() async throws {
        let text = String(repeating: "Synthetic café 👨‍👩‍👧‍👦. ", count: 400)
        #expect(ChapterSummarizer.chunks(text, limit: 700).joined() == text)
        let model = SummaryFake(contextFailures: 1)
        let result = try await ChapterSummarizer(model: model).summarize(chapter(text))
        #expect(result == "Synthetic test overview.")
        let prompts = await model.prompts
        #expect(prompts.count > 3)
        #expect(prompts.allSatisfy { $0.contains("Synthetic 1") })
        #expect(prompts.map(\.count).max()! < 5500)
    }

    @Test @MainActor func contextFailureCanRetryWithoutChangingChapter() async {
        let model = SummaryFake(contextFailures: 1)
        let doc = chapter("Synthetic content")
        let state = ChapterSummaryState(chapter: doc, model: model)
        await state.run()
        #expect(state.status == .failed(ChapterSummaryError.contextLimit.message))
        await state.run()
        #expect(state.status == .complete("Synthetic test overview."))
        #expect(state.chapter == doc)
    }

    @Test @MainActor func cancellationRejectsLateResponse() async {
        let model = DelayedSummaryFake()
        let state = ChapterSummaryState(chapter: chapter("Synthetic content"), model: model)
        let task = Task { await state.run() }
        while !(await model.isPending()) { await Task.yield() }
        state.cancel()
        task.cancel()
        await model.finish()
        await task.value
        #expect(state.status == .cancelled)
    }
}
