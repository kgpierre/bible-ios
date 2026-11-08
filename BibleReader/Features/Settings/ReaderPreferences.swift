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

/// Wide landscape presentation, including regular-width phones. Stored beside typography: switching layouts must not
/// rebuild the reader's attributed text the way a typography change does.
enum ReadingPageLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case scroll, twoPages
    var id: Self { self }
    var title: String { self == .scroll ? String(localized: "Scroll") : String(localized: "Two Pages") }
}

struct ReadingTypography: Codable, Equatable, Sendable {
    var face: ReadingFace = .serif
    var sizeAdjustment = 0
    var spacing: ReadingSpacing = .standard
    /// Marks verses that have source-edition notes. Added after v1 preferences shipped, so a
    /// stored payload without it decodes with the default instead of discarding the others.
    var showsNotes = true
    /// Whole 2-point steps on top of Dynamic Type.
    static let sizeRange = -4...4
    static func clamp(_ step: Int) -> Int { min(sizeRange.upperBound, max(sizeRange.lowerBound, step)) }
    var pointAdjustment: Double { Double(Self.clamp(sizeAdjustment)) * 2 }
    /// Only the fields that change text layout or pagination. Note markers sit in the gutter, so
    /// toggling them alone must not rebuild text, repaginate, or disturb a selection.
    var layout: ReadingTypography {
        var layout = self
        layout.showsNotes = true
        return layout
    }

    init(face: ReadingFace = .serif, sizeAdjustment: Int = 0, spacing: ReadingSpacing = .standard, showsNotes: Bool = true) {
        self.face = face
        self.sizeAdjustment = sizeAdjustment
        self.spacing = spacing
        self.showsNotes = showsNotes
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        face = try values.decodeIfPresent(ReadingFace.self, forKey: .face) ?? .serif
        sizeAdjustment = try values.decodeIfPresent(Int.self, forKey: .sizeAdjustment) ?? 0
        spacing = try values.decodeIfPresent(ReadingSpacing.self, forKey: .spacing) ?? .standard
        showsNotes = try values.decodeIfPresent(Bool.self, forKey: .showsNotes) ?? true
    }
}

@MainActor @Observable
final class ReaderPreferences {
    var theme: AppAppearance { didSet { save() } }
    var typography: ReadingTypography { didSet { save() } }
    /// Facing pages by default wherever two readable pages fit; narrow windows still scroll.
    var pageLayout: ReadingPageLayout { didSet { save() } }
    /// Opt-in (owner request, 7 November 2026): while a foldable is open, offer the book and chapter
    /// to its outer display, which the system shows only where it makes that display available.
    var showsChapterOnOuterDisplay: Bool { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults
    /// Version 2 made Two Pages the default. A version 1 page layout predates that default, so it
    /// reads as Two Pages once; every other value carries over. An older `automaticBookLayout`
    /// key is ignored: facing pages in a book pose are always on.
    private struct Payload: Codable {
        var version = 2
        var theme: AppAppearance
        var typography: ReadingTypography
        var pageLayout: ReadingPageLayout?
        /// Added after version 2 shipped; absent means off.
        var showsChapterOnOuterDisplay: Bool?
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
           let stored = try? JSONDecoder().decode(Payload.self, from: data), (1...2).contains(stored.version) {
            theme = stored.theme
            typography = stored.typography
            pageLayout = stored.version == 1 ? .twoPages : stored.pageLayout ?? .twoPages
            showsChapterOnOuterDisplay = stored.showsChapterOnOuterDisplay ?? false
            typography.sizeAdjustment = ReadingTypography.clamp(typography.sizeAdjustment)
        } else { theme = .system; typography = ReadingTypography(); pageLayout = .twoPages; showsChapterOnOuterDisplay = false }
    }

    func resetReadingStyle() { typography = ReadingTypography() }
    private func save() {
        guard let data = try? JSONEncoder().encode(Payload(theme: theme, typography: typography, pageLayout: pageLayout,
                                                           showsChapterOnOuterDisplay: showsChapterOnOuterDisplay)) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
