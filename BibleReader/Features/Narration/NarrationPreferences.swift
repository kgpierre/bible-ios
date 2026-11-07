import AVFAudio
import Foundation
import Observation

enum NarrationRate: String, Codable, CaseIterable, Identifiable, Sendable {
    case slower = "0.75", normal = "1", faster = "1.25", fast = "1.5", fastest = "2"
    var id: Self { self }
    var multiplier: Float { Float(rawValue) ?? 1 }
    var title: String { "\(rawValue)×" }
    /// Multiplicative around the system default, clamped to the synthesizer's range. The perceived
    /// speed of each preset still needs calibration on device (plan spike S3).
    var utteranceRate: Float {
        min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * multiplier))
    }
}

/// A short silence after each verse, so chapters don't run together (owner request, 7 November 2026).
/// It uses the utterance's post-delay, not SSML: an SSML utterance ignores rate (plan §4.5).
enum NarrationVersePause: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, short, long
    var id: Self { self }
    var seconds: TimeInterval {
        switch self {
        case .none: 0
        case .short: 0.35
        case .long: 0.8
        }
    }
    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .short: String(localized: "Short")
        case .long: String(localized: "Long")
        }
    }
}

/// Read Aloud settings. Stores voice identifiers only; a missing voice falls back without
/// overwriting the stored choice, so reinstalling the voice restores it.
@MainActor @Observable
final class NarrationPreferences {
    var voiceID: String? { didSet { save() } }
    var rate: NarrationRate { didSet { save() } }
    var announcesChapters: Bool { didSet { save() } }
    var announcesVerseNumbers: Bool { didSet { save() } }
    var continuesToNextChapter: Bool { didSet { save() } }
    /// With VoiceOver running, speak with the VoiceOver voice and rate instead.
    var usesVoiceOverSettings: Bool { didSet { save() } }
    var versePause: NarrationVersePause { didSet { save() } }
    /// Owner-reviewed pronunciation hints for names (plan §4.5). Off uses each voice's own reading.
    var usesPronunciationHints: Bool { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults

    private struct Payload: Codable {
        var version = 1
        var voiceID: String?
        var rate: NarrationRate?
        var announcesChapters: Bool?
        var announcesVerseNumbers: Bool?
        var continuesToNextChapter: Bool?
        var usesVoiceOverSettings: Bool?
        var versePause: NarrationVersePause?
        var usesPronunciationHints: Bool?
    }
    private static let key = "reader.narration.v1"

    init(defaults: UserDefaults? = nil) {
        #if DEBUG
        if let defaults { self.defaults = defaults }
        else if let testID = ProcessInfo.processInfo.environment["BIBLE_TEST_STORE"],
                let isolated = UserDefaults(suiteName: "BibleReader.UI-\(testID)") { self.defaults = isolated }
        else { self.defaults = .standard }
        #else
        self.defaults = defaults ?? .standard
        #endif
        let stored = self.defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
            .flatMap { $0.version == 1 ? $0 : nil }
        voiceID = stored?.voiceID
        rate = stored?.rate ?? .normal
        announcesChapters = stored?.announcesChapters ?? true
        announcesVerseNumbers = stored?.announcesVerseNumbers ?? false
        continuesToNextChapter = stored?.continuesToNextChapter ?? true
        usesVoiceOverSettings = stored?.usesVoiceOverSettings ?? false
        versePause = stored?.versePause ?? .short
        usesPronunciationHints = stored?.usesPronunciationHints ?? true
    }

    var scriptOptions: NarrationScriptOptions {
        NarrationScriptOptions(announcesChapter: announcesChapters, announcesVerseNumbers: announcesVerseNumbers)
    }

    private func save() {
        let payload = Payload(voiceID: voiceID, rate: rate, announcesChapters: announcesChapters, announcesVerseNumbers: announcesVerseNumbers,
                              continuesToNextChapter: continuesToNextChapter, usesVoiceOverSettings: usesVoiceOverSettings,
                              versePause: versePause, usesPronunciationHints: usesPronunciationHints)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

struct NarrationVoice: Identifiable, Equatable, Sendable {
    enum Quality: Int, Comparable, Sendable, CaseIterable {
        case standard, enhanced, premium, personal
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        var title: String {
            switch self {
            case .standard: String(localized: "Default")
            case .enhanced: String(localized: "Enhanced")
            case .premium: String(localized: "Premium")
            case .personal: String(localized: "Personal Voice")
            }
        }
    }
    let id: String
    let name: String
    /// BCP 47, for example "en-GB".
    let language: String
    let quality: Quality
}

/// English on-device Apple voices plus an authorized Personal Voice (0023). Third-party provider
/// voices are excluded because their privacy behavior is outside the app's control.
@MainActor @Observable
final class NarrationVoiceCatalog {
    /// The app's permission to speak with the user's Personal Voice (plan phase 5).
    enum PersonalVoiceAccess: Sendable, Equatable {
        case notDetermined, denied, unsupported, authorized
        init(_ status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus) {
            switch status {
            case .authorized: self = .authorized
            case .denied: self = .denied
            case .unsupported: self = .unsupported
            default: self = .notDetermined
            }
        }
    }

    private(set) var voices: [NarrationVoice] = []
    private(set) var personalVoiceAccess: PersonalVoiceAccess = .notDetermined
    @ObservationIgnored private let load: @MainActor () -> [NarrationVoice]
    @ObservationIgnored private let personalStatus: @MainActor () -> PersonalVoiceAccess
    @ObservationIgnored private let requestPersonal: @MainActor () async -> PersonalVoiceAccess
    @ObservationIgnored private let preferredLanguage: String
    @ObservationIgnored private let preview = AVSpeechSynthesizer()

    init(load: @escaping @MainActor () -> [NarrationVoice] = NarrationVoiceCatalog.installedVoices,
         preferredLanguage: String = "en-\(Locale.current.region?.identifier ?? "US")",
         personalStatus: @escaping @MainActor () -> PersonalVoiceAccess = { PersonalVoiceAccess(AVSpeechSynthesizer.personalVoiceAuthorizationStatus) },
         requestPersonal: @escaping @MainActor () async -> PersonalVoiceAccess = NarrationVoiceCatalog.requestSystemPersonalVoice) {
        self.load = load
        self.preferredLanguage = preferredLanguage
        self.personalStatus = personalStatus
        self.requestPersonal = requestPersonal
        refresh()
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVSpeechSynthesizer.availableVoicesDidChangeNotification) {
                self?.refresh()
            }
        }
    }

    /// Asks once; the system remembers the answer, and later calls return it without a prompt.
    func requestPersonalVoice() async {
        personalVoiceAccess = await requestPersonal()
        refresh()
    }

    /// Whether any Enhanced or Premium voice is installed. Without one, Read Aloud suggests them.
    var hasNaturalVoice: Bool { voices.contains { $0.quality == .enhanced || $0.quality == .premium } }
    var hasPersonalVoice: Bool { voices.contains { $0.quality == .personal } }

    static func requestSystemPersonalVoice() async -> PersonalVoiceAccess {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { continuation.resume(returning: PersonalVoiceAccess($0)) }
        }
    }

