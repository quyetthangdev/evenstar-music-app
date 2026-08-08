import XCTest
@testable import Evenstar

/// `stop()` — ending playback because the user asked, rather than because the
/// queue ran out.
///
/// The behaviour underneath is `stopPlayback()`, which has always existed and is
/// covered elsewhere for the paths that reach it on their own. What is new is
/// that anything can reach it *on purpose*, and these pin the parts a caller now
/// depends on: the pill goes away, the queue goes with it, and nothing is left
/// half torn down.
@MainActor
final class PlaybackStopTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        return (PlaybackService(player: player, nowPlaying: nowPlaying, library: library),
                player, nowPlaying, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        try (0..<count).map { i in
            let t = Track(
                title: "Track \(i)", artistName: "Artist", albumTitle: "Album",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3", format: "mp3"
            )
            try library.insert(t)
            return t
        }
    }

    /// The reason the control exists: with nothing current, `PlayerCard` hides
    /// itself, so this is what actually removes the pill from the screen.
    func testStopLeavesNoCurrentTrack() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        XCTAssertNotNil(service.currentTrack)

        service.stop()

        XCTAssertNil(service.currentTrack)
    }

    /// **It really discards the queue.** Stopping that only paused and hid the
    /// pill would be a different feature wearing this one's name, and the choice
    /// to put it behind a long press was made *because* it throws work away.
    func testStopDiscardsTheQueueRatherThanKeepingItHidden() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)

        service.stop()

        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.position, 0)
    }

    func testStopEndsPlayback() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)
        XCTAssertTrue(service.isPlaying)

        service.stop()

        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(player.isPlaying)
    }

    /// The lock screen and Control Center are a second surface showing the same
    /// thing. Leaving them populated after a stop would put a phantom track on
    /// the Lock Screen with no way to reach the app state behind it.
    func testStopClearsTheLockScreen() throws {
        let (service, _, nowPlaying, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)

        service.stop()

        XCTAssertGreaterThan(nowPlaying.clearCallCount, 0)
    }

    /// Stopping when nothing is playing is something a stale menu can do, and it
    /// must be a no-op rather than a crash or a half-torn-down state.
    func testStoppingWithNothingPlayingIsHarmless() throws {
        let (service, _, _, _) = try makeStack()

        service.stop()

        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertFalse(service.isPlaying)
    }
}
