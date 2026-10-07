import Foundation

/// A widget card the user designed from a Saved passage or chapter. `text` is copied verbatim from
/// the bundled corpus (or the exact saved excerpt) when the card is made; it is never generated.
struct ScriptureCard: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case passage, chapter }

    var id: UUID
    var kind: Kind
    var chapterID: String
    /// First verse, opened by the widget link. Nil opens the chapter at its start.
    var verseID: String?
    var reference: String
    var text: String
    var isExcerpt: Bool
    var editionLabel: String
    var verseCount: Int?
    var style: CardStyle
    var created: Date
    var updated: Date

    /// "— John 3:16, KJV", matching copy/share attribution.
    var attribution: String { "— \(reference), \(editionLabel)" }
}

struct CardStyle: Codable, Hashable, Sendable {
    enum Background: Codable, Hashable, Sendable {
        case preset(CardPreset)
        /// A downsampled JPEG in the card library; luminance (0–1) chooses automatic ink.
        case image(file: String, source: ImageSource, luminance: Double)
    }

    enum ImageSource: String, Codable, Sendable { case imagePlayground, photo }

    enum Ink: String, Codable, CaseIterable, Identifiable, Sendable {
        case automatic, light, dark
        var id: Self { self }
    }

    enum Typeface: String, Codable, CaseIterable, Identifiable, Sendable {
        case serif, sans
        var id: Self { self }
    }

    var background: Background = .preset(.paper)
    var ink: Ink = .automatic
    var typeface: Typeface = .serif

    var usesLightInk: Bool {
        switch ink {
        case .light: true
        case .dark: false
        case .automatic:
            switch background {
            case .preset(let preset): preset.isDark
            case .image(_, _, let luminance): luminance < 0.6
            }
        }
    }

    var imageFile: String? {
        if case .image(let file, _, _) = background { file } else { nil }
    }
}

enum CardPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case paper, evening, sage, dawn, ink, rose
    var id: Self { self }

    var title: String {
        switch self {
        case .paper: String(localized: "Paper")
        case .evening: String(localized: "Evening")
        case .sage: String(localized: "Sage")
        case .dawn: String(localized: "Dawn")
        case .ink: String(localized: "Ink")
        case .rose: String(localized: "Rose")
        }
    }

    var isDark: Bool { self == .evening || self == .ink }

    /// Top and bottom gradient stops as 0xRRGGBB, drawn from the reader palette.
    var stops: (UInt32, UInt32) {
        switch self {
        case .paper: (0xF7F4ED, 0xEDE6D6)
        case .evening: (0x26324A, 0x463A5C)
        case .sage: (0xE1EBD7, 0xBFD2B4)
        case .dawn: (0xF8E3CF, 0xEBC0B0)
        case .ink: (0x1E211E, 0x2E332E)
        case .rose: (0xF2E1E5, 0xDDBAC4)
        }
    }
}

/// Links from a widget back into the reader. Callers still validate IDs against the catalog.
enum CardLink {
    static let scheme = "dev.kpierre.bible"

    static func url(chapterID: String, verseID: String?) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "chapter", value: chapterID)] + (verseID.map { [URLQueryItem(name: "verse", value: $0)] } ?? [])
        return components.url
    }

    static func parse(_ url: URL) -> (chapterID: String, verseID: String?)? {
        guard url.scheme == scheme, url.host == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let chapterID = items.first(where: { $0.name == "chapter" })?.value,
              !chapterID.isEmpty, chapterID.count <= 128 else { return nil }
        let verseID = items.first(where: { $0.name == "verse" })?.value
        // A verse must belong to the linked chapter (edition:book:chapter:verse).
        if let verseID, !verseID.hasPrefix(chapterID + ":") || verseID.count > 160 { return nil }
        return (chapterID, verseID)
    }
}

/// Cards and their backgrounds in the App Group container. The widget extension only reads here;
/// it never opens the corpus or the user database.
struct CardLibrary: Sendable {
    static let appGroup = "group.dev.kpierre.bible"
    static let formatVersion = 1

    enum LibraryError: Error { case unavailable, newerFormat, imageTooLarge }

    private struct File: Codable {
        var version: Int
        var cards: [ScriptureCard]
    }

    let directory: URL
    var cardsURL: URL { directory.appendingPathComponent("cards.json") }
    var backgroundsURL: URL { directory.appendingPathComponent("Backgrounds", isDirectory: true) }

    init(directory: URL) { self.directory = directory }

    static func shared() -> CardLibrary? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { CardLibrary(directory: $0.appendingPathComponent("Cards", isDirectory: true)) }
    }

    /// A missing file is an empty library. A newer format is an error, never an overwrite.
    func load() throws -> [ScriptureCard] {
        guard FileManager.default.fileExists(atPath: cardsURL.path) else { return [] }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: cardsURL))
        guard file.version <= Self.formatVersion else { throw LibraryError.newerFormat }
        return file.cards
    }

    /// Replaces the file atomically. Widgets render while locked, so card files use
    /// protection until first unlock rather than the user database's complete protection.
    func save(_ cards: [ScriptureCard]) throws {
        try prepareDirectory(directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(File(version: Self.formatVersion, cards: cards))
            .write(to: cardsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func upsert(_ card: ScriptureCard) throws {
        var cards = try load()
        if let index = cards.firstIndex(where: { $0.id == card.id }) { cards[index] = card } else { cards.append(card) }
        try save(cards)
        try removeUnreferencedBackgrounds(cards)
    }

    func delete(_ id: UUID) throws {
        let cards = try load().filter { $0.id != id }
        try save(cards)
        try removeUnreferencedBackgrounds(cards)
    }

    /// Stores prepared JPEG data and returns its file name.
    func storeBackground(_ jpeg: Data) throws -> String {
        guard jpeg.count <= 4_000_000 else { throw LibraryError.imageTooLarge }
        try prepareDirectory(backgroundsURL)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: backgroundsURL.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    /// Only plain generated names are accepted, so a card can never point outside the library.
    func backgroundURL(_ file: String) -> URL? {
        guard file.range(of: #"^[0-9A-F-]{36}\.jpg$"#, options: .regularExpression) != nil else { return nil }
        return backgroundsURL.appendingPathComponent(file)
    }

    private func removeUnreferencedBackgrounds(_ cards: [ScriptureCard]) throws {
        let referenced = Set(cards.compactMap(\.style.imageFile))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: backgroundsURL.path)) ?? []
        for file in files where !referenced.contains(file) {
            try FileManager.default.removeItem(at: backgroundsURL.appendingPathComponent(file))
        }
    }

    private func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    /// Daily rotation: a stable order (oldest first) and the local day number pick one card.
    static func rotationCard(_ cards: [ScriptureCard], on date: Date, calendar: Calendar = .current) -> ScriptureCard? {
        guard !cards.isEmpty else { return nil }
        let ordered = cards.sorted { $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created }
        let day = calendar.dateComponents([.day], from: Date(timeIntervalSinceReferenceDate: 0), to: calendar.startOfDay(for: date)).day ?? 0
        return ordered[((day % ordered.count) + ordered.count) % ordered.count]
    }
}
