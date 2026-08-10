import XCTest
@testable import Evenstar

/// The queue view's three service entry points.
///
/// All offsets in `moveUpcoming` and `playUpcoming` are into `upcoming` — the
/// tail — not into `queue`. Every test here asserts against that, because a
/// method that quietly took queue indices would still pass a test that only
/// ever moved the first element.
@MainActor
final class PlaybackServiceUpcomingTests: XCTestCase {

    private func makeStack(
        shuffleTail: @escaping ([any Playable]) -> [any Playable] = { $0.reversed() }
    ) throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player,
            nowPlaying: MockNowPlayingPublisher(),
            library: library,
            shuffleTail: shuffleTail
        )
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

    private func titles(_ tracks: [any Playable]) -> [String] { tracks.map(\.title) }

    // MARK: - upcoming

    func testUpcomingIsEverythingAfterThePlayingTrack() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()

        XCTAssertEqual(titles(service.upcoming), ["Track 2", "Track 3", "Track 4"])
    }

    func testUpcomingIsEmptyOnTheLastTrack() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[2], in: all)

        XCTAssertTrue(service.upcoming.isEmpty)
    }

    func testUpcomingIsEmptyWithNoQueue() throws {
        let (service, _, _) = try makeStack()

        XCTAssertTrue(service.upcoming.isEmpty)
    }

    // MARK: - moveUpcoming

    /// The offsets are into `upcoming`. Moving *its* first element must move
    /// `queue[queueIndex + 1]` — a method that took queue indices instead would
    /// move the playing track here and this assertion is what catches it.
    func testMoveUpcomingOffsetsAreIntoTheTailNotTheQueue() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()
        // queue: [0, 1, |2, 3, 4], playing index 1, upcoming [2, 3, 4]

        service.moveUpcoming(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(titles(service.queue), ["Track 0", "Track 1", "Track 3", "Track 4", "Track 2"])
    }

    func testMoveUpcomingLeavesThePlayingTrackAndIndexAlone() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()
        service.next()
        XCTAssertEqual(service.currentTrack?.title, "Track 2", "precondition")

        service.moveUpcoming(from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.title, "Track 2")
        XCTAssertEqual(Array(titles(service.queue).prefix(3)), ["Track 0", "Track 1", "Track 2"])
    }

    func testMoveUpcomingKeepsEveryTrack() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)

        service.moveUpcoming(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(Set(service.queue.map(\.id)), Set(all.map(\.id)))
        XCTAssertEqual(service.queue.count, 5)
    }

    func testMoveUpcomingOnAnEmptyTailDoesNothing() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[2], in: all)

        service.moveUpcoming(from: IndexSet(integer: 0), to: 1)

        XCTAssertEqual(titles(service.queue), ["Track 0", "Track 1", "Track 2"])
        XCTAssertEqual(service.queueIndex, 2)
    }

    /// The spec's ruling: a drag edits the shuffled arrangement, so turning
    /// shuffle off discards it and restores what was there before the shuffle.
    func testTurningShuffleOffAfterAReorderStillRestoresTheOriginalOrder() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        service.moveUpcoming(from: IndexSet(integer: 0), to: 3)

        service.toggleShuffle()

        XCTAssertEqual(titles(service.queue), ["Track 0", "Track 1", "Track 2", "Track 3", "Track 4"])
    }

    /// A reorder is a queue change like any other, so it has to reach the
    /// store. `moveUpcoming` calls `persistImmediately()` for that reason;
    /// without it the order would survive until the app was killed and no
    /// longer.
    func testAReorderSurvivesASaveAndRestore() async throws {
        let library = try InMemoryLibrary.make()
        let first = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        let all = try tracks(4, library: library)
        first.play(all[0], in: all)
        first.moveUpcoming(from: IndexSet(integer: 0), to: 3)
        let reordered = first.queue.map(\.id)

        let second = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await second.restoreFromPersistedState()

        XCTAssertEqual(second.queue.map(\.id), reordered)
    }

    // MARK: - playUpcoming

    func testPlayUpcomingPlaysTheTrackAtThatTailOffset() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        // upcoming: [1, 2, 3, 4]; offset 2 is "Track 3"

        service.playUpcoming(at: 2)

        XCTAssertEqual(service.currentTrack?.title, "Track 3")
        XCTAssertEqual(service.queueIndex, 3)
    }

    /// `play(_:in:)` would rebuild the queue and, with shuffle armed, reshuffle
    /// the tail and reset `unshuffledQueue` — so tapping row three would
    /// silently reorder everything below it. This is why `playUpcoming` exists.
    func testPlayUpcomingDoesNotReshuffleOrResetTheUnshuffledOrder() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        let orderBefore = service.queue.map(\.id)
        let unshuffledBefore = service.unshuffledQueue.map(\.id)

        service.playUpcoming(at: 1)

        XCTAssertEqual(service.queue.map(\.id), orderBefore, "the queue was reordered")
        XCTAssertEqual(service.unshuffledQueue.map(\.id), unshuffledBefore, "the restore order was reset")
        XCTAssertTrue(service.isShuffled)
    }

    func testPlayUpcomingPastTheEndDoesNothing() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)

        service.playUpcoming(at: 99)

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.title, "Track 0")
    }

    func testPlayUpcomingWithNoQueueDoesNothing() throws {
        let (service, _, _) = try makeStack()

        service.playUpcoming(at: 0)

        XCTAssertNil(service.currentTrack)
    }
}
