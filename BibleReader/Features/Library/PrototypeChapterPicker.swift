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
                                Button("Books", systemImage: "books.vertical") { showingBooks = true }
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
    @ScaledMetric(relativeTo: .title2) private var cellWidth = 56.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let chapters = state.catalog.filter { $0.bookID == bookID }
                Text(state.books.first { $0.id == bookID }?.name ?? "Books")
                    .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(chapters.count == 1 ? "1 chapter" : "\(chapters.count) chapters").font(.subheadline).foregroundStyle(.secondary)
                ReferenceInputView(reader: state, didOpen: didOpen)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth))]) {
                    ForEach(chapters) { chapter in
                        Button {
                            state.navigate(to: chapter)
                            didOpen()
                        } label: {
                            Text(chapter.label)
                                .font(.title2)
                                .frame(minWidth: cellWidth, minHeight: cellWidth)
                                .foregroundStyle(state.chapterID == chapter.id ? Color(.readingCanvas) : Color(.readingPrimary))
                                .background(state.chapterID == chapter.id ? Color(.accent) : .clear, in: .circle)
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(chapter.bookName), chapter \(chapter.label)")
                        .accessibilityIdentifier("chapter-\(chapter.bookID)-\(chapter.label)")
                        .accessibilityAddTraits(state.chapterID == chapter.id ? .isSelected : [])
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.readingCanvas))
    }
}
