import SwiftUI

struct SearchView: View {
    @Bindable var state: SearchState
    var active = true
    let open: (ResolvedPassage) -> Void
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 38.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search")
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color(.readingSecondary))
                    TextField("Word, phrase, or reference", text: $state.query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).submitLabel(.search)
                        .accessibilityIdentifier("searchField")
                        .onSubmit { focused = false }
                    if !state.query.isEmpty {
                        Button { state.query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Clear search")
                            .accessibilityIdentifier("clearSearch")
                    }
                }
                .padding(.leading,12)
                .frame(minHeight: 44)
                .background(Color(.readingPrimary).opacity(0.06), in: .rect(cornerRadius: 14))
                if focused {
                    Button("Cancel") { focused = false }.frame(minHeight: 44)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    results
                }
                .scrollTargetLayout()
                .padding(.bottom,20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollPosition(id: Binding(get: { state.scrollID }, set: { if let id = $0 { state.scrollID = id } }), anchor: .top)
            .accessibilityIdentifier("searchResults")
        }
        .padding(.horizontal,20)
        .padding(.top,12)
        .foregroundStyle(Color(.readingPrimary))
        .tint(Color(.accent))
        .background(Color(.readingCanvas))
        .task(id: "\(state.query)|\(state.retryToken)|\(active)") { if active { await state.run() } }
        .onChange(of: active, initial: true) { _, active in focused = active && state.query.isEmpty }
        .onChange(of: state.focusRequest) { _,_ in focused = active }
    }

    @ViewBuilder private var results: some View {
        switch state.status {
        case .idle:
            guidance("Search a reference like John 3:16, or a word or phrase in the King James Version. Use quotation marks for an exact phrase.")
        case .loading:
            ProgressView("Searching…").frame(maxWidth: .infinity).padding(.top,30)
        case .failed:
            guidance("Search could not complete. Your query has been kept.")
            Button("Retry search") { state.retry() }.frame(minHeight: 44)
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
                    Text("No results for “\(state.query)”")
                        .font(.system(.title2, design: .serif)).padding(.top,28)
                        .accessibilityIdentifier("searchNoResults")
                    guidance("Try another word or phrase from the King James Version.")
                } else {
                    Text("\(page.total) verses · King James Version")
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
                        Divider()
                    }
                    if page.hasMore {
                        Button(state.pageError ? "Retry loading results" : "Load more results") { Task { await state.loadMore() } }
                            .frame(maxWidth: .infinity,minHeight: 44)
                            .disabled(state.isLoadingMore)
                            .accessibilityIdentifier("searchLoadMore")
                        if state.isLoadingMore { ProgressView("Loading more…").frame(maxWidth: .infinity) }
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
