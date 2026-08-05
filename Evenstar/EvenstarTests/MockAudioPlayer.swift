import Foundation
import UIKit
@testable import Evenstar

enum MockAudioPlayerError: Error {
    case loadFailed
}

final class MockAudioPlayer: AudioPlayerProtocol {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 180
    var didFinishCallback: (() -> Void)?
    var didFailCallback: ((Error) -> Void)?

    /// URLs that `load(url:)` should fail for, in the spirit of
    /// `MockMetadataReader.outcomesByURL`. Lets tests simulate an
    /// unplayable/missing file for specific tracks.
    var failingURLs: Set<URL> = []

    private(set) var loadedURL: URL?
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func load(url: URL) throws {
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
    func simulateFailure(_ error: Error = URLError(.notConnectedToInternet)) {
        isPlaying = false
        didFailCallback?(error)
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
