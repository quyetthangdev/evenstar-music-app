import XCTest
@testable import Evenstar

/// Quy tắc gộp hai hàng cùng khoá tự nhiên về một.
///
/// Test quan trọng nhất ở đây là `testTwoDevicesChooseTheSameSurvivorWhenDatesTie`,
/// và nó đáng được đọc trước. Lượt gộp chạy **độc lập trên mỗi máy**: máy A
/// quyết định, xoá hàng thừa, và lệnh xoá ấy đồng bộ lên. Nếu máy B quyết định
/// khác, nó xoá hàng *kia*, và lệnh xoá của B cũng đồng bộ lên — **cả hai hàng
/// biến mất**. Nên quy tắc không được phép phụ thuộc vào thứ tự đầu vào hay vào
/// bất cứ thứ gì khác nhau giữa hai máy.
final class DuplicateMergeTests: XCTestCase {

    private func candidate(
        _ id: UUID = UUID(),
        added: TimeInterval,
        plays: Int = 0,
        lastPlayed: TimeInterval? = nil
    ) -> MergeCandidate {
        MergeCandidate(
            id: id,
            dateAdded: Date(timeIntervalSince1970: added),
            playCount: plays,
            lastPlayedAt: lastPlayed.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// Hàng vào thư viện trước là hàng "gốc"; hàng kia là bản sao sinh sau.
    func testTheOlderRowSurvives() {
        let old = candidate(added: 100)
        let new = candidate(added: 200)
        let merged = DuplicateMerge.merge([new, old])
        XCTAssertEqual(merged?.keepID, old.id)
        XCTAssertEqual(merged?.removeIDs, [new.id])
    }

    /// Mỗi máy đếm lượt nghe riêng, nên tổng mới là con số thật. Giữ số của
    /// hàng sống sót thôi là vứt đi số lần người dùng thực sự đã nghe.
    func testPlayCountsAreSummed() {
        let merged = DuplicateMerge.merge([
            candidate(added: 100, plays: 3),
            candidate(added: 200, plays: 4),
        ])
        XCTAssertEqual(merged?.playCount, 7)
    }

    func testTheLaterLastPlayedWins() {
        let merged = DuplicateMerge.merge([
            candidate(added: 100, lastPlayed: 500),
            candidate(added: 200, lastPlayed: 900),
        ])
        XCTAssertEqual(merged?.lastPlayedAt, Date(timeIntervalSince1970: 900))
    }

    /// `nil` thua mọi ngày, và hai `nil` vẫn là `nil` — không phải `.distantPast`.
    func testNeverPlayedStaysNil() {
        let merged = DuplicateMerge.merge([
            candidate(added: 100),
            candidate(added: 200),
        ])
        XCTAssertNil(merged?.lastPlayedAt)

        let one = DuplicateMerge.merge([
            candidate(added: 100),
            candidate(added: 200, lastPlayed: 700),
        ])
        XCTAssertEqual(one?.lastPlayedAt, Date(timeIntervalSince1970: 700))
    }

    /// **Ca hỏng nặng nhất mà quy tắc này phải chặn.** Hai máy lưu cùng một bài
    /// trong cùng một giây thì `dateAdded` bằng nhau, và không còn gì để so.
    /// Cắt hoà bằng `id` cho kết quả giống nhau trên mọi máy; cắt hoà bằng thứ
    /// tự đầu vào thì máy A xoá hàng X, máy B xoá hàng Y, và người dùng mất cả
    /// hai.
    func testTwoDevicesChooseTheSameSurvivorWhenDatesTie() {
        let a = candidate(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, added: 100)
        let b = candidate(UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!, added: 100)

        // Máy A thấy chúng theo thứ tự này...
        let onDeviceA = DuplicateMerge.merge([a, b])
        // ...máy B thấy ngược lại. Kết quả phải y hệt.
        let onDeviceB = DuplicateMerge.merge([b, a])

        XCTAssertEqual(onDeviceA, onDeviceB)
        XCTAssertEqual(onDeviceA?.keepID, a.id, "id nhỏ hơn sống sót, và đó là quy tắc tất định.")
    }

    /// Bản tổng quát của test trên: thứ tự đầu vào không được đổi kết quả, kể
    /// cả khi ngày không hoà. Lượt quét gom nhóm bằng `Dictionary`, và thứ tự
    /// duyệt `Dictionary` trong Swift không được bảo đảm.
    func testInputOrderNeverChangesTheOutcome() {
        let x = candidate(added: 300, plays: 1, lastPlayed: 400)
        let y = candidate(added: 100, plays: 2, lastPlayed: 800)
        let z = candidate(added: 200, plays: 3)
        XCTAssertEqual(
            DuplicateMerge.merge([x, y, z]),
            DuplicateMerge.merge([z, x, y])
        )
    }

    /// Một hàng không phải trùng lặp. Trả `nil` chứ không trả một `GroupMerge`
    /// rỗng: người gọi phải phân biệt được "không có gì để làm" với "gộp xong".
    func testASingleRowIsNotAMerge() {
        XCTAssertNil(DuplicateMerge.merge([candidate(added: 100)]))
        XCTAssertNil(DuplicateMerge.merge([]))
    }

    /// Ba máy, ba hàng. Một hàng sống, hai hàng đi, và tổng lượt nghe cộng cả ba.
    func testThreeDuplicatesCollapseToOne() {
        let first = candidate(added: 100, plays: 1)
        let second = candidate(added: 200, plays: 2)
        let third = candidate(added: 300, plays: 3)
        let merged = DuplicateMerge.merge([third, first, second])
        XCTAssertEqual(merged?.keepID, first.id)
        XCTAssertEqual(Set(merged?.removeIDs ?? []), [second.id, third.id])
        XCTAssertEqual(merged?.playCount, 6)
    }

    /// `PlaybackState` giữ thành viên hàng đợi bằng `UUID` trần, không có quan
    /// hệ ngược nào nối lại hộ. Đây là bước dễ quên nhất của cả quy tắc, và
    /// quên nó nghĩa là hàng đợi khôi phục xong mất bài trong im lặng.
    func testRepointingReplacesEveryRemovedID() {
        let gone = UUID(), kept = UUID(), untouched = UUID()
        let map = [gone: kept]
        XCTAssertEqual(
            DuplicateMerge.repointing([untouched, gone, untouched], through: map),
            [untouched, kept, untouched]
        )
        XCTAssertEqual(DuplicateMerge.repointing(gone as UUID?, through: map), kept)
        XCTAssertEqual(DuplicateMerge.repointing(untouched as UUID?, through: map), untouched)
        XCTAssertNil(DuplicateMerge.repointing(nil as UUID?, through: map))
    }

    /// Ghim một quyết định, không phải một chỗ sót. Nếu cả hàng bị xoá và hàng
    /// được giữ đều đang nằm trong hàng đợi thì sau khi trỏ lại, cùng một bài
    /// nằm hai chỗ — nó phát hai lần liền.
    ///
    /// Khử trùng lặp thì phải ánh xạ `queueIndex` sang một mảy ngắn hơn, và
    /// một phép ánh xạ sai ở đó làm hàng đợi nhảy sang **bài khác** — hỏng nặng
    /// hơn hẳn cái nó chữa. Nghe một bài hai lần là khó chịu; nghe nhầm bài là
    /// hỏng.
    func testRepointingDeliberatelyLeavesTheSameTrackTwice() {
        let gone = UUID(), kept = UUID()
        XCTAssertEqual(
            DuplicateMerge.repointing([kept, gone], through: [gone: kept]),
            [kept, kept]
        )
    }
}
