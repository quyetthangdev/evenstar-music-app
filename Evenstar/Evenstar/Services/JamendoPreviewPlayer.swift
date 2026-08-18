import Foundation
import Observation

/// Plays a catalogue track the library has never heard of, so someone can hear
/// a song before deciding to keep it.
///
/// **Deliberately not `PlaybackService`.** A `JamendoCatalogueTrack` cannot be
/// a `Playable`: that protocol is `AnyObject` with a `UUID` id and mutable
/// `playCount`/`lastPlayedAt`, and a catalogue row is a `struct` of `let`s
/// identified by Jamendo's own `String`. Bending one to fit the other would
/// mean inventing a UUID for a track that has none — and `PlaybackState`
/// persists `currentTrackID` and looks it up in SwiftData on the next launch,
/// so an invented id is a restore that silently finds nothing. That is the
/// failure C1 was filed for; this type exists so previewing cannot recreate it.
///
/// What it gives up by being separate is real: no lock screen, no Now Playing,
/// no queue, no play counting, no session restore. All of that is correct for a
/// preview. What it must **not** give up is the audio session, which is shared
/// (`AVAudioSession.playback`, activated once by `PlaybackService`) — two
/// players sounding at once would simply overlap. So a preview suspends the
/// main player for its duration and puts it back afterwards, through the two
/// closures below.
@Observable
@MainActor
final class JamendoPreviewPlayer {
    /// The catalogue id currently sounding, or `nil`. The discovery list reads
    /// this to mark its row.
    private(set) var playingID: String?

    /// Set when a preview fails to start or dies mid-stream — offline being the
    /// ordinary case. The view turns it into an alert and clears it.
    var failureMessage: String?

    /// Pause the main player, and report whether there was anything to pause.
    ///
    /// Returning `false` is what stops a preview from resuming music the user
    /// had already paused themselves: the resume below only runs if this
    /// returned `true`, so a preview started in silence ends in silence.
    var suspendMainPlayback: (() -> Bool)?

    /// Undo the above. Called exactly once per suspension — on a manual stop,
    /// on the track ending by itself, on a failure, and when the screen goes
    /// away — never twice, and never without a suspension first.
    var resumeMainPlayback: (() -> Void)?

    private let player: AudioPlayerProtocol

    /// Whether *this* type is what paused the main player. Without it, a
    /// preview started while the user was already paused would resume playback
    /// they never asked for when it ended.
    private var didSuspendMain = false

    /// The URL of the sounding preview, for the identity check in the failure
    /// callback — see `AudioPlayerProtocol.didFailCallback`, which requires it:
    /// a stream that takes two seconds to fail can report long after the user
    /// has moved to a different row, and acting on that would stop the preview
    /// they are actually listening to.
    private var playingURL: URL?

    init(player: AudioPlayerProtocol = StreamingAudioPlayer()) {
        self.player = player
        self.player.didFinishCallback = { [weak self] in
            MainActor.assumeIsolated { self?.stop() }
        }
        self.player.didFailCallback = { [weak self] error, url in
            MainActor.assumeIsolated {
                guard let self, url == self.playingURL else { return }
                self.failureMessage = error.localizedDescription
                self.stop()
            }
        }
    }

    /// Start this track, stop it if it is already the one playing.
    ///
    /// Switching straight from one row to another does **not** resume the main
    /// player in between: the suspension belongs to the previewing session, not
    /// to one track, so `didSuspendMain` stays set across the switch.
    func toggle(_ track: JamendoCatalogueTrack) {
        if playingID == track.id {
            stop()
            return
        }
        suspendMainIfNeeded()
        do {
            try player.load(url: track.audioURL)
            player.play()
            playingID = track.id
            playingURL = track.audioURL
        } catch {
            failureMessage = error.localizedDescription
            playingID = nil
            playingURL = nil
            resumeMainIfSuspended()
        }
    }

    /// Silence to whatever the screen was doing before. Safe to call when
    /// nothing is previewing — the discovery screen calls it unconditionally on
    /// the way out.
    func stop() {
        guard playingID != nil else { return }
        player.pause()
        playingID = nil
        playingURL = nil
        resumeMainIfSuspended()
    }

    private func suspendMainIfNeeded() {
        guard !didSuspendMain else { return }
        didSuspendMain = suspendMainPlayback?() ?? false
    }

    private func resumeMainIfSuspended() {
        guard didSuspendMain else { return }
        didSuspendMain = false
        resumeMainPlayback?()
    }
}
