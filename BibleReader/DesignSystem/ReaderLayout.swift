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

    /// Clearance between the last line of a scrolling chapter and the top of the floating bottom
    /// controls (passage, tabs, and Read Aloud's player), which the reader measures directly.
    static let chapterEndClearance: CGFloat = 40
    /// Width of the lens capsule in the Duo's vertical bar, matched to the system's vertical
    /// toolbar pill as measured on the iPhone Duo outer display simulator (iOS 27.2). Recheck on hardware.
    static let sideRailControlWidth: CGFloat = 48

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
