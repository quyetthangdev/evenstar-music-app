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
    ///
    /// **The `URL` says which load failed, and callers must check it.** An
    /// asynchronous failure carries no identity of its own, and nothing can
    /// retract a callback already delivered: a Drive track that takes two
    /// seconds to fail can report long after the user has moved on to a local
    /// track that is playing perfectly. Acting on that unconditionally would
    /// pause the track the user is actually listening to and show them an error
    /// about a different one.
    var didFailCallback: ((Error, URL) -> Void)? { get set }

    /// Whether `duration` is a real answer yet, as opposed to a stand-in.
    ///
    /// Only a streaming player ever answers `false`: `AVPlayer` reports an
    /// indefinite duration for the first few hundred milliseconds after a load,
    /// and `duration` reports `0` in that window to keep NaN away from the
    /// scrubber's arithmetic. Anything that *clamps* against `duration` has to
    /// be able to tell that `0` apart from a genuine zero-length track, or it
    /// silently clamps a restored position of 2:31 down to 0:00.
    ///
    /// Defaulted to `true` — a local file knows its duration the moment it
    /// opens, so `AVAudioPlayerWrapper` needs no opinion here.
    var isDurationKnown: Bool { get }

    func load(url: URL) throws
    func play()
    func pause()

    /// Đặt âm lượng của riêng bản phát này, có thể trượt dần tới đó.
    ///
    /// Chỉ hẹn giờ ngủ dùng: mờ về 0 trước khi tắt, và trả về 1 khi người dùng
    /// huỷ hẹn hoặc đặt lại. **Không phải âm lượng hệ thống** — `SystemVolumeSlider`
    /// mới là thứ chỉnh cái đó, và hai thứ nhân với nhau. Mờ ở tầng này nên nếu
    /// app bị giết giữa lúc mờ, âm lượng máy vẫn nguyên như người dùng để.
    ///
    /// `fadeDuration` bằng 0 nghĩa là đổi ngay.
    func setVolume(_ volume: Float, fadeDuration: TimeInterval)
}

extension AudioPlayerProtocol {
    var isDurationKnown: Bool { true }

    /// Mặc định không làm gì.
    ///
    /// Một bản phát không chỉnh được âm lượng thì hẹn giờ ngủ vẫn phải chạy —
    /// nó tắt nhạc đúng giờ, chỉ là tắt thẳng thay vì mờ dần. Ép mọi bản phát
    /// phải hiện thực chỉ để trả về một chỗ trống thì không mua được gì.
    func setVolume(_ volume: Float, fadeDuration: TimeInterval) {}
}

final class AVAudioPlayerWrapper: NSObject, AudioPlayerProtocol, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    var didFinishCallback: (() -> Void)?

    /// Never called here, on purpose. A local file that will not open still
    /// throws from `load(url:)`, so `PlaybackService`'s skip-forward loop keeps
    /// handling local failures exactly as it always has and local playback
    /// behaviour is unchanged by this protocol addition.
    var didFailCallback: ((Error, URL) -> Void)?

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

    /// `AVAudioPlayer` tự trượt âm lượng, nên ở đây không phải tự nội suy.
    func setVolume(_ volume: Float, fadeDuration: TimeInterval) {
        player?.setVolume(volume, fadeDuration: fadeDuration)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        didFinishCallback?()
    }
}
