import SwiftUI

extension View {
    /// Direct-reference navigation through the system search field, using the Search parser.
    func referenceSearch(reader: ReaderState, didOpen: @escaping () -> Void) -> some View {
        modifier(ReferenceSearch(reader: reader, didOpen: didOpen))
    }
}

private struct ReferenceSearch: ViewModifier {
    let reader: ReaderState
    let didOpen: () -> Void
    @State private var state: SearchState
    @State private var submission: Task<Void, Never>?

    init(reader: ReaderState, didOpen: @escaping () -> Void) {
        self.reader = reader
        self.didOpen = didOpen
        _state = State(initialValue: SearchState { query,_ in try await reader.lookupReference(query) })
    }

    private var passage: ResolvedPassage? {
        if case .loaded(.reference(let passage)) = state.status { return passage }
        return nil
    }

    func body(content: Content) -> some View {
        content
            .searchable(text: $state.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Go to reference, e.g. John 3:16"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .searchSuggestions { suggestions }
            .onSubmit(of: .search) { submit() }
            .task(id: "\(state.query)|\(state.retryToken)") { await state.run() }
            .onDisappear { submission?.cancel() }
    }

    @ViewBuilder private var suggestions: some View {
        switch state.status {
        case .loaded(.reference(let passage)):
            Button { open(passage) } label: {
                Label("Open \(passage.reference)", systemImage: "arrow.right")
            }
            .accessibilityIdentifier("openReference")
        case .loaded(.suggestion(let passage)):
            // Typo corrections always wait for a tap; they are never applied silently.
            Button { open(passage) } label: {
                Label("Did you mean \(passage.reference)?", systemImage: "arrow.right")
            }
            .accessibilityIdentifier("openReferenceSuggestion")
        case .loaded(.invalid(let message)):
            Text(message).font(.footnote).foregroundStyle(.secondary)
        case .failed:
            Button("Retry Reference Check") { state.retry() }
        case .loading:
            ProgressView("Checking reference…")
        default:
            EmptyView()
        }
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
        reader.openPassage(passage)
        didOpen()
    }
}
