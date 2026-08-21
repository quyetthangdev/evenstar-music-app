import XCTest
import SwiftData
@testable import Evenstar

/// Dây nối giữa `SleepTimer` và thứ thật sự phát ra tiếng.
///
/// `SleepTimerTests` ghim phần đếm ngược, và nó không biết gì về audio. File này
/// ghim phần còn lại: hết giờ thì **tạm dừng chứ không xoá hàng đợi**, mờ dần
/// tác động lên đúng bản phát, và âm lượng được trả về sau đó.
///
/// Tách hai file vì hai loại lỗi khác nhau. Sai ở đằng kia là đếm sai; sai ở đây
/// là đếm đúng mà nối nhầm dây — và một quy tắc đúng nối nhầm dây vẫn làm người
/// dùng mất chỗ đang nghe dở.
@MainActor
final class SleepTimerPlaybackTests: XCTestCase {
    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player,
                                      nowPlaying: MockNowPlayingPublisher(),
                                      library: library)
        return (service, player, library)
    }

    private func makeTrack(_ library: LibraryService) throws -> Track {
        let t = Track(title: "Bài", artistName: "Ai đó", albumTitle: "Đĩa",
                      durationSeconds: 100,
                      relativePath: "Music/\(UUID().uuidString).mp3",
                      format: "mp3")
        library.context.insert(t)
        try library.save()
        return t
    }

    /// Chờ tới khi điều kiện đúng, có hạn chót.
    ///
    /// `didFinishCallback` đi qua `Task { @MainActor in ... }`, nên nó chạy ở
    /// lượt sau chứ không ngay trong lời gọi `simulateFinish()`. Assert thẳng
    /// sau đó là đọc trạng thái cũ. Cùng hình dạng với `PlaybackServiceRepeatTests`,
    /// và vì cùng lý do: một số lượt `yield` cố định thì chạy được ở máy rảnh và
    /// hỏng khi máy bận.
    @discardableResult
    private func yieldUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date.now.addingTimeInterval(5)
        while !condition(), Date.now < deadline {
            await Task.yield()
        }
        return condition()
    }

    /// Hết giờ thì tạm dừng, và hàng đợi phải còn nguyên.
    ///
    /// Đây là lời hứa trung tâm của tính năng. `stopPlayback()` xoá cả hàng đợi
    /// lẫn bài đang phát, nên nối vào nó thì người ngủ quên sáng mai mở lên sẽ
    /// thấy trống trơn — mất đúng thứ họ đang nghe dở.
    func testExpiringPausesButKeepsTheQueue() throws {
        let (service, player, library) = try makeStack()
        let track = try makeTrack(library)
        service.play(track, in: [track])
        XCTAssertTrue(service.isPlaying)

        service.sleepTimer.start(seconds: 0)
        service.tickForTesting()

        XCTAssertFalse(service.isPlaying, "hết giờ thì phải im")
        XCTAssertEqual(service.queue.count, 1, "hàng đợi phải còn nguyên")
        XCTAssertNotNil(service.currentTrack, "bài đang nghe dở phải còn")
        XCTAssertEqual(player.pauseCallCount, 1)
    }

    /// Âm lượng trả về 1 ngay sau khi im.
    ///
    /// Không có bước này thì bài mở sau đó bắt đầu ở âm lượng 0 và người dùng
    /// tưởng app hỏng — không có gì trong giao diện nói rằng âm lượng của bản
    /// phát đang bị kéo xuống.
    func testTheVolumeIsRestoredAfterTheTimerFires() throws {
        let (service, player, library) = try makeStack()
        let track = try makeTrack(library)
        service.play(track, in: [track])

        service.sleepTimer.start(seconds: 0)
        service.tickForTesting()

        XCTAssertEqual(player.volumeChanges.last?.volume, 1,
                       "phải trả âm lượng về sau khi tắt")
        XCTAssertEqual(player.volumeChanges.last?.fade, 0,
                       "trả về ngay, không mờ — lúc này không còn tiếng nào để nghe cú nhảy")
    }

    /// Quãng mờ đi tới đúng bản phát, với đúng thời lượng.
    ///
    /// So với sai số chứ không so bằng: `PlaybackService` dựng `SleepTimer` với
    /// đồng hồ thật, nên vài micro giây trôi qua giữa lúc đặt hẹn và lúc gọi
    /// nhịp. `SleepTimerTests` mới là chỗ so bằng được, vì ở đó đồng hồ là giả.
    func testTheFadeReachesThePlayer() throws {
        let (service, player, library) = try makeStack()
        let track = try makeTrack(library)
        service.play(track, in: [track])

        service.sleepTimer.start(seconds: 10)
        service.tickForTesting()

        XCTAssertEqual(player.volumeChanges.first?.volume, 0, "mờ về 0")
        XCTAssertEqual(player.volumeChanges.first?.fade ?? 0, 10, accuracy: 0.1,
                       "mờ trong đúng thời gian còn lại")
    }

    /// Huỷ hẹn giữa lúc đang mờ thì nhạc phải to lại.
    func testCancellingMidFadeBringsTheVolumeBack() throws {
        let (service, player, library) = try makeStack()
        let track = try makeTrack(library)
        service.play(track, in: [track])

        service.sleepTimer.start(seconds: 10)
        service.tickForTesting()
        service.sleepTimer.cancel()

        XCTAssertEqual(player.volumeChanges.last?.volume, 1)
        XCTAssertEqual(player.volumeChanges.last?.fade, 0)
        XCTAssertTrue(service.isPlaying, "huỷ hẹn không được làm nhạc dừng")
    }

    /// Không có hẹn thì nhịp không được đụng gì tới âm lượng.
    ///
    /// Nhịp này chạy hai lần mỗi giây suốt thời gian phát nhạc. Một lời gọi
    /// `setVolume` thừa ở đây là một lời gọi mỗi nửa giây, mãi mãi.
    func testTickingWithoutATimerTouchesNothing() throws {
        let (service, player, library) = try makeStack()
        let track = try makeTrack(library)
        service.play(track, in: [track])

        service.tickForTesting()
        service.tickForTesting()

        XCTAssertTrue(player.volumeChanges.isEmpty,
                      "không có hẹn thì không được chỉnh âm lượng lần nào")
        XCTAssertTrue(service.isPlaying)
    }

    // MARK: - Hết bài hiện tại

    /// Bài kết thúc thì dừng, và **không nhảy sang bài kế**.
    ///
    /// Đây là chỗ dễ sai nhất của chế độ này. Nếu chốt đặt sau `switch repeatMode`
    /// thì `advance` đã chạy: bài kế đã nạp, đã phát, và người dùng nghe được một
    /// quãng đầu của đúng bài họ vừa bảo đừng phát.
    func testEndOfTrackStopsInsteadOfAdvancing() async throws {
        let (service, player, library) = try makeStack()
        let a = try makeTrack(library)
        let b = try makeTrack(library)
        service.play(a, in: [a, b])
        XCTAssertEqual(service.currentTrack?.id, a.id)

        service.sleepTimer.startAtEndOfTrack()
        player.simulateFinish()
        await yieldUntil { !service.sleepTimer.isRunning }

        XCTAssertFalse(service.isPlaying, "phải im sau khi bài hết")
        XCTAssertEqual(service.currentTrack?.id, a.id,
                       "không được nhảy sang bài kế")
        XCTAssertEqual(service.queue.count, 2, "hàng đợi phải còn nguyên")
        XCTAssertFalse(service.sleepTimer.isRunning, "hẹn đã xong thì tắt")
    }

    /// Không có hẹn thì bài hết vẫn chuyển tiếp như thường.
    ///
    /// Chốt mới nằm ngay đầu `handleFinish`, nên nó là chỗ có thể chặn nhầm
    /// đường đi bình thường của mọi lần chuyển bài trong app.
    func testWithoutTheTimerFinishingStillAdvances() async throws {
        let (service, player, library) = try makeStack()
        let a = try makeTrack(library)
        let b = try makeTrack(library)
        service.play(a, in: [a, b])

        player.simulateFinish()
        await yieldUntil { service.currentTrack?.id == b.id }

        XCTAssertEqual(service.currentTrack?.id, b.id, "phải sang bài kế như thường")
    }

    /// Hẹn đếm ngược không được chặn việc chuyển bài.
    func testACountdownDoesNotStopTheTrackFromAdvancing() async throws {
        let (service, player, library) = try makeStack()
        let a = try makeTrack(library)
        let b = try makeTrack(library)
        service.play(a, in: [a, b])

        service.sleepTimer.start(minutes: 30)
        player.simulateFinish()
        await yieldUntil { service.currentTrack?.id == b.id }

        XCTAssertEqual(service.currentTrack?.id, b.id,
                       "hẹn ba mươi phút thì bài hết vẫn sang bài kế")
        XCTAssertTrue(service.sleepTimer.isRunning, "và hẹn vẫn còn chạy")
    }
}
