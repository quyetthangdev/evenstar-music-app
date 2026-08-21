import Foundation
import SwiftData
import OSLog

/// Dọn những hàng trùng mà CloudKit sinh ra khi hai máy cùng lưu một thứ trong
/// lúc ngoại tuyến.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO CHỈ HAI BẢNG
/// ─────────────────────────────────────────────────────────────────────────
/// Quét `DriveTrack` và `JamendoTrack`. **Không** quét `Track`, **không** quét
/// `DriveFolder`, và cả hai chỗ loại trừ đều là quyết định có lý do riêng.
///
/// **`Track`.** `ImportService` dựng `relativePath = "Music/\(id.uuidString).\(ext)"`
/// — đường dẫn chứa `id` của chính hàng ấy, nên hai máy nhập cùng một file sinh
/// hai đường dẫn khác nhau. Nó không phải khoá tự nhiên, nó là khoá riêng của
/// máy. Đổi sang khoá tên+nghệ sĩ+thời lượng còn tệ hơn: gộp xong, hàng sống sót
/// giữ **một** `relativePath`, và máy không phải chủ đường dẫn đó vẫn còn file
/// thật trên đĩa nhưng không còn hàng nào trỏ tới. Mất quyền phát một bài mình
/// đang có, để đổi lấy một danh sách gọn hơn — không đáng.
///
/// Hai hàng `Track` cùng tên trên hai máy **không phải trùng lặp**. Chúng là hai
/// file thật ở hai chỗ thật, và `TrackPresence` làm hàng của máy kia mờ đi để
/// người dùng thấy đúng sự thật đó.
///
/// **`DriveFolder`.** Nó không có trường nào phân biệt được hai hàng cùng
/// `folderID` — không `id`, không bộ đếm. Không có tiêu chí cắt hoà tất định thì
/// hai máy có thể chọn giữ hai hàng khác nhau, mỗi máy xoá hàng kia, và cả hai
/// lệnh xoá cùng đồng bộ lên: **mất sạch**. Một hàng thừa là chuyện thẩm mỹ.
///
/// ─────────────────────────────────────────────────────────────────────────
/// KHI NÀO CHẠY
/// ─────────────────────────────────────────────────────────────────────────
/// Một lượt lúc khởi động, từ `EvenstarApp`, **trước**
/// `PlaybackService.restoreFromPersistedState()` và tuần tự trong cùng một
/// `.task` với nó. Thứ tự ấy là bắt buộc; lý do đầy đủ ở ngay chỗ gọi.
///
/// Nghĩa là hàng trùng đến trong phiên này chỉ được dọn ở **lần mở app sau**,
/// và đó là đánh đổi có chủ ý: bám theo
/// `NSPersistentStoreRemoteChange` thì dọn sớm hơn nhưng thêm một luồng sự kiện
/// bắn liên tục vào một thao tác có xoá hàng. Hàng trùng nằm lại thêm một phiên
/// là chuyện chịu được.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO LƯỢT QUÉT PHẢI BÁO TRƯỚC KHI XOÁ
/// ─────────────────────────────────────────────────────────────────────────
/// Đây từng là **đường xoá duy nhất trong app không đi qua
/// `onTrackWillBeDeleted`**. `LibraryService`, `DriveLibraryService` và
/// `JamendoLibraryService` đều có cái móc ấy, và cả ba doc comment đều ghi cùng
/// một lý do: `PlaybackService.queue` và `currentTrack` giữ hàng của chúng
/// **mạnh**, nên xoá-rồi-lưu sau lưng chúng để lại một `PersistentModel` chết
/// trong hàng đợi; lần đọc thuộc tính kế tiếp — nhịp ghi lượt nghe 30 giây,
/// lượt ghi `queue.map(\.id)` ≤5s, hay một cú chạm Next — ném
/// `NSObjectInaccessibleException`, ngoại lệ Objective-C mà Swift không bắt
/// được.
///
/// Ca thật, không phải giả định — và nay đã bị chặn ở chỗ gọi: có một thời
/// `.task` của `RootView` khôi phục hàng đợi đã lưu **song song** với `.task`
/// của `EvenstarApp` chạy lượt quét này, mà SwiftUI không xếp thứ tự hai cái
/// đó. Khôi phục xong trước thì hàng đợi trong bộ nhớ đang giữ đúng hàng mà
/// lượt quét sắp xoá. Giờ hai việc chạy tuần tự trong một `.task`, quét trước
/// khôi phục sau, nên lúc lượt quét chạy thì hàng đợi vẫn còn rỗng.
///
/// Cái báo trước vì thế **vẫn giữ nhưng đã thành dây bảo hiểm**, không còn là
/// thứ đứng chắn duy nhất: nó bảo vệ mọi chỗ gọi tương lai chạy lượt quét khi
/// hàng đợi đã có bài — một lượt quét theo `NSPersistentStoreRemoteChange`
/// chẳng hạn, thứ mục "KHI NÀO CHẠY" bên trên để ngỏ. Đừng bỏ nó đi vì "đã có
/// thứ tự rồi": thứ tự chỉ đúng cho đúng một chỗ gọi.
///
/// Hỏng thứ hai, không cần crash nào: `PlaybackService` ghi lại các `id`
/// **trong bộ nhớ** ở nhịp ghi tiết chế kế tiếp, đè lên `PlaybackState` mà lượt
/// quét vừa trỏ lại — huỷ sạch việc trỏ lại. Báo trước làm hàng chết rời khỏi
/// hàng đợi trong bộ nhớ, nên lượt ghi đè sau đó là một trạng thái nhất quán
/// chứ không phải một trạng thái cũ.
///
/// Cái báo trước **không** làm: nó không chèn hàng sống sót vào chỗ hàng bị
/// xoá. Hàng đợi trong bộ nhớ mất bài ấy cho tới lần dựng hàng đợi sau. Đó là
/// đánh đổi có chủ ý — mất một bài khỏi hàng đợi là chuyện chịu được, đọc một
/// hàng đã chết thì không — và nó cùng hướng với bước khử trùng lặp bên dưới.
///
/// ─────────────────────────────────────────────────────────────────────────
/// LƯỢT `save()` Ở CUỐI **KHÔNG CÒN** LÀ MỘT GIAO DỊCH
/// ─────────────────────────────────────────────────────────────────────────
/// Từ khi app tách làm hai kho (xem `EvenstarStores`), một lời gọi
/// `context.save()` duy nhất ở cuối `run(context:)` chạm vào **hai** file kho:
/// những lượt `delete` nằm ở `default.store`, còn `PlaybackState` được trỏ lại
/// nằm ở `Playback.store`. Core Data phát **một lệnh lưu cho mỗi kho** và
/// không có commit hai pha bắc qua chúng. Trước khi tách, cả hai nửa nằm gọn
/// trong một giao dịch SQLite; nay thì không, và không có gì ở chỗ gọi nói ra
/// chuyện đó.
///
/// Nghĩa là một lỗi giữa chừng — đĩa đầy, SQLite hỏng — có thể để lại **một
/// nửa**: hàng trùng đã xoá mà `state.queueTrackIDs` vẫn trỏ vào những `UUID`
/// vừa chết, hoặc ngược lại, `PlaybackState` đã trỏ lại mà hàng trùng vẫn còn.
///
/// Vẫn chịu được, và đây là hai cơ chế tự chữa, mỗi cơ chế lo một nửa:
///
/// - **Nửa "id trỏ vào hàng đã chết"**: `restoreFromPersistedState` dựng lại
///   hàng đợi bằng `compactMap { resolveTrack(byID:) }`, nên một `id` không
///   phân giải được chỉ đơn giản rơi ra khỏi hàng đợi khôi phục, và
///   `queueIndex` được kẹp vào khoảng còn sống. Không có đường nào từ đó tới
///   một hàng đã chết trong bộ nhớ.
/// - **Nửa "hàng trùng còn nguyên"**: lượt quét là tất định và chạy lại mỗi
///   lần mở app. Lần mở sau gặp đúng nhóm trùng ấy, chọn đúng hàng giữ lại như
///   lần trước (xem `DuplicateMerge`), và làm nốt.
///
/// Nên chỗ này cố tình **không** có commit hai pha: giá của nó là một máy trạng
/// thái cho một ca mà hai đường trên đã dọn sạch trong vòng một lần mở app.
/// Nhưng đừng thêm việc gì vào `run(context:)` mà dựa vào chuyện hai kho lưu
/// được-ăn-cả-ngã-về-không — cái bảo đảm ấy không còn nữa.
@MainActor
enum DuplicateSweep {