    func refresh() {
        personalVoiceAccess = personalStatus()
        voices = load().sorted {
            ($0.quality, $0.language == preferredLanguage ? 1 : 0, $1.name) > ($1.quality, $1.language == preferredLanguage ? 1 : 0, $0.name)
        }
    }

    /// The best voice in the reader's region, else the best US English voice, else any English voice.
    /// Personal Voice is used only when chosen.
    var defaultVoice: NarrationVoice? {
        let system = voices.filter { $0.quality != .personal }
        return system.first { $0.language == preferredLanguage } ?? system.first { $0.language == "en-US" } ?? system.first
    }

    /// The stored voice when installed, otherwise the default. `isFallback` is true only when a
    /// stored choice is missing.
    func resolve(_ storedID: String?) -> (voice: NarrationVoice?, isFallback: Bool) {
        if let storedID, let voice = voices.first(where: { $0.id == storedID }) { return (voice, false) }
        return (defaultVoice, storedID != nil)
    }

    /// Genesis 1:1, verbatim from the bundled corpus (checked by `NarrationControllerTests`).
    static let sampleText = "In the beginning God created the heaven and the earth."

    func playSample(_ voice: NarrationVoice, rate: NarrationRate) {
        preview.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: Self.sampleText)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voice.id)
        utterance.rate = rate.utteranceRate
        preview.speak(utterance)
    }

    func stopSample() { preview.stopSpeaking(at: .immediate) }

    static func installedVoices() -> [NarrationVoice] {
        let personalAllowed = AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized
        return AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
            guard voice.language.hasPrefix("en"), !voice.voiceTraits.contains(.isNoveltyVoice) else { return nil }
            let quality: NarrationVoice.Quality
            if voice.voiceTraits.contains(.isPersonalVoice) {
                guard personalAllowed else { return nil }
                quality = .personal
            } else {
                // The identifier prefix is a heuristic for Apple voices (plan §17, unverified).
                guard voice.identifier.hasPrefix("com.apple.") else { return nil }
                switch voice.quality {
                case .premium: quality = .premium
                case .enhanced: quality = .enhanced
                default: quality = .standard
                }
            }
            return NarrationVoice(id: voice.identifier, name: voice.name, language: voice.language, quality: quality)
        }
    }
}
