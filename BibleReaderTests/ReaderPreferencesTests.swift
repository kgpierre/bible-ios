import Foundation
import Testing
import UIKit
import SwiftUI
@testable import BibleReader

struct ReaderPreferencesTests {
    @Test @MainActor func preferencesPersistAndResetWithoutResettingTheme() throws {
        let name = "BibleReader.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ReaderPreferences(defaults: defaults)
        preferences.theme = .dark
        preferences.typography = ReadingTypography(face: .sans, sizeAdjustment: 3, spacing: .relaxed)
        let reopened = ReaderPreferences(defaults: defaults)
        #expect(reopened.theme == .dark)
        #expect(reopened.typography == preferences.typography)
        reopened.resetReadingStyle()
        let reset = ReaderPreferences(defaults: defaults)
        #expect(reset.typography == ReadingTypography())
        #expect(reset.theme == .dark)
    }

    @Test @MainActor func typographyReflowsAndPreservesSemanticSelection() async throws {
        let doc = try #require(try await PrototypeLibrary.load().first { $0.bookID == "JHN" })
        let state = ReaderState()
        state.chapters = [doc]
        state.chapterID = doc.id
        let view = ChapterTextView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        view.configure(document: doc, state: state, wide: false, scheme: .light)
        view.layoutIfNeeded()
        let map = try #require(view.map)
        let selected = NSRange(location: map.entries[0].range.location + 6, length: 15)
        view.selectedRange = selected
        view.capturePosition()
        let anchor = state.selection
        let oldFont = try #require(view.attributedText.attribute(.font, at: selected.location, effectiveRange: nil) as? UIFont)
        let oldSpacing = try #require(view.attributedText.attribute(.paragraphStyle, at: selected.location, effectiveRange: nil) as? NSParagraphStyle).lineSpacing
        state.typography = ReadingTypography(face: .sans, sizeAdjustment: 4, spacing: .relaxed)
        view.configure(document: doc, state: state, wide: false, scheme: .dark)
        view.layoutIfNeeded()
        let newFont = try #require(view.attributedText.attribute(.font, at: selected.location, effectiveRange: nil) as? UIFont)
        #expect(newFont.pointSize > oldFont.pointSize)
        #expect(newFont.fontName != oldFont.fontName)
        #expect((view.attributedText.attribute(.paragraphStyle, at: selected.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0 > oldSpacing)
        #expect(view.selectedRange == selected)
        #expect(state.selection == anchor)
        #expect(view.text == map.text)
        view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        view.updateTraitsIfNeeded()
        view.configure(document: doc, state: state, wide: false, scheme: .dark)
        view.layoutIfNeeded()
        let accessibleFont = try #require(view.attributedText.attribute(.font, at: selected.location, effectiveRange: nil) as? UIFont)
        #expect(accessibleFont.pointSize > newFont.pointSize)
        #expect(view.selectedRange == selected)
    }
}
