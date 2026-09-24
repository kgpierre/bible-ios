import Foundation
import Observation

enum ReadingFace: String, Codable, CaseIterable, Identifiable, Sendable {
    case serif, sans
    var id: Self { self }
    var title: String { self == .serif ? String(localized: "Serif") : String(localized: "System Sans") }
}

enum ReadingSpacing: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact, standard, relaxed
    var id: Self { self }
    var extraPoints: Double { switch self { case .compact: -2; case .standard: 0; case .relaxed: 4 } }
    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .standard: String(localized: "Standard")
        case .relaxed: String(localized: "Relaxed")
        }
    }
}

struct ReadingTypography: Codable, Equatable, Sendable {
    var face: ReadingFace = .serif
    var sizeAdjustment = 0
    var spacing: ReadingSpacing = .standard
    var pointAdjustment: Double { Double(min(4, max(-2, sizeAdjustment))) * 2 }
}

@MainActor @Observable
final class ReaderPreferences {
    var theme: AppAppearance { didSet { save() } }
    var typography: ReadingTypography { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults
    private struct Payload: Codable {
        var version = 1
        var theme: AppAppearance
        var typography: ReadingTypography
    }
    private static let key = "reader.appearance.v1"

    init(defaults: UserDefaults? = nil) {
        #if DEBUG
        if let defaults { self.defaults = defaults }
        else if let testID = ProcessInfo.processInfo.environment["BIBLE_TEST_STORE"],
                let isolated = UserDefaults(suiteName: "BibleReader.UI-\(testID)") { self.defaults = isolated }
        else { self.defaults = .standard }
        #else
        self.defaults = defaults ?? .standard
        #endif
        if let data = self.defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Payload.self, from: data), stored.version == 1 {
            theme = stored.theme
            typography = stored.typography
            typography.sizeAdjustment = min(4, max(-2, typography.sizeAdjustment))
        } else { theme = .system; typography = ReadingTypography() }
    }

    func resetReadingStyle() { typography = ReadingTypography() }
    private func save() {
        guard let data = try? JSONEncoder().encode(Payload(theme: theme, typography: typography)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
