import XCTest
import SwiftData
@testable import Evenstar

/// Thứ tự danh sách bài hát.
///
/// `TrackSort.apply(to:)` là hàm thuần, nên toàn bộ phần đáng sai của tính năng
/// kiểm được ở đây mà không cần dựng view: bài chưa nghe rơi đúng chỗ, hoà thì
/// vẫn tất định, và mỗi kiểu sắp xếp thật sự sắp theo trường nó nói.
@MainActor
final class TrackSortTests: XCTestCase {
    private func track(_ title: String,
                       artist: String = "Ai đó",
                       added: Date = Date(timeIntervalSince1970: 0),
                       plays: Int = 0,
                       lastPlayed: Date? = nil) -> Track {
        Track(title: title,
              artistName: artist,
              albumTitle: "Đĩa",
              durationSeconds: 100,
              relativePath: "Music/\(UUID().uuidString).mp3",
              format: "mp3",
              dateAdded: added,
              playCount: plays,
              lastPlayedAt: lastPlayed)
    }

    private func titles(_ sort: TrackSort, _ tracks: [Track]) -> [String] {
        sort.apply(to: tracks).map(\.title)
    }

    // MARK: - Tên

    func testTitleSortsAlphabetically() {
        let list = [track("Chiều"), track("Anh"), track("Biển")]
        XCTAssertEqual(titles(.title, list), ["Anh", "Biển", "Chiều"])
    }

    /// So sánh theo kiểu người đọc, không theo mã ký tự.
    ///
    /// `"Ô"` đứng sau `"O"` với người Việt, nhưng đứng rất xa nếu so bằng giá
    /// trị scalar. Đây cũng là kiểu so mà `LibraryStore` đang dùng cho danh sách
    /// mặc định, nên đổi kiểu sắp xếp rồi quay lại phải ra đúng thứ tự cũ.
    func testTitleUsesLocalizedComparison() {
        let list = [track("Ông"), track("Anh"), track("Ơn")]
        XCTAssertEqual(titles(.title, list), ["Anh", "Ơn", "Ông"])
    }

    // MARK: - Mới thêm

    func testDateAddedPutsTheNewestFirst() {
        let list = [
            track("Cũ", added: Date(timeIntervalSince1970: 100)),
            track("Mới", added: Date(timeIntervalSince1970: 300)),
            track("Giữa", added: Date(timeIntervalSince1970: 200)),
        ]
        XCTAssertEqual(titles(.dateAdded, list), ["Mới", "Giữa", "Cũ"])
    }

    // MARK: - Nghe gần đây

    func testLastPlayedPutsTheMostRecentFirst() {
        let list = [
            track("Lâu rồi", lastPlayed: Date(timeIntervalSince1970: 100)),
            track("Vừa xong", lastPlayed: Date(timeIntervalSince1970: 300)),
        ]
        XCTAssertEqual(titles(.lastPlayed, list), ["Vừa xong", "Lâu rồi"])
    }

    /// Bài chưa nghe bao giờ xuống **cuối**, không lên đầu.
    ///
    /// `lastPlayedAt` là `nil` ở đó. Coi `nil` như "rất xa xưa" thì đúng; coi nó
    /// như "chưa có nên xếp trước" thì màn "Nghe gần đây" mở ra toàn bài chưa
    /// nghe bao giờ — đúng ngược nghĩa cái tên nó mang.
    func testNeverPlayedSinkToTheBottomOfRecentlyPlayed() {
        let list = [
            track("Chưa nghe"),
            track("Đã nghe", lastPlayed: Date(timeIntervalSince1970: 100)),
        ]
        XCTAssertEqual(titles(.lastPlayed, list), ["Đã nghe", "Chưa nghe"])
    }

    // MARK: - Nghe nhiều nhất

    func testPlayCountPutsTheMostPlayedFirst() {
        let list = [track("Ít", plays: 2), track("Nhiều", plays: 9), track("Vừa", plays: 5)]
        XCTAssertEqual(titles(.playCount, list), ["Nhiều", "Vừa", "Ít"])
    }

    func testNeverPlayedSinkToTheBottomOfMostPlayed() {
        let list = [track("Chưa nghe", plays: 0), track("Một lần", plays: 1)]
        XCTAssertEqual(titles(.playCount, list), ["Một lần", "Chưa nghe"])
    }

    // MARK: - Hoà

    /// Hoà thì so theo tên, và kết quả phải **giống nhau qua mọi thứ tự đầu vào**.
    ///
    /// Không có chốt này thì mười bài cùng 0 lượt nghe xếp theo thứ tự
    /// `store.tracks` tình cờ đưa tới, và danh sách xáo lại mỗi lần thư viện đổi
    /// — đọc ra như app hỏng chứ không như một thứ tự.
    func testTiesBreakByTitleAndAreStable() {
        let a = track("An", plays: 3)
        let b = track("Bình", plays: 3)
        let c = track("Cường", plays: 3)

        XCTAssertEqual(titles(.playCount, [c, a, b]), ["An", "Bình", "Cường"])
        XCTAssertEqual(titles(.playCount, [b, c, a]), ["An", "Bình", "Cường"])
        XCTAssertEqual(titles(.playCount, [a, b, c]), ["An", "Bình", "Cường"])
    }

