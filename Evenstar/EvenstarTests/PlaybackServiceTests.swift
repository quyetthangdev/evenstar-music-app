import XCTest
@testable import Evenstar

final class PlaybackServiceTests: XCTestCase {

    private func makeService() -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying)
        return (service, player, nowPlaying)
    }

    func testLoadStoresMetadataAndCallsPlayerLoad() throws {
        let (service, player, _) = makeService()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")

        try service.load(url: url, metadata: .sample)

        XCTAssertEqual(service.currentTrackTitle, "Sample")
        XCTAssertEqual(player.loadedURL, url)
        XCTAssertFalse(service.isPlaying)
    }

    func testTogglePlayPauseStartsPlaybackAndPushesNowPlaying() throws {
        let (service, player, nowPlaying) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.togglePlayPause()

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.title, "Sample")
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, true)
    }

    func testTogglePlayPausePausesAndPushesNowPlaying() throws {
        let (service, player, nowPlaying) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)
        service.togglePlayPause()

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, false)
    }

    func testTogglePlayPauseIsNoOpWhenNothingLoaded() {
        let (service, player, nowPlaying) = makeService()

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 0)
        XCTAssertEqual(nowPlaying.updates.count, 0)
    }

    func testSeekUpdatesPlayerCurrentTime() throws {
        let (service, player, _) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.seek(to: 42)

        XCTAssertEqual(player.currentTime, 42)
        XCTAssertEqual(service.position, 42)
    }

    func testSeekClampsAtZero() throws {
        let (service, _, _) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.seek(to: -10)

        XCTAssertEqual(service.position, 0)
    }

    func testSeekClampsAtDuration() throws {
        let (service, player, _) = makeService()
        player.duration = 120
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.seek(to: 999)

        XCTAssertEqual(service.position, 120)
    }
}

private extension TrackMetadata {
    static let sample = TrackMetadata(
        title: "Sample",
        artist: "Unknown Artist",
        album: "Unknown Album",
        artwork: nil,
        durationSeconds: 180
    )
}
