import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceRestoreTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
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
}
