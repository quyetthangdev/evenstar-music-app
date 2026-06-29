import Foundation
import Observation
import AVFoundation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?

    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false

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
        hasLoaded = true
        pushNowPlaying()
    }

    func play() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        pushNowPlaying()
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        pushNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    private func handleFinish() {
        isPlaying = false
        pushNowPlaying()
    }

    private func pushNowPlaying() {
        guard let metadata = currentMetadata else { return }
        nowPlaying.update(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            artwork: metadata.artwork,
            duration: metadata.durationSeconds,
            elapsed: player.currentTime,
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
