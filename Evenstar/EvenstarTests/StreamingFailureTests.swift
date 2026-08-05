import XCTest
@testable import Evenstar

@MainActor
final class StreamingFailureTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player, nowPlaying: MockNowPlayingPublisher(), library: library
        )
        return (service, player, library)
    }

    private func track(_ library: LibraryService, title: String) throws -> Track {
        let track = Track(
            title: title, artistName: "A", albumTitle: "B",
            durationSeconds: 100, relativePath: "Music/\(UUID().uuidString).mp3", format: "mp3"
        )
        try library.insert(track)
        return track
    }

    /// Without this, an offline device leaves the player showing a track that
    /// will never start and no way to find out why.
    ///
    /// `await Task.yield()` because `PlaybackService` hops the callback onto the
    /// main actor exactly as it does `didFinishCallback` — the same shape every
    /// `simulateFinish()` test in the suite already uses.
    func testAnAsyncFailureStopsPlaybackAndSurfacesTheError() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        service.play(one, in: [one])
        XCTAssertTrue(service.isPlaying)

        player.simulateFailure()
        await Task.yield()

        XCTAssertFalse(service.isPlaying)
        XCTAssertNotNil(service.lastPlaybackError)
    }

    /// The error must clear when something plays again, or the banner sticks
    /// around after the problem is gone.
    func testStartingAnotherTrackClearsTheError() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let two = try track(library, title: "Two")
        service.play(one, in: [one, two])
        player.simulateFailure()
        await Task.yield()
        XCTAssertNotNil(service.lastPlaybackError)

        service.play(two, in: [one, two])

        XCTAssertNil(service.lastPlaybackError)
    }

    /// A missing API key must not look like a network outage.
    ///
    /// `DriveClient.mediaURL` returns a sentinel `.invalid` URL when no key is
    /// configured, because `Playable.playbackURL()` cannot throw. Handed
    /// straight to `AVPlayer` that would fail DNS like any unreachable host and
    /// the user would never see `DriveError.missingAPIKey`'s message, so
    /// `StreamingAudioPlayer` recognises the sentinel itself.
    func testTheMissingAPIKeySentinelSurfacesDriveErrorRatherThanADNSFailure() throws {
        let player = StreamingAudioPlayer()
        let recorder = ErrorRecorder()
        player.didFailCallback = { recorder.error = $0 }

        try player.load(url: DriveClient.missingAPIKeyURL)

        XCTAssertEqual(recorder.error as? DriveError, .missingAPIKey)
    }

    /// A box rather than a captured `var`, so the escaping failure callback —
    /// which `StreamingAudioPlayer` stores on a non-isolated property — has
    /// somewhere to write that does not depend on the test's actor isolation.
    private final class ErrorRecorder {
        var error: Error?
    }
}
