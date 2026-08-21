import Foundation
import SwiftData

/// Hai kho dữ liệu của app, và ranh giới giữa chúng: **cái nào đi theo Apple
/// Account, cái nào ở lại từng máy.**
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO HAI CẤU HÌNH CHỨ KHÔNG MỘT
/// ─────────────────────────────────────────────────────────────────────────
/// CloudKit bật/tắt theo **kho**, không theo bảng: một `ModelConfiguration` là
/// một file `.store`, và cả file ấy hoặc đồng bộ hoặc không. Muốn bốn bảng đi
/// theo tài khoản còn `PlaybackState` ở lại máy thì không có cách nào khác
/// ngoài tách làm hai kho trong cùng một `ModelContainer`.
///
/// Bản thiết kế đầu định cho `PlaybackState` đồng bộ luôn. Sửa ngày 2026-08-21,
/// và đây là lý do: `PlaybackState` **không có khoá tự nhiên** — không
/// `fileID`, không `jamendoID`, không gì phân biệt được hai hàng — nên nó sẽ
/// nhân đôi qua CloudKit đúng như mọi bảng khác, mà `DuplicateSweep` lại không
/// có tiêu chí cắt hoà tất định nào để gộp nó. Trong khi đó
/// `LibraryService.playbackState` lấy `.first` của một lượt fetch **không thứ
/// tự**. Hệ quả: máy nào khôi phục hàng đợi nào có thể lật giữa các lần mở app,
/// và hai hàng ghi đè vị trí của nhau.
///
/// Nó là trạng thái của từng máy, đúng nghĩa như "file có trên máy này" — nên
/// nó ở lại từng máy. Giá phải trả: nghe dở nửa bài trên iPhone thì mở iPad
/// phải tự tìm lại.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO KHO THƯ VIỆN KHÔNG CÓ TÊN
/// ─────────────────────────────────────────────────────────────────────────
/// Tên của một `ModelConfiguration` **là tên file kho**. Bản chưa bật CloudKit
/// dùng một cấu hình mặc định duy nhất, nên thư viện của người dùng đang nằm
/// trong `default.store`. Đặt tên cho cấu hình thư viện ở đây sẽ trỏ nó sang
/// một file mới và bỏ lại toàn bộ thư viện cũ — không mất trên đĩa, nhưng biến
/// mất khỏi app, thứ người dùng không phân biệt được. Nên cấu hình thư viện
/// **giữ nguyên tên mặc định**, và kho mới là kho của `PlaybackState`.
///
/// Cái mất một lần, có chủ ý: hàng `PlaybackState` cũ nằm trong `default.store`
/// không đi theo sang kho mới. Mất **cả hàng**, không chỉ hàng đợi — nói cho
/// đủ, vì đọc lướt sẽ tưởng chỉ hàng đợi đi còn cài đặt ở lại:
///
/// - `queueTrackIDs`, `unshuffledQueueTrackIDs`, `currentTrackID`,
///   `queueIndex`, `positionSeconds` — hàng đợi và chỗ đang nghe dở.
/// - `repeatModeRaw`, `isShuffled`, `isAutoplay` — **ba cài đặt** về mặc định.
///   Người bật repeat-all và autoplay mở app sau nâng cấp thấy cả hai tắt, im
///   lặng, không có thông báo nào.
///
/// Chỗ này dễ đọc thành mâu thuẫn nên nói luôn:
/// `restoreFromPersistedState` cố tình đọc `repeatMode`, `isShuffled` và
/// `isAutoplay` **phía trên** cái guard hàng-đợi-rỗng của nó, đúng để ba thứ ấy
/// sống sót qua một trạng thái rỗng — mà rỗng chính là thứ một `Playback.store`
/// mới toanh sinh ra. Cơ chế giữ chúng nằm sẵn ở đó; thứ vô hiệu hoá nó là bản
/// thân **hàng** nằm ở kho kia, nên chẳng có gì để đọc.
///
/// Vẫn chấp nhận được — ba cài đặt bật lại bằng ba cú chạm — và đổi lại là
/// không phải viết một `SchemaMigrationPlan` chép hàng giữa hai kho cho một thứ
/// vốn sẽ được ghi đè ngay lần bấm play kế tiếp. Nhưng nếu ai đó quyết định ba
/// cài đặt kia đáng giữ, đây là chỗ ghi vì sao chúng mất.
///
/// ─────────────────────────────────────────────────────────────────────────
/// SỬA TÊN CONTAINER THÌ PHẢI SỬA Ở HAI CHỖ
/// ─────────────────────────────────────────────────────────────────────────
/// `.private(_:)` chứ không `.automatic`: `.automatic` chọn container theo
/// entitlement, thứ đọc được từ file nhưng không đọc được từ đây. Viết thẳng
/// tên ra làm một cấu hình sai thành lỗi lúc chạy ngay lần đầu, thay vì thành
/// một app âm thầm đồng bộ vào nhầm chỗ.
///
/// Đổi tên này thì phải đổi cả trong Signing & Capabilities của target
/// (`Evenstar.entitlements`), và phải Deploy Schema to Production lại.
/// `EvenstarStoresTests.testCloudKitContainerIdentifierKhopEntitlements` ghim
/// hai chỗ ấy vào nhau.
///
/// ─────────────────────────────────────────────────────────────────────────
/// HỆ QUẢ LÊN BÓ TEST
/// ─────────────────────────────────────────────────────────────────────────
/// Việc tách kho **rò ra ngoài tiến trình**, và nó đã làm đỏ 40+ test trước khi
/// được xử lý. `NSManagedObjectModel` được lưu đệm theo tiến trình, và app host
/// của bó test chạy `EvenstarApp.init()` trước mọi test — nên mô hình năm entity
/// trong tiến trình ấy mang sẵn hai *configuration* của Core Data. Một
/// `ModelContainer` dựng sau đó bằng **một** cấu hình trên cùng năm model sẽ
/// thêm một kho cho configuration mặc định, thứ không còn chứa `PlaybackState`,
/// và lượt `insert` đầu tiên ném `NSInvalidArgumentException`.
///
/// Nên mọi container trong bó test đi qua `InMemoryLibrary.makeContainer()`,
/// nơi dựng lại đúng hình dạng hai kho. Đừng viết `ModelConfiguration` một mình
/// trong một test mới; xem ghi chú ở `InMemoryLibrary`.
enum EvenstarStores {

