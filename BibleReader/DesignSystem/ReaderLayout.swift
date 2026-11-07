import Foundation

/// Content layout tokens, not device dimensions or fixed accessibility constraints.
enum ReaderLayout {
    static let outerMargin: CGFloat = 16
    static let sectionSpacing: CGFloat = 26
    static let maximumColumnWidth: CGFloat = 640
    static let minimumControlTarget: CGFloat = 44
    static let verseGap: CGFloat = 6
    static let compactGutter: CGFloat = 36
    static let wideGutter: CGFloat = 40

    /// A page needs a 340-point text column plus its gutter and outer margins at default type.
    /// This is a content requirement, not an iPad or Duo screen-size check.
    static let minimumPageWidth: CGFloat = 420
    /// Book posture accepts a narrower 280-point column plus gutter/margins, like a small book.
    static let minimumBookPageWidth: CGFloat = 360

    /// Clearance below the last line of a scrolling chapter, beyond the floating bottom chrome the
    /// safe area already reserves, so the final verse rests well clear of the capsules.
    static let chapterEndClearance: CGFloat = 72
    /// Side controls need this much trailing safe area (the system status/toolbar column) to fit.
    static let minimumSideRailInset: CGFloat = 60

    /// Width of the trailing system column when navigation should move into it (the Duo outer
    /// display's presentation: status and toolbar stacked at one side). Derived only from live
    /// asymmetric safe areas, so a symmetric landscape phone or a plain portrait phone is untouched.
    /// Accessibility sizes keep the bottom bars, whose two-row layout already fits every label.
    static func sideRailWidth(safeLeading: CGFloat, safeTrailing: CGFloat, accessibilitySize: Bool,
                              verticalCompact: Bool = false, usableSize: CGSize) -> CGFloat? {
        // A landscape phone (compact height) never takes the rail, even if one side's inset is large.
        guard !accessibilitySize, !verticalCompact, safeTrailing >= minimumSideRailInset, safeLeading <= 20 else { return nil }
        // The system's own toolbar shares the column, so the rail needs a tall, portrait container.
        // A rotated (landscape) outer display is too short and keeps the bottom row (7 November 2026).
        guard usableSize.height >= minimumSideRailHeight, usableSize.height > usableSize.width else { return nil }
        return safeTrailing
    }

    /// Width and center of the Duo rail's controls, matched to the system's vertical toolbar pill as
    /// measured on the iPhone Duo outer display simulator (iOS 27.2): about 48 points wide, centered
    /// 36 points in from the trailing column's leading edge. Recheck on hardware.
    static let sideRailControlWidth: CGFloat = 48
    static let sideRailCenterInset: CGFloat = 36

    /// Room for the system toolbar column plus the passage control and three destinations.
    static let minimumSideRailHeight: CGFloat = 560

    /// Regular-width windows with room in height (iPad, Duo inner display) use the system top tab bar
    /// and a trailing passage capsule. Compact width, or compact height such as a landscape phone,
    /// keeps the 2a bottom row so both controls share one baseline below the text.
    static func usesTopTabLayout(horizontalCompact: Bool, verticalCompact: Bool) -> Bool {
        !horizontalCompact && !verticalCompact
    }

    static func supportsTwoPages(in size: CGSize, regularWidth: Bool,
                                 minimumPageWidth: CGFloat, accessibilitySize: Bool) -> Bool {
        regularWidth && !accessibilitySize && size.width.isFinite && size.height.isFinite &&
            size.height >= 320 && size.width > size.height &&
            size.width >= 2 * max(Self.minimumPageWidth, minimumPageWidth)
    }
}
