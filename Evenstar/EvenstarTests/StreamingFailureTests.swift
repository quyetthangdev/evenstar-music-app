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

    // MARK: - A failure must not cost the user their place in the track

    /// A three-second blip forty minutes into a track used to cost the forty
    /// minutes. A failed `AVPlayerItem` is terminal, so recovery means loading
    /// the track again — and every load started at 0 and then persisted that 0
    /// straight over the saved position, with no undo anywhere.
    func testRetryingTheTrackThatFailedResumesWhereItStopped() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        player.duration = 3000
        service.play(one, in: [one])
        // Forty minutes in.
        player.currentTime = 2400
        service.tickForTesting()
        XCTAssertEqual(service.position, 2400, accuracy: 0.01)

        player.simulateFailure()
        await Task.yield()
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(
            library.playbackState.positionSeconds, 2400, accuracy: 0.01,
            "a failure must write the position down — a stalled app gets force-quit"
        )

        // The user taps the same track again once the network is back.
        service.play(one, in: [one])

        XCTAssertEqual(service.position, 2400, accuracy: 0.01)
        XCTAssertEqual(player.currentTime, 2400, accuracy: 0.01)
    }

    /// Scoped to the retry, not a general memory: playing something else after
    /// a failure must start that track at its own beginning.
    func testADifferentTrackAfterAFailureStillStartsAtTheTop() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let two = try track(library, title: "Two")
        player.duration = 3000
        service.play(one, in: [one, two])
        player.currentTime = 2400
        service.tickForTesting()
        player.simulateFailure()
        await Task.yield()

        service.play(two, in: [one, two])

        XCTAssertEqual(service.position, 0, accuracy: 0.01)
    }

    /// Consumed once. Coming back to the track a third time — after the retry
    /// already worked — is an ordinary play and must start from the top, or the
    /// resume point becomes a position the user can never get rid of.
    func testTheResumePointIsSpentByTheRetryThatUsesIt() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        player.duration = 3000
        service.play(one, in: [one])
        player.currentTime = 2400
        service.tickForTesting()
        player.simulateFailure()
        await Task.yield()

        service.play(one, in: [one])
        XCTAssertEqual(service.position, 2400, accuracy: 0.01)
        service.play(one, in: [one])

        XCTAssertEqual(service.position, 0, accuracy: 0.01)
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

    // MARK: - A deferred seek must never be deferred forever

    /// The trap the first fix set. Deferring on `!isDurationKnown` while
    /// draining on `.readyToPlay` are two different conditions, and a Drive
    /// `alt=media` response — served chunked, no `Content-Length` — is the item
    /// that tells them apart: it reaches `.readyToPlay` with an indefinite
    /// duration and keeps it for the whole track. `.readyToPlay` fires once and
    /// is already gone, so every seek from that point on was written to
    /// `pendingSeek` and never applied. Tapping Previous wrote 0 there, the
    /// track never restarted, and the position display froze at 0:00 while the
    /// audio played on — with nothing able to correct it, because the reconcile
    /// in `tickPosition` compares `0 < 0 - 0.5`.
    func testASeekIsAppliedOnceTheItemIsReadyEvenIfTheDurationNeverResolves() throws {
        let player = StreamingAudioPlayer()
        try player.load(url: URL(string: "https://example.invalid/chunked.mp3")!)
        player.markReadyForTesting()
        XCTAssertFalse(player.isDurationKnown, "the case only exists while the duration is indefinite")

        player.currentTime = 30

        XCTAssertNil(
            player.pendingSeekForTesting,
            "a ready item must be seeked, not have the request parked forever"
        )
    }

    /// The other half of the same gate: a seek asked for before the item can
    /// take one is held, reported to the scrubber meanwhile so the thumb does
    /// not jump back, and applied the moment readiness arrives.
    func testASeekAskedForBeforeReadinessIsHeldAndThenApplied() throws {
        let player = StreamingAudioPlayer()
        try player.load(url: URL(string: "https://example.invalid/a.mp3")!)

        player.currentTime = 45

        XCTAssertEqual(player.pendingSeekForTesting, 45)
        XCTAssertEqual(player.currentTime, 45, accuracy: 0.01,
                       "the scrubber must show where the user asked to be")

        player.markReadyForTesting()

        XCTAssertNil(player.pendingSeekForTesting, "readiness must drain the held seek")
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

    // MARK: - A duration that arrives late must still reach the lock screen

    /// `pushNowPlaying()` publishes `player.duration`, and the push that follows
    /// `player.play()` happens while a streaming item still reports 0. Nothing
    /// re-published afterwards — `markItemReady()` drains a pending seek and
    /// stops — so `MPMediaItemPropertyPlaybackDuration` stayed 0.0 for the whole
    /// track: the lock-screen progress bar sat at zero and its scrubber, enabled
    /// in Phase 1, had no range to drag.
    func testADurationThatResolvesAfterTheLoadIsPushedToNowPlaying() throws {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        let one = try track(library, title: "One")
        // What a freshly-started AVPlayer item looks like.
        player.isDurationKnown = false
        player.duration = 0

        service.play(one, in: [one])
        XCTAssertEqual(nowPlaying.updates.last?.duration, 0, "the first push cannot know it yet")

        // The asset resolves a few hundred milliseconds later.
        player.isDurationKnown = true
        player.duration = 211
        service.tickForTesting()

        XCTAssertEqual(nowPlaying.updates.last?.duration, 211)
    }

    /// The other half: the timer must not re-publish twice a second for the life
    /// of every track. Assigning `nowPlayingInfo` ships the payload across XPC to
    /// the media server, and a local file's duration is right from the first
    /// push, so there is nothing to correct.
    func testASettledDurationIsNotRePushedOnEveryTick() throws {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        let one = try track(library, title: "One")
        player.duration = 180
        service.play(one, in: [one])
        let pushesAfterLoad = nowPlaying.updates.count

        service.tickForTesting()
        service.tickForTesting()

        XCTAssertEqual(nowPlaying.updates.count, pushesAfterLoad)
    }

    // MARK: - A file gone from Drive is not a connection failure

    /// The spec's error table asks for two behaviours from two causes, and
    /// `handleFailure` used to collapse them: everything stopped, and everything
    /// said "Không thể kết nối tới Google Drive. Vui lòng thử lại sau." about a
    /// connection that was working perfectly.
    func testAnHTTPShapedFailureIsClassifiedApartFromAConnectionFailure() {
        XCTAssertEqual(DriveError.classify(URLError(.fileDoesNotExist)), .fileUnavailable)
        XCTAssertEqual(DriveError.classify(URLError(.resourceUnavailable)), .fileUnavailable)
        XCTAssertEqual(DriveError.classify(URLError(.badServerResponse)), .fileUnavailable)
        XCTAssertEqual(DriveError.classify(URLError(.userAuthenticationRequired)), .fileUnavailable)
        XCTAssertEqual(DriveError.classify(URLError(.noPermissionsToReadFile)), .fileUnavailable)

        // What AVFoundation hands back when its own HTTP loader judged the
        // response: the real code sits under `NSUnderlyingErrorKey` in
        // CoreMedia's domain.
        let coreMedia = NSError(domain: "CoreMediaErrorDomain", code: -12660)
        let wrapped = NSError(
            domain: AVFoundationErrorDomain, code: -11800,
            userInfo: [NSUnderlyingErrorKey: coreMedia]
        )
        XCTAssertEqual(DriveError.classify(wrapped), .fileUnavailable)

        // And it must not steal the offline case: a timeout is still a
        // connection failure, not a missing file.
        XCTAssertEqual(DriveError.classify(URLError(.timedOut)), .connectionFailed)
        XCTAssertEqual(
            DriveError.fileUnavailable.errorDescription,
            "Không phát được bài này. Tệp có thể đã bị xoá khỏi Drive hoặc thư mục không còn được chia sẻ."
        )
    }

    /// Connectivity is tested before the HTTP shapes, and the walk down
    /// `NSUnderlyingErrorKey` no longer stops after one level. An offline device
    /// three wrappers deep used to be reported as a generic connection failure.
    func testOfflineIsStillFoundUnderTwoLayersOfWrapping() {
        let urlError = URLError(.notConnectedToInternet) as NSError
        let coreMedia = NSError(
            domain: "CoreMediaErrorDomain", code: -12660,
            userInfo: [NSUnderlyingErrorKey: urlError]
        )
        let wrapped = NSError(
            domain: AVFoundationErrorDomain, code: -11800,
            userInfo: [NSUnderlyingErrorKey: coreMedia]
        )

        XCTAssertEqual(DriveError.classify(wrapped), .offline)
    }

    /// Spec: "File deleted from Drive mid-playback → Skip to next, note it."
    /// Both halves. The note lands on `lastPlaybackError`, which the Drive list's
    /// banner reads — and deliberately *not* on `stalledPlaybackError`, which the
    /// player's own subtitle reads, because the track now playing is fine and
    /// must not be captioned with the previous one's failure.
    func testAFileMissingFromDriveSkipsToTheNextTrackAndSaysSo() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let two = try track(library, title: "Two")
        service.play(one, in: [one, two])

        player.simulateFailure(DriveError.fileUnavailable)
        await Task.yield()

        XCTAssertEqual(service.currentTrack?.id, two.id, "the queue must move on past a dead file")
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(service.lastPlaybackError as? DriveError, .fileUnavailable,
                       "a silent skip is a track vanishing for no stated reason")
        XCTAssertNil(service.stalledPlaybackError,
                     "the track that is playing must not wear the failure of the one before it")
    }

    /// The offline case keeps the behaviour it was given on purpose: skipping
    /// would march through the whole queue failing once per track.
    func testAConnectivityFailureStillStopsRatherThanSkipping() async throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let two = try track(library, title: "Two")
        service.play(one, in: [one, two])

        player.simulateFailure(DriveError.offline)
        await Task.yield()

        XCTAssertEqual(service.currentTrack?.id, one.id)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.stalledPlaybackError as? DriveError, .offline,
                       "a dead play button with no message is what this exists to prevent")
    }

    /// The bound on the skip. A streaming load reports its failure
    /// asynchronously, straight back into `handleFailure`, and with a repeat mode
    /// armed `canGoNext` is true forever — a folder whose sharing was revoked
    /// wholesale would circle its own queue issuing requests until the user
    /// force-quit.
    func testARunOfMissingFilesStopsInsteadOfCirclingARepeatingQueue() async throws {
        let (service, player, library) = try makeStack()
        let list = [
            try track(library, title: "One"),
            try track(library, title: "Two"),
            try track(library, title: "Three"),
        ]
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        XCTAssertEqual(service.repeatMode, .all)

        for _ in 0..<12 {
            player.simulateFailure(DriveError.fileUnavailable)
            await Task.yield()
        }

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.queue.count, 3, "the queue itself is untouched — only playback stops")
        XCTAssertEqual(service.stalledPlaybackError as? DriveError, .fileUnavailable)
        XCTAssertEqual(
            player.playCallCount, 1 + list.count,
            "each position may be tried at most once per run: the first play plus three skips"
        )
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
