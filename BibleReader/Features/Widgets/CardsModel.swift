import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
import WidgetKit

/// Serializes card-library file work off the main actor: reading and decoding the library,
/// rewriting it, writing background JPEGs, and cleaning up unused ones.
actor CardLibraryWorker {
    let library: CardLibrary

    init(library: CardLibrary) { self.library = library }

    /// The library, newest first. Retries cleanup a previous edit couldn't finish; leftover files
    /// are harmless meanwhile.
    func load() throws -> [ScriptureCard] {
        let cards = try library.load().sorted { $0.updated > $1.updated }
        try? library.removeUnreferencedBackgrounds()
        return cards
    }

    /// Stores a newly prepared background first, then commits the card. Returns the reloaded library.
    func save(_ card: ScriptureCard, newBackground: PreparedBackground?) throws -> [ScriptureCard] {
        var card = card
        if let newBackground {
            let file = try library.storeBackground(newBackground.jpeg)
            card.style.background = .image(file: file, source: newBackground.source, luminance: newBackground.luminance)
        }
        card.updated = .now
        try library.upsert(card)
        return try library.load().sorted { $0.updated > $1.updated }
    }

    func delete(_ id: UUID) throws -> [ScriptureCard] {
        try library.delete(id)
        return try library.load().sorted { $0.updated > $1.updated }
    }

    func backgroundURL(_ file: String) -> URL? { library.backgroundURL(file) }
}

/// Widget cards the user has made. Writes go to the App Group library and reload widget timelines.
@MainActor
@Observable
final class CardsModel {
    private(set) var cards: [ScriptureCard] = []
    private(set) var isSaving = false
    var errorMessage: String?
    @ObservationIgnored private let library: CardLibrary?
    @ObservationIgnored private let worker: CardLibraryWorker?
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void
    /// Every published library result advances this, so a slow older read never replaces a newer one.
    @ObservationIgnored private var generation = 0

    init(library: CardLibrary? = CardsModel.defaultLibrary(),
         reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.library = library
        worker = library.map(CardLibraryWorker.init)
        self.reloadWidgets = reloadWidgets
    }

    var isAvailable: Bool { library != nil }

    static func defaultLibrary() -> CardLibrary? {
        #if DEBUG
        // UI tests get isolated card folders, like their isolated user stores; widgets ignore them.
        if let token = ProcessInfo.processInfo.environment["BIBLE_TEST_STORE"], let uuid = UUID(uuidString: token),
           let shared = CardLibrary.shared() {
            return CardLibrary(directory: shared.directory.appendingPathComponent("Tests/\(uuid.uuidString)", isDirectory: true))
        }
        #endif
        return CardLibrary.shared()
    }

    func load() async {
        guard let worker else { return }
        generation += 1
        let request = generation
        do {
            let loaded = try await worker.load()
            guard request == generation else { return }
            cards = loaded
        } catch {
            guard request == generation else { return }
            errorMessage = String(localized: "Your widget cards could not load. They have been kept. Try again.")
        }
    }

    /// File names are validated without touching the disk, so this stays synchronous.
    func backgroundURL(for card: ScriptureCard) -> URL? {
        card.style.imageFile.flatMap { library?.backgroundURL($0) }
    }

    /// Saves the card, storing a newly prepared background first. Returns false and keeps the
    /// previous card if anything fails before the library is committed.
    @discardableResult
    func save(_ card: ScriptureCard, newBackground: PreparedBackground? = nil) async -> Bool {
        guard let worker else {
            errorMessage = String(localized: "Widgets are unavailable in this build.")
            return false
        }
        isSaving = true
        defer { isSaving = false }
        generation += 1
        let request = generation
        do {
            let saved = try await worker.save(card, newBackground: newBackground)
            if request == generation { cards = saved }
            reloadWidgets()
            return true
        } catch {
            errorMessage = String(localized: "This widget card could not be saved. Your other cards have been kept. Try again.")
            return false
        }
    }

    func delete(_ card: ScriptureCard) async {
        guard let worker else { return }
        generation += 1
        let request = generation
        do {
            let remaining = try await worker.delete(card.id)
            if request == generation { cards = remaining }
            reloadWidgets()
        } catch {
            errorMessage = String(localized: "This widget card could not be deleted. Try again.")
        }
    }

    /// A new card from a Saved row. Text is the row's own verbatim corpus text or exact excerpt.
    static func draft(from item: SavedItem, editionLabel: String) -> ScriptureCard? {
        guard !item.unavailable else { return nil }
        let exact = item.records.exact.first?.passage
        return ScriptureCard(id: UUID(), kind: item.savedChapter ? .chapter : .passage, chapterID: item.chapterID,
            verseID: item.savedChapter ? nil : item.verseID,
            reference: exact?.reference ?? item.reference, text: item.text, isExcerpt: exact != nil,
            editionLabel: editionLabel, verseCount: item.verseCount,
            style: CardStyle(background: .preset(item.savedChapter ? .paper : preset(for: item.color))),
            created: .now, updated: .now)
    }

    private static func preset(for color: HighlightColor?) -> CardPreset {
        switch color {
        case .sage: .sage
        case .rose: .rose
        case .blue: .evening
        case .yellow: .dawn
        case nil: .paper
        }
    }
}

/// A background downsampled for widgets, with the luminance that selects automatic ink.
struct PreparedBackground: Sendable {
    let jpeg: Data
    let luminance: Double
    let source: CardStyle.ImageSource

    enum Failure: Error { case unreadable }

    /// Downsamples to 1200 pixels on the long edge and re-encodes, discarding metadata such as location.
    nonisolated static func prepare(_ data: Data, source: CardStyle.ImageSource) throws -> PreparedBackground {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1200,
              ] as CFDictionary) else { throw Failure.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.unreadable }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return PreparedBackground(jpeg: output as Data, luminance: averageLuminance(image), source: source)
    }

    /// Mean relative luminance from a 16×16 reduction.
    nonisolated static func averageLuminance(_ image: CGImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0.5 }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
        }
        return total / Double(side * side)
    }
}
