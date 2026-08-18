import XCTest
@testable import Evenstar

/// Shuffle reorders the queue *after* the playing track and nothing else.
///
/// Every test here injects `{ $0.reversed() }` as the shuffle, so the expected
/// order is exact rather than "some permutation". A real random shuffle can
/// return the input unchanged, which is a test that passes whether or not the
/// code works.
@MainActor
final class PlaybackServiceShuffleTests: XCTestCase {

    private func makeStack(
        shuffleTail: @escaping ([any Playable]) -> [any Playable] = { $0.reversed() }
    ) throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player,
            nowPlaying: nowPlaying,
            library: library,
            shuffleTail: shuffleTail
        )
        return (service, player, library)
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

    private func titles(_ service: PlaybackService) -> [String] {
        service.queue.map(\.title)
    }

    // MARK: - Turning it on

    func testShuffleLeavesTheHeadAndThePlayingTrackAlone() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()
        service.next()
        XCTAssertEqual(service.queueIndex, 2, "precondition")

        service.toggleShuffle()

        XCTAssertEqual(service.queueIndex, 2, "the index must not move")
        XCTAssertEqual(
            Array(titles(service).prefix(3)),
            ["Track 0", "Track 1", "Track 2"],
            "the head and the playing track are untouched"
        )
    }

    func testShuffleReordersOnlyTheTail() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()

        service.toggleShuffle()

        // Injected shuffle is `reversed()`, so [Track 2, 3, 4] -> [4, 3, 2].
        XCTAssertEqual(titles(service), ["Track 0", "Track 1", "Track 4", "Track 3", "Track 2"])
    }

    func testShuffleKeepsEveryTrackInTheQueue() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)

        service.toggleShuffle()

        XCTAssertEqual(
            Set(service.queue.map(\.id)),
            Set(all.map(\.id)),
            "shuffling must not drop or duplicate a track"
        )
        XCTAssertEqual(service.queue.count, 5)
    }

    func testIsShuffledReflectsTheToggle() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)

        XCTAssertFalse(service.isShuffled)
        service.toggleShuffle()
        XCTAssertTrue(service.isShuffled)
        service.toggleShuffle()
        XCTAssertFalse(service.isShuffled)
    }

    // MARK: - Turning it off

    func testTurningShuffleOffRestoresTheOriginalOrder() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        XCTAssertNotEqual(titles(service), ["Track 0", "Track 1", "Track 2", "Track 3", "Track 4"])

        service.toggleShuffle()

        XCTAssertEqual(titles(service), ["Track 0", "Track 1", "Track 2", "Track 3", "Track 4"])
    }

    /// Every other test in this file injects `{ $0.reversed() }`, which is its
    /// own inverse — applying it twice returns the input. That makes them
    /// unable to tell a correct "off" (restore from the stored
    /// `unshuffledQueue`) apart from a wrong one that "undoes" shuffle by
    /// running `shuffleTail` over the tail a second time: under an
    /// involution, restoring and reapplying land on the same answer. A
    /// rotation is not an involution — applying it twice does not return the
    /// input — so this is the one test in the file that actually
    /// discriminates between the two implementations.
    func testTurningShuffleOffRestoresFromStoredOrderNotByReapplyingTheShuffle() throws {
        let rotateFirstToLast: ([any Playable]) -> [any Playable] = { tail in
            guard let first = tail.first else { return tail }
            return Array(tail.dropFirst()) + [first]
        }
        let (service, _, library) = try makeStack(shuffleTail: rotateFirstToLast)
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)

        service.toggleShuffle()
        // Tail [1, 2, 3, 4] rotated once -> [2, 3, 4, 1].
        XCTAssertEqual(
            titles(service),
            ["Track 0", "Track 2", "Track 3", "Track 4", "Track 1"],
            "precondition"
        )

        service.toggleShuffle()

        // A reapply-the-shuffle "off" would rotate the tail a second time —
        // [2, 3, 4, 1] -> [3, 4, 1, 2] — landing on ["Track 0", "Track 3",
        // "Track 4", "Track 1", "Track 2"], not the original order.
        XCTAssertEqual(titles(service), ["Track 0", "Track 1", "Track 2", "Track 3", "Track 4"])
    }

    /// The whole reason turning shuffle off needs a search rather than just
    /// restoring the array: playback moved on through the shuffled tail, so the
    /// playing track sits at a different index in the original order.
    func testTurningShuffleOffPointsTheIndexAtTheTrackStillPlaying() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        // Queue is now [0, 4, 3, 2, 1]. Advance twice: playing "Track 3".
        service.next()
        service.next()
        XCTAssertEqual(service.currentTrack?.title, "Track 3", "precondition")

        service.toggleShuffle()

        XCTAssertEqual(service.currentTrack?.title, "Track 3", "the same track keeps playing")
        XCTAssertEqual(service.queueIndex, 3, "which is index 3 in the original order")
    }

    // MARK: - Edge cases

    func testShufflingAnEmptyQueueIsANoOp() throws {
        let (service, _, _) = try makeStack()

        service.toggleShuffle()

        XCTAssertTrue(service.isShuffled, "the setting still flips")
        XCTAssertTrue(service.queue.isEmpty)
    }

    func testShufflingTheLastTrackIsANoOp() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[2], in: all)
        XCTAssertEqual(service.queueIndex, 2, "precondition: nothing after it")

        service.toggleShuffle()

        XCTAssertEqual(titles(service), ["Track 0", "Track 1", "Track 2"])
    }

    // MARK: - Deletion

    /// `unshuffledQueue` holds `any Playable` — live SwiftData rows. A deleted
    /// row left in it is a reference the next restore will read properties off,
    /// which raises an uncatchable Objective-C exception rather than throwing.
    func testDeletingATrackAlsoRemovesItFromTheUnshuffledOrder() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(4, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()

        service.handleTrackDeleted(all[3])

        XCTAssertFalse(
            service.unshuffledQueue.contains { $0.id == all[3].id },
            "a deleted row must not survive in the order shuffle restores to"
        )
        XCTAssertEqual(service.unshuffledQueue.count, 3)
    }

    /// The `if let` branch of the index restore, in the case where a deletion
    /// changed *what* is playing out from under the shuffle.
    ///
    /// Deleting the track at `queueIndex` when it is not the queue's last
    /// track does not stop playback — `handleTrackDeleted` leaves `queueIndex`
    /// where it was and loads whatever track slid into that slot, so
    /// `currentTrack` afterward is a *different* track than the one deleted.
    /// That track is still in `unshuffledQueue` (only the deleted one was
    /// removed from it), but at whatever index it held in the original order —
    /// not the shuffled one. This confirms `toggleShuffle()` finds it there by
    /// id rather than assuming the shuffled and original positions line up.
    ///
    /// This does **not** reach the `else` clamp below it: that requires
    /// `currentTrack` to be `nil` while `unshuffledQueue` is still non-empty,
    /// and the only path that ever produced that combination was the
    /// `stopPlayback()` bug that left `unshuffledQueue` stale — see
    /// `testTurningShuffleOffAfterTheLastTrackWasDeletedStaysEmpty` and the
    /// fix-round section of the task report for why, once that bug is fixed,
    /// the clamp has no known reachable caller left.
    func testTurningShuffleOffAfterThePlayingTrackWasDeletedKeepsAValidIndex() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(4, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        service.next()
        let playing = try XCTUnwrap(service.currentTrack)

        service.handleTrackDeleted(playing)
        service.toggleShuffle()

        XCTAssertFalse(service.isShuffled)
        XCTAssertTrue(
            service.queue.isEmpty || service.queue.indices.contains(service.queueIndex),
            "queueIndex \(service.queueIndex) is outside a queue of \(service.queue.count)"
        )
    }

    /// Regression test for a stale `unshuffledQueue` surviving a stop.
    ///
    /// Deleting the playing track when it is last in the queue routes through
    /// `handleTrackDeleted`'s "past the end, not repeat-all" branch, which
    /// calls `stopPlayback()` — clearing `queue` but, before this fix, not
    /// `unshuffledQueue`. A later "off" toggle then found `unshuffledQueue`
    /// still holding the *other* surviving tracks, took that as real state to
    /// restore, and resurrected a queue that was not loaded and not playing:
    /// the mini player would reappear over dead state.
    ///
    /// **Three tracks, not one.** `handleTrackDeleted` already removes the
    /// deleted track from `unshuffledQueue` on every call, before this fix is
    /// even reached — with only one track total that alone empties it, so a
    /// one-track queue passes whether or not `stopPlayback()` clears
    /// `unshuffledQueue` and proves nothing. What the fix actually has to
    /// clear is the *other* tracks still sitting in `unshuffledQueue` after
    /// the deleted one is gone from it — which needs at least one track
    /// besides the one deleted.
    func testTurningShuffleOffAfterTheLastTrackWasDeletedStaysEmpty() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        service.next()
        service.next()
        let playing = try XCTUnwrap(service.currentTrack)
        XCTAssertEqual(service.queueIndex, service.queue.count - 1, "precondition: playing the last track")

        service.handleTrackDeleted(playing)
        XCTAssertTrue(service.queue.isEmpty, "precondition: deleting it stopped playback")
        service.toggleShuffle()

        XCTAssertTrue(service.queue.isEmpty, "must not resurrect the other surviving tracks")
        XCTAssertNil(service.currentTrack)
    }

    // MARK: - A new queue while shuffle is on

    func testStartingANewQueueWhileShuffledShufflesItsTail() throws {
        let (service, _, library) = try makeStack()
        let first = try tracks(3, library: library)
        service.play(first[0], in: first)
        service.toggleShuffle()

        let second = try tracks(4, from: 3, library: library)
        service.play(second[0], in: second)

        // reversed() on the tail [4, 5, 6] -> [6, 5, 4]; "Track 3" stays first.
        XCTAssertEqual(titles(service).first, "Track 3", "the tapped track still plays")
        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(Array(titles(service).dropFirst()), ["Track 6", "Track 5", "Track 4"])
    }

    func testTurningShuffleOffAfterANewQueueRestoresThatQueuesOrder() throws {
        let (service, _, library) = try makeStack()
        let first = try tracks(3, library: library)
        service.play(first[0], in: first)
        service.toggleShuffle()
        let second = try tracks(4, from: 3, library: library)
        service.play(second[0], in: second)

        service.toggleShuffle()

        XCTAssertEqual(titles(service), ["Track 3", "Track 4", "Track 5", "Track 6"])
    }
}
