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
}
