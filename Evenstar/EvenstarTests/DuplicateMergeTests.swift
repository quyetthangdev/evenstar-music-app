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

    /// **Test này từng ghim một quyết định đã bị đảo lại.** Nó tên là
    /// `testRepointingDeliberatelyLeavesTheSameTrackTwice` và lý do đi kèm là
    /// "nghe một bài hai lần khó chịu chứ không hỏng". Điều đó sai:
    /// `QueuePanel.upcomingList` dựng `Dictionary(uniqueKeysWithValues:)` từ
    /// đúng mảng ấy và **trap** khi `id` lặp, nên một bài nằm hai chỗ là một cú
    /// crush chắc chắn ngay khi người dùng mở bảng hàng đợi.
    ///
    /// Hành vi của `repointing` **không đổi** — nó vẫn trả về đúng độ dài mảng
    /// đầu vào, vì nó là hàm thuần và đó là hợp đồng đúng cho một phép thay
    /// giá trị. Cái đổi là chỗ khử trùng lặp có tồn tại và ở đâu, và test này
    /// giờ mô tả đúng chuyện đó:
    ///
    ///   - `repointing` **sinh ra** bản trùng (dòng dưới), và
    ///   - `deduplicating(_:index:)` là chỗ bỏ nó đi, `DuplicateSweep` gọi
    ///     ngay sau khi trỏ lại — xem nhóm test tiếp theo.
    ///   - Cửa sổ trước lượt quét đầu tiên do hai chỗ tra tự chịu:
    ///     `QueuePanel` và `DriveLibraryService.scan`.
    func testRepointingProducesTheDuplicateThatDeduplicatingThenRemoves() {
        let gone = UUID(), kept = UUID()
        let repointed = DuplicateMerge.repointing([kept, gone], through: [gone: kept])
        XCTAssertEqual(repointed, [kept, kept],
                       "`repointing` giữ độ dài — bản trùng sinh ra ở đây.")
        XCTAssertEqual(DuplicateMerge.deduplicating(repointed), [kept],
                       "Và bị bỏ ở đây, không phải để nguyên.")
    }

    // MARK: - Khử trùng lặp và ánh xạ chỉ số

    /// Giữ lần xuất hiện **đầu**, và tất định: hai máy chạy lượt quét độc lập
    /// phải ra cùng một hàng đợi.
    func testDeduplicatingKeepsTheFirstOccurrence() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(DuplicateMerge.deduplicating([a, b, a, c, b]), [a, b, c])
        XCTAssertEqual(DuplicateMerge.deduplicating([a, b, c]), [a, b, c])
        XCTAssertEqual(DuplicateMerge.deduplicating([]), [])
    }

    /// **Ca một trong ba: chỉ số nằm TRƯỚC bản trùng bị bỏ.** Không có gì phía
    /// trước nó biến mất, nên nó không được xê dịch.
    func testIndexBeforeTheRemovedDuplicateDoesNotMove() {
        let a = UUID(), b = UUID(), c = UUID()
        let out = DuplicateMerge.deduplicating([a, b, b, c], index: 0)
        XCTAssertEqual(out.ids, [a, b, c])
        XCTAssertEqual(out.index, 0)
        XCTAssertEqual(out.ids[out.index], a, "Vẫn phải là đúng bài cũ.")
    }

    /// **Ca hai: chỉ số nằm ĐÚNG ở bản trùng bị bỏ.** Bài mà nó trỏ vào vẫn còn
    /// trong hàng đợi — ở lần xuất hiện đầu — nên chỉ số lùi về đúng đó, chứ
    /// không kẹp bừa và cũng không trỏ sang bài bên cạnh.
    func testIndexAtTheRemovedDuplicateMovesToTheFirstCopyOfTheSameTrack() {
        let a = UUID(), b = UUID(), c = UUID()
        let out = DuplicateMerge.deduplicating([a, b, b, c], index: 2)
        XCTAssertEqual(out.ids, [a, b, c])
        XCTAssertEqual(out.index, 1)
        XCTAssertEqual(out.ids[out.index], b, "Cùng **bài**, không phải cùng vị trí.")
    }

    /// **Ca ba: chỉ số nằm SAU bản trùng bị bỏ.** Đây là ca mà "để nguyên
    /// `queueIndex`" trỏ sang bài khác — giữ 3 trên mảng đã khử là trỏ ra ngoài
    /// hoặc trỏ vào `c` sai chỗ.
    func testIndexAfterTheRemovedDuplicateShiftsBackByWhatWasRemoved() {
        let a = UUID(), b = UUID(), c = UUID()
        let out = DuplicateMerge.deduplicating([a, b, b, c], index: 3)
        XCTAssertEqual(out.ids, [a, b, c])
        XCTAssertEqual(out.index, 2)
        XCTAssertEqual(out.ids[out.index], c, "Vẫn phải là đúng bài cũ.")
    }

    /// Nhiều bản trùng, rải rác: chỉ số lùi đúng bằng số bản bị bỏ **phía
    /// trước** nó, không phải tổng số bản bị bỏ.
    func testIndexShiftsOnlyByTheDuplicatesRemovedBeforeIt() {
        let a = UUID(), b = UUID(), c = UUID()
        //          0  1  2  3  4  5   → [a, b, c]
        let ids = [a, a, b, c, b, c]
        let out = DuplicateMerge.deduplicating(ids, index: 3)
        XCTAssertEqual(out.ids, [a, b, c])
        XCTAssertEqual(out.index, 2)
        XCTAssertEqual(out.ids[out.index], c)
    }

    /// Không có bản trùng nào thì cả mảng lẫn chỉ số phải đi qua nguyên vẹn —
    /// lượt quét chạy ở **mỗi** lần khởi động, nên đường "không có việc" phải
    /// tuyệt đối vô hại.
    func testNoDuplicatesLeavesBothUntouched() {
        let a = UUID(), b = UUID()
        let out = DuplicateMerge.deduplicating([a, b], index: 1)
        XCTAssertEqual(out.ids, [a, b])
        XCTAssertEqual(out.index, 1)
    }

    /// `PlaybackState` là dữ liệu đã lưu và có thể đến từ một phiên bản app
    /// khác, nên một chỉ số ngoài phạm vi là đầu vào không tin được chứ không
    /// phải một bất biến — kẹp, không trap.
    func testAnOutOfRangeIndexIsClampedRatherThanTrapping() {
        let a = UUID()
        let out = DuplicateMerge.deduplicating([a, a], index: 9)
        XCTAssertEqual(out.ids, [a])
        XCTAssertEqual(out.index, 0)

        // Mảng rỗng không có bản trùng nào, nên nó đi qua nhánh "không có gì
        // bị bỏ" và chỉ số **không** bị đụng vào. Cố ý: hàm này chỉ sửa cái nó
        // vừa làm ngắn đi; kẹp một chỉ số mà nó không làm gì với mảng là việc
        // của `PlaybackService.restoreFromPersistedState`, chỗ đã kẹp sẵn.
        let empty = DuplicateMerge.deduplicating([], index: 3)
        XCTAssertEqual(empty.ids, [])
        XCTAssertEqual(empty.index, 3)
    }
}
