import XCTest
@testable import Evenstar

/// `TrackSwipe.commit` là chỗ duy nhất cú vuốt chạm vào `PlaybackService`. Nó
/// hỏi lại `canGoNext`/`canGoPrevious` **lúc đổi bài** — sau cú trượt ra, chứ
/// không chỉ lúc thả tay — vì bài có thể hết giữa chừng.
@MainActor
final class TrackSwipeCommitTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: MockNowPlayingPublisher(), library: library)
        return (service, player, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        try (0..<count).map { i in
            let t = Track(title: "Track \(i)", artistName: "Artist", albumTitle: "Album",
                          durationSeconds: 100, relativePath: "Music/\(UUID().uuidString).mp3",
                          format: "mp3")
            try library.insert(t)
            return t
        }
    }

    func testNextMidQueueAdvancesWithoutOpeningThePlayer() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        let selections = service.explicitSelections

        XCTAssertTrue(TrackSwipe.commit(.next, on: service))

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.explicitSelections, selections, "vuốt đổi bài không bung player")
    }

    /// Phải là lùi hẳn một bài, kể cả khi bài đã chạy quá 3 giây.
    func testPreviousPastTheRestartThresholdStepsBack() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        player.currentTime = 30
        service.tickForTesting()
        let selections = service.explicitSelections

        XCTAssertTrue(TrackSwipe.commit(.previous, on: service))

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.explicitSelections, selections)
    }

    /// `next()` ở cuối hàng đợi khi tắt repeat **dừng phát**. Cú vuốt không
    /// bao giờ được gọi nó ở đó.
    func testNextAtTheEndWithRepeatOffKeepsPlaying() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        XCTAssertTrue(service.isPlaying, "precondition")

        XCTAssertFalse(TrackSwipe.commit(.next, on: service))

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.id, list[2].id)
        XCTAssertTrue(service.isPlaying, "không dừng phát")
    }

    func testPreviousAtTheHeadWithRepeatOffDoesNothing() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        player.currentTime = 30
        service.tickForTesting()

        XCTAssertFalse(TrackSwipe.commit(.previous, on: service))

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.position, 30, accuracy: 0.001, "không phát lại từ đầu")
    }

    func testNextAtTheEndWithRepeatAllWraps() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        service.cycleRepeatMode()  // .all

        XCTAssertTrue(TrackSwipe.commit(.next, on: service))

        XCTAssertEqual(service.queueIndex, 0)
    }

    func testCancelChangesNothing() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)

        XCTAssertFalse(TrackSwipe.commit(.cancel, on: service))

        XCTAssertEqual(service.queueIndex, 1)
    }
}
