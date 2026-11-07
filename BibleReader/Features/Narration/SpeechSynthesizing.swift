import AVFAudio
import Foundation

/// Identifies one queued segment. A newer generation (stop, seek, rate or voice change) makes
/// every earlier token stale.
struct SpeechToken: Hashable, Sendable {
    let generation: Int
    let chapterID: String
    let segment: Int
}

struct SpeechRequest: Sendable, Equatable {
    let token: SpeechToken
    let text: String
    let voiceID: String?
    let rate: Float
    let usesAssistiveSettings: Bool
    var postDelay: TimeInterval = 0
}

/// Ranges are UTF-16 ranges in the request's text.
enum SpeechEvent: Sendable, Equatable {
    case started(SpeechToken)
    case willSpeak(SpeechToken, NSRange)
    case finished(SpeechToken)
    case cancelled(SpeechToken)
}

/// A seam over the system synthesizer so the controller can be tested without audio.
@MainActor protocol SpeechSynthesizing: AnyObject {
    /// One consumer: the narration controller.
    var events: AsyncStream<SpeechEvent> { get }
    func enqueue(_ request: SpeechRequest)
    /// Pauses at the next word boundary. False when nothing is speaking.
    @discardableResult func pause() -> Bool
    @discardableResult func resume() -> Bool
    func stop()
    /// Replaces the engine after a media services reset; nothing queued survives.
    func reset()
}

@MainActor final class SystemSpeechSynthesizer: SpeechSynthesizing {
    let events: AsyncStream<SpeechEvent>
    private let continuation: AsyncStream<SpeechEvent>.Continuation
    /// Held strongly for the app's lifetime: a deallocated synthesizer goes silent mid-speech.
    private var synthesizer = AVSpeechSynthesizer()
    private let delegate: SpeechDelegate
    /// Utterances stay retained until they finish or cancel, so an identifier is never reused
    /// while a callback for it may still arrive.
    private var utterances: [ObjectIdentifier: (utterance: AVSpeechUtterance, token: SpeechToken)] = [:]

    init() {
        (events, continuation) = AsyncStream.makeStream()
        let (callbacks, callbackContinuation) = AsyncStream<SpeechDelegate.Callback>.makeStream()
        delegate = SpeechDelegate(continuation: callbackContinuation)
        synthesizer.delegate = delegate
        // The delegate thread is undocumented; callbacks carry only Sendable values and are
        // translated to tokens here, on the main actor.
        Task { [weak self] in
            for await callback in callbacks { self?.handle(callback) }
        }
    }

    func enqueue(_ request: SpeechRequest) {
        let utterance = AVSpeechUtterance(string: request.text)
        if let id = request.voiceID, let voice = AVSpeechSynthesisVoice(identifier: id) { utterance.voice = voice }
        utterance.rate = request.rate
        utterance.prefersAssistiveTechnologySettings = request.usesAssistiveSettings
        utterance.postUtteranceDelay = request.postDelay
        utterances[ObjectIdentifier(utterance)] = (utterance, request.token)
        synthesizer.speak(utterance)
    }

    /// Immediate: a word-boundary pause requested before an utterance starts, or near its end, can
    /// be accepted and never take effect (seen on device, 7 November 2026).
    func pause() -> Bool { synthesizer.isSpeaking && synthesizer.pauseSpeaking(at: .immediate) }
    func resume() -> Bool { synthesizer.isPaused && synthesizer.continueSpeaking() }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    func reset() {
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        for (_, entry) in utterances { continuation.yield(.cancelled(entry.token)) }
        utterances = [:]
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = delegate
    }

    private func handle(_ callback: SpeechDelegate.Callback) {
        switch callback {
        case .started(let id):
            if let token = utterances[id]?.token { continuation.yield(.started(token)) }
        case .range(let id, let range):
            if let token = utterances[id]?.token { continuation.yield(.willSpeak(token, range)) }
        case .finished(let id):
            if let token = utterances.removeValue(forKey: id)?.token { continuation.yield(.finished(token)) }
        case .cancelled(let id):
            if let token = utterances.removeValue(forKey: id)?.token { continuation.yield(.cancelled(token)) }
        }
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
    enum Callback: Sendable {
        case started(ObjectIdentifier), range(ObjectIdentifier, NSRange), finished(ObjectIdentifier), cancelled(ObjectIdentifier)
    }
    private let continuation: AsyncStream<Callback>.Continuation
    init(continuation: AsyncStream<Callback>.Continuation) { self.continuation = continuation }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        continuation.yield(.started(ObjectIdentifier(utterance)))
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        continuation.yield(.range(ObjectIdentifier(utterance), characterRange))
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        continuation.yield(.finished(ObjectIdentifier(utterance)))
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        continuation.yield(.cancelled(ObjectIdentifier(utterance)))
    }
}

/// Session changes narration must react to.
enum NarrationAudioEvent: Sendable, Equatable {
    /// The system deactivated the session (a call, Siri, an alarm, another app's audio).
    case interrupted
    case interruptionEnded(shouldResume: Bool)
    /// Headphones, AirPods, Bluetooth, or CarPlay went away; never resume by itself.
    case routeLost
    /// The media server restarted; the synthesizer must be rebuilt.
    case mediaServicesReset
}

