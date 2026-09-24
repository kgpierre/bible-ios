import UIKit

/// A finite opportunity to finish a protected local write; never a guarantee after device lock.
@MainActor final class BackgroundWriteLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save reading position") { [weak self] in
            self?.end()
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
