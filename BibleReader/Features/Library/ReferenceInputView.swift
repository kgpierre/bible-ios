import SwiftUI

struct ReferenceInputView: View {
    let reader: ReaderState
    let didOpen: () -> Void
    @State private var state: SearchState
    @FocusState private var focused: Bool

    init(reader: ReaderState, didOpen: @escaping () -> Void) {
        self.reader = reader
        self.didOpen = didOpen
        _state = State(initialValue: SearchState { query,_ in try await reader.lookupReference(query) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Go to a reference, e.g. John 3:16", text: $state.query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                .focused($focused)
                .accessibilityIdentifier("referenceField")
                .onSubmit {
                    if case .loaded(.reference(let passage)) = state.status { open(passage) }
                }
            switch state.status {
            case .loaded(.reference(let passage)):
                ReferenceResult(passage: passage,suggestion: false) { open(passage) }
            case .loaded(.suggestion(let passage)):
                Text("Did you mean:").font(.subheadline)
                ReferenceResult(passage: passage,suggestion: true) { open(passage) }
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
    }

    private func open(_ passage: ResolvedPassage) {
        focused = false
        reader.openPassage(passage)
        didOpen()
    }
}
