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
    /// **Không khử trùng lặp**, và đó là quyết định. Nếu cả hàng bị xoá lẫn hàng
    /// được giữ đều đang trong hàng đợi thì cùng một bài nằm hai chỗ và phát hai
    /// lần liền. Khử trùng lặp thì phải ánh xạ `queueIndex` sang mảy ngắn hơn,
    /// và một phép ánh xạ sai ở đó làm hàng đợi nhảy sang **bài khác**. Nghe một
    /// bài hai lần là khó chịu; nghe nhầm bài là hỏng.
    static func repointing(_ ids: [UUID], through map: [UUID: UUID]) -> [UUID] {
        guard !map.isEmpty else { return ids }
        return ids.map { map[$0] ?? $0 }
    }

    /// Bản một-giá-trị của hàm trên, cho `PlaybackState.currentTrackID`.
    static func repointing(_ id: UUID?, through map: [UUID: UUID]) -> UUID? {
        guard let id else { return nil }
        return map[id] ?? id
    }
}
