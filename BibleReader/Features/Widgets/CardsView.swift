import SwiftUI

/// What the Widgets sheet opens to: the card list, or the editor for a new card from Saved.
enum CardsRequest: Identifiable {
    case library
    case new(ScriptureCard)
    var id: String {
        switch self {
        case .library: "library"
        case .new(let card): card.id.uuidString
        }
    }
}

/// The user's widget cards, with live previews, editing, and deletion.
struct CardsView: View {
    let model: CardsModel
    let onDone: () -> Void
    @State private var editing: ScriptureCard?
    @State private var pendingDelete: ScriptureCard?
    @State private var images: [UUID: Image] = [:]

    var body: some View {
        List {
            if model.cards.isEmpty {
                ContentUnavailableView {
                    Label("No Widgets Yet", systemImage: "widget.small")
                } description: {
                    Text("In Saved, touch and hold a passage or chapter and choose Make Widget.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.cards) { card in
                        // A navigation row with a disclosure chevron: tapping opens the card's editor.
                        NavigationLink(value: card) { row(card) }
                            .accessibilityIdentifier("card-\(card.reference)")
                            .accessibilityHint("Edit widget card")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { deleteButton(card) }
                            .contextMenu {
                                Button("Edit", systemImage: "paintbrush") { editing = card }
                                deleteButton(card)
                            }
                    }
                } footer: {
                    Text("To add a widget, touch and hold the Home Screen or Lock Screen, tap Edit, then Add Widget, and choose Bible. Touch and hold the widget and choose Edit Widget to pick a card or rotate daily.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.readingCanvas))
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .close) { onDone() }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("cardsDoneButton")
            }
        }
        .navigationDestination(for: ScriptureCard.self) { card in
            CardEditorView(card: card, model: model, isRoot: false) {}
        }
        .navigationDestination(item: $editing) { card in
            CardEditorView(card: card, model: model, isRoot: false) { editing = nil }
        }
        .confirmationDialog("Delete this widget card?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { card in
            Button("Delete Card", role: .destructive) { model.delete(card) }
        } message: { _ in
            Text("Widgets showing this card will ask you to choose another. Your saved passage is not affected.")
        }
        .task(id: model.cards.map(\.updated)) { await loadImages() }
    }

    private func row(_ card: ScriptureCard) -> some View {
        GeometryReader { proxy in
            let size = CardFamily.medium.previewSize
            ScriptureCardPreview(card: card, family: .medium, image: images[card.id])
                .scaleEffect(min(1, proxy.size.width / size.width), anchor: .topLeading)
        }
        .aspectRatio(CardFamily.medium.previewSize.width / CardFamily.medium.previewSize.height, contentMode: .fit)
        .frame(maxWidth: CardFamily.medium.previewSize.width)
        .padding(.vertical, 6)
    }

    private func deleteButton(_ card: ScriptureCard) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = card }
    }

    private func loadImages() async {
        var loaded: [UUID: Image] = [:]
        for card in model.cards {
            guard let url = model.backgroundURL(for: card) else { continue }
            if let image = await Task.detached(operation: { UIImage(contentsOfFile: url.path) }).value {
                loaded[card.id] = Image(uiImage: image)
            }
        }
        images = loaded
    }
}

/// The sheet's navigation root for either entry point.
struct CardsSheet: View {
    let request: CardsRequest
    let model: CardsModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            switch request {
            case .library:
                CardsView(model: model, onDone: onDone)
            case .new(let card):
                CardEditorView(card: card, model: model, isRoot: true, onFinish: onDone)
            }
        }
        .tint(Color(.accent))
        .onAppear { model.load() }
        .alert("Couldn’t Update Widget Cards", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
