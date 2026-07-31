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
}
