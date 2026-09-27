#if DEBUG
import UIKit

/// Debug-only physical-device check of Complete file protection. Launch with `--lock-probe`,
/// open a chapter, lock the device, wait at least 30 seconds, then unlock. The probe reads and
/// writes the user store at +0, +2 and +20 seconds after backgrounding (the class keys are
/// discarded about 10 seconds after lock), then again after unlock, runs an integrity check, and
/// shows a report. It records timings and outcomes only: no passages, anchors, or paths.
@MainActor final class LockProbe {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--lock-probe")
    private let reader: ReaderState
    private let report: (String) -> Void
    private var lines: [String] = []
    private var backgrounded: Date?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var run: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(reader: ReaderState, report: @escaping (String) -> Void) {
        self.reader = reader
        self.report = report
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didEnterBackground() }
            },
            center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.log("protected data will become unavailable") }
            },
            center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.log("protected data available") }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willEnterForeground() }
            },
        ]
    }

    private func log(_ event: String) {
        let offset = backgrounded.map { String(format: "+%.1fs", Date().timeIntervalSince($0)) } ?? "–"
        lines.append("\(offset) \(event) [protected data \(UIApplication.shared.isProtectedDataAvailable ? "available" : "unavailable")]")
    }

    private func didEnterBackground() {
        run?.cancel()
        lines = []
        backgrounded = Date()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Lock probe") { [weak self] in
            MainActor.assumeIsolated {
                self?.log("background time expired")
                self?.endBackgroundTask()
            }
        }
        run = Task {
            for (delay, label) in [(0.0, "check"), (2.0, "check"), (18.0, "check")] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                log("\(label): \(await reader.lockProbeCheck())")
            }
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func willEnterForeground() {
        run?.cancel()
        endBackgroundTask()
        Task {
            log("after unlock: \(await reader.lockProbeCheck())")
            report(lines.joined(separator: "\n"))
        }
    }
}
#endif
