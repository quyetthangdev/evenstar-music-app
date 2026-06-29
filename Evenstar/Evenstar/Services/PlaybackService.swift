import Foundation
import Observation
import AVFoundation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?

    private let player: AudioPlayerProtocol
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false

    init(player: AudioPlayerProtocol) {
        self.player = player
        self.player.didFinishCallback = { [weak self] in
            self?.isPlaying = false
        }
    }

    func load(url: URL, title: String) throws {
        try player.load(url: url)
        currentTrackTitle = title
        isPlaying = false
        hasLoaded = true
    }

    func togglePlayPause() {
        guard hasLoaded else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            activateSessionIfNeeded()
            player.play()
            isPlaying = true
        }
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
