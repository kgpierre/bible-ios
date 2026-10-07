import SwiftUI
import WidgetKit

enum CardFamily: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large, extraLarge
    var id: Self { self }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .extraLarge: String(localized: "Extra Large")
        }
    }

    /// Representative iPhone widget sizes in points, for in-app previews only.
    var previewSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .extraLarge: CGSize(width: 715, height: 330)
        }
    }

    /// Candidate Scripture sizes, largest first. The smallest truncates rather than clip glyphs.
    var textSizes: [CGFloat] {
        switch self {
        case .small: [17, 15, 13, 12]
        case .medium: [20, 18, 16, 14, 13]
        case .large, .extraLarge: [26, 23, 20, 18, 16, 14]
        }
    }
}

extension Color {
    init(cardHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The card's background: a preset gradient, or an image under a legibility scrim.
struct CardBackgroundView: View {
    let style: CardStyle
    let image: Image?

    var body: some View {
        switch style.background {
        case .preset(let preset):
            LinearGradient(colors: [Color(cardHex: preset.stops.0), Color(cardHex: preset.stops.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .image:
            ZStack {
                Color(cardHex: style.usesLightInk ? 0x1E211E : 0xF7F4ED)
                if let image {
                    // Tinted Home Screens desaturate the image instead of flattening it.
                    image.resizable().widgetAccentedRenderingMode(.desaturated).scaledToFill()
                }
                // Contrast for the text, independent of what the image contains.
                LinearGradient(colors: [scrim.opacity(0.25), scrim.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var scrim: Color { style.usesLightInk ? .black : .white }
}

/// Text and attribution. Backgrounds are separate so WidgetKit can own the container background.
struct CardContentView: View {
    let card: ScriptureCard
    let family: CardFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Tinted and clear Home Screens (and the Lock Screen) remove the card background and render by
    /// luminance, where the dark card ink would vanish; let the system style the text there.
    private var ink: Color {
        guard renderingMode == .fullColor else { return .primary }
        return card.style.usesLightInk ? Color(cardHex: 0xF4F1EA) : Color(cardHex: 0x242824)
    }
    private var secondary: Color { ink.opacity(0.72) }
    private var design: Font.Design { card.style.typeface == .serif ? .serif : .default }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .small ? 6 : 10) {
            if card.kind == .chapter { chapterHeading }
            ViewThatFits(in: .vertical) {
                ForEach(family.textSizes.dropLast(), id: \.self) { size in
                    scripture(size).fixedSize(horizontal: false, vertical: true)
                }
                // Smallest size: truncate with an ellipsis instead of clipping.
                scripture(family.textSizes.last ?? 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: card.kind == .chapter ? .topLeading : .leading)
            footer
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var chapterHeading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.reference)
                .font(.system(size: family == .small ? 22 : 26, weight: .semibold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.7)
            if let count = card.verseCount {
                Text("^[\(count) verse](inflect: true)")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(secondary)
            }
        }
    }

    private func scripture(_ size: CGFloat) -> some View {
        Text(card.text)
            .font(.system(size: size, design: design))
            .lineSpacing(size * 0.22)
    }

    @ViewBuilder private var footer: some View {
        if card.kind == .passage {
            Text(family == .small ? card.reference : card.attribution)
                .font(.system(size: family == .small ? 11 : 12, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        } else if family != .small {
            Text(card.editionLabel)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(secondary)
        }
    }

    private var accessibilityText: String {
        card.kind == .chapter
            ? String(localized: "\(card.reference), \(card.editionLabel). \(card.text)")
            : String(localized: "\(card.text) \(card.reference)\(card.isExcerpt ? ", excerpt" : ""), \(card.editionLabel)")
    }
}

/// The composed card as seen in the app (the widget composes the same parts itself).
struct ScriptureCardPreview: View {
    let card: ScriptureCard
    let family: CardFamily
    let image: Image?

    var body: some View {
        CardContentView(card: card, family: family)
            .padding(family == .small ? 14 : 18)
            .frame(width: family.previewSize.width, height: family.previewSize.height)
            .background { CardBackgroundView(style: card.style, image: image) }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }
}
