import XCTest
@testable import Evenstar

/// Shuffle survives a relaunch — both the flag and the order it can be undone
/// back to.
///
/// Restoring is exercised by building a *second* service over the same library,
/// which is what a relaunch is: same store on disk, fresh objects on top.
@MainActor
final class PlaybackServiceShufflePersistenceTests: XCTestCase {

    private func makeService(
        library: LibraryService,
        shuffleTail: @escaping ([any Playable]) -> [any Playable] = { $0.reversed() }
    ) -> PlaybackService {
        PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library,
            shuffleTail: shuffleTail
        )
    }

    /// `from` offsets the numbering so a second call produces distinct titles.
    /// Without it both calls name their tracks "Track 0…", and a test that
    /// starts a second queue asserts against titles that collide with the
    /// first — passing or failing for reasons unrelated to shuffle.
    private func tracks(_ count: Int, from start: Int = 0,
                        library: LibraryService) throws -> [Track] {
        var out: [Track] = []
        for i in start..<(start + count) {
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

    /// The literal default is what lets SwiftData open a store written before
    /// these properties existed. Without it the app cannot launch for anyone who
    /// has used it before.
    func testFreshPlaybackStateDefaultsToUnshuffled() throws {
        let library = try InMemoryLibrary.make()
        XCTAssertFalse(library.playbackState.isShuffled)
        XCTAssertTrue(library.playbackState.unshuffledQueueTrackIDs.isEmpty)
    }

    func testTogglingShuffleWritesBothFieldsToTheStore() throws {
        let library = try InMemoryLibrary.make()
        let service = makeService(library: library)
        let all = try tracks(4, library: library)
        service.play(all[0], in: all)

        service.toggleShuffle()

        XCTAssertTrue(library.playbackState.isShuffled)
        XCTAssertEqual(
            library.playbackState.unshuffledQueueTrackIDs,
            all.map(\.id),
            "the pre-shuffle order is what must be stored"
        )
        XCTAssertEqual(
            library.playbackState.queueTrackIDs,
            service.queue.map(\.id),
            "the shuffled order rides on the existing field"
        )
    }

    func testRestoreBringsBackTheFlagAndTheShuffledOrder() async throws {
        let library = try InMemoryLibrary.make()
        let first = makeService(library: library)
        let all = try tracks(4, library: library)
        first.play(all[0], in: all)
        first.toggleShuffle()
        let shuffledIDs = first.queue.map(\.id)

        let second = makeService(library: library)
        await second.restoreFromPersistedState()

        XCTAssertTrue(second.isShuffled)
        XCTAssertEqual(second.queue.map(\.id), shuffledIDs)
    }

    /// The point of persisting the unshuffled order at all: without it, the
    /// toggle has nothing to restore after a relaunch and the queue is stuck
    /// shuffled forever.
    func testShuffleCanBeTurnedOffAfterARestore() async throws {
        let library = try InMemoryLibrary.make()
        let first = makeService(library: library)
        let all = try tracks(4, library: library)
        first.play(all[0], in: all)
        first.toggleShuffle()

        let second = makeService(library: library)
        await second.restoreFromPersistedState()
        second.toggleShuffle()

        XCTAssertFalse(second.isShuffled)
        XCTAssertEqual(second.queue.map(\.id), all.map(\.id))
    }

    /// Mirrors `repeatMode`, which is restored above the empty-queue guard for
    /// the same reason: it is a setting, not part of the queue, so finishing a
    /// queue before quitting must not silently reset it.
    func testTheFlagIsRestoredEvenWithNoQueueToRestore() async throws {
        let library = try InMemoryLibrary.make()
        library.playbackState.isShuffled = true
        try library.save()

        let service = makeService(library: library)
        await service.restoreFromPersistedState()

        XCTAssertTrue(service.isShuffled)
    }

    /// `unshuffledQueue` and `queue` are resolved from persisted track IDs
    /// through two *separate* `compactMap` lookups. A track deleted from the
    /// library between the save and the next launch can resolve in one and
    /// not the other, so the two restored arrays can come back as different
    /// sets — reopening `toggleShuffle()`'s "playing track not found in the
    /// restored order" branch, which is otherwise unreachable through the
    /// public API (see the comment on its clamp).
    ///
    /// This persists a shuffled queue, deletes one of its tracks from the
    /// library so it fails to resolve, restores into a fresh service, and
    /// turns shuffle off. The assertion is just that `queueIndex` stays a
    /// valid index into whatever queue comes out the other side — the clamp's
    /// whole job.
    func testTurningShuffleOffAfterARestoreMissingATrackKeepsAValidIndex() async throws {
        let library = try InMemoryLibrary.make()
        let first = makeService(library: library)
        let all = try tracks(4, library: library)
        first.play(all[0], in: all)
        first.toggleShuffle()

        // Delete the track currently playing so it cannot resolve on restore —
        // that is what makes the playing track absent from the restored
        // unshuffled order specifically, rather than merely shrinking it.
        guard let playingID = first.currentTrack?.id,
              let playingTrack = all.first(where: { $0.id == playingID }) else {
            XCTFail("expected a current track after play()")
            return
        }
        try library.delete(playingTrack)

        let second = makeService(library: library)
        await second.restoreFromPersistedState()
        second.toggleShuffle()

        XCTAssertFalse(second.isShuffled)
        if second.queue.isEmpty {
            XCTAssertEqual(second.queueIndex, 0)
        } else {
            XCTAssertTrue(second.queue.indices.contains(second.queueIndex))
        }
    }
}
