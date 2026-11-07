import AVFAudio
import Foundation
import Testing
@testable import BibleReader

/// Read Aloud phase 5: pronunciation hints steer voices without changing what is spoken.
struct NarrationLexiconTests {
    private static func entry(_ word: String, _ ipa: String = "ˈtɛst", reviewed: String = "test 2026-11-07") -> NarrationLexicon.Entry {
        .init(word: word, ipa: ipa, voices: ["com.apple.voice.test"], reviewed: reviewed)
    }

    @Test func bundledLexiconParsesAndEveryEntryIsReviewed() throws {
        let url = try #require(Bundle.main.url(forResource: "NarrationLexicon", withExtension: "json"))
        let raw = try JSONDecoder().decode([NarrationLexicon.Entry].self, from: Data(contentsOf: url))
        // Every shipped entry was approved by listening (decision Q11); none may be dropped silently.
        #expect(NarrationLexicon.bundled().entries.count == raw.count)
        #expect(raw.allSatisfy { !$0.reviewed.isEmpty && !$0.voices.isEmpty })
    }

    @Test func matchesWholeWordsCaseSensitivelyWithoutOverlaps() {
        let lexicon = NarrationLexicon(entries: [Self.entry("Jordan", "ˈdʒɔɹdən"), Self.entry("Cæsar", "ˈsizɚ")])
        let text = "Jordan, Jordanian jordan; unto Cæsar’s, “Jordan”"
        let hints = lexicon.hints(in: text)
        let words = hints.map { (text as NSString).substring(with: $0.range) }
        #expect(words == ["Jordan", "Cæsar", "Jordan"])
        #expect(hints.first?.ipa == "ˈdʒɔɹdən")
    }

    @Test func unreviewedOrEmptyEntriesAreDropped() {
        let lexicon = NarrationLexicon(entries: [Self.entry("Jordan", reviewed: " "), Self.entry("Cæsar", " "), Self.entry("Gaza")])
        #expect(lexicon.entries.map(\.word) == ["Gaza"])
        #expect(NarrationLexicon.empty.hints(in: "Gaza").isEmpty)
    }

    @Test func attributedSpeechKeepsTheExactStringAndMarksOnlyHints() {
        let text = "And Jesus came to Jordan."
        let hints = NarrationLexicon(entries: [Self.entry("Jordan", "ˈdʒɔɹdən")]).hints(in: text)
        let token = SpeechToken(generation: 1, chapterID: "c", segment: 0)
        let attributed = SystemSpeechSynthesizer.attributed(SpeechRequest(token: token, text: text, voiceID: nil, rate: 0.5,
                                                                          usesAssistiveSettings: false, pronunciations: hints))
        #expect(attributed.string == text)
        let key = NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute)
        var marked: [String] = []
        attributed.enumerateAttribute(key, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if value != nil { marked.append((text as NSString).substring(with: range)) }
        }
        #expect(marked == ["Jordan"])
    }

    /// With hints on common names across the whole corpus, every verse's spoken string is unchanged
    /// and every hint covers exactly its word.
    @Test func fullCorpusSpeechIsUnchangedByHints() async throws {
        let corpus = try #require(Bundle.main.url(forResource: "BibleCorpus", withExtension: "sqlite"))
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("User.sqlite")
        let store = try BibleStore(corpusURL: corpus, userURL: user)
        let counts = Dictionary(uniqueKeysWithValues: try await store.books().map { ($0.id, $0.chapterCount) })
        let lexicon = NarrationLexicon(entries: ["Jordan", "Israel", "Cæsar", "LORD", "Jerusalem", "Melchisedec"].map { Self.entry($0) })
        var hinted = 0
        for summary in try await store.chapters() {
            let document = try await store.chapter(summary.id)
            let script = NarrationScript(document: document, options: .init(), bookChapterCount: try #require(counts[document.bookID]))
            for segment in script.segments {
                let hints = lexicon.hints(in: segment.speech)
                let token = SpeechToken(generation: 1, chapterID: summary.id, segment: 0)
                let attributed = SystemSpeechSynthesizer.attributed(SpeechRequest(token: token, text: segment.speech, voiceID: nil, rate: 0.5,
                                                                                  usesAssistiveSettings: false, pronunciations: hints))
                #expect(attributed.string == segment.speech, "\(summary.id)")
                for hint in hints {
                    let word = (segment.speech as NSString).substring(with: hint.range)
                    #expect(lexicon.entries.contains { $0.word == word }, "\(summary.id): \(word)")
                }
                hinted += hints.count
            }
        }
        #expect(hinted > 1_000)
    }
}
