import Foundation
import AVFoundation

protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var didFinishCallback: (() -> Void)? { get set }

    func load(url: URL) throws
    func play()
    func pause()
}

final class AVAudioPlayerWrapper: NSObject, AudioPlayerProtocol, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    var didFinishCallback: (() -> Void)?

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