    /// Container CloudKit, viết y hệt chuỗi trong `Evenstar.entitlements`.
    static let cloudKitContainerIdentifier = "iCloud.com.evenstar.app"

    /// Bốn bảng đi theo Apple Account.
    ///
    /// Cả bốn đã được làm hợp lệ với CloudKit ở các task trước — không
    /// `@Attribute(.unique)`, mọi thuộc tính lưu trữ có mặc định hoặc optional
    /// — và `ModelCloudKitConformanceTests` giữ nguyên trạng ấy.
    static let syncedModels: [any PersistentModel.Type] = [
        Track.self, DriveTrack.self, JamendoTrack.self, DriveFolder.self,
    ]

    /// Bảng ở lại từng máy. Xem ghi chú ở đầu kiểu.
    static let localOnlyModels: [any PersistentModel.Type] = [
        PlaybackState.self,
    ]

    /// Tên — tức tên file — của kho cục bộ. Kho thư viện không có tên, xem ghi
    /// chú ở đầu kiểu.
    static let localStoreName = "Playback"

    /// Kho thư viện: bốn bảng, có CloudKit, ở `default.store`.
    static func syncedConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            schema: Schema(syncedModels),
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
    }

    /// Kho trạng thái phát: một bảng, **không** CloudKit, ở `Playback.store`.
    ///
    /// `.none` chứ không để mặc định `.automatic`: mặc định sẽ nhìn thấy
    /// entitlement iCloud của target và bật đồng bộ cho kho này luôn, đúng thứ
    /// cả file này tồn tại để chặn.
    static func localOnlyConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            localStoreName,
            schema: Schema(localOnlyModels),
            cloudKitDatabase: .none
        )
    }

    /// Container thật của app. Một container, hai kho.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(syncedModels + localOnlyModels),
            configurations: syncedConfiguration(), localOnlyConfiguration()
        )
    }
}
