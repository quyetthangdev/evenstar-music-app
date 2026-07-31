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
}

final class MockNowPlayingPublisher: NowPlayingPublisher {
    struct Update {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let elapsed: TimeInterval
        let isPlaying: Bool
    }

    private(set) var updates: [Update] = []
    private(set) var clearCallCount = 0

    func update(title: String, artist: String, album: String,
                artwork _: UIImage?, duration: TimeInterval,
                elapsed: TimeInterval, isPlaying: Bool) {
        updates.append(.init(title: title, artist: artist, album: album,
                             duration: duration, elapsed: elapsed,
                             isPlaying: isPlaying))
    }

    func clear() { clearCallCount += 1 }
}
