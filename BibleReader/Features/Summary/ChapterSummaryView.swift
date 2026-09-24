import SwiftUI

/// Session-only questions; dismissal discards generated content and never changes Scripture.
struct ChapterSummaryView: View {
    @Bindable var state: ChapterSummaryState
    var openSource: (SummarySource) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var generation: Task<Void, Never>?
    @State private var questionsShown = false
    @FocusState private var questionFocused: Bool
    @AccessibilityFocusState private var statusFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        summary
                        if questionsShown { questions }
                        Color.clear.frame(height: 1).id("latestQuestion")
                    }
                    .foregroundStyle(Color(.readingPrimary))
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .onChange(of: state.isAnswering) { _, answering in
                    guard questionsShown else { return }
                    if answering { proxy.scrollTo("pendingQuestion", anchor: .top) }
                    else if state.questionMessage != nil { proxy.scrollTo("questionError", anchor: .top) }
                    else if let last = state.exchanges.last { proxy.scrollTo(last.id, anchor: .top) }
                }
                .onChange(of: state.questionMessage) { _, message in
                    if message != nil { statusFocused = true }
                }
            }
            .background(Color(.readingCanvas))
            .safeAreaBar(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(questionsShown ? "Questions" : "Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .presentationDragIndicator(.visible)
        .onAppear { start() }
        .onDisappear { generation?.cancel(); state.cancel() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(questionsShown ? "Questions" : "Summary").font(.headline)
                Text(state.chapter.reference).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { generation?.cancel(); state.cancel(); dismiss() }
                .accessibilityIdentifier("chapterSummaryDone")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(state.chapter.reference.uppercased()).readerTypography(.eyebrow).tracking(0.6).foregroundStyle(.secondary)
                Text(state.overviewTitle).readerTypography(.bookTitle).accessibilityAddTraits(.isHeader)
            }
            Text(state.overviewQuestion).font(.subheadline).foregroundStyle(.secondary)
            overview
            if !state.peopleAndPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PEOPLE & PLACES").readerTypography(.eyebrow).tracking(0.6).foregroundStyle(.secondary)
                    SummaryChipLayout {
                        ForEach(state.peopleAndPlaces, id: \.self) { name in entity(name) }
                    }
                }
            }
            Label("AI-generated, not Scripture. May contain mistakes — compare with the text.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.readingSecondary).opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

        }
    }

    private func entity(_ name: String) -> some View {
        Text(name).font(.subheadline).padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(.readingSecondary).opacity(0.09), in: .capsule)
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(state.exchanges) { exchange in
                exchangeView(exchange).id(exchange.id)
            }
            if let pending = state.pendingQuestion {
                questionBubble(pending).id("pendingQuestion")
                ProgressView("Reading passages in \(state.chapter.bookName)…")
                Button("Cancel answer") { generation?.cancel(); state.cancel() }
            }
            if let message = state.questionMessage {
                questionBubble(state.question).id("questionError")
                Text(message).font(.body).lineSpacing(4)
                    .accessibilityIdentifier("bookQuestionStatus").accessibilityFocused($statusFocused)
            }
            Text("Questions stay within \(state.chapter.bookName). AI explanations are not Scripture. Compare them with the text.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func questionBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 24)
            Text(text).font(.body).padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color(.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }.accessibilityAddTraits(.isHeader)
    }

    private func exchangeView(_ exchange: ChapterSummaryState.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            questionBubble(exchange.question)
            Text(exchange.answer.text).font(.body).lineSpacing(4)
                .textSelection(.enabled).accessibilityIdentifier("bookAnswerText")
            if exchange.answer.showsSourceText {
                Text("Verse quotations · \(state.chapter.editionLabel)").font(.footnote).foregroundStyle(.secondary)
                ForEach(exchange.answer.sources) { source in
                    VStack(alignment: .leading, spacing: 12) {
                        sourceButtons([source])
                        Text(source.text).font(.body).lineSpacing(4).textSelection(.enabled)
                    }
                }
            } else {
                SummaryChipLayout { sourceButtons(exchange.answer.sources) }
            }
        }
    }

    @ViewBuilder private func sourceButtons(_ sources: [SummarySource]) -> some View {
        ForEach(sources) { source in
            Button {
                generation?.cancel(); state.cancel(); openSource(source); dismiss()
            } label: {
                HStack(spacing: 5) { Text(source.reference); Image(systemName: "chevron.right") }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 13).frame(minHeight: 44)
                    .background(Color(.accent).opacity(0.10), in: .capsule)
            }
            .buttonStyle(.plain).foregroundStyle(Color(.accent))
            .accessibilityLabel("Read \(source.reference)")
            .accessibilityIdentifier("summarySource-" + source.id)
        }
    }

    @ViewBuilder private var overview: some View {
        switch state.status {
        case .idle, .loading:
            if !state.draft.isEmpty {
                Text(state.draft).readerTypography(.verse).lineSpacing(6)
                    .accessibilityIdentifier("chapterSummaryDraft")
                Text("Draft overview · still generating and checking").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView("Summarizing this chapter…")
            Button("Cancel summary") { generation?.cancel(); state.cancel() }
        case .complete(let text):
            Text(text).readerTypography(.verse).lineSpacing(6)
                .textSelection(.enabled).accessibilityIdentifier("chapterSummaryText")
        case .unavailable(let message), .failed(let message):
            Text(message).readerTypography(.verse).foregroundStyle(.secondary).accessibilityIdentifier("chapterSummaryStatus")
            Button("Try again", systemImage: "arrow.clockwise") { start() }
                .buttonStyle(.borderedProminent).tint(Color(.accent)).controlSize(.large)
                .disabled(state.isAnswering).accessibilityIdentifier("retryChapterSummary")
        case .cancelled:
            Text("Summary cancelled.").foregroundStyle(.secondary)
            Button("Try again", systemImage: "arrow.clockwise") { start() }
                .buttonStyle(.borderedProminent).tint(Color(.accent)).controlSize(.large)
                .disabled(state.isAnswering)
        }
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                if !questionsShown && !questionFocused {
                    if dynamicType.isAccessibilitySize {
                        Menu("Suggested questions") {
                            ForEach(suggestions, id: \.self) { title in
                                Button(title) { state.question = title; questionFocused = true }
                            }
                        }.buttonStyle(.glass).buttonBorderShape(.capsule)
                            .padding(.horizontal, 20)
                    } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(suggestions, id: \.self) { suggestion($0) }
                        }.padding(.horizontal, 24)
                    }
                    }
                }
                if state.question.count > 350 {
                    Text("\(state.question.count)/400 characters").font(.caption).monospacedDigit()
                        .foregroundStyle(state.question.count > 400 ? Color.red : Color.secondary)
                }
                HStack(alignment: .center, spacing: 8) {
                    TextField(questionsShown ? "Ask a follow-up" : "Ask about \(state.chapter.reference)", text: $state.question, axis: .vertical)
                        .lineLimit(1...(dynamicType.isAccessibilitySize ? 2 : 4)).font(.body).focused($questionFocused)
                        .accessibilityLabel("Question about \(state.chapter.bookName)")
                        .accessibilityIdentifier("bookQuestionInput")
                        .padding(.leading, 18).padding(.vertical, 12)
                    Button(action: ask) {
                        Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                            .foregroundStyle(state.canAsk ? Color.white : Color(.readingSecondary))
                            .background(state.canAsk ? Color(.accent) : .clear, in: .circle)
                    }
                    .buttonStyle(.plain).padding(6)
                    .accessibilityLabel("Ask question").accessibilityIdentifier("askBookQuestion")
                    .disabled(!state.canAsk)
                }
                .frame(minHeight: 56)
                .background(reduceTransparency ? Color(.readingCanvas) : .clear, in: .rect(cornerRadius: 28))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: 688).frame(maxWidth: .infinity)
        .padding(.top, 14).padding(.bottom, 8)
    }

    private let suggestions = ["What happens in this chapter?", "Who is mentioned here?", "What are the main themes?"]

    private func suggestion(_ title: String) -> some View {
        Button(title) { state.question = title; questionFocused = true }
            .font(.subheadline.weight(.medium)).padding(.horizontal, 4)
            .frame(minHeight: 44)
            .buttonStyle(.glass).buttonBorderShape(.capsule)
    }

    private func ask() {
        guard state.canAsk else { return }
        questionFocused = false
        questionsShown = true
        generation?.cancel()
        generation = Task { await state.ask() }
    }

    private func start() {
        generation?.cancel()
        generation = Task { await state.run() }
    }
}

/// Wrap semantic chips without shrinking text or forcing every reference onto its own row.
private struct SummaryChipLayout: Layout {
    private let spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 640, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = layout.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let width = max(1, width)
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, natural.width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}
