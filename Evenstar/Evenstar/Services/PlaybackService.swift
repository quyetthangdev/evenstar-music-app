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
        pushNowPlaying()
        persistImmediately()
    }

    func resume() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
        persistImmediately()
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
            persistImmediately()
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
        guard let removalIndex = queue.firstIndex(where: { $0.id == track.id }) else { return }
        let wasCurrent = (removalIndex == queueIndex)
        queue.remove(at: removalIndex)

        if wasCurrent {
            if queueIndex >= queue.count {
                stopPlayback()
            } else {
                // queueIndex stays; the new track at this index becomes current.
                playCountedForCurrent = false
                loadCurrentAndPlay()
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
            try? library.savePlaybackState()
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
    private func loadCurrentAndPlay() {
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
            activateSessionIfNeeded()
            player.play()
            isPlaying = true
            startPositionUpdates()
            pushNowPlaying()
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
            try? library.savePlaybackState()
            playCountedForCurrent = true
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
        try? library.savePlaybackState()
        lastPersistAt = .now
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

    private func metadata(from track: Track) -> TrackMetadata {
        var artwork: UIImage? = nil
        if let path = track.artworkRelativePath,
           let data = try? Data(contentsOf: FileLocation.absoluteURL(forRelative: path)) {
            artwork = UIImage(data: data)
        }
        return TrackMetadata(
            title: track.title,
            artist: track.artistName,
            album: track.albumTitle,
            artwork: artwork,
            durationSeconds: track.durationSeconds
        )
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
