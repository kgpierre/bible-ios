import AVFAudio
import Foundation
import Testing
@testable import BibleReader

/// Phase 0 spike S1 (plan §14). Opt-in, device only: `TEST_RUNNER_BIBLE_SPIKE_S1=1 xcodebuild test …
/// -only-testing:BibleReaderTests/NarrationVoiceSpikeTests`. It measures, never asserts behavior:
/// rendered duration of corpus text against a plain baseline (a much longer variant means the voice
/// voiced the extra mark or spelled the word), `willSpeakRange` granularity, and the delegate thread.
/// Results print as `S1|…` lines. Nothing here ships or runs in normal suites.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BIBLE_SPIKE_S1"] == "1"), .serialized)
struct NarrationVoiceSpikeTests {
    struct Pair { let name: String; let variant: String; let baseline: String }

    static let pairs: [Pair] = [
        .init(name: "pilcrow", variant: "¶ For God so loved the world.", baseline: "For God so loved the world."),
        .init(name: "LORD", variant: "The LORD is my shepherd; I shall not want.", baseline: "The Lord is my shepherd; I shall not want."),
        .init(name: "LORD-spelled-ref", variant: "The L. O. R. D. is my shepherd; I shall not want.", baseline: "The Lord is my shepherd; I shall not want."),
        .init(name: "ae", variant: "Render therefore unto Cæsar the things which are Cæsar’s.", baseline: "Render therefore unto Caesar the things which are Caesar’s."),
        .init(name: "hebrew", variant: "\u{05D0} ALEPH.", baseline: "ALEPH."),
    ]

    final class Recorder: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        let lock = NSLock()
        var ranges: [NSRange] = []
        var mainThreadCallbacks = 0
        var otherThreadCallbacks = 0
        var finished: CheckedContinuation<Void, Never>?

        func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
            lock.withLock {
                ranges.append(range)
                if Thread.isMainThread { mainThreadCallbacks += 1 } else { otherThreadCallbacks += 1 }
            }
        }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { resumeOnce() }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { resumeOnce() }
        func resumeOnce() { lock.withLock { let c = finished; finished = nil; return c }?.resume() }
    }

    /// One voice per (language, quality), English only, as the app's catalog filters them.
    static func sampleVoices() -> [AVSpeechSynthesisVoice] {
        let allowed = Set(NarrationVoiceCatalog.installedVoices().map(\.id))
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { allowed.contains($0.identifier) }
            .sorted { $0.identifier < $1.identifier }
            .filter { seen.insert("\($0.language)|\(family($0))|\($0.quality.rawValue)").inserted }
    }

    /// Engine family from the identifier (eloquence, super-compact, siri ttsbundle, legacy MacinTalk).
    static func family(_ voice: AVSpeechSynthesisVoice) -> String {
        let id = voice.identifier
        for f in ["eloquence", "super-compact", "ttsbundle", "speech.synthesis", "personal"] where id.contains(f) { return f }
        return "other"
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality = voice.voiceTraits.contains(.isPersonalVoice) ? "personal" : [1: "default", 2: "enhanced", 3: "premium"][voice.quality.rawValue] ?? "q\(voice.quality.rawValue)"
        return "\(voice.name)|\(voice.language)|\(quality)|\(voice.identifier)"
    }

    /// Renders offline (faster than real time) and returns seconds of audio.
    func renderedSeconds(_ text: String, voice: AVSpeechSynthesisVoice) async -> Double {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        return await withCheckedContinuation { continuation in
            let box = Box()
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if box.markDone() { continuation.resume(returning: box.seconds) }
                    return
                }
                box.add(Double(pcm.frameLength) / pcm.format.sampleRate)
            }
            box.synthesizer = synthesizer
        }
    }

    final class Box: @unchecked Sendable {
        let lock = NSLock()
        var seconds = 0.0
        var done = false
        var synthesizer: AVSpeechSynthesizer?
        func add(_ s: Double) { lock.withLock { seconds += s } }
        func markDone() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }

    @Test func voiceInventory() {
        for voice in AVSpeechSynthesisVoice.speechVoices() where voice.language.hasPrefix("en") {
            print("S1|inventory|\(Self.label(voice))|novelty=\(voice.voiceTraits.contains(.isNoveltyVoice))")
        }
        print("S1|personalVoiceAuth|\(AVSpeechSynthesizer.personalVoiceAuthorizationStatus.rawValue)")
        print("S1|catalog|\(NarrationVoiceCatalog.installedVoices().map { "\($0.name)(\($0.quality))" }.joined(separator: ","))")
    }

    @Test func renderedDurations() async {
        for voice in Self.sampleVoices() {
            for pair in Self.pairs {
                let v = await renderedSeconds(pair.variant, voice: voice)
                let b = await renderedSeconds(pair.baseline, voice: voice)
                print(String(format: "S1|duration|%@|%@|variant=%.3f|baseline=%.3f|delta=%.3f", Self.label(voice), pair.name, v, b, v - b))
            }
        }
    }

    /// Real-time speech (audible on the device) to record word ranges and the callback thread.
    @Test func wordRangesAndThread() async {
        let text = "¶ For God so loved the world, that he gave his only begotten Son. The LORD is my shepherd."
        for voice in Self.sampleVoices() {
            let synthesizer = AVSpeechSynthesizer()
            let recorder = Recorder()
            synthesizer.delegate = recorder
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            await withCheckedContinuation { continuation in
                recorder.finished = continuation
                synthesizer.speak(utterance)
            }
            let (ranges, main, other) = recorder.lock.withLock { (recorder.ranges, recorder.mainThreadCallbacks, recorder.otherThreadCallbacks) }
            let words = ranges.map { (text as NSString).substring(with: $0) }
            print("S1|ranges|\(Self.label(voice))|count=\(ranges.count)|main=\(main)|other=\(other)|words=\(words.joined(separator: "/"))")
            withExtendedLifetime(synthesizer) {}
        }
    }
}
