import SwiftUI

struct PrototypeChapterPicker: View {
    @Bindable var state: ReaderState
    let didOpen: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingBooks: Bool
    @State private var newTestament: Bool
    @State private var path: [String] = []

    init(state: ReaderState, startsWithBooks: Bool = false, didOpen: @escaping () -> Void = {}) {
        self.didOpen = didOpen
        self.state = state
        _showingBooks = State(initialValue: startsWithBooks)
        _newTestament = State(initialValue: (state.books.first { $0.id == state.document?.bookID }?.ordinal ?? 0) >= 39)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if showingBooks {
                    VStack(spacing: 0) {
                        TestamentPicker(newTestament: $newTestament).padding(.horizontal, 20).padding(.vertical, 12)
                        List(state.books.filter { ($0.ordinal >= 39) == newTestament }) { book in
                            NavigationLink(value: book.id) {
                                BookRow(book: book, selected: state.document?.bookID == book.id)
                            }
                            .accessibilityIdentifier("book-\(book.id)")
                            .listRowBackground(Color(.readingCanvas))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    .navigationTitle("Books")
                } else {
                    ChapterChoices(state: state, bookID: state.document?.bookID ?? "GEN") { didOpen(); dismiss() }
                        .navigationTitle("Chapters")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { showingBooks = true } label: {
                                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Books") }
                                }
                                    .accessibilityIdentifier("chapterBooksButton")
                            }
                        }
                }
            }
            .background(Color(.readingCanvas))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { bookID in
                ChapterChoices(state: state, bookID: bookID) { didOpen(); dismiss() }
                    .navigationTitle("Chapters")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            newTestament = (state.books.first { $0.id == state.document?.bookID }?.ordinal ?? 0) >= 39
        }
        .tint(Color(.accent))
        .frame(idealWidth: 420, idealHeight: 600)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct ChapterChoices: View {
    @Bindable var state: ReaderState
    let bookID: String
    let didOpen: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .title2) private var cellWidth = 60.0
    @ScaledMetric(relativeTo: .title2) private var numberSize = 26.0

    private var chapters: [ChapterSummary] { state.catalog.filter { $0.bookID == bookID } }
    private var bookName: String { state.books.first { $0.id == bookID }?.name ?? "Books" }

    var body: some View {
        let highlighted = state.highlightedChapterIDs
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(chapters) { chapter in
                            chapterButton(chapter, highlighted: highlighted.contains(chapter.id))
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { readingStatus; Spacer(minLength: 12); highlightLegend }
                    VStack(alignment: .leading, spacing: 8) { readingStatus; highlightLegend }
                }
                .font(.footnote).foregroundStyle(Color(.readingSecondary))
                VStack(alignment: .leading, spacing: 10) {
                    Text("GO TO").readerTypography(.eyebrow).tracking(0.6).foregroundStyle(Color(.readingSecondary))
                    ReferenceInputView(reader: state, didOpen: didOpen)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.chapterPickerCanvas))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BookDescriptions.eyebrow(for: bookID)).readerTypography(.eyebrow).tracking(0.6)
                .foregroundStyle(Color(.readingSecondary))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    bookTitle.fixedSize()
                    Spacer(minLength: 12)
                    chapterCount.fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) { bookTitle; chapterCount }
            }
        }
    }
    private var bookTitle: some View {
        Text(bookName).readerTypography(.bookTitle).foregroundStyle(Color(.readingPrimary))
            .accessibilityAddTraits(.isHeader)
    }
    private var chapterCount: some View {
        Text(chapters.count == 1 ? "1 chapter" : "\(chapters.count) chapters")
            .font(.subheadline).foregroundStyle(Color(.readingSecondary))
    }
    private var readingStatus: some View {
        Text(state.document?.bookID == bookID ? "Reading chapter \(state.document?.label ?? "")" : "Choose a chapter")
    }
    private var highlightLegend: some View {
        Label {
            Text("Has highlights")
        } icon: {
            Circle().fill(Color(.chapterHighlightMarker)).frame(width: 9, height: 9)
        }
    }

    private func chapterButton(_ chapter: ChapterSummary, highlighted: Bool) -> some View {
        let selected = state.chapterID == chapter.id
        return Button {
            state.navigate(to: chapter)
            didOpen()
        } label: {
            ZStack {
                Text(chapter.label)
                    .font(.system(size: numberSize, weight: selected ? .semibold : .regular, design: .serif))
                    .foregroundStyle(selected ? Color(.readingCanvas) : Color(.readingPrimary))
                if highlighted {
                    Circle().strokeBorder(Color(.chapterHighlightMarker), lineWidth: 1.5)
                    VStack { Spacer(); Circle().fill(Color(.chapterHighlightMarker)).frame(width: 5, height: 5).padding(.bottom, 5) }
                }
            }
                .frame(width: cellWidth, height: cellWidth)
                .background(selected ? Color(.accent) : (reduceTransparency ? Color(.chapterPickerCanvas) : .clear), in: .circle)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.bookName), chapter \(chapter.label)")
        .accessibilityValue(highlighted ? "Has highlights" : "")
        .accessibilityIdentifier("chapter-\(chapter.bookID)-\(chapter.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
