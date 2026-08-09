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

    /// The `else` branch of the index restore. With the playing track gone from
    /// the original order there is no index to find, and the queue must still
    /// end up somewhere valid.
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
