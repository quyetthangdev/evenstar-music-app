import Foundation
import Observation
import AVFoundation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?
    private(set) var position: TimeInterval = 0
    var duration: TimeInterval { player.duration }

    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false
    private var positionTimer: Timer?

    init(player: AudioPlayerProtocol, nowPlaying: NowPlayingPublisher) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.player.didFinishCallback = { [weak self] in
            self?.handleFinish()
        }
    }

    func load(url: URL, metadata: TrackMetadata) throws {
        try player.load(url: url)
        currentMetadata = metadata
        currentTrackTitle = metadata.title
        isPlaying = false
        position = 0
        hasLoaded = true
        pushNowPlaying()
    }

    func play() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopPositionUpdates()
        pushNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to target: TimeInterval) {
        guard hasLoaded else { return }
        let clamped = max(0, min(target, player.duration))
        player.currentTime = clamped
        position = clamped
        pushNowPlaying()
    }

    private func startPositionUpdates() {
        stopPositionUpdates()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.position = self.player.currentTime
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func handleFinish() {
        isPlaying = false
        position = player.duration
        stopPositionUpdates()
        pushNowPlaying()
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
