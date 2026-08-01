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

    /// Restores Task 7's dropped `testTogglePlayPauseIsNoOpWhenNothingLoaded`
    /// against the current API. Covers the `hasLoaded` guard in
    /// pause()/resume() — the guard that prevents the "stranded on a dead
    /// player screen" bug where toggling play/pause with nothing loaded
    /// would tell a nonexistent player to play.
    func testTogglePlayPauseIsNoOpWhenNothingLoaded() throws {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 0)
        XCTAssertEqual(player.pauseCallCount, 0)
    }

    /// Simulates an interruption (phone call, headphone unplug): the
    /// underlying player stops on its own, not via pause(). The service must
    /// reconcile isPlaying to false on the next tick rather than continuing
    /// to claim playback. currentTime is kept well below duration to stay
    /// clear of the end-of-track race guard.
    func testTickReconciliatesStateWhenPlayerStopsUnderneathUs() throws {
        let (service, player, nowPlaying, track) = try makeStack()
        player.duration = 180
        service.play(track, in: [track])
        XCTAssertTrue(service.isPlaying)

        player.currentTime = 50
        player.isPlaying = false
        service.tickForTesting()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, false)
    }
}
