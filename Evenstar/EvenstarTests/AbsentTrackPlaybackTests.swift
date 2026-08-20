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
    ///
    /// **`isPlaying == false` không đủ.** Một quy hồi tự nhiên — thay `catch`
    /// bằng `stopPlayback(); return` ngay lần thất bại đầu tiên, xoá bộ đếm
    /// `attempts` và cái chặn — cũng dừng ở `isPlaying == false`, vì lần thử
    /// đầu tiên trong hàng đợi này vốn đã thất bại. `loadedURL` cũng không
    /// giúp gì: nó chỉ ghi khi thành công, nên vẫn là `nil` dù vòng lặp thử
    /// một bài hay cả ba. `player.loadAttempts` ghi lại mọi lần gọi
    /// `load(url:)` bất kể thành hay bại, nên đây là thứ duy nhất phân biệt
    /// được "thử cả ba rồi mới dừng" với "thử một rồi dừng".
    func testAQueueOfEntirelyAbsentTracksStopsRatherThanLooping() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        player.failingURLs = Set(all.map { $0.playbackURL() })

        service.play(all[0], in: all)

        XCTAssertFalse(service.isPlaying, "Không mở được bài nào thì phải dừng.")
        XCTAssertEqual(player.loadAttempts, all.map { $0.playbackURL() },
                       "Phải thử đúng cả ba bài, theo đúng thứ tự hàng đợi, trước khi dừng.")
    }

    /// Cùng ca trên nhưng có repeat bật. `loadCurrentAndPlay()` quay về đầu
    /// hàng đợi khi hết, nên đây là đường dễ lặp vô hạn nhất — và nó vẫn dừng
    /// vì mỗi lần thử đều tăng bộ đếm, kể cả lần quay vòng.
    ///
    /// `repeatMode` chỉ đọc được từ ngoài (`private(set)`); cách duy nhất để
    /// bật nó là `cycleRepeatMode()`, đi từ `.off` sang `.all` sau đúng một
    /// lần gọi — xem `PlaybackServiceRepeatTests.testCycleRunsOffAllOneOff`.
    ///
    /// **Cùng điểm mù với test trên, và còn dễ bỏ sót hơn:** dưới quy hồi
    /// "dừng ngay lần thất bại đầu", `next()` thử đúng một bài (`all[1]`) rồi
    /// dừng, và `isPlaying == false` giống hệt kết quả đúng. Chỉ có chuỗi
    /// `loadAttempts` mới lộ ra rằng vòng lặp đúng phải thử hết `all[1]`,
    /// `all[2]`, rồi **quay về `all[0]`** — cái quay vòng chính là thứ một
    /// con số đếm đơn thuần không phân biệt được với ba lần thử xuôi liên
    /// tiếp.
    func testRepeatAllDoesNotLoopForeverOverAbsentTracks() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)
        service.cycleRepeatMode()  // .all
        player.failingURLs = Set(all.map { $0.playbackURL() })
        let attemptsBeforeNext = player.loadAttempts.count

        service.next()

        XCTAssertFalse(service.isPlaying)
        let attemptedDuringNext = Array(player.loadAttempts[attemptsBeforeNext...])
        XCTAssertEqual(attemptedDuringNext, [all[1], all[2], all[0]].map { $0.playbackURL() },
                       "Phải thử all[1], all[2], rồi quay vòng về all[0] trước khi dừng.")
    }
}
