import Foundation

/// Một hàng ứng viên trong lượt gộp trùng — chỉ bốn trường quyết định kết quả.
///
/// Một `struct` chứ không phải chính `@Model`: quy tắc phải test được mà không
/// dựng `ModelContainer` nào, và nó phải chạy y hệt trên bốn bảng khác nhau.
struct MergeCandidate: Equatable {
    let id: UUID
    let dateAdded: Date
    let playCount: Int
    let lastPlayedAt: Date?
}

/// Kết quả gộp một nhóm cùng khoá tự nhiên: giữ hàng nào, xoá hàng nào, và hàng
/// sống sót mang số liệu gì.
struct GroupMerge: Equatable {
    let keepID: UUID
    let removeIDs: [UUID]
    let playCount: Int
    let lastPlayedAt: Date?
}

/// Quy tắc gộp trùng. Toàn bộ là hàm thuần — không `ModelContext`, không I/O,
/// không đồng hồ.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO PHẢI TẤT ĐỊNH, VÀ HẬU QUẢ NẾU KHÔNG
/// ─────────────────────────────────────────────────────────────────────────
/// Lượt gộp chạy **độc lập trên mỗi máy**. Máy A quyết định giữ hàng X, xoá
/// hàng Y, và lệnh xoá ấy đồng bộ lên. Nếu máy B quyết định ngược lại, nó xoá
/// hàng X, và lệnh xoá của B cũng đồng bộ lên — **cả hai hàng biến mất**, và
/// người dùng mất bài chứ không phải mất bản sao.
///
/// Nên không có chỗ nào trong quy tắc này được phép phụ thuộc vào thứ tự đầu
/// vào. Lượt quét gom nhóm bằng `Dictionary`, mà thứ tự duyệt `Dictionary`
/// trong Swift không được bảo đảm — kể cả trong cùng một tiến trình.
enum DuplicateMerge {

    /// Gộp một nhóm hàng cùng khoá tự nhiên về một. `nil` khi không có gì để
    /// gộp, để người gọi phân biệt được với "gộp xong".
    static func merge(_ candidates: [MergeCandidate]) -> GroupMerge? {
        guard candidates.count > 1 else { return nil }

        let ordered = candidates.sorted { lhs, rhs in
            // Ngày vào thư viện trước thì sống sót: đó là hàng "gốc".
            if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded < rhs.dateAdded }
            // Hoà ngày thì cắt bằng `id`, và cắt bằng `id` chứ không phải bằng
            // thứ tự đầu vào chính là chỗ giữ cho hai máy chọn giống nhau. Xem
            // ghi chú ở đầu kiểu.
            return lhs.id.uuidString < rhs.id.uuidString
        }

