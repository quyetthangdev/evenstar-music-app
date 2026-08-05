import AVFoundation
import Foundation

/// `AudioPlayerProtocol` over `AVPlayer`, for tracks that live on the network.
///
/// `AVAudioPlayer` cannot do this — it needs a complete local file. `AVPlayer`
/// streams with range requests, which is what makes playing from Drive possible
/// without downloading first.
///
/// `load(url:)` deliberately does not block. `AVPlayer(url:)` returns
/// immediately and resolves the asset in the background; the duration that
/// arrives late is picked up by `PlaybackService`'s existing 0.5s timer, and a
/// failure arrives through `didFailCallback`.
final class StreamingAudioPlayer: NSObject, AudioPlayerProtocol {
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    /// The item the end-of-playback observer is registered against, so
    /// `teardown()` can deregister *that* observation rather than every
    /// `AVPlayerItemDidPlayToEndTime` registration this object ever made.
    private var observedItem: AVPlayerItem?

    var didFinishCallback: (() -> Void)?
    var didFailCallback: ((Error) -> Void)?

    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    var currentTime: TimeInterval {
        get {
            let seconds = player?.currentTime().seconds ?? 0
            return seconds.isFinite ? seconds : 0
        }
        set {
            player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
        }
    }

    /// 0 until the asset reports a real duration. `AVPlayer` returns
    /// `indefinite` — whose `seconds` is NaN — before then, and NaN reaching
    /// the scrubber's arithmetic would put the thumb somewhere undefined.
    var duration: TimeInterval {
        let seconds = player?.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    /// Point a fresh `AVPlayer` at `url`.
    ///
    /// `teardown()` runs first and unconditionally, which is what keeps a queue
    /// advancing through ten tracks from accumulating ten KVO observations and
    /// ten notification registrations. It also matters for correctness, not just
    /// for memory: a stale `AVPlayerItemDidPlayToEndTime` observer left on the
    /// previous item would fire `didFinishCallback` while the *current* track is
    /// still playing, skipping a track out from under the user.
    ///
    /// Marked `throws` only to satisfy the protocol — this player has nothing to
    /// report synchronously. The one exception is the missing-API-key sentinel,
    /// and even that goes out through `didFailCallback` rather than a throw; see
    /// below.
    func load(url: URL) throws {
        teardown()

        // `DriveClient.mediaURL(fileID:apiKey:)` cannot throw — `Playable
        // .playbackURL()` returns a plain `URL` — so with no API key configured
        // it returns a sentinel `https://drive-error.invalid/...` address
        // instead. Handed straight to `AVPlayer` that fails DNS like any
        // unreachable host, which would make a missing key indistinguishable
        // from a genuine network outage and would never show the user
        // `DriveError.missingAPIKey`'s message. This is the one place that can
        // still tell the two apart, so it does.
        //
        // Reported through `didFailCallback` rather than thrown, deliberately.
        // A throw would enter `PlaybackService`'s skip-forward loop, which would
        // march through every remaining Drive track — all of which fail for the
        // same reason — and end in `stopPlayback()` with nothing said. The
        // failure callback stops once and surfaces why.
        guard url != DriveClient.missingAPIKeyURL else {
            didFailCallback?(DriveError.missingAPIKey)
            return
        }

        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error ?? URLError(.cannotLoadFromNetwork)
            self?.didFailCallback?(error)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        observedItem = item
        player = AVPlayer(playerItem: item)
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    @objc private func itemDidFinish() {
        didFinishCallback?()
    }

    /// Releases every observation the previous `load(url:)` set up. Idempotent,
    /// and safe to call when nothing was ever loaded.
    private func teardown() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let observedItem {
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemDidPlayToEndTime, object: observedItem
            )
        }
        observedItem = nil
        player?.pause()
        player = nil
    }

    deinit {
        statusObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
