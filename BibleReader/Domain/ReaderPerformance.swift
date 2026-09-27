import os

/// Static interval names only: no passages, questions, annotations, or paths enter diagnostics.
/// Instruments can enable these locally without an analytics or logging service.
enum ReaderPerformance {
    static let signposter = OSSignposter(subsystem: "dev.kpierre.bible", category: .pointsOfInterest)
    /// Emitted once per process when laid-out Scripture first has real bounds; pair with launch
    /// instruments to separate first frame, first readable chapter, and responsiveness.
    @MainActor private static var firstScriptureMarked = false
    @MainActor static func markFirstScriptureLaidOut() {
        guard !firstScriptureMarked else { return }
        firstScriptureMarked = true
        signposter.emitEvent("First Scripture laid out")
    }
}