    func testTiesInLastPlayedAlsoBreakByTitle() {
        let when = Date(timeIntervalSince1970: 500)
        let a = track("An", lastPlayed: when)
        let b = track("Bình", lastPlayed: when)
        XCTAssertEqual(titles(.lastPlayed, [b, a]), ["An", "Bình"])
    }

    /// Nhiều bài chưa nghe cũng phải tất định, không chỉ nhiều bài đã nghe.
    func testSeveralNeverPlayedKeepATitleOrder() {
        let list = [track("Cường"), track("An"), track("Bình")]
        XCTAssertEqual(titles(.lastPlayed, list), ["An", "Bình", "Cường"])
        XCTAssertEqual(titles(.playCount, list), ["An", "Bình", "Cường"])
    }

    // MARK: - Biên

    func testAnEmptyLibrarySortsToNothing() {
        for sort in TrackSort.allCases {
            XCTAssertEqual(sort.apply(to: []).count, 0, "\(sort)")
        }
    }

    /// Không kiểu nào được làm mất hay nhân đôi bài.
    func testEverySortIsAPermutation() {
        let list = [
            track("An", added: Date(timeIntervalSince1970: 1), plays: 4,
                  lastPlayed: Date(timeIntervalSince1970: 9)),
            track("Bình", added: Date(timeIntervalSince1970: 2)),
            track("Cường", plays: 1),
        ]
        for sort in TrackSort.allCases {
            let out = sort.apply(to: list)
            XCTAssertEqual(Set(out.map(\.id)), Set(list.map(\.id)), "\(sort)")
            XCTAssertEqual(out.count, list.count, "\(sort)")
        }
    }

    /// `title` là mặc định, và phải khớp thứ tự `LibraryStore` vốn đã đưa ra.
    func testTitleIsTheDefault() {
        XCTAssertEqual(TrackSort.default, .title)
    }

    // MARK: - Dòng phụ

    /// `.title` trả `nil` để `SongRow` quay về tên nghệ sĩ.
    func testTitleSortShowsNoSubtitleOfItsOwn() {
        XCTAssertNil(TrackSort.title.subtitle(for: track("A", plays: 5)))
    }

    /// Bài chưa nghe nói **cùng một câu** ở cả hai kiểu sắp theo lượt nghe.
    ///
    /// `playCount == 0` và `lastPlayedAt == nil` là cùng một sự thật nhìn từ hai
    /// phía. Hai câu khác nhau ở hai chỗ là hai chỗ để chúng trôi khỏi nhau.
    func testNeverPlayedReadsTheSameInBothSorts() {
        let never = track("A")
        let byCount = TrackSort.playCount.subtitle(for: never)
        let byRecent = TrackSort.lastPlayed.subtitle(for: never)
        XCTAssertNotNil(byCount)
        XCTAssertEqual(byCount, byRecent)
    }

    /// Đã nghe rồi thì không được đọc ra là chưa nghe.
    ///
    /// Chốt này bắt cú lật ngược `guard`: đổi `> 0` thành `== 0` vẫn biên dịch,
    /// vẫn chạy, và mọi bài đều báo sai — nhưng không test nào khác thấy, vì
    /// thứ tự sắp xếp không đổi.
    func testAPlayedTrackNeverReadsAsNeverPlayed() {
        let played = track("A", plays: 3, lastPlayed: Date(timeIntervalSince1970: 500))
        let never = TrackSort.playCount.subtitle(for: track("B"))
        XCTAssertNotEqual(TrackSort.playCount.subtitle(for: played), never)
        XCTAssertNotEqual(TrackSort.lastPlayed.subtitle(for: played), never)
    }

    /// Con số lượt nghe có mặt trong chữ.
    func testThePlayCountAppearsInItsSubtitle() {
        let subtitle = TrackSort.playCount.subtitle(for: track("A", plays: 12))
        XCTAssertEqual(subtitle?.contains("12"), true, "thấy: \(subtitle ?? "nil")")
    }

    /// Mọi kiểu đều nói được gì đó cho mọi bài — không kiểu nào để trống ngoài
    /// `.title`, thứ cố ý trả `nil`.
    func testEverySortExceptTitleAlwaysSaysSomething() {
        let bare = track("A")
        for sort in TrackSort.allCases where sort != .title {
            XCTAssertNotNil(sort.subtitle(for: bare), "\(sort) để trống")
        }
    }
}
