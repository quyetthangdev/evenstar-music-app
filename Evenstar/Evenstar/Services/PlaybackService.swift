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
        persistImmediately()
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
    private func loadArtworkIntoNowPlaying(for track: Track) {
        let path = track.artworkRelativePath
        let id = track.id
        Task { @MainActor in
            guard let image = await Self.decodeArtwork(path) else { return }
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

    /// `@concurrent`, not a bare `nonisolated async`. Under this project's
    /// `SWIFT_APPROACHABLE_CONCURRENCY` setting the latter inherits its
    /// caller's executor, so called from the main actor it would decode on the
    /// main thread and change nothing. Same reasoning as `ArtworkStore`.
    ///
    /// Takes a path rather than a `Track`: `Track` is a SwiftData `@Model`,
    /// neither `Sendable` nor safe to touch from another executor.
    @concurrent
    private static func decodeArtwork(_ relativePath: String?) async -> UIImage? {
        guard let relativePath,
              let data = try? Data(contentsOf: FileLocation.absoluteURL(forRelative: relativePath))
        else { return nil }
        return UIImage(data: data)
    }

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
