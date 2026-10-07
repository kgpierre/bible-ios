import Testing
import Foundation
import SwiftUI
import UIKit
@testable import BibleReader

@MainActor
struct ScriptureCardTests {
    private func library() -> CardLibrary {
        CardLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func card(_ reference: String = "John 3:16", created: Date = .now, style: CardStyle = CardStyle()) -> ScriptureCard {
        ScriptureCard(id: UUID(), kind: .passage, chapterID: "eng-kjv-1769-protestant:JHN:3", verseID: "eng-kjv-1769-protestant:JHN:3:16",
                      reference: reference, text: "For God so loved the world", isExcerpt: true, editionLabel: "KJV",
                      verseCount: nil, style: style, created: created, updated: created)
    }

    private func jpeg(_ color: UIColor, size: CGSize = CGSize(width: 2400, height: 1600)) -> Data {
        UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).jpegData(withCompressionQuality: 0.9) { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func libraryRoundTripsAndReplacesByID() throws {
        let library = library()
        #expect(try library.load().isEmpty)
        var first = card()
        try library.upsert(first)
        try library.upsert(card("Psalms 23"))
        first.style.typeface = .sans
        try library.upsert(first)
        let loaded = try library.load()
        #expect(loaded.count == 2)
        #expect(loaded.first { $0.id == first.id }?.style.typeface == .sans)
        try library.delete(first.id)
        #expect(try library.load().map(\.reference) == ["Psalms 23"])
    }

    @Test func newerFormatIsRejectedAndNeverOverwritten() throws {
        let library = library()
        try library.save([card()])
        let future = Data(#"{"version":99,"cards":[]}"#.utf8)
        try future.write(to: library.cardsURL)
        #expect(throws: CardLibrary.LibraryError.self) { try library.load() }
        #expect(throws: CardLibrary.LibraryError.self) { try library.upsert(card()) }
        #expect(try Data(contentsOf: library.cardsURL) == future)
    }

    @Test func backgroundsAreRemovedOnlyWhenUnreferenced() throws {
        let library = library()
        let prepared = try PreparedBackground.prepare(jpeg(.darkGray), source: .photo)
        let file = try library.storeBackground(prepared.jpeg)
        let style = CardStyle(background: .image(file: file, source: .photo, luminance: prepared.luminance))
        let a = card(style: style), b = card("Psalms 23", style: style)
        try library.upsert(a)
        try library.upsert(b)
        let url = try #require(library.backgroundURL(file))
        try library.delete(a.id)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try library.delete(b.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Card data can only name generated files inside the library.
        #expect(library.backgroundURL("../User.sqlite") == nil)
        #expect(library.backgroundURL("/etc/passwd") == nil)
    }

    @Test func preparedImagesAreDownsampledWithLuminance() throws {
        let dark = try PreparedBackground.prepare(jpeg(.black), source: .imagePlayground)
        let light = try PreparedBackground.prepare(jpeg(.white), source: .photo)
        #expect(dark.luminance < 0.1)
        #expect(light.luminance > 0.9)
        let image = try #require(UIImage(data: dark.jpeg))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 1200)
        #expect(CardStyle(background: .image(file: "x", source: .photo, luminance: dark.luminance)).usesLightInk)
        #expect(!CardStyle(background: .image(file: "x", source: .photo, luminance: light.luminance)).usesLightInk)
        #expect(!CardStyle(background: .image(file: "x", source: .photo, luminance: dark.luminance), ink: .dark).usesLightInk)
        #expect(throws: PreparedBackground.Failure.self) { try PreparedBackground.prepare(Data("not an image".utf8), source: .photo) }
    }

    @Test func linksRoundTripAndRejectMismatchedVerses() throws {
        let url = try #require(CardLink.url(chapterID: "eng-kjv-1769-protestant:JHN:3", verseID: "eng-kjv-1769-protestant:JHN:3:16"))
        let parsed = try #require(CardLink.parse(url))
        #expect(parsed.chapterID == "eng-kjv-1769-protestant:JHN:3")
        #expect(parsed.verseID == "eng-kjv-1769-protestant:JHN:3:16")
        for bad in ["dev.kpierre.bible://open?chapter=eng-kjv-1769-protestant:JHN:3&verse=eng-kjv-1769-protestant:GEN:1:1",
                    "https://example.com/open?chapter=x", "dev.kpierre.bible://delete?chapter=x", "dev.kpierre.bible://open?chapter="] {
            let url = try #require(URL(string: bad))
            #expect(CardLink.parse(url) == nil, "\(bad)")
        }
        let chapterLink = try #require(CardLink.url(chapterID: "eng-kjv-1769-protestant:JHN:3", verseID: nil))
        #expect(CardLink.parse(chapterLink)?.verseID == nil)
    }

    @Test func dailyRotationIsStableAndCyclesEveryCard() throws {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let cards = (0..<3).map { card("Card \($0)", created: base.addingTimeInterval(Double($0))) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let days = (0..<3).map { calendar.date(byAdding: .day, value: $0, to: base)! }
        let picks = days.map { CardLibrary.rotationCard(cards.shuffled(), on: $0, calendar: calendar)?.id }
        #expect(Set(picks).count == 3)
        #expect(CardLibrary.rotationCard(cards, on: days[0], calendar: calendar)?.id ==
                CardLibrary.rotationCard(cards.reversed(), on: days[0].addingTimeInterval(3600), calendar: calendar)?.id)
        #expect(CardLibrary.rotationCard([], on: base) == nil)
    }

    @Test func draftsCopySavedTextVerbatim() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let chapterID = "eng-kjv-1769-protestant:PSA:23"
        let document = try await store.chapter(chapterID)
        let verse = document.verses[0]
        let part = try #require(SavedTextPart(verseID: verse.id, text: verse.text, range: NSRange(location: 4, length: 4)))
        _ = try await store.editExact(ExactPassage(chapterID: chapterID, reference: "Psalms 23:1", parts: [part]), color: .sage)
        _ = try await store.setChapterSaved(chapterID, saved: true)
        let items = try await store.savedItems()
        let excerptItem = try #require(items.first { !$0.savedChapter })
        let chapterItem = try #require(items.first { $0.savedChapter })
        let excerpt = try #require(CardsModel.draft(from: excerptItem, editionLabel: "KJV"))
        #expect(excerpt.text == "LORD")
        #expect(excerpt.isExcerpt && excerpt.kind == .passage)
        #expect(excerpt.reference == "Psalms 23:1")
        #expect(excerpt.style.background == .preset(.sage))
        let chapter = try #require(CardsModel.draft(from: chapterItem, editionLabel: "KJV"))
        #expect(chapter.kind == .chapter && chapter.verseID == nil)
        #expect(chapter.text == verse.text)
        #expect(chapter.verseCount == document.verses.count)
        var unavailable = try #require(items.first)
        unavailable.unavailable = true
        #expect(CardsModel.draft(from: unavailable, editionLabel: "KJV") == nil)
    }

    @Test func modelSavesStoresBackgroundAndReloadsWidgets() throws {
        var reloads = 0
        let model = CardsModel(library: library()) { reloads += 1 }
        let prepared = try PreparedBackground.prepare(jpeg(.white), source: .photo)
        #expect(model.save(card(), newBackground: prepared))
        let saved = try #require(model.cards.first)
        #expect(saved.style.imageFile != nil)
        #expect(model.backgroundURL(for: saved).map { FileManager.default.fileExists(atPath: $0.path) } == true)
        model.delete(saved)
        #expect(model.cards.isEmpty && reloads == 2)
        #expect(!CardsModel(library: nil).save(card()))
    }

    @Test func editorSymbolsExist() {
        for name in ["widget.small", "apple.image.playground", "photo.on.rectangle", "book.closed", "book.closed.fill"] {
            #expect(UIImage(systemName: name) != nil, "\(name)")
        }
    }

    /// Renders every family and a range of styles for visual review (exported from the result bundle).
    @Test func renderCardGallery() throws {
        let long = "And the LORD God formed man of the dust of the ground, and breathed into his nostrils the breath of life; and man became a living soul."
        var cards: [(String, ScriptureCard)] = []
        for preset in CardPreset.allCases {
            var c = card()
            c.reference = "Genesis 2:7"
            c.text = long
            c.isExcerpt = false
            c.style = CardStyle(background: .preset(preset), typeface: preset == .ink ? .sans : .serif)
            cards.append((preset.rawValue, c))
        }
        var chapter = card()
        chapter.kind = .chapter
        chapter.reference = "Psalms 23"
        chapter.text = "The LORD is my shepherd; I shall not want."
        chapter.verseCount = 6
        cards.append(("chapter", chapter))
        for (name, card) in cards {
            for family in CardFamily.allCases {
                let renderer = ImageRenderer(content: ScriptureCardPreview(card: card, family: family, image: nil))
                renderer.scale = 2
                let png = try #require(renderer.uiImage?.pngData())
                Attachment.record(png, named: "card-\(name)-\(family.rawValue).png")
            }
        }
    }
}
