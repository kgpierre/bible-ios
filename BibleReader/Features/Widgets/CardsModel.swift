import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
import WidgetKit

/// Widget cards the user has made. Writes go to the App Group library and reload widget timelines.
@MainActor
@Observable
final class CardsModel {
    private(set) var cards: [ScriptureCard] = []
    var errorMessage: String?
    @ObservationIgnored private let library: CardLibrary?
    @ObservationIgnored private let reloadWidgets: @MainActor () -> Void

    init(library: CardLibrary? = CardsModel.defaultLibrary(),
         reloadWidgets: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.library = library
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

    func load() {
        guard let library else { return }
        do { cards = try library.load().sorted { $0.updated > $1.updated } }
        catch { errorMessage = String(localized: "Your widget cards could not load. They have been kept. Try again.") }
    }

    func backgroundURL(for card: ScriptureCard) -> URL? {
        card.style.imageFile.flatMap { library?.backgroundURL($0) }
    }

    /// Saves the card, storing a newly prepared background first. Returns false and keeps the
    /// previous card if anything fails.
    @discardableResult
    func save(_ card: ScriptureCard, newBackground: PreparedBackground? = nil) -> Bool {
        guard let library else {
            errorMessage = String(localized: "Widgets are unavailable in this build.")
            return false
        }
        var card = card
        do {
            if let newBackground {
                let file = try library.storeBackground(newBackground.jpeg)
                card.style.background = .image(file: file, source: newBackground.source, luminance: newBackground.luminance)
            }
            card.updated = .now
            try library.upsert(card)
            load()
            reloadWidgets()
            return true
        } catch {
            errorMessage = String(localized: "This widget card could not be saved. Your other cards have been kept. Try again.")
            return false
        }
    }

    func delete(_ card: ScriptureCard) {
        guard let library else { return }
        do {
            try library.delete(card.id)
            load()
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
