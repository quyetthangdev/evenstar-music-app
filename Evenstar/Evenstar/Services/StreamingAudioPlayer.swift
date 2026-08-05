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
///
/// **All mutable state here is main-thread confined.** `AVPlayerItem.status`
/// KVO is delivered on an AVFoundation-internal queue, and the two
/// notifications can be posted from anywhere, so every one of those entry
/// points funnels through `onMain` before it touches `observedItem`,
/// `pendingSeek` or a callback. Without that, a status change racing a
/// main-thread `load()` would read a half-updated view of which item is
/// current.
final class StreamingAudioPlayer: NSObject, AudioPlayerProtocol {
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    /// The item every observation registered by the last `load(url:)` belongs
    /// to. Two jobs: `teardown()` deregisters against *this* item rather than
    /// wildcarding the notification name, and every asynchronous entry point
    /// compares against it to drop events belonging to a load already moved on
    /// from.
    private var observedItem: AVPlayerItem?
    /// The URL `observedItem` was built from, reported back with every failure
    /// so `PlaybackService` can tell a failure for the track it is playing from
    /// one for a track it abandoned two seconds ago.
    private var loadedURL: URL?
    /// A seek asked for before the item could take one, applied as soon as it
    /// can.
    ///
    /// Seeking an `AVPlayer` whose item is not yet `.readyToPlay` is not
    /// reliable — the request can simply be discarded — so a restored position
    /// handed over in that window would be dropped on the floor and the track
    /// would start from the beginning.
    ///
    /// **The gate is readiness, and never `isDurationKnown`.** The two look
    /// interchangeable and are not. A Drive `alt=media` response is served
    /// chunked, with no `Content-Length`, so its item reaches `.readyToPlay`
    /// with an *indefinite* duration and keeps it for the whole track. Gating
    /// the deferral on the duration while draining on `.readyToPlay` — which
    /// fires exactly once per item, and by then has already been and gone —
    /// parks every subsequent seek here permanently: Previous would write
    /// `pendingSeek = 0`, the track would never restart, and the `currentTime`
    /// getter below would report 0:00 for the rest of a track that is still
    /// playing. Deferring and draining must therefore test the *same*
    /// condition, which is why both go through `canSeekNow` and why
    /// `applyPendingSeekIfPossible()` is the only place a seek reaches
    /// `AVPlayer`.
    private var pendingSeek: TimeInterval?
    /// Whether the current item has reached `.readyToPlay`.
    ///
    /// Stored when the transition happens rather than read back off the item on
    /// demand, so that the one condition governing both halves above lives in
    /// exactly one place and cannot drift.
    private var isItemReady: Bool = false

    var didFinishCallback: (() -> Void)?
    var didFailCallback: ((Error, URL) -> Void)?

    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    var currentTime: TimeInterval {
        get {
            // A seek that has not been applied yet is nonetheless where the
            // user asked to be, and is what the scrubber should show; reporting
            // the item's 0 would make the thumb jump back and then forward.
            if let pendingSeek { return pendingSeek }
            let seconds = player?.currentTime().seconds ?? 0
            return seconds.isFinite ? seconds : 0
        }
        set {
            // The getter has always guarded finiteness; the setter did not, and
            // it is the dangerous side. `CMTime(seconds:preferredTimescale:)`
            // built from NaN or infinity is invalid, and `AVPlayer.seek` raises
            // an Objective-C exception on an invalid time — not a Swift error,
            // so nothing downstream could catch it and the app would terminate.
            guard newValue.isFinite else { return }
            // Recorded first and unconditionally, then drained through the one
            // gate. Writing the request down before testing anything is what
            // keeps the "defer" and "apply" decisions from being two separate
            // conditions that can disagree; see `pendingSeek`.
            pendingSeek = max(0, newValue)
            applyPendingSeekIfPossible()
        }
    }

