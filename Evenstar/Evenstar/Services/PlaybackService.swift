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

    init(player: AudioPlayerProtocol,
         nowPlaying: NowPlayingPublisher,
         library: LibraryService) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.library = library
        self.player.didFinishCallback = { [weak self] in
            Task { @MainActor in self?.handleFinish() }
        }
    }

    // MARK: - Public

    func play(_ track: Track, in queueTracks: [Track]) {
        queue = queueTracks
        queueIndex = queueTracks.firstIndex(where: { $0.id == track.id }) ?? 0
        loadCurrentAndPlay()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopPositionUpdates()
        pushNowPlaying()
    }

    func resume() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
    }

    func seek(to target: TimeInterval) {
        guard hasLoaded else { return }
        let clamped = max(0, min(target, player.duration))
        player.currentTime = clamped
        position = clamped
        pushNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCountedForCurrent = false
            loadCurrentAndPlay()
        } else {
            stopPlayback()
        }
    }

    /// Test-only hook: drives the same code path as the 0.5s position timer.
    /// Not for production callers.
    func tickForTesting() { tickPosition() }

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
