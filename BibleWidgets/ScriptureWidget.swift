import AppIntents
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

@main
struct BibleWidgetsBundle: WidgetBundle {
    var body: some Widget { ScriptureWidget() }
}

struct ScriptureWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ScriptureCard", intent: SelectCardIntent.self, provider: CardProvider()) { entry in
            CardWidgetView(entry: entry)
        }
        .configurationDisplayName("Scripture")
        .description("A passage or chapter you saved, on a card you designed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Configuration

struct CardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static let defaultQuery = CardQuery()
    let id: UUID
    let reference: String
    let preview: String

    init(_ card: ScriptureCard) {
        id = card.id
        reference = card.reference
        preview = String(card.text.prefix(60))
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(reference)", subtitle: "\(preview)")
    }
}

struct CardQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CardEntity] {
        let wanted = Set(identifiers)
        return loadCards().filter { wanted.contains($0.id) }.map(CardEntity.init)
    }

    func suggestedEntities() async throws -> [CardEntity] {
        loadCards().sorted { $0.updated > $1.updated }.map(CardEntity.init)
    }

    func defaultResult() async -> CardEntity? {
        loadCards().max { $0.updated < $1.updated }.map(CardEntity.init)
    }
}

struct SelectCardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Card"
    static let description = IntentDescription("Choose one of the widget cards you made in Bible, or rotate through them daily.")

    @Parameter(title: "Card")
    var card: CardEntity?

    @Parameter(title: "Rotate Daily", default: false)
    var rotate: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$rotate, .equalTo, true) {
            Summary("Rotate through my cards daily \(\.$rotate)")
        } otherwise: {
            Summary("Show \(\.$card) \(\.$rotate)")
        }
    }
}

private func loadCards() -> [ScriptureCard] {
    (try? CardLibrary.shared()?.load()) ?? []
}

// MARK: - Timeline

struct CardEntry: TimelineEntry {
    enum Content {
        case card(ScriptureCard, UIImage?)
        /// No cards yet, or the chosen card was deleted.
        case empty(removed: Bool)
    }

    let date: Date
    let content: Content
}

struct CardProvider: AppIntentTimelineProvider {
    /// Verbatim from the bundled corpus (Psalm 23:1, KJV). Shown redacted while loading.
    private static let sample = ScriptureCard(id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!, kind: .passage,
        chapterID: "eng-kjv-1769-protestant:PSA:23", verseID: "eng-kjv-1769-protestant:PSA:23:1",
        reference: "Psalms 23:1", text: "The LORD is my shepherd; I shall not want.", isExcerpt: false,
        editionLabel: "KJV", verseCount: nil, style: CardStyle(background: .preset(.sage)),
        created: .distantPast, updated: .distantPast)

    func placeholder(in context: Context) -> CardEntry {
        CardEntry(date: .now, content: .card(Self.sample, nil))
    }

    func snapshot(for configuration: SelectCardIntent, in context: Context) async -> CardEntry {
        let entry = entry(for: configuration, on: .now, in: context)
        // The widget gallery shows a real-looking card even before the user has made one.
        if context.isPreview, case .empty = entry.content { return placeholder(in: context) }
        return entry
    }

    func timeline(for configuration: SelectCardIntent, in context: Context) async -> Timeline<CardEntry> {
        let now = Date.now
        guard configuration.rotate else {
            // The app reloads timelines whenever cards change.
            return Timeline(entries: [entry(for: configuration, on: now, in: context)], policy: .never)
        }
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        return Timeline(entries: [entry(for: configuration, on: now, in: context),
                                  entry(for: configuration, on: tomorrow, in: context)], policy: .after(dayAfter))
    }

    private func entry(for configuration: SelectCardIntent, on date: Date, in context: Context) -> CardEntry {
        let cards = loadCards()
        let card: ScriptureCard?
        if configuration.rotate {
            card = CardLibrary.rotationCard(cards, on: date)
        } else if let chosen = configuration.card {
            card = cards.first { $0.id == chosen.id }
            if card == nil { return CardEntry(date: date, content: .empty(removed: true)) }
        } else {
            card = cards.max { $0.updated < $1.updated }
        }
        guard let card else { return CardEntry(date: date, content: .empty(removed: false)) }
        return CardEntry(date: date, content: .card(card, image(for: card, size: context.displaySize)))
    }

    /// Decodes only as many pixels as the widget shows; full-size images exceed widget memory limits.
    private func image(for card: ScriptureCard, size: CGSize) -> UIImage? {
        guard let file = card.style.imageFile, let url = CardLibrary.shared()?.backgroundURL(file),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxPixels = max(size.width, size.height) * 3
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 300)]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

// MARK: - Views

struct CardWidgetView: View {
    let entry: CardEntry
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch entry.content {
        case .card(let card, let image):
            cardView(card, image: image)
                .widgetURL(CardLink.url(chapterID: card.chapterID, verseID: card.verseID))
        case .empty(let removed):
            emptyView(removed: removed)
        }
    }

    @ViewBuilder private func cardView(_ card: ScriptureCard, image: UIImage?) -> some View {
        switch widgetFamily {
        case .accessoryInline:
            Text("\(card.reference) \(card.text)")
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(card.reference).font(.headline).widgetAccentable()
                Text(card.text).font(.system(.caption, design: .serif)).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        default:
            CardContentView(card: card, family: family)
                .containerBackground(for: .widget) {
                    CardBackgroundView(style: card.style,
                                       image: image.map { Image(uiImage: $0) })
                }
        }
    }

    private var family: CardFamily {
        switch widgetFamily {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemExtraLarge: .extraLarge
        default: .large
        }
    }

    @ViewBuilder private func emptyView(removed: Bool) -> some View {
        let message: LocalizedStringKey = removed ? "This card was removed. Edit the widget to choose another."
                                                  : "Make a widget from Saved in Bible."
        switch widgetFamily {
        case .accessoryInline:
            Text(message).containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            Text(message).font(.caption).containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.title2)
                Text(message)
                    .font(.system(.subheadline, design: .serif))
            }
            .foregroundStyle(renderingMode == .fullColor ? Color(cardHex: 0x242824) : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { CardBackgroundView(style: CardStyle(), image: nil) }
        }
    }
}