    /// 0 until the asset reports a real duration. `AVPlayer` returns
    /// `indefinite` — whose `seconds` is NaN — before then, and NaN reaching
    /// the scrubber's arithmetic would put the thumb somewhere undefined.
    ///
    /// Callers that clamp against this must consult `isDurationKnown` first;
    /// see that property.
    var duration: TimeInterval {
        let seconds = player?.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    /// False while `AVPlayer` still reports an indefinite duration, which is
    /// the first few hundred milliseconds of every streaming load.
    var isDurationKnown: Bool {
        guard let seconds = player?.currentItem?.duration.seconds else { return false }
        return seconds.isFinite
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
        loadedURL = url
        guard url != DriveClient.missingAPIKeyURL else {
            didFailCallback?(DriveError.missingAPIKey, url)
            return
        }

        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            // Delivered on an AVFoundation queue, so hop before reading any
            // state — and re-check ownership *after* the hop, since a `load()`
            // may have replaced the item in the meantime.
            self?.onMain { [weak self] in
                guard let self, item === self.observedItem else { return }
                switch item.status {
                case .failed:
                    self.report(item.error ?? URLError(.cannotLoadFromNetwork))
                case .readyToPlay:
                    self.markItemReady()
                default:
                    break
                }
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime, object: item
        )
        // `.status` only ever reports a *load-time* failure. A connection lost
        // mid-track does not flip it: with `automaticallyWaitsToMinimizeStalling`
        // on, `AVPlayer` stalls, `rate` stays 1.0 and `timeControlStatus`
        // becomes `.waitingToPlayAtSpecifiedRate` — so `isPlaying` stays true,
        // `PlaybackService`'s reconcile never fires, and the user gets frozen
        // audio, a pause glyph and no explanation. Exactly the silently-hung
        // state `didFailCallback` exists to prevent, reached by the other road.
        // This notification is the reliable signal for it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemFailedToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime, object: item
        )
        observedItem = item
        player = AVPlayer(playerItem: item)
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    /// Test-only: the item the current load registered its observers against.
    /// Lets a test post an end-of-item notification for a superseded item and
    /// prove a stale observer cannot skip the track that is playing. Not for
    /// production callers, in the spirit of `PlaybackService.tickForTesting()`.
    var observedItemForTesting: AVPlayerItem? { observedItem }

    @objc private func itemDidFinish(_ note: Notification) {
        onMain { [weak self] in
            guard let self, (note.object as? AVPlayerItem) === self.observedItem else { return }
            self.didFinishCallback?()
        }
    }

    @objc private func itemFailedToPlayToEnd(_ note: Notification) {
        onMain { [weak self] in
            guard let self, (note.object as? AVPlayerItem) === self.observedItem else { return }
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.report(error ?? URLError(.cannotLoadFromNetwork))
        }
    }

    /// Hands a failure out with the URL it belongs to, translated into a case
    /// that can describe itself in Vietnamese.
    ///
    /// Raw `URLError`/`AVFoundation` errors would reach the banner as English
    /// system text; `DriveError.classify` is the same mapping `DriveClient`
    /// applies to its own transport failures, so both paths describe an offline
    /// device identically.
    ///
    /// **Every failure is classified as a `DriveError`, and that is a
    /// constraint, not an oversight.** This player exists to stream from Drive
    /// and nothing else constructs it. Pointed at some other remote source it
    /// would tell the user "Không thể kết nối tới Google Drive" about a host
    /// that has nothing to do with Drive, so a second source has to bring its
    /// own classifier past this line rather than inherit this one.
    private func report(_ error: Error) {
        guard let url = loadedURL else { return }
        didFailCallback?(DriveError.classify(error), url)
    }

    /// Whether the item can take a seek right now. The single condition behind
    /// both deferring a seek and draining a deferred one — see `pendingSeek`.
    private var canSeekNow: Bool { isItemReady && player != nil }

    /// The only place a seek ever reaches `AVPlayer`. A request that cannot be
    /// applied yet stays in `pendingSeek` and is drained by `markItemReady()`,
    /// which tests the identical condition.
    private func applyPendingSeekIfPossible() {
        guard canSeekNow, let player, let target = pendingSeek else { return }
        pendingSeek = nil
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// The current item reached `.readyToPlay`.
    private func markItemReady() {
        isItemReady = true
        applyPendingSeekIfPossible()
    }

    /// Test-only: drives the `.readyToPlay` transition, which no unit test can
    /// make a real `AVPlayerItem` for an unreachable URL actually reach. Calls
    /// straight into the shipping path rather than reproducing it, so a test
    /// using this exercises the same code the KVO branch does. In the spirit of
    /// `PlaybackService.tickForTesting()`.
    func markReadyForTesting() { markItemReady() }

    /// Test-only: the seek still waiting to be applied, or nil when none is.
    var pendingSeekForTesting: TimeInterval? { pendingSeek }

    /// Runs `work` on the main thread, synchronously when already there.
    ///
    /// Synchronous in the common case on purpose: AVFoundation usually posts
    /// these on the main thread already, and bouncing through the run loop
    /// anyway would delay a failure by a frame and make the whole class
    /// untestable without an expectation for every assertion.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
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
            NotificationCenter.default.removeObserver(
                self, name: .AVPlayerItemFailedToPlayToEndTime, object: observedItem
            )
        }
        observedItem = nil
        loadedURL = nil
        pendingSeek = nil
        isItemReady = false
        player?.pause()
        player = nil
    }

    deinit {
        statusObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
