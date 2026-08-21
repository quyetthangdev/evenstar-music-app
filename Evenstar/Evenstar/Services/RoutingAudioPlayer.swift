import Foundation

/// One `AudioPlayerProtocol` in front of the two engines the app actually needs,
/// choosing between them by the URL it is handed.
///
/// **Why this exists.** `PlaybackService` takes exactly one player, but the two
/// sources cannot share one: `AVAudioPlayer` needs a complete local file and
/// rejects an `https` URL outright, while `AVPlayer` is what streams Drive's
/// `alt=media` response with range requests. Without something here, every Drive
/// track would fail at `load(url:)` and the whole streaming feature would be
/// unreachable — `StreamingAudioPlayer` is otherwise constructed nowhere.
///
/// Written as a router rather than as a branch inside `PlaybackService` on
/// purpose. `PlaybackService` is the most heavily tested file in the project and
/// its queue, repeat, restore and failure logic is deliberately source-agnostic
/// (see `Playable`); teaching it which engine to use would put a source check
/// back into the one place the whole design keeps free of them. It stays
/// untouched, and every existing test of it keeps testing the same code.
///
/// **The hard part is the callbacks, not the forwarding.** Both engines are
/// alive for the whole session — only one is *active* — and a superseded engine
/// can still report. `AVPlayer` reaches `.failed` seconds after a load was
/// abandoned, and an `AVAudioPlayer` left paused mid-file can still post its
/// finish notification. Either one arriving from the inactive engine would skip
/// or stop the track the user is actually listening to. So the router installs
/// its *own* closures on both children at construction and gates each one on
/// which engine is live; `PlaybackService`'s callbacks are stored here and only
/// ever reached through that gate.
///
/// `PlaybackService`'s own staleness guard (`handleFailure`'s `url ==
/// lastRequestedURL`) is a second line of defence for the same class of bug, not
/// a substitute: it cannot see a `didFinishCallback`, which carries no URL at
/// all.
final class RoutingAudioPlayer: AudioPlayerProtocol {
    /// Which engine a URL belongs to. Named rather than compared by object
    /// identity so the gate in each forwarded callback is a value comparison
    /// that cannot accidentally capture — and retain — the engine it guards.
    private enum Engine {
        case local
        case streaming
    }

    private let local: AudioPlayerProtocol
    private let streaming: AudioPlayerProtocol

    /// The engine the last `load(url:)` chose, or nil before the first load.
    ///
    /// Set *before* `load` is called, deliberately: `StreamingAudioPlayer`
    /// reports the missing-API-key sentinel through `didFailCallback`
    /// synchronously from inside `load(url:)`, and a gate that had not been
    /// opened yet would swallow it — the user would get silence instead of
    /// "Chưa cấu hình API key cho Google Drive."
    private var activeEngine: Engine?

    private var activePlayer: AudioPlayerProtocol? {
        guard let activeEngine else { return nil }
        return player(for: activeEngine)
    }

    private func player(for engine: Engine) -> AudioPlayerProtocol {
        switch engine {
        case .local: return local
        case .streaming: return streaming
        }
    }

    var didFinishCallback: (() -> Void)?
    var didFailCallback: ((Error, URL) -> Void)?

    init(local: AudioPlayerProtocol = AVAudioPlayerWrapper(),
         streaming: AudioPlayerProtocol = StreamingAudioPlayer()) {
        self.local = local
        self.streaming = streaming
        // Captures `self` weakly and the engine as a plain enum case — never the
        // player object — so neither child can retain the router and the router
        // cannot retain a child through a closure the child itself owns.
        self.local.didFinishCallback = { [weak self] in self?.forwardFinish(from: .local) }
        self.streaming.didFinishCallback = { [weak self] in self?.forwardFinish(from: .streaming) }
        self.local.didFailCallback = { [weak self] error, url in
            self?.forwardFailure(error, url: url, from: .local)
        }
        self.streaming.didFailCallback = { [weak self] error, url in
            self?.forwardFailure(error, url: url, from: .streaming)
        }
    }

    // MARK: - Live state, read off whichever engine is active

    var isPlaying: Bool { activePlayer?.isPlaying ?? false }

    var currentTime: TimeInterval {
        get { activePlayer?.currentTime ?? 0 }
        set { activePlayer?.currentTime = newValue }
    }

    var duration: TimeInterval { activePlayer?.duration ?? 0 }

    /// Reaches through to the live engine, so a streaming load's "not yet"
    /// survives the trip and `PlaybackService.clampToDuration` still declines to
    /// flatten a restored position to 0:00.
    ///
    /// `true` before anything has loaded, which is what `AVAudioPlayerWrapper`
    /// answers through the protocol's default — the app's behaviour before this
    /// type existed, preserved exactly. Nothing reads it in that window anyway:
    /// every caller is behind `hasLoaded` or a successful `load`.
    var isDurationKnown: Bool { activePlayer?.isDurationKnown ?? true }

    // MARK: - Routing

    /// A file URL is a local file and nothing else can open it; everything else
    /// is a network stream.
    ///
    /// Keyed on `isFileURL` rather than on an allow-list of schemes so an
    /// unfamiliar remote scheme goes to the streaming player, which can at least
    /// report a real failure, rather than to `AVAudioPlayer`, which would throw
    /// an opaque OSStatus and be silently skipped by the queue loop.
    private func engine(for url: URL) -> Engine {
        url.isFileURL ? .local : .streaming
    }

    /// Points the engine that suits `url` at it, stopping the other one first.
    ///
    /// Stopping the outgoing engine is not tidiness: `AVAudioPlayer` keeps
    /// playing across a switch that never touches it, so a queue stepping from a
    /// local track to a Drive track would play both at once.
    func load(url: URL) throws {
        let target = engine(for: url)
        if let activeEngine, activeEngine != target {
            activePlayer?.pause()
        }
        // Before the load, so a failure reported synchronously from inside it
        // passes the gate — see `activeEngine`.
        activeEngine = target
        try player(for: target).load(url: url)
    }

    func play() { activePlayer?.play() }
    func pause() { activePlayer?.pause() }

    /// Chỉ bản phát đang hoạt động, giống mọi thứ khác trong khối này.
    ///
    /// Bản phát bị thay thế vẫn còn sống nhưng đã im, nên chỉnh âm lượng của
    /// nó là chỉnh một thứ không ai nghe — và tệ hơn, nếu nó được kích hoạt
    /// lại thì mức âm lượng cũ sẽ đi theo.
    func setVolume(_ volume: Float, fadeDuration: TimeInterval) {
        activePlayer?.setVolume(volume, fadeDuration: fadeDuration)
    }

    // MARK: - Gated callbacks

    private func forwardFinish(from engine: Engine) {
        guard engine == activeEngine else { return }
        didFinishCallback?()
    }

    private func forwardFailure(_ error: Error, url: URL, from engine: Engine) {
        guard engine == activeEngine else { return }
        didFailCallback?(error, url)
    }

    /// Test-only: whether the streaming engine is the one currently live. Lets a
    /// test assert the routing decision itself rather than inferring it from a
    /// side effect. In the spirit of `PlaybackService.tickForTesting()`.
    var isStreamingActiveForTesting: Bool { activeEngine == .streaming }
}
