import Testing
import UIKit
@testable import BibleReader

struct ReadingColorTests {
    /// Protect actual asset readability, including the proposed dark highlight fills.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    @MainActor
    func scriptureContrastAcrossReadingSurfaces(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let foreground = try color(named: "ReadingPrimary", traits: traits)
        for name in ["ReadingCanvas", "HighlightYellow", "HighlightSage", "HighlightBlue", "HighlightRose"] {
            let background = try color(named: name, traits: traits)
            let ratio = (max(luminance(foreground), luminance(background)) + 0.05)
                / (min(luminance(foreground), luminance(background)) + 0.05)
            #expect(ratio >= 4.5, "Insufficient text contrast over \(name)")
        }
    }

    @MainActor
    private func color(named name: String, traits: UITraitCollection) throws -> UIColor {
        try #require(UIColor(named: name, in: .main, compatibleWith: traits))
            .resolvedColor(with: traits)
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
