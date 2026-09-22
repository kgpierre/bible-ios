import os

/// Static interval names only: no passages, questions, annotations, or paths enter diagnostics.
/// Instruments can enable these locally without an analytics or logging service.
enum ReaderPerformance {
    static let signposter = OSSignposter(subsystem: "org.example.BibleReader", category: .pointsOfInterest)
}
