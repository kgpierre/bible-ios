import SwiftUI

struct SearchView: View {
    @Bindable var state: SearchState
    var active = true
    let open: (ResolvedPassage) -> Void
    @FocusState private var focused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                results
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition(id: Binding(get: { state.scrollID }, set: { if let id = $0 { state.scrollID = id } }), anchor: .top)
        .accessibilityIdentifier("searchResults")
        .foregroundStyle(Color(.readingPrimary))
        .background(Color(.readingCanvas))
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $state.query,
                    placement: horizontalSizeClass == .regular ? .automatic : .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Word, phrase, or reference"))
        .searchFocused($focused)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) { focused = false }
        .task(id: "\(state.query)|\(state.retryToken)|\(active)") { if active { await state.run() } }
        // Opening the tab must not summon the keyboard: its first presentation after launch
        // stalls the main thread on device. Tapping the field, ⌘F, or More → Search focuses it.
        .onChange(of: active) { _, active in if !active { focused = false } }
        .onChange(of: state.focusRequest) { _,_ in focused = active }
    }

    @ViewBuilder private var results: some View {
        switch state.status {
        case .idle:
            ContentUnavailableView {
                Label("Search the Bible", systemImage: "magnifyingglass")
            } description: {
                Text("Search a reference like John 3:16, or a word or phrase in the King James Version. Use quotation marks for an exact phrase.")
            }
            .padding(.top, 40)
            .accessibilityIdentifier("searchGuidance")
        case .loading:
            ProgressView("Searching…").frame(maxWidth: .infinity).padding(.top,30)
        case .failed:
            ContentUnavailableView {
                Label("Search Couldn’t Complete", systemImage: "exclamationmark.magnifyingglass")
            } description: {
                Text("Your query has been kept.")
            } actions: {
                Button("Try Again") { state.retry() }
                    .accessibilityIdentifier("searchRetry")
            }
            .padding(.top, 40)
        case .loaded(let response):
            switch response {
            case .empty: guidance("Enter a word, a quoted phrase, or a reference such as John 3:16.")
            case .invalid(let message): guidance(message)
            case .reference(let passage):
                ReferenceResult(passage: passage, suggestion: false) { focused = false; open(passage) }
            case .suggestion(let passage):
                guidance("No reference found for “\(state.query)”. Did you mean:")
                ReferenceResult(passage: passage, suggestion: true) { focused = false; open(passage) }
            case .results(let page):
                if page.total == 0 {
                    ContentUnavailableView {
                        Label("No Results for “\(state.query)”", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another word or phrase from the King James Version.")
                    }
                    .padding(.top, 40)
                    .accessibilityIdentifier("searchNoResults")
                } else {
                    Text("^[\(page.total) verse](inflect: true) · King James Version")
                        .font(.caption).foregroundStyle(Color(.readingSecondary)).padding(.vertical,12)
                        .accessibilityIdentifier("searchCount")
                    ForEach(page.hits) { hit in
                        Button {
                            state.selectedID = hit.id
                            focused = false
                            open(ResolvedPassage(chapterID: hit.chapterID,verseIDs: [hit.id],reference: hit.reference,preview: hit.plainExcerpt))
                        } label: { SearchResultRow(hit: hit) }
                        .buttonStyle(.plain)
                        .background(state.selectedID == hit.id ? Color(.accent).opacity(0.08) : Color.clear)
                        .accessibilityIdentifier("search-hit-\(hit.id)")
                        .accessibilityAddTraits(state.selectedID == hit.id ? .isSelected : [])
                        .id(hit.id)
                        .onAppear {
                            // Load the next page as the last rows arrive; a failed page waits for Retry.
                            if hit.id == page.hits.last?.id, page.hasMore, !state.pageError {
                                Task { await state.loadMore() }
                            }
                        }
                        Divider()
                    }
                    if page.hasMore {
                        if state.pageError {
                            Button("Retry Loading Results") { Task { await state.loadMore() } }
                                .frame(maxWidth: .infinity,minHeight: 44)
                                .disabled(state.isLoadingMore)
                                .accessibilityIdentifier("searchLoadMore")
                        } else {
                            ProgressView("Loading more…").frame(maxWidth: .infinity).padding(.vertical, 12)
                                .accessibilityIdentifier("searchLoadingMore")
                        }
                    }
                }
            }
        }
    }

    private func guidance(_ message: String) -> some View {
        Text(message).font(.subheadline).foregroundStyle(Color(.readingSecondary)).padding(.vertical,20)
            .accessibilityIdentifier("searchGuidance")
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit
    @ScaledMetric(relativeTo: .body) private var excerptSize = 18.0
    private var excerpt: AttributedString {
        var result = AttributedString()
        for part in hit.excerpt {
            var run = AttributedString(part.text)
            if part.isMatch {
                run.font = .system(size: excerptSize,weight: .semibold,design: .serif)
                run.backgroundColor = Color(.accent).opacity(0.12)
            }
            result.append(run)
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 4) {
            Text(hit.reference).font(.subheadline.weight(.semibold)).foregroundStyle(Color(.accent))
            Text(excerpt).font(.system(size: excerptSize,design: .serif)).lineSpacing(4)
                .foregroundStyle(Color(.readingPrimary))
        }
        .frame(maxWidth: .infinity,alignment: .leading)
        .padding(.vertical,14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct ReferenceResult: View {
    let passage: ResolvedPassage
    let suggestion: Bool
    var active = true
    let open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Open \(passage.reference)", systemImage: "arrow.right") { open() }
                .font(.body.weight(.semibold)).frame(minHeight: 44)
                .accessibilityIdentifier(suggestion ? "openReferenceSuggestion" : "openReference")
            if !suggestion {
                Text(passage.preview).font(.system(.body,design: .serif)).lineLimit(4)
                    .foregroundStyle(Color(.readingSecondary))
            }
        }
        .padding(.vertical,12)
    }
}
