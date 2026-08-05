import XCTest
import AVFoundation
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

    // MARK: - The failure path reaches the user

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

    // MARK: - A failure must not reach across to a different track

    /// Offline, the user taps Drive track A; it takes seconds to fail. Meanwhile
    /// they tap local track B, which plays fine. A's failure must not pause B,
    /// stop its timer, and put a network banner over a track that is playing
    /// perfectly well.
    func testAStaleFailureDoesNotStopTheTrackThatIsNowPlaying() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let two = try track(library, title: "Two")
        service.play(one, in: [one, two])
        let abandonedURL = one.playbackURL()

        service.play(two, in: [one, two])
        XCTAssertTrue(service.isPlaying)

        player.simulateFailure(url: abandonedURL)
        await Task.yield()

        XCTAssertTrue(service.isPlaying, "a failure for an abandoned load must not stop playback")
        XCTAssertNil(service.lastPlaybackError)
        XCTAssertEqual(service.currentTrack?.id, two.id)
    }

    // MARK: - The transport must not lie after a failure

    /// After a failure, tapping play used to give a pause glyph, a position
    /// frozen at 0:00 and no sound — `resume()`'s guard still passed and the
    /// reconcile could never correct it, because a failed item reports duration
    /// 0 and currentTime 0.
    func testPlayIsInertAfterAFailureRatherThanClaimingToPlay() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        service.play(one, in: [one])
        player.simulateFailure()
        await Task.yield()
        let playsBefore = player.playCallCount

        service.resume()

        XCTAssertFalse(service.isPlaying, "the pause glyph must not appear with nothing playing")
        XCTAssertEqual(player.playCallCount, playsBefore, "must not ask a failed player to play")
    }

    // MARK: - A duration that has not arrived yet is not a duration of zero

    /// Every restored Drive track used to lose its saved position: restore
    /// clamps with `min(saved, duration)`, and a streaming player reports
    /// duration 0 for the first few hundred milliseconds of a load.
    func testRestoreKeepsTheSavedPositionWhileTheDurationIsStillUnknown() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let state = library.playbackState
        state.queueTrackIDs = [one.id]
        state.queueIndex = 0
        state.positionSeconds = 151
        try library.save()
        // What a freshly-loaded AVPlayer item looks like: no duration yet, so
        // `duration` stands in with 0.
        player.isDurationKnown = false
        player.duration = 0

        await service.restoreFromPersistedState()

        XCTAssertEqual(service.position, 151, accuracy: 0.01)
        XCTAssertEqual(player.currentTime, 151, accuracy: 0.01)
    }

    /// A scrub in that same window must not jump to the start either.
    func testSeekIsNotFlattenedToZeroWhileTheDurationIsStillUnknown() throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        player.isDurationKnown = false
        player.duration = 0
        service.play(one, in: [one])

        service.seek(to: 90)

        XCTAssertEqual(service.position, 90, accuracy: 0.01)
    }

    /// The clamp must still apply once the duration is real, or the scrubber
    /// could seek past the end.
    func testSeekStillClampsOnceTheDurationIsKnown() throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        player.isDurationKnown = true
        player.duration = 100
        service.play(one, in: [one])

        service.seek(to: 500)

        XCTAssertEqual(service.position, 100, accuracy: 0.01)
    }

    // MARK: - StreamingAudioPlayer itself

    /// A missing API key must not look like a network outage.
    ///
    /// `DriveClient.mediaURL` returns a sentinel `.invalid` URL when no key is
    /// configured, because `Playable.playbackURL()` cannot throw. Handed
    /// straight to `AVPlayer` that would fail DNS like any unreachable host and
    /// the user would never see `DriveError.missingAPIKey`'s message, so
    /// `StreamingAudioPlayer` recognises the sentinel itself.
    func testTheMissingAPIKeySentinelSurfacesDriveErrorRatherThanADNSFailure() throws {
        let player = StreamingAudioPlayer()
        let recorder = FailureRecorder()
        player.didFailCallback = { recorder.record($0, $1) }

        try player.load(url: DriveClient.missingAPIKeyURL)

        XCTAssertEqual(recorder.error as? DriveError, .missingAPIKey)
        XCTAssertEqual(recorder.url, DriveClient.missingAPIKeyURL)
    }

    /// The reviewer's top structural concern, made testable.
    ///
    /// Loading a second track must leave nothing behind that can fire for the
    /// first. This asserts the user-visible property rather than an observer
    /// count — a stale end-of-item notification must not advance the queue —
    /// which is what both halves of the defence (deregistering against the exact
    /// item in `teardown()`, and the identity check in the handler) exist to
    /// guarantee. A queue advancing through ten tracks accumulating ten
    /// observers would fail here on the second.
    func testASupersededItemCannotFireTheFinishCallback() throws {
        let player = StreamingAudioPlayer()
        let counter = FinishCounter()
        player.didFinishCallback = { counter.count += 1 }

        try player.load(url: URL(string: "https://example.invalid/a.mp3")!)
        let first = try XCTUnwrap(player.observedItemForTesting)
        try player.load(url: URL(string: "https://example.invalid/b.mp3")!)
        let second = try XCTUnwrap(player.observedItemForTesting)
        XCTAssertFalse(first === second)

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: first)
        XCTAssertEqual(counter.count, 0, "a superseded item must never skip the current track")

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: second)
        XCTAssertEqual(counter.count, 1, "the current item must still advance the queue")
    }

    /// A connection dropped mid-track does not flip `AVPlayerItem.status` — the
    /// player stalls instead, `rate` stays 1.0, and nothing ever reports it.
    /// `AVPlayerItemFailedToPlayToEndTime` is the signal that does arrive.
    func testAMidPlaybackStallIsReportedRatherThanHangingSilently() throws {
        let player = StreamingAudioPlayer()
        let recorder = FailureRecorder()
        player.didFailCallback = { recorder.record($0, $1) }
        let url = URL(string: "https://example.invalid/a.mp3")!
        try player.load(url: url)
        let item = try XCTUnwrap(player.observedItemForTesting)

        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime, object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: URLError(.notConnectedToInternet)]
        )

        XCTAssertEqual(recorder.error as? DriveError, .offline)
        XCTAssertEqual(recorder.url, url)
    }

    /// A non-finite seek must be dropped rather than reaching `AVPlayer.seek`,
    /// which raises an uncatchable Objective-C exception on an invalid
    /// `CMTime` — a crash, not an error anything could handle.
    func testANonFiniteSeekIsIgnoredRatherThanCrashing() throws {
        let player = StreamingAudioPlayer()
        try player.load(url: URL(string: "https://example.invalid/a.mp3")!)

        player.currentTime = .nan
        player.currentTime = .infinity

        XCTAssertTrue(player.currentTime.isFinite)
    }

    // MARK: - Vietnamese copy on the failure path

    /// `lastPlaybackError` is typed `Error`, so whatever the player hands over
    /// is what the banner will read. A raw `URLError` says "The Internet
    /// connection appears to be offline" — English, in an app whose copy is
    /// Vietnamese throughout. One shared classifier keeps `DriveClient` and the
    /// streaming player describing the same failure the same way.
    func testTransportErrorsAreClassifiedIntoVietnameseCarryingCases() throws {
        XCTAssertEqual(DriveError.classify(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(DriveError.classify(URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(DriveError.classify(URLError(.timedOut)), .connectionFailed)
        XCTAssertEqual(DriveError.classify(URLError(.cannotFindHost)), .connectionFailed)

        // What `AVPlayerItem.error` actually looks like: an AVFoundation error
        // with the real cause underneath. A plain `as? URLError` misses this and
        // reports a genuinely offline device as a generic connection failure.
        let wrapped = NSError(
            domain: AVFoundationErrorDomain, code: -11800,
            userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet) as NSError]
        )
        XCTAssertEqual(DriveError.classify(wrapped), .offline)

        XCTAssertEqual(DriveError.offline.errorDescription, "Không có kết nối mạng.")
    }

    // MARK: - Helpers

    /// Boxes rather than captured `var`s, because these callbacks are stored on
    /// non-isolated properties of the player and can in principle be invoked
    /// off the test's actor.
    private final class FailureRecorder {
        var error: Error?
        var url: URL?
        func record(_ error: Error, _ url: URL) {
            self.error = error
            self.url = url
        }
    }

    private final class FinishCounter {
        var count = 0
    }
}
