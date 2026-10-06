import XCTest
@testable import Evenstar

/// Cú vuốt phải trên mini player **luôn lùi hẳn một bài**, khác nút ⏮ ở chỗ bỏ
/// qua ngưỡng "phát lại từ đầu sau 3 giây". Hình bài cũ trượt vào mà kết quả
/// là phát lại bài hiện tại thì sai với điều mắt thấy.
@MainActor
final class PlaybackServiceStepBackTests: XCTestCase {

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

    func testPastTheRestartThresholdItStillStepsBack() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        player.currentTime = 30
        service.tickForTesting()

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
    }

    func testAtTheHeadWithRepeatOffThereIsNowhereToGo() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        XCTAssertFalse(service.canGoPrevious)

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 0, "không lùi, và không phát lại từ đầu")
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
    }

    func testAtTheHeadWithRepeatAllItWrapsToTheLast() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all
        XCTAssertTrue(service.canGoPrevious)

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 2)
    }

    func testAtTheHeadWithRepeatOneItAlsoWraps() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 2)
    }

    func testMidQueueCanGoPreviousWhateverTheRepeatMode() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        XCTAssertTrue(service.canGoPrevious)
        service.cycleRepeatMode()
        XCTAssertTrue(service.canGoPrevious)
    }

    func testAnEmptyQueueCannotGoPrevious() throws {
        let (service, _, _) = try makeStack()
        XCTAssertFalse(service.canGoPrevious)
        service.stepBack()  // không sập
        XCTAssertNil(service.currentTrack)
    }

    /// `previous()` không được đổi hành vi.
    func testThePreviousButtonStillRestartsPastTheThreshold() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        player.currentTime = 30
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 1)
    }
}
