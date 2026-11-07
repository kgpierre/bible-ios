import Foundation
import MediaPlayer

/// What the Lock Screen, Control Center, and accessories show: the chapter reference and edition,
/// never verse text (owner decision Q7).
struct NarrationNowPlayingInfo: Equatable, Sendable {
    let title: String
    let edition: String
    let isPlaying: Bool
}

enum NarrationRemoteCommand: Sendable, Equatable {
    case play, pause, togglePlayPause, nextChapter, previousChapter
}

/// A seam over `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` (plan §9.5).
@MainActor protocol NarrationNowPlaying: AnyObject {
    var commands: AsyncStream<NarrationRemoteCommand> { get }
    /// nil clears Now Playing and disables every command.
    func update(_ info: NarrationNowPlayingInfo?)
}

@MainActor final class SystemNarrationNowPlaying: NarrationNowPlaying {
    let commands: AsyncStream<NarrationRemoteCommand>
    private var current: NarrationNowPlayingInfo?

    init() {
        let (commands, continuation) = AsyncStream<NarrationRemoteCommand>.makeStream()
        self.commands = commands
        let center = MPRemoteCommandCenter.shared()
        // Targets are added once for the app's lifetime and gated by `isEnabled`. Handlers only
        // forward the command, so the thread they are called on does not matter.
        let routes: [(MPRemoteCommand, NarrationRemoteCommand)] = [
            (center.playCommand, .play), (center.pauseCommand, .pause), (center.togglePlayPauseCommand, .togglePlayPause),
            (center.nextTrackCommand, .nextChapter), (center.previousTrackCommand, .previousChapter),
        ]
        for (command, value) in routes {
            command.addTarget { @Sendable _ in
                continuation.yield(value)
                return .success
            }
        }
        // No time base for synthesized speech, and Lock Screen bookmarking would write while locked.
        for command in [center.skipForwardCommand, center.skipBackwardCommand, center.seekForwardCommand, center.seekBackwardCommand,
                        center.changePlaybackPositionCommand, center.changePlaybackRateCommand, center.likeCommand,
                        center.dislikeCommand, center.bookmarkCommand, center.ratingCommand] {
            command.isEnabled = false
        }
        setEnabled(false)
    }

    func update(_ info: NarrationNowPlayingInfo?) {
        guard info != current else { return }
        current = info
        setEnabled(info != nil)
        guard let info else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.edition,
            MPMediaItemPropertyAlbumTitle: String(localized: "Bible"),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
    }

    private func setEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.nextTrackCommand, center.previousTrackCommand] {
            command.isEnabled = enabled
        }
    }
}

#if DEBUG
@MainActor final class RecordingNowPlaying: NarrationNowPlaying {
    let commands: AsyncStream<NarrationRemoteCommand>
    private let continuation: AsyncStream<NarrationRemoteCommand>.Continuation
    private(set) var info: NarrationNowPlayingInfo?
    private(set) var updates = 0
    init() { (commands, continuation) = AsyncStream.makeStream() }
    func update(_ info: NarrationNowPlayingInfo?) {
        guard info != self.info else { return }
        self.info = info
        updates += 1
    }
    /// Delivers a remote command, as the Lock Screen or headphones would.
    func send(_ command: NarrationRemoteCommand) { continuation.yield(command) }
}
#endif