/// Spoken-audio session for user-started narration (plan §9.1–9.3).
@MainActor protocol NarrationAudioSession: AnyObject {
    var events: AsyncStream<NarrationAudioEvent> { get }
    func activate() throws
    func deactivate()
}

@MainActor final class SystemNarrationAudioSession: NarrationAudioSession {
    let events: AsyncStream<NarrationAudioEvent>
    private var observers: [any NSObjectProtocol] = []

    init() {
        let (events, continuation) = AsyncStream<NarrationAudioEvent>.makeStream()
        self.events = events
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ map: @escaping @Sendable (Notification) -> NarrationAudioEvent?) {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { note in
                if let event = map(note) { continuation.yield(event) }
            })
        }
        if #available(iOS 27, *) {
            observe(AVAudioSession.didBecomeInactiveNotification) { note in
                let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
                return context?.source == .system ? .interrupted : nil
            }
            observe(AVAudioSession.resumptionRecommendationNotification) { note in
                let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
                return .interruptionEnded(shouldResume: context?.recommendation == .shouldResume)
            }
        } else {
            observe(AVAudioSession.interruptionNotification, Self.legacyInterruption)
        }
        observe(AVAudioSession.routeChangeNotification) { note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            return raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable ? .routeLost : nil
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { _ in .mediaServicesReset }
    }

    /// iOS 26 interruption keys, deprecated from iOS 27 and reached only below it.
    @available(iOS, deprecated: 27, message: "iOS 26 only; iOS 27 uses deactivation and resumption contexts.")
    private nonisolated static func legacyInterruption(_ note: Notification) -> NarrationAudioEvent? {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began: return .interrupted
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default: return nil
        }
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }

    /// Lets audio the user paused for narration resume.
    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#if DEBUG
/// A deterministic synthesizer for tests and `BIBLE_TEST_FAKE_SPEECH`. With `pacing`, each segment
/// starts, reports its first word, and finishes after that interval; without it, tests drive
/// every event.
@MainActor final class ScriptedSpeechSynthesizer: SpeechSynthesizing {
    let events: AsyncStream<SpeechEvent>
    private let continuation: AsyncStream<SpeechEvent>.Continuation
    private(set) var queue: [SpeechRequest] = []
    private(set) var history: [SpeechRequest] = []
    private(set) var current: SpeechRequest?
    private(set) var isPaused = false
    private let pacing: Duration?
    private var epoch = 0

    init(pacing: Duration? = nil) {
        self.pacing = pacing
        (events, continuation) = AsyncStream.makeStream()
    }

    func enqueue(_ request: SpeechRequest) {
        queue.append(request)
        history.append(request)
        advance()
    }

    /// Accepts pause requests without pausing, like the system synthesizer sometimes does.
    var ignoresPause = false

    func pause() -> Bool {
        guard current != nil || !queue.isEmpty, !isPaused else { return false }
        if ignoresPause { return true }
        isPaused = true
        return true
    }

    func resume() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        advance()
        return true
    }

    func stop() {
        epoch += 1
        isPaused = false
        let cancelled = (current.map { [$0] } ?? []) + queue.filter { $0 != current }
        current = nil
        queue = []
        for request in cancelled { continuation.yield(.cancelled(request.token)) }
    }

    private(set) var resets = 0
    func reset() { stop(); resets += 1 }

    /// Starts the queued head. Returns nil when nothing is queued or a segment is speaking.
    @discardableResult func startNext() -> SpeechRequest? {
        guard current == nil, let next = queue.first else { return nil }
        current = next
        continuation.yield(.started(next.token))
        return next
    }

    func speak(_ range: NSRange) {
        if let current { continuation.yield(.willSpeak(current.token, range)) }
    }

    func finishCurrent() {
        guard let finished = current else { return }
        current = nil
        queue.removeFirst()
        continuation.yield(.finished(finished.token))
    }

    private func advance() {
        guard let pacing, current == nil, !isPaused, startNext() != nil, let request = current else { return }
        let epoch = epoch
        let firstWord = (request.text as NSString).range(of: #"\S+"#, options: .regularExpression)
        if firstWord.location != NSNotFound { speak(firstWord) }
        Task { [weak self] in
            try? await Task.sleep(for: pacing)
            while let self, self.epoch == epoch, self.isPaused { try? await Task.sleep(for: .milliseconds(50)) }
            guard let self, self.epoch == epoch else { return }
            self.finishCurrent()
            self.advance()
        }
    }
}

@MainActor final class SilentNarrationAudioSession: NarrationAudioSession {
    let events: AsyncStream<NarrationAudioEvent>
    private let continuation: AsyncStream<NarrationAudioEvent>.Continuation
    init() { (events, continuation) = AsyncStream.makeStream() }
    /// Delivers a session change, as the system would.
    func send(_ event: NarrationAudioEvent) { continuation.yield(event) }
    var failsActivation = false
    private(set) var activations = 0
    private(set) var deactivations = 0
    func activate() throws {
        if failsActivation { throw CocoaError(.featureUnsupported) }
        activations += 1
    }
    func deactivate() { deactivations += 1 }
}
#endif