    /// Trả về số hàng đã xoá.
    ///
    /// - Parameter onRowWillBeDeleted: gọi với **từng** hàng sắp bị xoá, trong
    ///   lúc hàng còn đọc được — trước `context.delete(_:)` và trước `save()`.
    ///   Cùng hợp đồng với `LibraryService.onTrackWillBeDeleted` và hai bản sao
    ///   của nó ở `DriveLibraryService`/`JamendoLibraryService`; xem ghi chú ở
    ///   đầu kiểu về chuyện gì xảy ra khi không có nó. `EvenstarApp` nối nó vào
    ///   `PlaybackService.handleTrackDeleted`.
    ///
    ///   Tuỳ chọn, và mặc định `nil`, chỉ để test gọi được mà không phải dựng
    ///   `PlaybackService`. Ở bản chạy thật nó **luôn** được truyền.
    @discardableResult
    static func run(
        context: ModelContext,
        onRowWillBeDeleted: (@MainActor (any Playable) -> Void)? = nil
    ) throws -> Int {
        var repointing: [UUID: UUID] = [:]

        repointing.merge(try sweep(
            DriveTrack.self, in: context,
            key: { $0.fileID },
            candidate: { MergeCandidate(id: $0.id, dateAdded: $0.dateAdded,
                                        playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt) },
            apply: { row, merged in
                row.playCount = merged.playCount
                row.lastPlayedAt = merged.lastPlayedAt
            },
            willDelete: { row in onRowWillBeDeleted?(row) }
        )) { existing, _ in existing }

        repointing.merge(try sweep(
            JamendoTrack.self, in: context,
            key: { $0.jamendoID },
            candidate: { MergeCandidate(id: $0.id, dateAdded: $0.dateAdded,
                                        playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt) },
            apply: { row, merged in
                row.playCount = merged.playCount
                row.lastPlayedAt = merged.lastPlayedAt
            },
            willDelete: { row in
                onRowWillBeDeleted?(row)
                // Hàng gộp đi mang theo file bìa `save` đã tải về. Không dọn ở
                // đây thì mỗi hàng `JamendoTrack` bị gộp để lại vĩnh viễn một
                // JPEG không còn gì trỏ tới — cùng cái rò rỉ mà
                // `JamendoLibraryService.unsave` được viết ra để chặn, và đó
                // là lý do hàm dọn ấy đã được tách ra thành `static`.
                JamendoLibraryService.removeDownloadedArtwork(for: row)
            }
        )) { existing, _ in existing }

        guard !repointing.isEmpty else { return 0 }

        // Fetch thẳng chứ không qua `LibraryService.playbackState`: cái đó tạo
        // một hàng mới khi chưa có, và một lượt dọn dẹp không có việc gì phải
        // tạo trạng thái phát cho một người chưa từng bấm play.
        if let state = try context.fetch(FetchDescriptor<PlaybackState>()).first {
            state.currentTrackID = DuplicateMerge.repointing(state.currentTrackID, through: repointing)
            // Trỏ lại **rồi** khử trùng lặp, và bước thứ hai là bắt buộc chứ
            // không phải dọn dẹp cho gọn. Nếu cả hàng bị xoá lẫn hàng được giữ
            // đều đang trong hàng đợi, trỏ lại làm cùng một `id` nằm hai chỗ —
            // và `QueuePanel.upcomingList` dựng
            // `Dictionary(uniqueKeysWithValues:)` từ đúng mảng ấy, một khởi
            // tạo **trap** khi khoá lặp. Xem `DuplicateMerge.repointing` về
            // quyết định này và về việc nó đảo lại điều gì.
            //
            // `queueIndex` đi cùng mảng trong một lời gọi chứ không được để
            // nguyên: mảng ngắn đi thì một chỉ số giữ nguyên trỏ sang **bài
            // khác**. `deduplicating(_:index:)` ánh xạ cả hai cùng lúc.
            let queue = DuplicateMerge.deduplicating(
                DuplicateMerge.repointing(state.queueTrackIDs, through: repointing),
                index: state.queueIndex
            )
            state.queueTrackIDs = queue.ids
            state.queueIndex = queue.index
            // Không có chỉ số riêng — `unshuffledQueue` chỉ là thứ tự để quay
            // về khi tắt trộn bài. Khử theo cùng quy tắc "giữ lần đầu" thì hai
            // mảng vẫn là hoán vị của nhau, đúng cái bất biến mà
            // `PlaybackService.restoreFromPersistedState` dựa vào.
            state.unshuffledQueueTrackIDs = DuplicateMerge.deduplicating(
                DuplicateMerge.repointing(state.unshuffledQueueTrackIDs, through: repointing)
            )
        }

        // **Một lời gọi, hai kho, không phải một giao dịch.** Lượt xoá nằm ở
        // `default.store`, `PlaybackState` vừa sửa ở trên nằm ở
        // `Playback.store`. Xem mục cuối trong ghi chú ở đầu kiểu về chuyện gì
        // xảy ra khi chỉ một nửa lưu được, và hai cơ chế dọn nó.
        try context.save()
        AppLog.library.info("Gộp trùng: xoá \(repointing.count, privacy: .public) hàng.")
        return repointing.count
    }

