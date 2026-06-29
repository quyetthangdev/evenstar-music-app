import Foundation
import Observation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?

    private let player: AudioPlayerProtocol
    private var hasLoaded: Bool = false

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
            player.play()
            isPlaying = true
        }
    }
}
