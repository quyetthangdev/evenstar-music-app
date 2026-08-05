import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceRepeatTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, library)
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

    /// Bounded rather than a fixed number of yields: `cycleRepeatMode()`
    /// persists through `deferPersist()`, whose `Task { @MainActor in ... }`
    /// takes an unpredictable number of yields to land. A fixed count passes
    /// locally and fails under load. The deadline turns a real regression into
    /// a failed assertion rather than a hung suite.
    private func yieldUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(5)
        while !condition(), Date.now < deadline {
            await Task.yield()
        }
        return condition()
    }

    // MARK: - The cycle

    func testCycleRunsOffAllOneOff() throws {
        let (service, _, _) = try makeStack()
        XCTAssertEqual(service.repeatMode, .off)

        service.cycleRepeatMode()
        XCTAssertEqual(service.repeatMode, .all)

        service.cycleRepeatMode()
        XCTAssertEqual(service.repeatMode, .one)

        service.cycleRepeatMode()
        XCTAssertEqual(service.repeatMode, .off)
    }

    // MARK: - Persistence

    /// `repeatModeRaw` carries a string literal default so SwiftData can
    /// migrate existing rows without a migration plan. This pins that literal
    /// to the enum, so changing one and not the other fails here rather than
    /// silently resetting everyone's saved mode on upgrade.
    func testFreshPlaybackStateDefaultsToOff() {
        XCTAssertEqual(PlaybackState().repeatModeRaw, RepeatMode.off.rawValue)
    }

    func testCyclingPersistsTheMode() async throws {
        let (service, _, library) = try makeStack()

        service.cycleRepeatMode()  // .all

        let written = await yieldUntil { library.playbackState.repeatModeRaw == RepeatMode.all.rawValue }
        XCTAssertTrue(written, "cycleRepeatMode() should reach PlaybackState")
    }

    func testModeSurvivesRestore() async throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[0], in: list)   // writes a queue worth restoring
        library.playbackState.repeatModeRaw = RepeatMode.one.rawValue
        try library.save()

        // A second service over the *same* library, standing in for a relaunch.
        // `InMemoryLibrary.make()` builds a fresh store each call, so a second
        // `makeStack()` would restore from an empty one and pass for the wrong
        // reason.
        let relaunched = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await relaunched.restoreFromPersistedState()

        XCTAssertEqual(relaunched.repeatMode, .one)
        XCTAssertEqual(relaunched.queue.count, 2, "the queue should have come back too")
    }

    /// The mode is a setting, not part of the queue. A launch with nothing to
    /// restore must still bring it back — which means reading it *before*
    /// `restoreFromPersistedState()`'s empty-queue guard, not after.
    func testModeSurvivesRestoreWithNoQueue() async throws {
        let (_, _, library) = try makeStack()
        library.playbackState.repeatModeRaw = RepeatMode.all.rawValue
        try library.save()
        XCTAssertTrue(library.playbackState.queueTrackIDs.isEmpty)

        let service = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await service.restoreFromPersistedState()

        XCTAssertEqual(service.repeatMode, .all)
    }

    /// An unreadable value must degrade, not crash or wedge the player.
    func testUnknownStoredValueFallsBackToOff() async throws {
        let (_, _, library) = try makeStack()
        library.playbackState.repeatModeRaw = "sideways"
        try library.save()

        let service = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await service.restoreFromPersistedState()

        XCTAssertEqual(service.repeatMode, .off)
    }

    // MARK: - A track ending by itself

    func testFinishWithRepeatOffOnLastTrackStops() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)

        player.simulateFinish()
        await Task.yield()

        XCTAssertFalse(service.isPlaying)
        XCTAssertTrue(service.queue.isEmpty)
    }

    func testFinishWithRepeatAllOnLastTrackWrapsToTheFirst() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()  // .all

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(service.queue.count, 3, "wrapping must not tear down the queue")
    }

    func testFinishWithRepeatAllMidQueueStillAdvances() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
    }

    func testFinishWithRepeatOneReplaysTheSameTrack() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all
        service.cycleRepeatMode()  // .one
        let playsBefore = player.playCallCount

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 0, "repeat-one must not advance")
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertGreaterThan(player.playCallCount, playsBefore, "it must actually start again")
        XCTAssertEqual(service.position, 0, accuracy: 0.01)
    }

    func testFinishWithRepeatOneOnTheLastTrackReplaysRatherThanStopping() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertTrue(service.isPlaying)
        XCTAssertFalse(service.queue.isEmpty)
    }

    /// A track left on repeat is genuinely being played again, so each pass
    /// past 30 seconds counts. This fails if the replay path forgets to clear
    /// `playCountedForCurrent`.
    func testRepeatOneCountsEachPassAsAPlay() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        player.currentTime = 31
        service.tickForTesting()
        XCTAssertEqual(list[0].playCount, 1)

        player.simulateFinish()
        await Task.yield()
        player.currentTime = 31
        service.tickForTesting()

        XCTAssertEqual(list[0].playCount, 2)
    }

    // MARK: - The Next button

    /// The regression this whole đợt turns on: repeat-one governs a track that
    /// runs out, never a button the user pressed.
    func testNextWithRepeatOneStillAdvances() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.next()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
    }

    func testNextWithRepeatAllOnLastTrackWraps() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()  // .all

        service.next()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertEqual(service.queue.count, 3)
    }

    func testNextWithRepeatOneOnLastTrackWraps() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.next()

        XCTAssertEqual(service.queueIndex, 0)
    }

    func testNextWithRepeatOffOnLastTrackStillStops() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)

        service.next()

        XCTAssertFalse(service.isPlaying)
        XCTAssertTrue(service.queue.isEmpty)
    }

    // MARK: - The Previous button

    func testPreviousWithRepeatAllAtTheHeadWrapsToTheLast() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all
        player.currentTime = 1  // inside the restart threshold
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.id, list[2].id)
    }

    /// `.all` and `.one` take the same branch here, and only `.all` was
    /// covered — so narrowing the condition to `repeatMode == .all` used to
    /// pass the whole suite. This closes that.
    func testPreviousWithRepeatOneAtTheHeadAlsoWrapsToTheLast() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one
        player.currentTime = 1  // inside the restart threshold
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.id, list[2].id)
    }

    /// The step-back branch (`queueIndex > 0`) was only ever exercised with
    /// repeat off, so narrowing it to `queueIndex > 0 && repeatMode == .off`
    /// used to pass the whole suite — and that mutation would send a mid-queue
    /// Previous to the *end* of the queue instead of one track back. Same
    /// mutation class already caught once in this method; this pins the branch
    /// with a mode armed.
    func testPreviousMidQueueWithRepeatAllStepsBackRatherThanWrapping() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        service.cycleRepeatMode()  // .all
        player.currentTime = 1  // inside the restart threshold
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 0, "must step back, not wrap to the end")
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
    }

    func testPreviousWithRepeatOffAtTheHeadStillRestarts() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        player.currentTime = 1
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.position, 0, accuracy: 0.01)
    }

    /// The three-second rule outranks the repeat mode: past it, Previous means
    /// "this one, from the top" no matter what is armed.
    func testPreviousPastTheThresholdRestartsEvenWithRepeatAll() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all
        player.currentTime = PlaybackService.restartThreshold + 0.5
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 0, "must not have wrapped to the end")
        XCTAssertEqual(service.position, 0, accuracy: 0.01)
    }

    // MARK: - canGoNext

    func testCanGoNextIsFalseOnlyAtTheEndWithRepeatOff() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(2, library: library)

        service.play(list[0], in: list)
        XCTAssertTrue(service.canGoNext)

        service.next()
        XCTAssertFalse(service.canGoNext, "last track, repeat off")

        service.cycleRepeatMode()  // .all
        XCTAssertTrue(service.canGoNext, "repeat all reopens the end of the queue")

        service.cycleRepeatMode()  // .one
        XCTAssertTrue(service.canGoNext)
    }

    func testCanGoNextIsFalseWithNoQueue() throws {
        let (service, _, _) = try makeStack()
        XCTAssertFalse(service.canGoNext)
    }

    // MARK: - Deleting the current track (the third "the queue has no end" site)

    /// Swipe-to-delete on the last track, repeat-all armed. `next()` and
    /// `handleFinish()` both learned that an armed mode reopens the end of the
    /// queue; `handleTrackDeleted()` did not, so this stopped the music and
    /// wiped the two surviving tracks.
    func testDeletingCurrentLastTrackWithRepeatAllWrapsToTheTop() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()  // .all

        service.handleTrackDeleted(list[2])

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertTrue(service.isPlaying, "repeat-all must keep playing")
        XCTAssertEqual(service.queue.map(\.id), [list[0].id, list[1].id],
                       "the surviving tracks must not be torn down")
    }

    /// The wrap has to reach disk too, or a relaunch reads back the empty queue
    /// the old `stopPlayback()` persisted.
    func testDeletingCurrentLastTrackWithRepeatAllPersistsTheWrappedQueue() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()  // .all

        service.handleTrackDeleted(list[2])

        let state = library.playbackState
        XCTAssertEqual(state.queueTrackIDs, [list[0].id, list[1].id])
        XCTAssertEqual(state.currentTrackID, list[0].id)
        XCTAssertEqual(state.queueIndex, 0)
    }

    /// A paused player stays paused through the wrap, the same way the ordinary
    /// delete-and-advance path does.
    func testDeletingCurrentLastTrackWithRepeatAllWhilePausedDoesNotResume() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()  // .all
        service.pause()

        service.handleTrackDeleted(list[2])

        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertFalse(service.isPlaying)
    }

    /// Repeat-one deliberately does *not* wrap here. It means "keep replaying
    /// this track", and the track it named is the one just deleted — there is
    /// nothing left to repeat, so stopping is correct. Wrapping would quietly
    /// turn repeat-one into repeat-all.
    func testDeletingCurrentLastTrackWithRepeatOneStops() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.handleTrackDeleted(list[2])

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
    }

    /// Nothing to wrap to. The emptiness guard on the wrap is what keeps this
    /// from indexing into an empty queue.
    func testDeletingTheSoleTrackWithRepeatAllStillStops() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all

        service.handleTrackDeleted(list[0])

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
    }

    // MARK: - The skip-forward loop

    /// An overnight repeat-all queue whose last file has been deleted from the
    /// Files app. The bounded skip loop only ever walked forward, so it ran off
    /// the end and stopped — in the middle of the night, with the whole queue
    /// wiped, though every earlier track was fine.
    func testUnplayableLastTrackWithRepeatAllWrapsInsteadOfStopping() async throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        player.failingURLs = [FileLocation.absoluteURL(forRelative: list[2].relativePath)]
        service.play(list[1], in: list)
        service.cycleRepeatMode()  // .all

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(service.queue.map(\.id), list.map(\.id),
                       "the queue itself is untouched; only queueIndex moves")
    }

    /// The same wrap from a Next press rather than a natural finish.
    func testNextOntoAnUnplayableLastTrackWithRepeatAllWraps() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        player.failingURLs = [FileLocation.absoluteURL(forRelative: list[2].relativePath)]
        service.play(list[1], in: list)
        service.cycleRepeatMode()  // .all

        service.next()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertTrue(service.isPlaying)
    }

    /// The bound the loop's doc comment promises, now that a failed attempt can
    /// wrap as well as advance: with *nothing* loadable it must still terminate
    /// rather than circle the queue forever. A regression here hangs the suite
    /// rather than failing it, which is why it is stated explicitly.
    func testAllTracksFailWithRepeatAllStillStopsWithoutHanging() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        for track in list {
            player.failingURLs.insert(FileLocation.absoluteURL(forRelative: track.relativePath))
        }
        service.cycleRepeatMode()  // .all

        service.play(list[0], in: list)

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
    }

    /// Restore's own skip loop, which is the same shape one method down. Lower
    /// stakes — restore never autoplays — but without the wrap a relaunch with
    /// repeat armed and the last track's file missing threw away a queue whose
    /// earlier tracks all load.
    func testRestoreWrapsPastAnUnplayableCurrentTrackWithRepeatAll() async throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        library.playbackState.repeatModeRaw = RepeatMode.all.rawValue
        try library.save()

        let player = MockAudioPlayer()
        player.failingURLs = [FileLocation.absoluteURL(forRelative: list[2].relativePath)]
        let relaunched = PlaybackService(
            player: player,
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await relaunched.restoreFromPersistedState()

        XCTAssertEqual(relaunched.queueIndex, 0)
        XCTAssertEqual(relaunched.currentTrack?.id, list[0].id)
        XCTAssertEqual(relaunched.queue.count, 3)
        XCTAssertFalse(relaunched.isPlaying, "restore must never autoplay")
    }

    // MARK: - stopPlayback() must not disarm the mode

    /// `stopPlayback()` clears the queue, the metadata and the position, and it
    /// must leave `repeatMode` alone — the mode is a setting the user armed, not
    /// part of the queue that just ended. Nothing pinned this: adding
    /// `repeatMode = .off` to the most-reached method in the service used to
    /// pass the entire suite.
    ///
    /// Reached by deleting the sole track in the queue, which stops whatever is
    /// armed, so this stays honest even if the delete path's mode rules change.
    func testStopPlaybackLeavesTheArmedModeInMemory() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.handleTrackDeleted(list[0])

        XCTAssertTrue(service.queue.isEmpty, "precondition: playback really stopped")
        XCTAssertEqual(service.repeatMode, .one, "ending a queue must not disarm the mode")
    }

    /// The other half, and the one the spec's persistence argument rests on:
    /// `stopPlayback()` ends with `persistImmediately()`, which rewrites
    /// `repeatModeRaw` from the live value. A reset in `stopPlayback()` would
    /// therefore not merely be forgotten on relaunch — it would be written to
    /// disk, so the user who finishes a queue with repeat-one armed comes back
    /// to repeat off.
    func testStopPlaybackLeavesTheArmedModeOnDisk() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.handleTrackDeleted(list[0])

        XCTAssertTrue(library.playbackState.queueTrackIDs.isEmpty,
                      "precondition: the stop was persisted")
        XCTAssertEqual(library.playbackState.repeatModeRaw, RepeatMode.one.rawValue)
    }
}
