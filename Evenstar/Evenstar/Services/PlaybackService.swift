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
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    private(set) var repeatMode: RepeatMode = .off
    var duration: TimeInterval { player.duration }
    var currentTrack: Track? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
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
    }

    // MARK: - Public

    func play(_ track: Track, in queueTracks: [Track]) {
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
        let clamped = max(0, min(target, player.duration))
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

    /// Restarts the current track, or steps back to the one before it.
    ///
    /// Never a no-op while a queue exists, which is why nothing disables the
    /// button: at the head of the queue, and anywhere past the threshold,
    /// "previous" still means restart.
    func previous() {
        guard !queue.isEmpty else { return }
        if position > Self.restartThreshold || queueIndex == 0 {
            seek(to: 0)
            return
        }
        queueIndex -= 1
        playCountedForCurrent = false
        loadCurrentAndPlay()
        // Deferred for the same reason `next()` defers its own: a SwiftData
        // write between the tap and the next render is felt as button latency,
        // and `loadCurrentAndPlay` has already pushed to the lock screen.
        deferPersist()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCountedForCurrent = false
            loadCurrentAndPlay()
            // Deferred for the same reason `pause()`/`resume()` defer theirs:
            // a SwiftData write between the tap and the next render is felt as
            // button latency. `loadCurrentAndPlay` has already pushed the new
            // track to the lock screen synchronously, so nothing user-visible
            // waits on this.
            deferPersist()
        } else {
            stopPlayback()
        }
    }

    /// Test-only hook: drives the same code path as the 0.5s position timer.
    /// Not for production callers.
    func tickForTesting() { tickPosition() }

    /// Keeps the in-memory queue consistent when a track is deleted from the
    /// library. No-op if `track` isn't in the queue. If it's the currently
    /// playing track, advances to the next track (or stops if it was last).
    /// Otherwise just removes it and shifts `queueIndex` if it sat before the
    /// current position.
    func handleTrackDeleted(_ track: Track) {
        let wasPlaying = isPlaying
        guard let removalIndex = queue.firstIndex(where: { $0.id == track.id }) else { return }
        let wasCurrent = (removalIndex == queueIndex)
        queue.remove(at: removalIndex)

        if wasCurrent {
            if queueIndex >= queue.count {
                stopPlayback()
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
        let resolved: [Track] = state.queueTrackIDs.compactMap { id in
            try? library.findTrack(byID: id)
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
            let url = FileLocation.absoluteURL(forRelative: track.relativePath)
            do {
                try player.load(url: url)
                hasLoaded = true
            } catch {
                attempts += 1
                if queueIndex + 1 < queue.count {
                    queueIndex += 1
                    continue
                } else {
                    stopPlayback()
                    return
                }
            }
            // The saved position only applies to the track it was recorded
            // against; a track reached by skipping forward starts at 0.
            let pos = queueIndex == originalIndex
                ? max(0, min(savedPosition, player.duration))
                : 0
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
    /// `queueIndex` advances. This is a bounded loop (at most `queue.count`
    /// attempts, since each failed attempt either advances `queueIndex` or
    /// exits) so a queue whose files have all been deleted still terminates in
    /// `stopPlayback()` rather than recursing or spinning forever.
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
            let url = FileLocation.absoluteURL(forRelative: track.relativePath)
            do {
                try player.load(url: url)
                hasLoaded = true
            } catch {
                attempts += 1
                if queueIndex + 1 < queue.count {
                    queueIndex += 1
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

    private func handleFinish() {
        if queueIndex + 1 < queue.count {
            next()
        } else {
            stopPlayback()
        }
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
    private func metadata(from track: Track) -> TrackMetadata {
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
    /// Takes the path out of the `Track` before hopping: `Track` is a SwiftData
    /// `@Model`, neither `Sendable` nor safe to touch from another executor.
    private func loadArtworkIntoNowPlaying(for track: Track) {
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
