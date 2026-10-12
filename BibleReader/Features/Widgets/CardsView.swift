import ImageIO
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
            Button("Delete Card", role: .destructive) { Task { await model.delete(card) } }
        } message: { _ in
            Text("Widgets showing this card will ask you to choose another. Your saved passage is not affected.")
        }
    }

    private func row(_ card: ScriptureCard) -> some View {
        CardRow(card: card, backgroundURL: model.backgroundURL(for: card))
    }

    private func deleteButton(_ card: ScriptureCard) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = card }
    }
}

/// One list row. Its background loads only while the row is on screen, downsampled to the
/// preview's size, and the task is cancelled when the row scrolls away.
private struct CardRow: View {
    let card: ScriptureCard
    let backgroundURL: URL?
    @State private var image: Image?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let size = CardFamily.medium.previewSize
                ScriptureCardPreview(card: card, family: .medium, image: image)
                    .scaleEffect(min(1, proxy.size.width / size.width), anchor: .topLeading)
            }
            .aspectRatio(CardFamily.medium.previewSize.width / CardFamily.medium.previewSize.height, contentMode: .fit)
            .frame(maxWidth: CardFamily.medium.previewSize.width)
            CardBackgroundSourceLabel(style: card.style)
        }
        .padding(.vertical, 6)
        .task(id: backgroundURL) {
            guard let url = backgroundURL else { image = nil; return }
            let pixels = CardFamily.medium.previewSize.width * displayScale
            let loaded = await CardThumbnails.shared.image(at: url, maxPixelSize: pixels)
            guard !Task.isCancelled else { return }
            image = loaded.map(Image.init(uiImage:))
        }
    }
}

/// Downsampled card backgrounds, bounded in count and cost. Background files are written once
/// under a new name and never changed in place, so the file name is a safe key.
final class CardThumbnails: Sendable {
    static let shared = CardThumbnails()
    nonisolated(unsafe) private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    func image(at url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let key = "\(url.lastPathComponent)@\(Int(maxPixelSize))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .userInitiated) { Self.downsample(url, maxPixelSize: maxPixelSize) }.value
        if let image, let cgImage = image.cgImage {
            cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }

    nonisolated private static func downsample(_ url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
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
        .task { await model.load() }
        .alert("Couldn’t Update Widget Cards", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
