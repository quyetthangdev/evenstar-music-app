import XCTest
@testable import Evenstar

final class PlaybackServiceTests: XCTestCase {

    private func makeService() -> (PlaybackService, MockAudioPlayer) {
        let mock = MockAudioPlayer()
        let service = PlaybackService(player: mock)
        return (service, mock)
    }

    func testLoadStoresTitleAndCallsPlayerLoad() throws {
        let (service, mock) = makeService()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")

        try service.load(url: url, title: "Sample")

        XCTAssertEqual(service.currentTrackTitle, "Sample")
        XCTAssertEqual(mock.loadedURL, url)
        XCTAssertFalse(service.isPlaying)
    }

    func testTogglePlayPauseStartsPlaybackWhenPaused() throws {
        let (service, mock) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Sample")

        service.togglePlayPause()

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(mock.playCallCount, 1)
        XCTAssertEqual(mock.pauseCallCount, 0)
    }

    func testTogglePlayPausePausesPlaybackWhenPlaying() throws {
        let (service, mock) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Sample")
        service.togglePlayPause()  // -> playing

        service.togglePlayPause()  // -> paused

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(mock.pauseCallCount, 1)
    }

    func testTogglePlayPauseIsNoOpWhenNothingLoaded() {
        let (service, mock) = makeService()

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(mock.playCallCount, 0)
    }
}
