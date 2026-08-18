import XCTest
@testable import Evenstar

/// Autoplay: hết hàng đợi thì nối thêm từ thư viện thay vì dừng.
///
/// Ba câu hỏi, và câu thứ ba mới là câu dễ sai: nó có nối không, nó có **thôi**
/// nối khi không còn gì để nối không, và nó có đứng ngoài những đường đi mà nó
/// không được phép đụng vào không.
@MainActor
final class PlaybackServiceAutoplayTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player,
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        return (service, player, library)
    }

    @discardableResult
    private func tracks(_ count: Int, library: LibraryService, prefix: String = "Track") throws -> [Track] {
        var out: [Track] = []
        for i in 0..<count {
            let t = Track(
                title: "\(prefix) \(i)",
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

    func testAutoplayIsOffUntilToggled() throws {
        let (service, _, _) = try makeStack()

        XCTAssertFalse(service.isAutoplay)
        service.toggleAutoplay()
        XCTAssertTrue(service.isAutoplay)
    }

    /// The point of the feature.
    func testFinishingTheLastTrackAppendsLibraryTracksAndKeepsPlaying() async throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.toggleAutoplay()
        service.play(all[4], in: [all[4]])
        XCTAssertEqual(service.queue.count, 1, "precondition")

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queue.count, 5)
        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertTrue(service.isPlaying)
    }

    /// Không có gì để nối thì dừng như thường. Autoplay là "còn nhạc thì phát
    /// tiếp", không phải "phát lại" — nếu không nó lặng lẽ thành repeat-all.
    func testFinishingWithNothingLeftToAppendStops() async throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(2, library: library)
        service.toggleAutoplay()
        service.play(all[0], in: all)
        service.next()

        player.simulateFinish()
        await Task.yield()

        // `stopPlayback()` xoá hàng đợi — đó là hợp đồng sẵn có, không phải
        // chuyện của autoplay. Nên phép kiểm đúng là "đã dừng hẳn": nếu
        // autoplay có nối được gì thì phát tiếp và cả hai điều dưới đây đều
        // sai.
        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertFalse(service.isPlaying)
    }

    /// Bài đã có trong hàng đợi không được nối lại. Không có phép lọc này thì
    /// mỗi lần hết hàng đợi lại nhân đôi nó.
    func testAppendedTracksExcludeWhatIsAlreadyQueued() async throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(4, library: library)
        service.toggleAutoplay()
        service.play(all[0], in: [all[0], all[1]])
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(Set(service.queue.map(\.id)).count, service.queue.count, "có bài lặp")
        XCTAssertEqual(service.queue.count, 4)
    }

    /// **Next ở bài cuối vẫn là "hết rồi".** Autoplay chỉ có nghĩa cho một lượt
    /// phát không ai trông; một cú bấm là một câu hỏi vừa được đặt, và trả lời
    /// nó bằng cách tự bịa thêm nhạc là trả lời một câu khác.
    func testNextAtTheEndStillStopsEvenWithAutoplayOn() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(4, library: library)
        service.toggleAutoplay()
        service.play(all[0], in: [all[0]])

        service.next()

        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertFalse(service.isPlaying)
    }

    /// `repeatMode` outranks it: cả hai cùng bật thì lặp lại là thứ người dùng
    /// nói rõ hơn về ý muốn.
    func testRepeatAllOutranksAutoplay() async throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(4, library: library)
        service.toggleAutoplay()
        service.play(all[0], in: [all[0], all[1]])
        service.cycleRepeatMode()
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queue.count, 2, "hàng đợi bị nối thêm dù đang lặp")
        XCTAssertEqual(service.queueIndex, 0)
    }

    func testAutoplaySurvivesASaveAndRestore() async throws {
        let library = try InMemoryLibrary.make()
        let first = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        let all = try tracks(2, library: library)
        first.play(all[0], in: all)
        first.toggleAutoplay()

        let second = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await second.restoreFromPersistedState()

        XCTAssertTrue(second.isAutoplay)
    }
}
