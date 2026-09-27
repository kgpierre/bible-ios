import CoreGraphics

/// Layout derived from active system division regions, never a device model or hinge angle.
struct ReaderFoldLayout: Equatable {
    enum Kind { case book, tabletop }
    let kind: Kind
    let division: CGRect
    let size: CGSize

    init?(size: CGSize, divisions: [CGRect]) {
        let bounds = CGRect(origin: .zero, size: size)
        guard let region = divisions.first(where: { $0.intersects(bounds) && !$0.isEmpty }) else { return nil }
        let regionInBounds = region.intersection(bounds)
        if regionInBounds.height > regionInBounds.width,
           regionInBounds.height >= size.height * 0.8,
           regionInBounds.minX > 0, regionInBounds.maxX < size.width {
            kind = .book
        } else if regionInBounds.width >= size.width * 0.8,
                  regionInBounds.minY > 0, regionInBounds.maxY < size.height {
            kind = .tabletop
        } else { return nil }
        division = regionInBounds
        self.size = size
    }

    /// UIKit's equal facing pages are centered on the actual fold, even with asymmetric bars.
    var spreadFrame: CGRect {
        let halfWidth = min(division.midX, size.width - division.midX)
        return CGRect(x: division.midX - halfWidth, y: 0, width: halfWidth * 2, height: size.height)
    }

    /// Each text view already has a 20-point outer margin. Add only the remaining fold clearance.
    var innerPageInset: CGFloat { max(0, division.width / 2 - 20) }

    func supportsBookPages(minimumPageWidth: CGFloat, accessibilitySize: Bool) -> Bool {
        kind == .book && !accessibilitySize && size.height >= 320 &&
            spreadFrame.width / 2 - innerPageInset >= minimumPageWidth
    }
}
