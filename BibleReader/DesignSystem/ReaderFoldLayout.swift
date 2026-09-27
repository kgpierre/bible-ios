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

    /// Where a single continuous reader goes when facing pages or the tabletop split do not fit:
    /// the larger side of a book fold, and above a tabletop fold whenever that side is usable.
    var clearPane: CGRect {
        switch kind {
        case .book:
            let leading = CGRect(x: 0, y: 0, width: division.minX, height: size.height)
            let trailing = CGRect(x: division.maxX, y: 0, width: size.width - division.maxX, height: size.height)
            return leading.width >= trailing.width ? leading : trailing
        case .tabletop:
            let above = CGRect(x: 0, y: 0, width: size.width, height: division.minY)
            let below = CGRect(x: 0, y: division.maxY, width: size.width, height: size.height - division.maxY)
            return above.height >= min(below.height, 200) ? above : below
        }
    }

    func supportsBookPages(minimumPageWidth: CGFloat, accessibilitySize: Bool) -> Bool {
        kind == .book && !accessibilitySize && size.height >= 320 &&
            spreadFrame.width / 2 - innerPageInset >= minimumPageWidth
    }
}
