import SwiftUI
import UIKit

/// Reports whether this window's device has a hinge, from UIKit's public hinge interaction.
/// A hierarchy on a device without a hinge never provides a hinge, so the answer stays false;
/// no device model or screen size is consulted.
struct HingeProbe: UIViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        if #available(iOS 27.1, *) {
            let report = onChange
            view.addInteraction(UIHingeInteraction { _, update in report(update.hinge != nil) })
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
