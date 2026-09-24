import SwiftUI

struct PrototypeChapterPicker: View {
    @Bindable var state: ReaderState
    let didOpen: () -> Void
    private let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showingBooks: Bool
    @State private var newTestament: Bool
    @State private var path: [String] = []

    init(state: ReaderState, startsWithBooks: Bool = false, onClose: (() -> Void)? = nil, didOpen: @escaping () -> Void = {}) {
        self.onClose = onClose
        self.didOpen = didOpen
        self.state = state
        _showingBooks = State(initialValue: startsWithBooks)
        _newTestament = State(initialValue: (state.books.first { $0.id == state.document?.bookID }?.ordinal ?? 0) >= 39)
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
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
                    ChapterChoices(state: state, bookID: state.document?.bookID ?? "GEN") { didOpen(); close() }
                        .navigationTitle("Chapters")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { showingBooks = true } label: {
                                    Label("Books", systemImage: "books.vertical")
                                }
                                    .accessibilityIdentifier("chapterBooksButton")
                            }
                        }
                }
            }
            .background(Color(.readingCanvas))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { bookID in
                ChapterChoices(state: state, bookID: bookID) { didOpen(); close() }
                    .navigationTitle("Chapters")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button(role: .close) { close() }
                            .labelStyle(.iconOnly).accessibilityIdentifier("chapterPickerClose") }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(role: .close) { close() }
                            .labelStyle(.iconOnly).accessibilityIdentifier("chapterPickerClose") }
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
                Group {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(chapters) { chapter in
                            chapterButton(chapter, highlighted: highlighted.contains(chapter.id))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("GO TO").readerTypography(.eyebrow).tracking(0.6).foregroundStyle(Color(.readingSecondary))
                    ReferenceInputView(reader: state, didOpen: didOpen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .overlay { Circle().strokeBorder(Color(.readingSecondary).opacity(selected ? 0 : 0.3), lineWidth: 1) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.bookName), chapter \(chapter.label)")
        .accessibilityValue(highlighted ? "Has highlights" : "")
        .accessibilityIdentifier("chapter-\(chapter.bookID)-\(chapter.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
