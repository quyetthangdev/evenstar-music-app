import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceRestoreTests: XCTestCase {

    private func makeStack(persistInterval: TimeInterval = 5) throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library, persistInterval: persistInterval)
        return (service, player, library)
    }

    private func seed(_ count: Int, library: LibraryService) throws -> [Track] {
        try (0..<count).map { i in
            let t = Track(
                title: "T\(i)",
                artistName: "A",
                albumTitle: "B",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3",
                format: "mp3"
            )
            try library.insert(t)
            return t
        }
    }

    func testRestoreLoadsLastTrackAtPersistedPositionButDoesNotAutoplay() async throws {
        let (service, player, library) = try makeStack()
        let tracks = try seed(3, library: library)
        let state = library.playbackState
        state.queueTrackIDs = tracks.map(\.id)
        state.queueIndex = 1
        state.positionSeconds = 42
        try library.savePlaybackState()

        await service.restoreFromPersistedState()

        XCTAssertEqual(service.queue.map(\.id), tracks.map(\.id))
        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(player.currentTime, 42, accuracy: 0.01)
        XCTAssertFalse(service.isPlaying)
    }

    func testRestoreSkipsMissingTracks() async throws {
        let (service, _, library) = try makeStack()
        var tracks = try seed(3, library: library)
        let state = library.playbackState
        state.queueTrackIDs = tracks.map(\.id)
        state.queueIndex = 1
        state.positionSeconds = 0
        try library.savePlaybackState()
        // Delete the middle track from the library after persistence captured the ID.
        let deleted = tracks.remove(at: 1)
        try library.delete(deleted)

        await service.restoreFromPersistedState()

        XCTAssertEqual(service.queue.map(\.id), tracks.map(\.id))
        // queueIndex was 1 (the deleted one). After shrink, index is clamped to remaining bounds.
        XCTAssertGreaterThanOrEqual(service.queueIndex, 0)
        XCTAssertLessThan(service.queueIndex, service.queue.count)
    }

    func testRestoreEmptyStateIsNoOp() async throws {
        let (service, _, _) = try makeStack()

        await service.restoreFromPersistedState()

        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertNil(service.currentTrack)
        XCTAssertFalse(service.isPlaying)
    }

    func testPersistWritesStateOnPause() throws {
        let (service, player, library) = try makeStack()
        let tracks = try seed(2, library: library)
        service.play(tracks[0], in: tracks)
        player.currentTime = 17

        service.pause()

        XCTAssertEqual(library.playbackState.currentTrackID, tracks[0].id)
        XCTAssertEqual(library.playbackState.positionSeconds, 17, accuracy: 0.01)
        XCTAssertEqual(library.playbackState.queueTrackIDs, tracks.map(\.id))
    }

    // MARK: - Restore failure path (ruling item 2)

    /// The saved current track's file can no longer be loaded (e.g. deleted
    /// from disk while its DB row survives). Restore must skip forward to a
    /// playable track — mirroring loadCurrentAndPlay() — rather than wiping
    /// the persisted row via stopPlayback(). The whole point of the fix is
    /// that the surviving queue stays recorded, so we assert directly on the
    /// persisted row, not just on in-memory service state.
    func testRestoreSkipsUnplayableCurrentTrackAndKeepsPersistedQueue() async throws {
        let (service, player, library) = try makeStack()
        let tracks = try seed(3, library: library)
        player.failingURLs = [FileLocation.absoluteURL(forRelative: tracks[1].relativePath)]
        let state = library.playbackState
        state.queueTrackIDs = tracks.map(\.id)
        state.queueIndex = 1
        state.positionSeconds = 42
        try library.savePlaybackState()

        await service.restoreFromPersistedState()

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.id, tracks[2].id)
        XCTAssertFalse(service.isPlaying)
        // The landed track was reached by skipping forward, not the track
        // the saved position was recorded against — it must start at 0.
        XCTAssertEqual(player.currentTime, 0, accuracy: 0.01)
        XCTAssertEqual(service.position, 0, accuracy: 0.01)
        // The persisted row must reflect the surviving queue, not be wiped.
        XCTAssertFalse(library.playbackState.queueTrackIDs.isEmpty)
        XCTAssertEqual(library.playbackState.queueTrackIDs, tracks.map(\.id))
        XCTAssertEqual(library.playbackState.currentTrackID, tracks[2].id)
    }

    /// No track in the persisted queue can be loaded. Restore must stop
    /// cleanly rather than hang or crash — the bounded skip loop must
    /// terminate.
    func testRestoreWhenNoTrackCanLoadStopsCleanlyWithoutHanging() async throws {
        let (service, player, library) = try makeStack()
        let tracks = try seed(3, library: library)
        for track in tracks {
            player.failingURLs.insert(FileLocation.absoluteURL(forRelative: track.relativePath))
        }
        let state = library.playbackState
        state.queueTrackIDs = tracks.map(\.id)
        state.queueIndex = 0
        state.positionSeconds = 10
        try library.savePlaybackState()

        await service.restoreFromPersistedState()

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
    }

    // MARK: - Persist throttle (ruling item 3)

    /// Two ticks close together should produce only one write beyond the
    /// initial persist from play(). We can't inspect the private throttle
    /// timestamp, so we detect a write indirectly: change the player's
    /// currentTime between ticks and check whether the persisted position
    /// moved.
    func testThrottleSuppressesWritesWithinWindow() throws {
        let (service, player, library) = try makeStack(persistInterval: 5)
        let tracks = try seed(1, library: library)
        service.play(tracks[0], in: tracks)
        // play() persists immediately at position 0.
        XCTAssertEqual(library.playbackState.positionSeconds, 0, accuracy: 0.01)

        player.currentTime = 1
        service.tickForTesting()
        let afterFirstTick = library.playbackState.positionSeconds
        XCTAssertEqual(afterFirstTick, 0, accuracy: 0.01, "first tick within the window should not write")

        player.currentTime = 2
        service.tickForTesting()
        let afterSecondTick = library.playbackState.positionSeconds
        XCTAssertEqual(afterSecondTick, 0, accuracy: 0.01, "second tick within the window should still not write")
    }

    /// Once the throttle window has elapsed, the next tick does write.
    /// Uses a near-zero injected interval so the test doesn't need to sleep
    /// for a real 5 seconds.
    func testThrottleWritesOnceWindowElapses() throws {
        let (service, player, library) = try makeStack(persistInterval: 0.01)
        let tracks = try seed(1, library: library)
        service.play(tracks[0], in: tracks)
        XCTAssertEqual(library.playbackState.positionSeconds, 0, accuracy: 0.01)

        Thread.sleep(forTimeInterval: 0.05)
        player.currentTime = 9
        service.tickForTesting()

        XCTAssertEqual(library.playbackState.positionSeconds, 9, accuracy: 0.01)
    }
}
