import SwiftUI

/// Named design targets from 2a and 3a–3c; fonts scale with Dynamic Type.
/// Nominal HTML line heights are deliberately not fixed native text heights.
enum ReaderTextRole {
    case eyebrow, bookTitle, chapterSubtitle, verse, verseNumber

    func pointSize(wide: Bool) -> CGFloat {
        switch self {
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
        case .verse: .body
        }
    }

    var weight: Font.Weight {
        switch self {
        case .eyebrow, .bookTitle: .semibold
        case .verseNumber: .medium
        case .chapterSubtitle, .verse: .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .eyebrow, .verseNumber: .default
        case .bookTitle, .chapterSubtitle, .verse: .serif
        }
    }
}

private struct ReaderTypography: ViewModifier {
    let role: ReaderTextRole
    @ScaledMetric private var pointSize: CGFloat

    init(role: ReaderTextRole, wide: Bool) {
        self.role = role
        _pointSize = ScaledMetric(wrappedValue: role.pointSize(wide: wide), relativeTo: role.relativeStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: pointSize, weight: role.weight, design: role.design))
    }
}

extension View {
    func readerTypography(_ role: ReaderTextRole, wide: Bool = false) -> some View {
        modifier(ReaderTypography(role: role, wide: wide))
    }
}
