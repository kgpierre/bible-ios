import SwiftUI
import UIKit

/// Reports whether the system places a vertical bar in this window (iOS 27.1's
/// `UITraitCollection.verticalBarEdge`), as on the iPhone Duo, where the status bar, toolbar, and
/// tab bar stack in a column. The system's own answer, rather than one inferred from safe areas;
/// it's `.unspecified` on hardware, size classes, and orientations without one.
struct VerticalBarProbe: UIViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) { view.onChange = onChange }

    final class ProbeView: UIView {
        var onChange: (@MainActor (Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: ProbeView, _: UITraitCollection) in
                    view.report()
                }
            }
        }

        required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { report() }
        }

        private func report() {
            if #available(iOS 27.1, *) {
                onChange?(traitCollection.verticalBarEdge != .unspecified)
            } else {
                onChange?(false)
            }
        }
    }
}