    /// Trả về ánh xạ `id bị xoá → id được giữ`, thứ mà `PlaybackState` cần để
    /// trỏ lại.
    /// - Parameter willDelete: chạy với hàng sắp bị xoá, **trước**
    ///   `context.delete(_:)`. Nằm ngay sát lệnh xoá, trong cùng một nhánh
    ///   `else`, chứ không phải một lượt duyệt riêng phía trước: như thế không
    ///   có cách nào sửa file này mà xoá được một hàng chưa báo.
    private static func sweep<M: PersistentModel>(
        _ type: M.Type,
        in context: ModelContext,
        key: (M) -> String,
        candidate: (M) -> MergeCandidate,
        apply: (M, GroupMerge) -> Void,
        willDelete: (M) -> Void
    ) throws -> [UUID: UUID] {
        let rows = try context.fetch(FetchDescriptor<M>())
        var groups: [String: [M]] = [:]
        for row in rows { groups[key(row), default: []].append(row) }

        var repointing: [UUID: UUID] = [:]
        for group in groups.values where group.count > 1 {
            // Thứ tự `group` phụ thuộc thứ tự fetch, và thứ tự duyệt `groups`
            // phụ thuộc `Dictionary`. Cả hai đều không sao: `DuplicateMerge.merge`
            // tự sắp xếp, nên kết quả không phụ thuộc thứ tự đầu vào. Đó là
            // điều kiện để hai máy không xoá mất của nhau — xem `DuplicateMerge`.
            guard let merged = DuplicateMerge.merge(group.map(candidate)) else { continue }
            for row in group {
                let id = candidate(row).id
                if id == merged.keepID {
                    apply(row, merged)
                } else {
                    repointing[id] = merged.keepID
                    willDelete(row)
                    context.delete(row)
                }
            }
        }
        return repointing
    }
}
