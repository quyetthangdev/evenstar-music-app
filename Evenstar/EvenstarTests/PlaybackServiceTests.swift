import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher, Track) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        let track = InMemoryLibrary.makeTrack(title: "Sample")
        try library.insert(track)
        return (service, player, nowPlaying, track)
    }

    func testPlayingTrackPushesNowPlaying() throws {
        let (service, player, nowPlaying, track) = try makeStack()

        service.play(track, in: [track])

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.title, "Sample")
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, true)
    }

    func testPausePausesPlaybackAndPushesNowPlaying() throws {
        let (service, player, nowPlaying, track) = try makeStack()
        service.play(track, in: [track])

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, false)
    }

    func testSeekClampsBetweenZeroAndDuration() throws {
        let (service, player, _, track) = try makeStack()
        player.duration = 120
        service.play(track, in: [track])

        service.seek(to: -10)
        XCTAssertEqual(service.position, 0)

        service.seek(to: 999)
        XCTAssertEqual(service.position, 120)

        service.seek(to: 42)
        XCTAssertEqual(player.currentTime, 42)
        XCTAssertEqual(service.position, 42)
    }
}
