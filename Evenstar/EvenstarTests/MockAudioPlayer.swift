import Foundation
import UIKit
import XCTest
@testable import Evenstar

enum MockAudioPlayerError: Error {
    case loadFailed
}

final class MockAudioPlayer: AudioPlayerProtocol {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 180
    var didFinishCallback: (() -> Void)?
    var didFailCallback: ((Error, URL) -> Void)?

    /// Defaults to `true`, matching a local player, so no existing test changes
    /// behaviour. Set false to stand in for a streaming player whose asset has
    /// not resolved yet.
    var isDurationKnown: Bool = true

    /// URLs that `load(url:)` should fail for, in the spirit of
    /// `MockMetadataReader.outcomesByURL`. Lets tests simulate an
    /// unplayable/missing file for specific tracks.
    var failingURLs: Set<URL> = []

    private(set) var loadedURL: URL?
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    /// Every URL handed to `load(url:)`, in call order — successes and
    /// failures alike.
    ///
    /// `loadedURL` is written only on success, so it cannot witness a skip: a
    /// test that only checks `loadedURL` (or a terminal state like
    /// `isPlaying`) after a run of failures cannot tell three tried-and-failed
    /// tracks apart from one, because a regression that gives up after the
    /// first failure reaches the same terminal state. This records the whole
    /// attempted sequence so a test can assert *how many* tracks the skip
    /// loop tried, and *in what order* — including a wrap back to the start
    /// of the queue, which a bare count would not distinguish from more
    /// forward attempts.
    private(set) var loadAttempts: [URL] = []

    func load(url: URL) throws {
        loadAttempts.append(url)
        if failingURLs.contains(url) {
            throw MockAudioPlayerError.loadFailed
        }
        loadedURL = url
        currentTime = 0
    }

    func play() {
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func simulateFinish() {
        isPlaying = false
        didFinishCallback?()
    }

    /// Drives the async-failure path the way `AVPlayer` would.
    ///
    /// `url` defaults to whatever was last loaded — the ordinary "the thing
    /// that is playing failed" case. Pass one explicitly to simulate a *stale*
    /// failure: a load the service has since moved on from reporting late,
    /// which must be ignored.
    ///
    /// Fails loudly with nothing loaded rather than returning quietly: a silent
    /// no-op there hands a test that forgot to load a green pass asserting
    /// nothing happened, which is exactly what it would have got had the code
    /// been broken.
    func simulateFailure(_ error: Error = URLError(.notConnectedToInternet), url: URL? = nil) {
        guard let target = url ?? loadedURL else {
            XCTFail("simulateFailure() with nothing loaded — load a track first, or pass a url:")
            return
        }
        isPlaying = false
        didFailCallback?(error, target)
    }
}

final class MockNowPlayingPublisher: NowPlayingPublisher {
    struct Update {
        let title: String
        let artist: String
        let album: String
        /// Whether this push carried a cover, and — when it did — how big the
        /// decoded image was.
        ///
        /// This used to discard the artwork argument entirely (`artwork _:`),
        /// which meant no test in the suite could see whether a push had a
        /// cover on it. That is precisely how the restore path shipped
        /// pushing `artwork: nil` forever with all 74 tests green.
        ///
        /// Recorded as a `Bool` plus a `CGSize`, not as the `UIImage` itself:
        /// `UIImage` is not `Sendable`, and holding one here would make
        /// `Update` non-`Sendable` for no gain — no assertion needs the pixels.
        let hasArtwork: Bool
        let artworkSize: CGSize
        let duration: TimeInterval
        let elapsed: TimeInterval
        let isPlaying: Bool
    }

    private(set) var updates: [Update] = []
    private(set) var clearCallCount = 0

    func update(title: String, artist: String, album: String,
                artwork: UIImage?, duration: TimeInterval,
                elapsed: TimeInterval, isPlaying: Bool) {
        updates.append(.init(title: title, artist: artist, album: album,
                             hasArtwork: artwork != nil,
                             artworkSize: artwork?.size ?? .zero,
                             duration: duration, elapsed: elapsed,
                             isPlaying: isPlaying))
    }

    func clear() { clearCallCount += 1 }
}
