import SwiftUI

/// Captured chapter → loading → overview / unavailable / retryable failure. Dismissal discards output.
struct ChapterSummaryView: View {
    @Bindable var state: ChapterSummaryState
    @Environment(\.dismiss) private var dismiss
    @State private var generation: Task<Void, Never>?
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(state.chapter.reference).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("AI-generated overview · Apple Intelligence")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Group {
                        switch state.status {
                        case .idle, .loading:
                            ProgressView("Summarizing this chapter…")
                            Button("Cancel summary") { generation?.cancel(); state.cancel() }
                        case .complete(let text):
                            Text(text)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("chapterSummaryText")
                        case .unavailable(let message), .failed(let message):
                            Text(message).accessibilityIdentifier("chapterSummaryStatus")
                            Button("Try again") { start() }.accessibilityIdentifier("retryChapterSummary")
                        case .cancelled:
                            Text("Summary cancelled.")
                            Button("Try again") { start() }
                        }
                    }
                    .accessibilityFocused($statusFocused)
                    Text("Summaries use the on-device model and may contain mistakes. Compare any overview with the chapter.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .font(.body)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.readingCanvas))
            .navigationTitle("Chapter summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { generation?.cancel(); state.cancel(); dismiss() }
                        .accessibilityIdentifier("chapterSummaryDone")
                }
            }
        }
        .onAppear { start() }
        .onDisappear { generation?.cancel(); state.cancel() }
        .onChange(of: state.status) { _, status in
            if case .loading = status { return }
            statusFocused = true
        }
    }

    private func start() {
        generation?.cancel()
        generation = Task { await state.run() }
    }
}
