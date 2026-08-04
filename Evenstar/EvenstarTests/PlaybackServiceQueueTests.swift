import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceQueueTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, nowPlaying, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        var out: [Track] = []
        for i in 0..<count {
            let t = Track(
                title: "Track \(i)",
                artistName: "Artist",
                albumTitle: "Album",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3",
                format: "mp3"
            )
            try library.insert(t)
            out.append(t)
        }
        return out
    }

    func testPlayInQueueSetsQueueAndStartsPlayback() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)

        service.play(list[1], in: list)

        XCTAssertEqual(service.queue.map(\.id), list.map(\.id))
        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
    }

    // NOTE: PlaybackService's didFinishCallback hops asynchronously via
    // `Task { @MainActor in self?.handleFinish() }`, so this test must be
    // async and yield before asserting or the assertions run before
    // handleFinish() executes. (Ruled by human partner; brief's synchronous
    // version fails.)
    func testFinishAdvancesToNextTrack() async throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        let initialPlayCount = player.playCallCount

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertGreaterThan(player.playCallCount, initialPlayCount)
    }

    // NOTE: same async-hop reasoning as testFinishAdvancesToNextTrack above.
    func testFinishOnLastTrackStopsAndClearsQueue() async throws {
        let (service, player, nowPlaying, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)

        player.simulateFinish()
        await Task.yield()

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertGreaterThan(nowPlaying.clearCallCount, 0)
    }

    func testNextManuallyAdvances() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.next()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
    }

    func testPreviousStepsBackWhenNearTheStartOfATrack() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.next()
        // Just inside the threshold, so Previous means "the one before".
        player.currentTime = PlaybackService.restartThreshold - 0.5
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
    }

    func testPreviousRestartsTheCurrentTrackWhenPastTheThreshold() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.next()
        // Past the threshold, so the same button means "this one, from the top".
        player.currentTime = PlaybackService.restartThreshold + 0.5
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 1, "Should not have stepped back")
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertEqual(service.position, 0, accuracy: 0.01)
    }

    func testPreviousRestartsAtTheHeadOfTheQueueRatherThanDoingNothing() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        // Before the threshold, where a step back would be the other branch —
        // but there is nothing to step back to, so it must still restart.
        player.currentTime = 1
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.position, 0, accuracy: 0.01)
    }

    func testPlayCountIncrementsAfter30Seconds() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)

        player.currentTime = 30.5
        service.tickForTesting()  // exposed helper that drives the same code path as the 0.5s timer

        XCTAssertEqual(list[0].playCount, 1)
        XCTAssertNotNil(list[0].lastPlayedAt)
    }

    func testPlayCountIncrementsOnlyOncePerPlayback() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)

        player.currentTime = 31
        service.tickForTesting()
        player.currentTime = 60
        service.tickForTesting()

        XCTAssertEqual(list[0].playCount, 1)
    }

    func testSkipsUnplayableTrackAndContinuesQueue() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        player.failingURLs = [FileLocation.absoluteURL(forRelative: list[1].relativePath)]

        service.play(list[0], in: list)
        service.next()

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.id, list[2].id)
        XCTAssertEqual(service.queue.map(\.id), list.map(\.id))
        XCTAssertTrue(service.isPlaying)
    }

    func testAllTracksFailToLoadStopsPlaybackWithoutHanging() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        for track in list {
            player.failingURLs.insert(FileLocation.absoluteURL(forRelative: track.relativePath))
        }

        service.play(list[0], in: list)

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
    }

    func testHandleDeletedCurrentTrackAdvances() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.handleTrackDeleted(list[0])

        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertEqual(service.queue.count, 2)
    }

    func testHandleDeletedLastTrackWhenItIsCurrentStopsPlayback() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)

        service.handleTrackDeleted(list[1])

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
    }

    func testHandleDeletedFutureTrackAdjustsQueueButKeepsCurrent() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.handleTrackDeleted(list[2])

        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertEqual(service.queue.count, 2)
    }

    func testHandleDeletedPastTrackAdjustsIndex() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        XCTAssertEqual(service.queueIndex, 2)

        service.handleTrackDeleted(list[0])

        XCTAssertEqual(service.currentTrack?.id, list[2].id)
        XCTAssertEqual(service.queueIndex, 1)  // shifted because one earlier item was removed
        XCTAssertEqual(service.queue.count, 2)
    }

    func testHandleDeletedTrackNotInQueueIsNoOp() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        let outsider = try tracks(1, library: library)[0]

        service.handleTrackDeleted(outsider)

        XCTAssertEqual(service.queue.map(\.id), list.map(\.id))
        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertTrue(service.isPlaying)
    }

    func testHandleDeletedCurrentTrackWhilePausedDoesNotResumePlayback() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.pause()
        XCTAssertFalse(service.isPlaying)

        service.handleTrackDeleted(list[0])

        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertFalse(service.isPlaying)
    }

    /// Delete-then-relaunch: `handleTrackDeleted`'s persistence was
    /// previously only ever checked against in-memory service state. This
    /// asserts the actual `PlaybackState` row — what a relaunch would read
    /// back — reflects the surviving queue and the new current track.
    func testHandleDeletedCurrentTrackPersistsSurvivingQueueAndCurrentTrack() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.handleTrackDeleted(list[0])

        let state = library.playbackState
        XCTAssertEqual(state.queueTrackIDs, [list[1].id, list[2].id])
        XCTAssertEqual(state.currentTrackID, list[1].id)
    }

    func testHandleDeletedSoleTrackWhenCurrentStopsPlayback() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)

        service.handleTrackDeleted(list[0])

        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertFalse(service.isPlaying)
    }
}
