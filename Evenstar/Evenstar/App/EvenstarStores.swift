import Foundation
import SwiftData
import OSLog

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
    /// Đang chạy dưới XCTest.
    ///
    /// `XCTestConfigurationFilePath` do chính XCTest đặt vào môi trường tiến
    /// trình trước khi bất cứ mã nào của app chạy, nên nó đúng ngay từ `init()`
    /// — sớm hơn mọi cờ mà app tự dựng được.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Cấu hình kho thư viện.
    ///
    /// Tham số `cloudKit` mặc định `true` vì đây là **sự thật của bản chạy
    /// thật**, và test đọc hàm này để kiểm đúng điều đó — `testChiKhoThuVienKhai
    /// CloudKit` sẽ vô nghĩa nếu hàm tự tắt CloudKit khi thấy mình đang bị test.
    /// Chỗ quyết định tắt nằm ở `load(cloudKit:)`, nơi container thật được dựng.
    static func syncedConfiguration(cloudKit: Bool = true) -> ModelConfiguration {
        ModelConfiguration(
            schema: Schema(syncedModels),
            cloudKitDatabase: cloudKit ? .private(cloudKitContainerIdentifier) : .none
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

    // MARK: - Mở kho

    /// Ba mức mà app chấp nhận mở kho ở đó, từ đủ nhất xuống mức chống sập.
    ///
    /// Trước bản này chỉ có một mức: hoặc mở được kho, hoặc
    /// `EvenstarApp.init()` gọi `fatalError`. Nghĩa là container iCloud chưa
    /// gán cho App ID, một lượt migrate SwiftData hỏng trên máy đã có dữ liệu
    /// cũ, hay kho trên đĩa hỏng vì bất cứ lý do nào — đều thành một cú sập ở
    /// màn hình đầu tiên. Máy của người duyệt App Store rơi vào nhóm đầu là
    /// chuyện thường.
    ///
    /// **Cái mà bộ tầng này KHÔNG cứu được:** lược đồ CloudKit chưa đẩy sang
    /// Production. Trường hợp ấy kho nạp bình thường và chỉ lượt mirror thất
    /// bại, bất đồng bộ — người dùng ở lại tầng `synced` với đồng bộ chết lặng,
    /// không tầng nào được kích hoạt. Đó là việc làm bằng tay trước khi nộp,
    /// không phải việc mã lo được; xem `docs/superpowers/audits/
    /// 2026-09-03-truoc-khi-nop.md`.
    enum Tier: String {
        /// CloudKit bật, hai kho trên đĩa. Bình thường.
        case synced
        /// Hai kho trên đĩa, CloudKit tắt. Đồng bộ mất, dữ liệu còn nguyên.
        case localOnly
        /// Không kho nào trên đĩa mở được. Thư viện hiện ra trống và mọi thay
        /// đổi mất khi đóng app — nhưng app **chạy**, và `RootView` nói cho
        /// người dùng biết điều đó thay vì để họ nhập lại cả thư viện.
        case inMemory
    }

    /// Kết quả một lượt mở kho.
    struct Load {
        let container: ModelContainer
        let tier: Tier
        /// Lý do tầng đầu tiên bị bỏ. `nil` khi mở được ngay ở tầng cao nhất
        /// **được phép thử** — nên dưới XCTest, mở ở `localOnly` vẫn là `nil`.
        let downgradeReason: String?
    }

    enum StoreLoadError: Error {
        case allTiersFailed(String)
    }

    /// Hình dạng kho của một tầng, **chưa dựng gì cả**.
    ///
    /// Tách khỏi `container(for:)` vì một lý do: chỗ dễ sai nhất trong cả bản
    /// sửa này là đảo nhầm `cloudKit: true`/`false` giữa hai nhánh `synced` và
    /// `localOnly` — làm thế thì tầng lùi vẫn đòi CloudKit, tức bản sửa mất
    /// sạch tác dụng, mà mọi test tiêm `build` vào `load` vẫn xanh vì chúng
    /// không bao giờ chạy qua đây. Trả về cấu hình thay vì container cho phép
    /// ghim đúng chỗ ấy: dựng một `ModelConfiguration` không mở kho nào trên
    /// đĩa và không chạm CloudKit, nên test đọc được nó mà không gánh cái giá
    /// mà `load(cloudKit:)` tồn tại để tránh.
    static func configurations(for tier: Tier) -> [ModelConfiguration] {
        switch tier {
        case .synced:
            return [syncedConfiguration(cloudKit: true), localOnlyConfiguration()]
        case .localOnly:
            return [syncedConfiguration(cloudKit: false), localOnlyConfiguration()]
        case .inMemory:
            // **Hai cấu hình, không phải một** — và đây là chỗ bản đầu tiên của
            // tầng này đã sai, theo đúng cái bẫy mà ghi chú `HỆ QUẢ LÊN BÓ TEST`
            // ở đầu kiểu mô tả.
            //
            // `NSManagedObjectModel` được lưu đệm theo tiến trình. Tầng này chỉ
            // được với tới sau khi `synced` và `localOnly` đã dựng xong mô hình
            // năm entity mang sẵn **hai** configuration của Core Data — mô hình
            // dựng trước lượt nạp kho, nên nó vẫn nằm trong đệm kể cả khi hai
            // tầng kia hỏng. Một `ModelConfiguration` đơn trên cùng năm model
            // sau đó sẽ thêm một kho cho configuration mặc định, thứ không còn
            // chứa `PlaybackState`, và lượt `insert` đầu tiên ném
            // `NSInvalidArgumentException` — một ngoại lệ ObjC, `try?` không
            // bắt được. Tầng sinh ra để app khỏi sập hoá ra là tầng làm app sập.
            //
            // Hình dạng dưới đây y hệt `InMemoryLibrary.makeContainer()`, thứ
            // cả bó test đứng trên và vì thế đã được chứng minh là chạy được.
            return [ModelConfiguration(schema: Schema(syncedModels),
                                       isStoredInMemoryOnly: true,
                                       cloudKitDatabase: .none),
                    ModelConfiguration(localStoreName,
                                       schema: Schema(localOnlyModels),
                                       isStoredInMemoryOnly: true,
                                       cloudKitDatabase: .none)]
        }
    }

    /// Dựng container cho đúng một tầng. Tách khỏi `load` để `load` kiểm được
    /// mà không chạm CloudKit.
    static func container(for tier: Tier) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(syncedModels + localOnlyModels),
            configurations: configurations(for: tier)
        )
    }

    /// Mở kho ở tầng cao nhất mở được.
    ///
    /// - Parameters:
    ///   - cloudKit: `false` bỏ hẳn tầng `synced`, và **đây không phải chuyện
    ///     dọn tiếng ồn trong log.** App host chạy `EvenstarApp.init()` trong
    ///     mỗi lượt test, nên mỗi lượt test dựng một `NSPersistentCloudKit
    ///     Container` thật. Trên máy chưa đăng nhập iCloud nó chỉ in
    ///     `CKAccountStatusNoAccount` rồi thôi — nhưng trên máy CÓ đăng nhập,
    ///     chạy test là **đẩy lược đồ lên server**, và lược đồ CloudKit chỉ
    ///     thêm được chứ không sửa ngược. Nghĩa là một lượt `xcodebuild test`
    ///     trên máy lập trình viên bất kỳ có thể khoá vĩnh viễn hình dạng dữ
    ///     liệu production — bằng một lược đồ chưa ai duyệt, từ một nhánh chưa
    ///     ai merge. Mặc định vì thế tắt khi `isRunningTests`, và
    ///     `testTatCloudKitThiKhongThuTangDongBo` ghim việc tầng `synced`
    ///     không được chạm tới.
    ///   - build: hàm dựng container cho một tầng. Tồn tại để test tiêm vào —
    ///     tầng `synced` là thứ duy nhất không kiểm được bằng cách nào khác,
    ///     đúng vì lý do vừa nói.
    static func load(
        cloudKit: Bool = !EvenstarStores.isRunningTests,
        build: (Tier) throws -> ModelContainer = EvenstarStores.container(for:)
    ) throws -> Load {
        let tiers: [Tier] = cloudKit ? [.synced, .localOnly, .inMemory] : [.localOnly, .inMemory]
        var firstFailure: String?

        for tier in tiers {
            do {
                let container = try build(tier)
                return Load(container: container, tier: tier, downgradeReason: firstFailure)
            } catch {
                let reason = error.localizedDescription
                if firstFailure == nil { firstFailure = reason }
                AppLog.library.error(
                    "Mở kho ở tầng \(tier.rawValue, privacy: .public) thất bại: \(reason, privacy: .public)"
                )
            }
        }

        throw StoreLoadError.allTiersFailed(firstFailure ?? "không rõ")
    }
}
