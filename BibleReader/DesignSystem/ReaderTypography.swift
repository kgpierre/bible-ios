import SwiftUI
import UIKit

/// Named design targets from 2a and 3a–3c; fonts scale with Dynamic Type.
/// Nominal HTML line heights are deliberately not fixed native text heights.
enum ReaderTextRole {
    case eyebrow, bookTitle, chapterSubtitle, verse, verseNumber
    /// Running prose outside Scripture, such as Apple Intelligence answers: body size in the system face.
    case prose

    func pointSize(wide: Bool) -> CGFloat {
        switch self {
        case .prose: 17
        case .eyebrow: wide ? 14 : 13
        case .bookTitle: wide ? 46 : 40
        case .chapterSubtitle: wide ? 24 : 22
        case .verse: wide ? 24 : 22
        case .verseNumber: wide ? 15 : 14
        }
    }

    var relativeStyle: Font.TextStyle {
        switch self {
        case .eyebrow, .verseNumber: .caption
        case .bookTitle: .largeTitle
        case .chapterSubtitle: .title2
        case .verse, .prose: .body
        }
    }

    /// Reading text follows the in-app size adjustment, as the reader's verses do.
    var followsReadingSize: Bool { self == .verse || self == .prose }

    var weight: Font.Weight {
        switch self {
        case .eyebrow, .bookTitle: .semibold
        case .verseNumber: .medium
        case .chapterSubtitle, .verse, .prose: .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .eyebrow, .verseNumber, .prose: .default
        case .bookTitle, .chapterSubtitle, .verse: .serif
        }
    }
}

extension EnvironmentValues {
    /// The in-app reading preferences, so text outside the reader (such as the chapter overview)
    /// follows the same size and face.
    @Entry var readingTypography = ReadingTypography()
}

private struct ReaderTypography: ViewModifier {
    let role: ReaderTextRole
    let base: CGFloat
    /// Dynamic Type's factor for the role's text style; the in-app adjustment is added before it,
    /// as in the reader (`base + pointAdjustment`, then scaled).
    @ScaledMetric private var scale: CGFloat
    @Environment(\.readingTypography) private var typography

    init(role: ReaderTextRole, wide: Bool) {
        self.role = role
        base = role.pointSize(wide: wide)
        _scale = ScaledMetric(wrappedValue: 1, relativeTo: role.relativeStyle)
    }

    func body(content: Content) -> some View {
        let size = role.followsReadingSize ? max(12, base + typography.pointAdjustment) : base
        let design = role == .verse ? (typography.face == .serif ? Font.Design.serif : .default) : role.design
        content.font(.system(size: size * scale, weight: role.weight, design: design))
    }
}

extension View {
    func readerTypography(_ role: ReaderTextRole, wide: Bool = false) -> some View {
        modifier(ReaderTypography(role: role, wide: wide))
    }
}

/// Destination large titles (Saved, Search) use the reading serif while staying system navigation titles,
/// so they collapse into the bar, name the screen for VoiceOver, and scale with Dynamic Type.
enum NavigationTitleStyle {
    @MainActor static func apply() {
        let base = UIFont.preferredFont(forTextStyle: .largeTitle)
        let descriptor = base.fontDescriptor.withDesign(.serif)?
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]]) ?? base.fontDescriptor
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(descriptor: descriptor, size: 0),
            .foregroundColor: UIColor(resource: .readingPrimary)
        ]
    }
}
