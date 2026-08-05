import Foundation
import Observation
import AVFoundation
import UIKit

@Observable
@MainActor
final class PlaybackService {
    // MARK: - Observable state
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?
    private(set) var position: TimeInterval = 0
    /// Holds `Track` and `DriveTrack` side by side — see `Playable`. Nothing
    /// below this line may re-introduce a source-specific assumption about the
    /// element type; the whole point is that repeat, restore, play counting and
    /// the lock-screen push are written once.
    private(set) var queue: [any Playable] = []
    private(set) var queueIndex: Int = 0
    private(set) var repeatMode: RepeatMode = .off
    /// The last playback failure, for the UI to show.
    ///
    /// Cleared when a track actually *starts playing* — the end of the
    /// `autoPlay` branch of `loadCurrentAndPlay()`. Not cleared by `resume()`,
    /// and deliberately so: after a failure `hasLoaded` is false, so `resume()`
    /// returns early and there is nothing successful to clear the error on
    /// behalf of. Playing something is what makes the banner stale, and playing
    /// something is what removes it.
    private(set) var lastPlaybackError: Error?
    var duration: TimeInterval { player.duration }
    var currentTrack: (any Playable)? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
    }

    /// Whether Next has anywhere to go.
    ///
    /// Derived here rather than in the views because two of them ask. Both the
    /// expanded player and the mini player used to compute
    /// `queueIndex >= queue.count - 1` for themselves, which was correct only
    /// while the end of the queue was always the end of playback. With a repeat
    /// mode armed it no longer is, and one rule living in two files is how a
    /// half-applied fix ships.
    var canGoNext: Bool {
        !queue.isEmpty && (queueIndex + 1 < queue.count || repeatMode != .off)
    }

    // MARK: - Dependencies
    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private let library: LibraryService

    // MARK: - Internal state
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false
    private var positionTimer: Timer?
    private var playCountedForCurrent: Bool = false
    private var lastPersistAt: Date = .distantPast
    private let persistInterval: TimeInterval
    /// The URL most recently handed to `player.load(url:)`.
    ///
    /// The identity an asynchronous failure is checked against. A streaming
    /// load can fail seconds after it was asked for, by which time the user may
    /// have started something else; without this, that stale failure would
    /// pause the track they are actually listening to. Nothing can retract a
    /// callback already delivered, so the only defence is to recognise it as
    /// stale on arrival.
    private var lastRequestedURL: URL?

    init(player: AudioPlayerProtocol,
         nowPlaying: NowPlayingPublisher,
         library: LibraryService,
         persistInterval: TimeInterval = 5) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.library = library
        self.persistInterval = persistInterval
        self.player.didFinishCallback = { [weak self] in
            Task { @MainActor in self?.handleFinish() }
        }
        self.player.didFailCallback = { [weak self] error, url in
            Task { @MainActor in self?.handleFailure(error, url: url) }
        }
    }

    // MARK: - Public

    func play(_ track: any Playable, in queueTracks: [any Playable]) {
        queue = queueTracks
        queueIndex = queueTracks.firstIndex(where: { $0.id == track.id }) ?? 0
        loadCurrentAndPlay()
        persistImmediately()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    /// Advances the repeat button through off → all → one → off.
    ///
    /// The mode change is applied inline, not deferred. For a mode button the
    /// state change *is* the feedback — the glyph and its tint both read from
    /// `repeatMode` — so deferring it would push the very thing being
    /// acknowledged a turn later, which is the mistake that made play/pause
    /// feel slow. Only the disk write is deferred.
    func cycleRepeatMode() {
        repeatMode = repeatMode.cycled
        deferPersist()
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        position = player.currentTime
        stopPositionUpdates()
        deferSideEffects()
    }

    func resume() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        deferSideEffects()
    }

    func seek(to target: TimeInterval) {
        guard hasLoaded else { return }
        let clamped = clampToDuration(target)
        player.currentTime = clamped
        position = clamped
        pushNowPlaying()
        // Deferred like every other tap path's write. This one is reached from
        // the scrubber on release and from `previous()` restarting a track, and
        // in both the user is waiting to see something move.
        deferPersist()
    }

    /// How far into a track Previous stops meaning "the one before" and starts
    /// meaning "this one, from the top".
    ///
    /// Every music player behaves this way, and the reason is that Previous has
    /// two jobs sharing a button: correcting a skip you just made, and
    /// restarting something you are part way through. Three seconds is the
    /// usual split — long enough that a mis-tap in the opening still goes back,
    /// short enough that it never blocks a deliberate restart.
    static let restartThreshold: TimeInterval = 3

    /// Restarts the current track, steps back to the one before it, or — at
    /// the head of the queue with a repeat mode armed — wraps to the last
    /// track, the same "the queue doesn't end" logic `next()` applies going
    /// forward.
    ///
    /// Never a no-op while a queue exists, which is why nothing disables the
    /// button: past the threshold it restarts, at the head of the queue it
    /// either wraps (repeat armed) or restarts (repeat off), and anywhere else
    /// it steps back.
    func previous() {
        guard !queue.isEmpty else { return }
        // The threshold outranks the repeat mode. Past three seconds this
        // button means "this one, from the top" whatever is armed.
        if position > Self.restartThreshold {
            seek(to: 0)
            return
        }
        if queueIndex > 0 {
            advance(to: queueIndex - 1)
        } else if repeatMode != .off {
            advance(to: queue.count - 1)
        } else {
            seek(to: 0)
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            advance(to: queueIndex + 1)
        } else if repeatMode != .off {
            // Repeat-one wraps here too. It means "an unattended track
            // repeats", not "the queue has an end" — and a Next press is not
            // unattended.
            advance(to: 0)
        } else {
            stopPlayback()
        }
    }

    /// Test-only hook: drives the same code path as the 0.5s position timer.
    /// Not for production callers.
    func tickForTesting() { tickPosition() }

    /// Keeps the in-memory queue consistent when a track is deleted from the
    /// library. No-op if `track` isn't in the queue. If it's the currently
    /// playing track, advances to the next track — or, if it was the last one,
    /// wraps to the top under repeat-all and otherwise stops. Tracks that
    /// aren't current are just removed, shifting `queueIndex` if they sat
    /// before the current position.
    ///
    /// Keeps its concrete `Track` parameter on purpose: deleting is a
    /// local-library action, and it matches queue members by `id`, so a mixed
    /// queue needs nothing else here.
    func handleTrackDeleted(_ track: Track) {
        let wasPlaying = isPlaying
        guard let removalIndex = queue.firstIndex(where: { $0.id == track.id }) else { return }
        let wasCurrent = (removalIndex == queueIndex)
        queue.remove(at: removalIndex)

        if wasCurrent {
            if queueIndex >= queue.count {
                // Deleting the current track took us past the end. This is the
                // third place that has to know an armed mode means the queue
                // has no end — `next()` and `handleFinish()` are the other two
                // — and it was the one left behind: swiping away the last track
                // with repeat-all on stopped the music and wiped the surviving
                // tracks, which is the worst possible answer to a delete.
                //
                // `.all` wraps: the tracks before it are still there and still
                // wanted. `.one` deliberately does not, and this is not an
                // oversight — repeat-one means "keep replaying *this* track",
                // and the track it named is the one the user just deleted. With
                // nothing left to repeat, stopping is the honest answer;
                // wrapping would silently convert repeat-one into repeat-all.
                //
                // The emptiness check is load-bearing: deleting the only track
                // in the queue leaves nothing to wrap to, whatever is armed.
                if repeatMode == .all, !queue.isEmpty {
                    queueIndex = 0
                    playCountedForCurrent = false
                    loadCurrentAndPlay(autoPlay: wasPlaying)
                    persistImmediately()
                } else {
                    stopPlayback()
                }
            } else {
                // queueIndex stays; the new track at this index becomes current.
                playCountedForCurrent = false
                loadCurrentAndPlay(autoPlay: wasPlaying)
                persistImmediately()
            }
        } else if removalIndex < queueIndex {
            queueIndex -= 1
            persistImmediately()
        } else {
            persistImmediately()
        }
    }

    /// Restores the queue, current track, and position from the persisted
    /// `PlaybackState` row on app launch. Loads and seeks the current track
    /// but deliberately leaves `isPlaying == false` — the user resumes by
    /// tapping play. Track IDs that no longer resolve in the library (e.g.
    /// deleted between sessions) are dropped from the restored queue, and
    /// `queueIndex` is clamped into the surviving range. An empty/absent
    /// persisted state is a no-op.
    ///
    /// If the file for the saved current track can no longer be loaded
    /// (missing/corrupt on disk, even though its DB row still exists), this
    /// mirrors `loadCurrentAndPlay()`'s resilience: it skips forward through
    /// the remaining queue looking for a track that does load, rather than
    /// tearing down the whole restored queue over one bad file. This is a
    /// separate, self-contained loop rather than a call into
    /// `loadCurrentAndPlay()` — that method also starts playback, which
    /// restore must never do, and duplicating the small skip mechanics here
    /// keeps `loadCurrentAndPlay()` itself untouched. Only when nothing in
    /// the queue can load does it fall through to `stopPlayback()`.
    func restoreFromPersistedState() async {
        let state = library.playbackState
        // Above the guard on purpose. The repeat mode is a setting rather than
        // part of the queue, so a launch with nothing to restore must still
        // bring it back. Reading it after the guard would quietly reset it to
        // off for anyone who finished their queue before quitting.
        repeatMode = RepeatMode(rawValue: state.repeatModeRaw) ?? .off
        guard !state.queueTrackIDs.isEmpty else { return }
        let resolved: [any Playable] = state.queueTrackIDs.compactMap { id -> (any Playable)? in
            // Local first: it is the commoner case and needs no second query
            // when it hits.
            if let track = try? library.findTrack(byID: id) { return track }
            return try? library.findDriveTrack(byID: id)
        }
        guard !resolved.isEmpty else {
            // Stale state — clear it.
            state.queueTrackIDs = []
            state.queueIndex = 0
            state.currentTrackID = nil
            state.positionSeconds = 0
            try? library.save()
            return
        }
        queue = resolved
        queueIndex = max(0, min(state.queueIndex, resolved.count - 1))
        let originalIndex = queueIndex
        let savedPosition = state.positionSeconds

        var attempts = 0
        while attempts < queue.count {
            guard let track = currentTrack else {
                stopPlayback()
                return
            }
            let url = track.playbackURL()
            // Recorded *before* the call, not after: the missing-API-key
            // sentinel path reports its failure synchronously from inside
            // `load`, and a callback that arrived before this was set would be
            // dropped by `handleFailure`'s ownership guard as belonging to
            // nothing.
            lastRequestedURL = url
            do {
                try player.load(url: url)
                hasLoaded = true
            } catch {
                attempts += 1
                if queueIndex + 1 < queue.count {
                    queueIndex += 1
                    continue
                } else if repeatMode != .off {
                    // Same wrap as `loadCurrentAndPlay()`'s loop, and bounded
                    // by the same already-incremented `attempts`. Lower stakes
                    // here — restore never autoplays, so nothing stops mid
                    // listen — but the outcome without it is still wrong: a
                    // relaunch with repeat armed and the last track's file gone
                    // threw away a queue whose earlier tracks were all fine.
                    //
                    // `repeatMode` is read above the queue guard, so it is
                    // already the restored value by the time this runs.
                    queueIndex = 0
                    continue
                } else {
                    stopPlayback()
                    return
                }
            }
            // The saved position only applies to the track it was recorded
            // against; a track reached by skipping forward starts at 0.
            let pos = queueIndex == originalIndex ? clampToDuration(savedPosition) : 0
            player.currentTime = pos
            position = pos
            currentMetadata = metadata(from: track)
            currentTrackTitle = track.title
            playCountedForCurrent = pos >= 30
            isPlaying = false
            pushNowPlaying()
            // Restore builds and pushes its own metadata rather than calling
            // `loadCurrentAndPlay()` (see above), so it has to ask for the
            // artwork itself — `metadata(from:)` returns `artwork: nil` by
            // design. Omitting this call left the most common launch path with
            // no cover at all: `NowPlayingService.update` simply drops the
            // artwork key when it is nil, and every later push on this track
            // (`resume()`, `pause()`, `seek()`, the `tickPosition()` reconcile)
            // re-reads the same nil-artwork `currentMetadata`, so the lock
            // screen stayed blank until the track changed.
            loadArtworkIntoNowPlaying(for: track)
            // Persist the queue/index/position that actually landed — the
            // stored row must reflect surviving tracks, not the pre-restore
            // state, and must not be silently left pointing at a dead track.
            persistImmediately()
            return
        }
        stopPlayback()
    }

    // MARK: - Private

    /// Loads the track at `queueIndex` and starts playback. If a track fails to
    /// load (missing/corrupt file), skips forward through the remaining queue
    /// looking for one that does — the queue itself is untouched, only
    /// `queueIndex` advances. Running off the end with a repeat mode armed
    /// wraps to index 0 and keeps looking, because an armed mode means the
    /// queue has no end: without that, one deleted file at the tail of an
    /// overnight repeat-all queue stopped the music and wiped the queue even
    /// though every track behind it played fine.
    ///
    /// **Still bounded, and the bound is what makes the wrap safe.** The loop
    /// runs at most `queue.count` times because every failed attempt increments
    /// `attempts` exactly once before it advances, wraps, or exits — the wrap
    /// changes *where* the next attempt looks, never how many are left. So a
    /// queue whose files have all been deleted still terminates in
    /// `stopPlayback()` rather than circling forever, and it does so having
    /// tried each position at most once.
    /// - Parameter autoPlay: When false, the track still loads, seeks to 0,
    ///   publishes Now Playing info, and persists — it just doesn't start
    ///   playback, and `isPlaying` ends up `false`. Defaults to `true` so
    ///   every existing call site (play, next, restore-adjacent flows) keeps
    ///   its current behavior unchanged.
    private func loadCurrentAndPlay(autoPlay: Bool = true) {
        var attempts = 0
        while attempts < queue.count {
            guard let track = currentTrack else {
                stopPlayback()
                return
            }
            let url = track.playbackURL()
            // Before the call, for the reason given on the same line in
            // `restoreFromPersistedState()`: the sentinel path reports
            // synchronously from inside `load`.
            lastRequestedURL = url
            do {
                try player.load(url: url)
                hasLoaded = true
            } catch {
                attempts += 1
                if queueIndex + 1 < queue.count {
                    queueIndex += 1
                    playCountedForCurrent = false
                    continue
                } else if repeatMode != .off {
                    // Wrap rather than stop, for the same reason `next()` does:
                    // with a mode armed the end of the queue is not the end of
                    // playback. `!= .off` rather than `== .all` because this
                    // isn't a choice about which track to play next — it is
                    // recovery from a file that won't open, and repeat-one's
                    // "an unattended track repeats" says nothing about what to
                    // do when that track cannot be opened at all. Stopping
                    // there would end the session over one bad file with the
                    // rest of the queue intact.
                    //
                    // `attempts` was already incremented above, so the loop
                    // condition still stops this after `queue.count` tries.
                    queueIndex = 0
                    playCountedForCurrent = false
                    continue
                } else {
                    stopPlayback()
                    return
                }
            }
            currentMetadata = metadata(from: track)
            currentTrackTitle = track.title
            position = 0
            playCountedForCurrent = false
            if autoPlay {
                activateSessionIfNeeded()
                player.play()
                isPlaying = true
                startPositionUpdates()
                // A track is starting, so whatever went wrong last time is no
                // longer what the user is looking at. Cleared here rather than
                // at the top of the method because the skip-forward loop above
                // can pass through several failing tracks first; clearing early
                // would wipe the explanation before anything had actually
                // started. `autoPlay == false` paths (restore, a delete that
                // reloads without playing) deliberately leave it alone —
                // nothing began playing there either.
                lastPlaybackError = nil
            } else {
                isPlaying = false
            }
            pushNowPlaying()
            loadArtworkIntoNowPlaying(for: track)
            return
        }
        stopPlayback()
    }

    private func stopPlayback() {
        player.pause()
        isPlaying = false
        hasLoaded = false
        // Nothing is loaded, so no in-flight failure belongs to the present any
        // more. Leaving this set would let a late failure for the track we just
        // stopped raise a banner about playback the user has already ended.
        lastRequestedURL = nil
        queue = []
        queueIndex = 0
        currentMetadata = nil
        currentTrackTitle = nil
        position = 0
        playCountedForCurrent = false
        stopPositionUpdates()
        nowPlaying.clear()
        persistImmediately()
    }

    /// Plays the track at `index`, from the top.
    ///
    /// Extracted because four callers now want it — Next, Previous, automatic
    /// advance, and the repeat-one replay, which is simply `advance(to:)` with
    /// the index it already has: `loadCurrentAndPlay()` reloads the file, seeks
    /// to 0 and starts, which is exactly what replaying a track is.
    ///
    /// The persist is deferred for the same reason every other tap path defers
    /// its own: a SwiftData write between the tap and the next render is felt
    /// as button latency, and `loadCurrentAndPlay()` has already pushed the
    /// track to the lock screen synchronously, so nothing user-visible waits.
    private func advance(to index: Int) {
        queueIndex = index
        playCountedForCurrent = false
        loadCurrentAndPlay()
        deferPersist()
    }

    /// A track ran out on its own.
    ///
    /// This deliberately no longer delegates to `next()`. The two are different
    /// events that happen to have shared an implementation: repeat-one applies
    /// here and *not* to the Next button, where pressing it means the user
    /// wants the next track regardless of the mode. Delegating would make Next
    /// replay the current track whenever repeat-one was armed, which reads as a
    /// broken button.
    private func handleFinish() {
        guard !queue.isEmpty else { return }
        switch repeatMode {
        case .one:
            advance(to: queueIndex)
        case .all:
            advance(to: queueIndex + 1 < queue.count ? queueIndex + 1 : 0)
        case .off:
            if queueIndex + 1 < queue.count {
                advance(to: queueIndex + 1)
            } else {
                stopPlayback()
            }
        }
    }

    /// Clamps a position into the track, skipping the upper bound while the
    /// player has no duration to offer.
    ///
    /// `AVPlayer` reports an indefinite duration for the first few hundred
    /// milliseconds after a streaming load, and `StreamingAudioPlayer.duration`
    /// reports `0` there to keep NaN out of the scrubber's arithmetic. Clamping
    /// against that `0` is what made **every restored Drive track lose its
    /// saved position** — `min(2:31, 0)` is `0` — and made a scrub in that
    /// window jump to the start. There is no fallback to fall back on:
    /// `DriveTrack.durationSeconds` defaults to 0 as well.
    ///
    /// Chosen over deferring the seek inside `PlaybackService` because the
    /// damage happens *here*, at the clamp: by the time a deferred seek ran, the
    /// position would already have been flattened to 0 and there would be
    /// nothing left to defer. The player still defers *applying* the seek until
    /// its item is ready — the two halves are complementary, and both are
    /// needed. Handing over a position past the eventual duration is safe;
    /// `AVPlayer` clamps a seek to the seekable range itself.
    private func clampToDuration(_ target: TimeInterval) -> TimeInterval {
        guard player.isDurationKnown else { return max(0, target) }
        return max(0, min(target, player.duration))
    }

    /// A player that failed after `load()` returned.
    ///
    /// Deliberately does not skip to the next track: the commonest cause is no
    /// network, and skipping would march through the whole queue failing once
    /// per track. Stopping and saying why is the useful behaviour.
    ///
    /// **The `url` guard is the whole safety of this method.** An asynchronous
    /// failure arrives with no inherent claim on the present: a Drive item can
    /// take seconds to reach `.failed`, the callback hop costs another
    /// main-actor turn, and `teardown()`'s `invalidate()` cannot retract a
    /// callback already in flight. Offline, tapping Drive track A and then
    /// local track B — which plays fine — would otherwise end with B paused,
    /// the timer stopped and a network banner about A. Same class of bug as the
    /// stale `didFinishCallback` skipping a track, and it needs the same answer.
    ///
    /// A repeat-one replay reloads the same URL and so passes the guard, which
    /// is correct rather than a hole: it is the same file failing for the same
    /// reason, and the report applies either way.
    private func handleFailure(_ error: Error, url: URL) {
        guard url == lastRequestedURL else { return }
        lastPlaybackError = error
        player.pause()
        isPlaying = false
        // Without this the transport lies. `resume()` guards on
        // `hasLoaded, !isPlaying`, both of which would still hold: a tap on
        // play would call `player.play()` — a no-op on a failed item — set
        // `isPlaying = true` and restart the timer, giving a pause glyph, a
        // position frozen at 0:00 and no sound. `tickPosition`'s reconcile
        // cannot rescue it either, because a failed item reports duration 0 and
        // currentTime 0, and `0 < 0 - 0.5` is false. Clearing the flag makes
        // play inert instead of dishonest.
        hasLoaded = false
        stopPositionUpdates()
        pushNowPlaying()
    }

    private func tickPosition() {
        position = player.currentTime
        if !playCountedForCurrent, position >= 30, let track = currentTrack {
            track.playCount += 1
            track.lastPlayedAt = .now
            try? library.save()
            playCountedForCurrent = true
        }
        // The player can stop underneath us without going through pause()/
        // stopPlayback() — a phone call, a headphone unplug. Reconcile our
        // state so the UI and lock screen stop claiming playback. Guarded
        // against the end-of-track race: `player.isPlaying` goes false a
        // moment before the async didFinishCallback hop lands, so only
        // reconcile when clearly not near the end, or this would fire on
        // every track's natural finish and fight auto-advance.
        if isPlaying, !player.isPlaying, player.currentTime < player.duration - 0.5 {
            isPlaying = false
            stopPositionUpdates()
            pushNowPlaying()
            persistImmediately()
            return
        }
        persistThrottled()
    }

    private func startPositionUpdates() {
        stopPositionUpdates()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tickPosition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func persistThrottled() {
        if Date.now.timeIntervalSince(lastPersistAt) >= persistInterval {
            persistImmediately()
        }
    }

    private func persistImmediately() {
        let state = library.playbackState
        state.queueTrackIDs = queue.map(\.id)
        state.queueIndex = queueIndex
        state.currentTrackID = currentTrack?.id
        state.positionSeconds = position
        state.repeatModeRaw = repeatMode.rawValue
        try? library.save()
        lastPersistAt = .now
    }

    /// Runs the lock-screen push and the disk write after the current
    /// main-actor turn, so SwiftUI renders the new play/pause glyph before
    /// either starts. Only for the tap path (`pause()`/`resume()`): assigning
    /// `nowPlayingInfo` ships the artwork across XPC to the media server and
    /// `persistImmediately()` does a SwiftData write, and both otherwise land
    /// inside the perceived button latency.
    private func deferSideEffects() {
        Task { @MainActor in
            pushNowPlaying()
            persistImmediately()
        }
    }

    /// The persist half alone, for callers that have already pushed to the lock
    /// screen synchronously and only need the disk write moved off the tap.
    ///
    /// **Nothing may be captured here, and the same goes for `deferSideEffects`
    /// above.** A deferred write can land *after* something else has already
    /// persisted — `next()` on the last track calls `stopPlayback()`, which
    /// persists an empty queue, and this task runs afterwards. That is safe
    /// only because `persistImmediately()` reads `queue`, `queueIndex`,
    /// `currentTrack` and `position` live at execution time and captures
    /// nothing at enqueue time, so a late write reproduces whatever state
    /// actually landed in between rather than resurrecting a stale snapshot.
    /// Passing captured values in (a queue, an index, a position taken at the
    /// tap) would turn a harmless duplicate write into a resurrection of a
    /// queue the user has already left — this project's worst bug to date came
    /// from exactly that shape. Change the behaviour only with that in mind.
    private func deferPersist() {
        Task { @MainActor in persistImmediately() }
    }

    private func pushNowPlaying() {
        guard let metadata = currentMetadata else { return }
        nowPlaying.update(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            artwork: metadata.artwork,
            duration: player.duration,
            elapsed: position,
            isPlaying: isPlaying
        )
    }

    /// Everything except the artwork — all of it already in memory, so it costs
    /// nothing to build while the user's finger is still on the button.
    ///
    /// The artwork used to be read and decoded here, synchronously, on every
    /// track change. That put a file read and a full-size `UIImage` decode
    /// between a tap on Next and anything happening on screen. It arrives
    /// separately now; see `loadArtworkIntoNowPlaying`.
    private func metadata(from track: any Playable) -> TrackMetadata {
        TrackMetadata(
            title: track.title,
            artist: track.artistName,
            album: track.albumTitle,
            artwork: nil,
            durationSeconds: track.durationSeconds
        )
    }

    /// Fills the artwork in behind the tap and pushes again.
    ///
    /// The lock screen gets title, artist and album immediately and the picture
    /// a moment later, which is the right trade: the text is what tells the user
    /// the track changed, and it no longer waits on a decode.
    ///
    /// Guarded on the track's id, because a user holding Next changes track
    /// faster than a decode finishes — without it, a late decode would put the
    /// previous track's cover under the current track's title.
    ///
    /// The load goes through `ArtworkStore`, not through a local
    /// `Data(contentsOf:)` + `UIImage(data:)`. That pair decoded the file at
    /// its full resolution, which for the 1000x1000–3000x3000 covers embedded
    /// in real files is up to ~36 MB a time, and it only *moved* the cost this
    /// method exists to remove: `NowPlayingService` wraps the result as
    /// `MPMediaItemArtwork(boundsSize: artwork.size)`, so the full-size bitmap
    /// is what crosses XPC to the media server. `ArtworkStore` downsamples
    /// through ImageIO to `lockScreenArtworkPixels` and caches the result, so
    /// each of these tasks holds a few MB rather than tens, and a track played
    /// again later is a cache hit rather than another file read.
    ///
    /// The task is deliberately unstructured and unstored. Holding Next starts
    /// one per track change, and the id guard below discards all but the last;
    /// what makes that acceptable rather than wasteful is that each is now a
    /// bounded, cached, downsampled read. If this ever goes back to decoding at
    /// full size, the fan-out has to be bounded too.
    ///
    /// Takes the path out of the row before hopping: both `Playable`
    /// conformers are SwiftData `@Model`s, neither `Sendable` nor safe to touch
    /// from another executor. A Drive track always reports a nil path, so this
    /// simply finds no artwork for one rather than needing a source check.
    private func loadArtworkIntoNowPlaying(for track: any Playable) {
        let path = track.artworkRelativePath
        let id = track.id
        Task { @MainActor in
            let image = await ArtworkStore.image(
                for: path,
                maxPixel: Self.lockScreenArtworkPixels
            )
            guard let image else { return }
            guard currentTrack?.id == id, let current = currentMetadata else { return }
            currentMetadata = TrackMetadata(
                title: current.title,
                artist: current.artist,
                album: current.album,
                artwork: image,
                durationSeconds: current.durationSeconds
            )
            pushNowPlaying()
        }
    }

    /// The longest edge, in pixels, the lock screen and Control Center need —
    /// the only two consumers of `TrackMetadata.artwork`. Nothing in the app
    /// draws it; `PlayerCard` asks `ArtworkStore` for its own size separately.
    ///
    /// The lock screen's cover fills most of the display's width, so the
    /// requirement scales with the largest device: ~360pt on a 440pt-wide
    /// iPhone 17 Pro Max, which at @3x is ~1080px. 1024 is the round number
    /// just under that — visually indistinguishable at this size, and 4 MB
    /// rather than the ~36 MB a full-resolution 3000x3000 cover would cost,
    /// which also keeps a queue's worth of entries inside `ArtworkStore`'s
    /// 50 MB cache budget.
    private static let lockScreenArtworkPixels: CGFloat = 1024

    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            sessionActivated = true
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
}
