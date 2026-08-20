import XCTest
@testable import Evenstar

/// Hàng đợi gặp một bài không có file trên máy này thì **đi tiếp**, không dừng.
///
/// Đây là test ghim một hành vi **đã có sẵn**, không phải test cho mã mới, và
/// lý do nó tồn tại đáng được viết ra: từ khi có CloudKit, một máy nhận về hàng
/// mô tả những bài nó không có file. Chúng nằm lẫn trong mọi hàng đợi dựng từ
/// thư viện. `loadCurrentAndPlay()` bỏ qua chúng vì `AVAudioPlayer(contentsOf:)`
/// ném lỗi với file vắng mặt — một cơ chế viết cho "file hỏng hoặc đã bị xoá",
/// giờ gánh thêm một ca thường xuyên hơn hẳn.
///
/// Không có test này thì một lần dọn dẹp `loadCurrentAndPlay()` làm nhạc dừng
/// giữa chừng ở đúng những máy có nhiều bài vắng mặt nhất, và không gì đỏ lên.
@MainActor
final class AbsentTrackPlaybackTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
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

    /// Bài giữa hàng đợi vắng mặt: nhảy qua nó, phát bài sau, và hàng đợi
    /// **không** bị cắt gọt — bài ấy có thể phát được trên máy khác.
    func testAnAbsentTrackInTheMiddleIsSkipped() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        player.failingURLs = [all[1].playbackURL()]

        service.play(all[0], in: all)
        service.next()

        XCTAssertEqual(player.loadedURL, all[2].playbackURL(),
                       "Phải nhảy qua bài vắng mặt và phát bài sau nó.")
        XCTAssertEqual(service.queue.count, 3, "Hàng đợi không được cắt bớt.")
    }

    /// **Ca phải chặn vòng lặp vô hạn.** Mọi bài còn lại đều vắng mặt — điều
    /// hoàn toàn bình thường trên một máy vừa đồng bộ xong mà chưa nhập file
    /// nào. Vòng lặp phải dừng hẳn, không quay vòng.
    ///
    /// Bó test treo cứng ở đây thì đó chính là lỗi cần bắt, và nó bắt được vì
    /// vòng lặp có chặn trên `queue.count`.
    func testAQueueOfEntirelyAbsentTracksStopsRatherThanLooping() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        player.failingURLs = Set(all.map { $0.playbackURL() })

        service.play(all[0], in: all)

        XCTAssertFalse(service.isPlaying, "Không mở được bài nào thì phải dừng.")
    }

    /// Cùng ca trên nhưng có repeat bật. `loadCurrentAndPlay()` quay về đầu
    /// hàng đợi khi hết, nên đây là đường dễ lặp vô hạn nhất — và nó vẫn dừng
    /// vì mỗi lần thử đều tăng bộ đếm, kể cả lần quay vòng.
    ///
    /// `repeatMode` chỉ đọc được từ ngoài (`private(set)`); cách duy nhất để
    /// bật nó là `cycleRepeatMode()`, đi từ `.off` sang `.all` sau đúng một
    /// lần gọi — xem `PlaybackServiceRepeatTests.testCycleRunsOffAllOneOff`.
    func testRepeatAllDoesNotLoopForeverOverAbsentTracks() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)
        service.cycleRepeatMode()  // .all
        player.failingURLs = Set(all.map { $0.playbackURL() })

        service.next()

        XCTAssertFalse(service.isPlaying)
    }
}
