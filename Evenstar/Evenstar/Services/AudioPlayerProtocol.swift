import Foundation
import AVFoundation

protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var didFinishCallback: (() -> Void)? { get set }
    /// Playback failed after loading succeeded — or failed to load at all, for
    /// players that cannot report that synchronously.
    ///
    /// **Required, not tidiness.** `AVAudioPlayer` reports a bad file by
    /// throwing from `load(url:)`, and `PlaybackService`'s skip-forward loop is
    /// built on that throw. `AVPlayer` reports failure asynchronously through
    /// `AVPlayerItem.status`, so without this an offline device would leave
    /// playback silently hung — the skip loop would never run.
    var didFailCallback: ((Error) -> Void)? { get set }

    func load(url: URL) throws
    func play()
    func pause()
}

final class AVAudioPlayerWrapper: NSObject, AudioPlayerProtocol, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    var didFinishCallback: (() -> Void)?

    /// Never called here, on purpose. A local file that will not open still
    /// throws from `load(url:)`, so `PlaybackService`'s skip-forward loop keeps
    /// handling local failures exactly as it always has and local playback
    /// behaviour is unchanged by this protocol addition.
    var didFailCallback: ((Error) -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }

    var duration: TimeInterval { player?.duration ?? 0 }

    func load(url: URL) throws {
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        player = newPlayer
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        didFinishCallback?()
    }
}