        let keep = ordered[0]
        return GroupMerge(
            keepID: keep.id,
            removeIDs: ordered.dropFirst().map(\.id),
            // Cộng, không lấy của hàng sống sót: mỗi máy đếm lượt nghe riêng.
            playCount: candidates.reduce(0) { $0 + $1.playCount },
            // `nil` khi chưa máy nào phát — `.max()` trên mảy rỗng trả `nil`,
            // và đó đúng là câu trả lời, không phải `.distantPast`.
            lastPlayedAt: candidates.compactMap(\.lastPlayedAt).max()
        )
    }

    /// Trỏ lại các `UUID` mà `PlaybackState` giữ, sau khi hàng bị gộp đi.
    ///
    /// Bước dễ quên nhất của cả quy tắc. `PlaybackState` giữ thành viên hàng đợi
    /// bằng `UUID` trần, không có `@Relationship` nào nối lại hộ — hai doc
    /// comment ở `DriveTrack` và `JamendoTrack` đã ghi lại đúng lỗi này ở một
    /// hoàn cảnh khác.
    ///
    /// **Hàm này không khử trùng lặp, và một `id` lặp lại KHÔNG phải chuyện vô
    /// hại.** Bản kế hoạch trước đây viết ở đúng chỗ này rằng nghe một bài hai
    /// lần "khó chịu chứ không hỏng". Điều đó **sai**, và nó đã bị đảo lại:
    ///
    ///   - `QueuePanel.upcomingList` dựng `Dictionary(uniqueKeysWithValues:)`
    ///     từ `upcoming.map { ($0.id, $0) }`. Khởi tạo ấy **trap** — `Fatal
    ///     error: Duplicate values for key`, không phải một lỗi ném ra — ngay
    ///     khi người dùng mở bảng hàng đợi.
    ///   - `ReorderableStack(ids:)` nhận cùng mảng `id` ấy và giả định chúng
    ///     duy nhất.
    ///   - `QueuePanel.playUpcoming(_:)` tra bằng `firstIndex(where:)`, nên
    ///     chạm vào bản thứ hai nhảy về bản thứ nhất.
    ///
    /// Đánh đổi đúng là: một chỉ số **có thể** sai đổi lấy một cú crash **chắc
    /// chắn**. Nên việc khử trùng lặp có thật, ở hai tầng, và không tầng nào
    /// nằm trong hàm này:
    ///
    ///   - `deduplicating(_:index:)` ngay bên dưới, `DuplicateSweep` gọi sau
    ///     khi trỏ lại — nó cũng ánh xạ `queueIndex` nên chỉ số vẫn trỏ đúng
    ///     bài cũ.
    ///   - Hai chỗ tra ở trên (`QueuePanel` và
    ///     `DriveLibraryService.scan`) tự chịu được `id`/khoá lặp. Cửa sổ mà
    ///     tầng thứ nhất **không** với tới là lúc chưa lượt quét nào chạy: hai
    ///     hàng trùng lúc ấy đều là hàng thật và đều vẽ ra.
    ///
    /// Bản thân `repointing` giữ nguyên hành vi vì nó là hàm thuần và người gọi
    /// khác có thể cần đúng độ dài mảng đầu vào; chỗ khử nằm ở hàm riêng bên
    /// dưới để `queueIndex` và mảng ids được ánh xạ **cùng nhau**.
    static func repointing(_ ids: [UUID], through map: [UUID: UUID]) -> [UUID] {
        guard !map.isEmpty else { return ids }
        return ids.map { map[$0] ?? $0 }
    }

    /// Bản một-giá-trị của hàm trên, cho `PlaybackState.currentTrackID`.
    static func repointing(_ id: UUID?, through map: [UUID: UUID]) -> UUID? {
        guard let id else { return nil }
        return map[id] ?? id
    }

    /// Một hàng đợi đã khử trùng lặp, kèm chỉ số đã ánh xạ theo.
    ///
    /// Hai giá trị đi cùng nhau trong một kiểu chứ không phải hai lời gọi, và
    /// đó là cả điểm của nó: ánh xạ chỉ số là bước dễ làm sai nhất ở đây, nên
    /// nó không được phép là thứ người gọi có thể quên.
    struct DeduplicatedQueue: Equatable {
        let ids: [UUID]
        let index: Int
    }

    /// Bỏ những `id` lặp lại, **giữ lần xuất hiện đầu**.
    ///
    /// Giữ lần đầu chứ không phải lần cuối vì đó là thứ tất định và không phụ
    /// thuộc gì ngoài chính mảng đầu vào — cùng lý do với mọi quyết định khác
    /// trong kiểu này: hai máy chạy lượt quét độc lập phải ra cùng kết quả.
    static func deduplicating(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>(minimumCapacity: ids.count)
        return ids.filter { seen.insert($0).inserted }
    }

    /// Bản có ánh xạ `queueIndex`, cho `PlaybackState.queueTrackIDs`.
    ///
    /// **Quy tắc: chỉ số phải trỏ vào đúng bài nó đang trỏ vào.** Không phải
    /// "cùng vị trí", mà cùng **bài**. Nên chỉ số mới là vị trí của *lần xuất
    /// hiện đầu tiên* của `ids[index]` trong mảng đã khử — ba ca được ghim
    /// riêng trong `DuplicateMergeTests`:
    ///
    ///   - chỉ số nằm **trước** bản trùng bị bỏ: không xê dịch.
    ///   - chỉ số nằm **đúng** ở bản trùng bị bỏ: lùi về bản đầu tiên của cùng
    ///     bài ấy.
    ///   - chỉ số nằm **sau**: lùi đúng số bản đã bị bỏ phía trước nó.
    ///
    /// Chỉ số ngoài phạm vi được kẹp vào mảng mới thay vì trap — `PlaybackState`
    /// là dữ liệu đã lưu và có thể đến từ một phiên bản app khác, nên nó là dữ
    /// liệu đầu vào không tin được chứ không phải một bất biến.
    static func deduplicating(_ ids: [UUID], index: Int) -> DeduplicatedQueue {
        let deduped = deduplicating(ids)
        guard deduped.count != ids.count else {
            return DeduplicatedQueue(ids: ids, index: index)
        }
        if ids.indices.contains(index),
           let mapped = deduped.firstIndex(of: ids[index]) {
            return DeduplicatedQueue(ids: deduped, index: mapped)
        }
        return DeduplicatedQueue(ids: deduped,
                                 index: min(max(0, index), max(0, deduped.count - 1)))
    }
}
