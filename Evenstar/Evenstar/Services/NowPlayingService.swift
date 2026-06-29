import Foundation
import MediaPlayer
import UIKit

struct TrackMetadata: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: UIImage?
    let durationSeconds: TimeInterval
}

protocol NowPlayingPublisher: AnyObject {
    func update(title: String,
                artist: String,
                album: String,
                artwork: UIImage?,
                duration: TimeInterval,
                elapsed: TimeInterval,
                isPlaying: Bool)
    func clear()
}

final class NowPlayingService: NowPlayingPublisher {
    func update(title: String,
                artist: String,
                album: String,
                artwork: UIImage?,
                duration: TimeInterval,
                elapsed: TimeInterval,
                isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
