import SwiftUI

struct ReferenceInputView: View {
    let reader: ReaderState
    let didOpen: () -> Void
    @State private var state: SearchState
    @State private var submission: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(reader: ReaderState, didOpen: @escaping () -> Void) {
        self.reader = reader
        self.didOpen = didOpen
        _state = State(initialValue: SearchState { query,_ in try await reader.lookupReference(query) })
    }

    private var passage: ResolvedPassage? {
        if case .loaded(.reference(let passage)) = state.status { return passage }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 18))
                    .foregroundStyle(Color(.readingSecondary)).padding(.leading, 18)
                TextField("Reference, e.g. John 3:16", text: $state.query)
                    .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                    .focused($focused).padding(.vertical, 12)
                    .accessibilityLabel("Bible reference").accessibilityIdentifier("referenceField")
                    .onSubmit { submit() }
                Button {
                    if let passage { open(passage) }
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(.readingSecondary).opacity(0.09), in: .circle)
                }
                .buttonStyle(.plain).padding(6)
                .foregroundStyle(Color(.accent))
                .disabled(passage == nil)
                .accessibilityLabel("Open reference")
                .accessibilityIdentifier(passage == nil ? "referenceGoButton" : "openReference")
            }
            .frame(minHeight: 56)
            .background(reduceTransparency ? Color(.chapterPickerCanvas) : .clear, in: .capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
            switch state.status {
            case .loaded(.reference(let passage)):
                Text(passage.reference).font(.footnote).foregroundStyle(Color(.readingSecondary))
            case .loaded(.suggestion(let passage)):
                Text("Did you mean:").font(.subheadline)
                ReferenceResult(passage: passage, suggestion: true) { open(passage) }
            case .loaded(.invalid(let message)):
                Text(message).font(.footnote).foregroundStyle(.secondary)
            case .failed:
                Text("The reference could not be checked.").font(.footnote)
                Button("Retry") { state.retry() }
            case .loading: ProgressView("Checking reference…")
            default: EmptyView()
            }
        }
        .task(id: "\(state.query)|\(state.retryToken)") { await state.run() }
        .onDisappear { submission?.cancel() }
    }

    private func submit() {
        submission?.cancel()
        let query = state.query
        submission = Task {
            await state.run(debounce: false)
            guard !Task.isCancelled, state.query == query, let passage else { return }
            open(passage)
        }
    }

    private func open(_ passage: ResolvedPassage) {
        focused = false
        reader.openPassage(passage)
        didOpen()
    }
}
