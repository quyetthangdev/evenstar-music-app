import XCTest
import SwiftData
@testable import Evenstar

/// Ghim ranh giới hai kho của `EvenstarStores`: bốn bảng thư viện đồng bộ,
/// `PlaybackState` ở lại máy.
///
/// **Không** test nào ở đây dựng container có CloudKit thật — cái đó đòi
/// entitlement iCloud mà bó test không có và không nên có (xem cùng lý do ở
/// `ModelCloudKitConformanceTests`). Chuỗi lập luận thay thế gồm ba mắt, và cả
/// ba đều kiểm được ở đây:
///
/// 1. CloudKit bật/tắt **theo kho**, không theo bảng — đó là hợp đồng của
///    `ModelConfiguration`.
/// 2. `PlaybackState` nằm ở một kho **khác file** với bốn bảng kia, và
///    `testPlaybackStateNamOKhoRiengTrenDia` chứng minh bằng cách đọc lại từng
///    file một.
/// 3. Kho chứa `PlaybackState` khai `cloudKitDatabase: .none`, còn kho thư viện
///    khai `.private(...)` đúng container trong entitlements.
final class EvenstarStoresTests: XCTestCase {

    // MARK: - Lược đồ chia đôi

    func testKhoDongBoKhongChuaPlaybackState() {
        let names = Set(EvenstarStores.syncedConfiguration().schema?.entities.map(\.name) ?? [])
        XCTAssertEqual(names, ["Track", "DriveTrack", "JamendoTrack", "DriveFolder"])
        XCTAssertFalse(names.contains("PlaybackState"))
    }

    func testKhoCucBoChiChuaPlaybackState() {
        let names = Set(EvenstarStores.localOnlyConfiguration().schema?.entities.map(\.name) ?? [])
        XCTAssertEqual(names, ["PlaybackState"])
    }

    /// Hai lược đồ phải **phủ kín và không chồng nhau**. Bỏ sót một model thì
    /// `ModelContainer` dựng được nhưng lượt insert đầu tiên của model ấy không
    /// biết đi kho nào; để nó ở cả hai kho thì cùng một bảng vừa đồng bộ vừa
    /// không.
    func testHaiLuocDoPhuKinVaKhongChongNhau() {
        let synced = Set(EvenstarStores.syncedModels.map { String(describing: $0) })
        let local = Set(EvenstarStores.localOnlyModels.map { String(describing: $0) })
        XCTAssertTrue(synced.isDisjoint(with: local))
        XCTAssertEqual(
            synced.union(local),
            ["Track", "DriveTrack", "JamendoTrack", "DriveFolder", "PlaybackState"]
        )
    }

    // MARK: - CloudKit bật ở đúng một kho

    func testChiKhoThuVienKhaiCloudKit() {
        XCTAssertEqual(
            EvenstarStores.syncedConfiguration().cloudKitContainerIdentifier,
            EvenstarStores.cloudKitContainerIdentifier
        )
        // `nil` là cách `ModelConfiguration` nói `.none`. Nếu dòng này đỏ,
        // `PlaybackState` đang đồng bộ.
        XCTAssertNil(EvenstarStores.localOnlyConfiguration().cloudKitContainerIdentifier)
    }

    /// Tên container trong mã và tên trong entitlements phải khớp. Lệch nhau
    /// không gây lỗi biên dịch và không gây lỗi lúc chạy ở simulator — nó chỉ
    /// làm app đồng bộ vào nhầm chỗ, hoặc không đồng bộ gì cả mà không báo.
    ///
    /// `#filePath` là đường dẫn tuyệt đối lúc biên dịch, cùng thủ thuật
    /// `ModelCloudKitConformanceTests` dùng để với tới cây nguồn thật.
    func testCloudKitContainerIdentifierKhopEntitlements() throws {
        let entitlements = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // EvenstarTests/
            .deletingLastPathComponent()            // Evenstar/ (thư mục dự án)
            .appendingPathComponent("Evenstar/Evenstar.entitlements")
        guard FileManager.default.fileExists(atPath: entitlements.path) else {
            throw XCTSkip("Không tìm thấy Evenstar.entitlements cạnh bó test — bỏ qua.")
        }
        let source = try String(contentsOf: entitlements, encoding: .utf8)
        XCTAssertTrue(
            source.contains("<string>\(EvenstarStores.cloudKitContainerIdentifier)</string>"),
            "Entitlements không khai container \(EvenstarStores.cloudKitContainerIdentifier)"
        )
        XCTAssertTrue(source.contains("CloudKit"), "Entitlements không bật dịch vụ CloudKit")
    }

    // MARK: - Tên file kho

    /// Thư viện của người đã dùng bản chưa bật CloudKit nằm trong
    /// `default.store`, vì bản ấy dựng một `ModelConfiguration` mặc định duy
    /// nhất. Cấu hình thư viện ở đây **không đặt tên** đúng để giữ nguyên file
    /// ấy. Đặt tên cho nó — hay để SwiftData suy ra tên từ lược đồ — sẽ trỏ
    /// sang file mới và bỏ lại toàn bộ thư viện cũ, thứ người dùng đọc thành
    /// "app xoá sạch nhạc của tôi".
    func testKhoThuVienVanLaDefaultStore() {
        XCTAssertEqual(
            EvenstarStores.syncedConfiguration().url.lastPathComponent, "default.store"
        )
        XCTAssertEqual(
            EvenstarStores.localOnlyConfiguration().url.lastPathComponent, "Playback.store"
        )
    }

    // MARK: - Chia kho thật trên đĩa

    /// Dựng đúng hình dạng container của app — hai cấu hình, hai lược đồ rời
    /// nhau — rồi ghi một `Track` và một `PlaybackState`, rồi **mở lại từng
    /// file kho một** để xem hàng nào rơi vào đâu.
    ///
    /// Đây là mắt xích chứng minh `PlaybackState` không đồng bộ: nó không nằm
    /// trong file kho mà CloudKit soi. Cả hai cấu hình ở đây khai `.none` —
    /// bài test là **định tuyến theo lược đồ**, không phải bản thân CloudKit,
    /// và bật CloudKit lên sẽ đòi entitlement.
    func testPlaybackStateNamOKhoRiengTrenDia() throws {
        let dir = try makeTempDirectory()
        let libraryURL = dir.appendingPathComponent("default.store")
        let playbackURL = dir.appendingPathComponent("Playback.store")

        do {
            let container = try ModelContainer(
                for: Schema(EvenstarStores.syncedModels + EvenstarStores.localOnlyModels),
                configurations:
                    ModelConfiguration(schema: Schema(EvenstarStores.syncedModels),
                                       url: libraryURL, cloudKitDatabase: .none),
                    ModelConfiguration(EvenstarStores.localStoreName,
                                       schema: Schema(EvenstarStores.localOnlyModels),
                                       url: playbackURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            context.insert(Track(title: "Bài một", artistName: "A", albumTitle: "B",
                                 durationSeconds: 100, relativePath: "Music/x.mp3",
                                 format: "mp3"))
            context.insert(PlaybackState(queueTrackIDs: [UUID()]))
            try context.save()
        }

        // Kho thư viện: có `Track`, và lược đồ của nó thậm chí không biết
        // `PlaybackState` là gì.
        do {
            let container = try ModelContainer(
                for: Schema(EvenstarStores.syncedModels),
                configurations: ModelConfiguration(schema: Schema(EvenstarStores.syncedModels),
                                                   url: libraryURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetch(FetchDescriptor<Track>()).count, 1)
        }

        // Kho cục bộ: có `PlaybackState`, không có `Track`.
        do {
            let container = try ModelContainer(
                for: Schema(EvenstarStores.localOnlyModels),
                configurations: ModelConfiguration(EvenstarStores.localStoreName,
                                                   schema: Schema(EvenstarStores.localOnlyModels),
                                                   url: playbackURL, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetch(FetchDescriptor<PlaybackState>()).count, 1)
        }
    }

    // MARK: - Đường nâng cấp: không có test, và vì sao

    // Kho `default.store` của người đã dùng bản trước được dựng từ **một** cấu
    // hình chứa cả năm bảng. Bản này mở lại đúng file ấy bằng một lược đồ chỉ
    // còn bốn. Không có test tự động nào cho bước ấy, và đó là giới hạn thật
    // chứ không phải chỗ bỏ quên:
    //
    // `NSManagedObjectModel` được lưu đệm theo tiến trình. App host của bó test
    // chạy `EvenstarApp.init()` trước mọi test, nên mô hình năm entity trong
    // tiến trình này **đã** mang sẵn hai configuration. Không có cách nào dựng
    // lại hình dạng "một cấu hình, năm bảng" ở đây để mà mở lại — mọi container
    // dựng sau đều nhận mô hình đã tách. Xem `InMemoryLibrary` về cùng cái đệm
    // ấy.
    //
    // Bằng chứng thay thế, đã đo trên simulator ngày 2026-08-21: `default.store`
    // do bản một-cấu-hình sinh ra (còn nguyên bảng `ZPLAYBACKSTATE`) được bản
    // hai kho mở lại **không lỗi** — không `fatalError` nào ở `EvenstarApp.init`
    // — và `Playback.store` được tạo mới bên cạnh. Cùng lượt đo ấy cho thấy
    // `default.store` mang 18 bảng metadata `ANSCK*` của CloudKit còn
    // `Playback.store` mang **không** bảng nào, tức chỉ kho thư viện được nhân
    // bản lên mây.

    // MARK: -

    private func makeTempDirectory() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EvenstarStoresTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - Test không được đồng bộ thật

    /// Chốt đang có tác dụng ngay lúc này.
    ///
    /// Nếu `isRunningTests` sai ở đây thì mọi thứ dưới đây vô nghĩa, và nó sai
    /// im lặng — không có gì trong app đỏ lên khi một cờ môi trường đổi tên.
    func testDangChayDuoiTest() {
        XCTAssertTrue(EvenstarStores.isRunningTests,
                      "chính lượt chạy này là một lượt test; nếu cờ nói khác thì cờ hỏng")
    }

    /// Container thật, dựng trong lúc test, **không** khai CloudKit.
    ///
    /// Đây là chỗ đáng canh nhất trong file. App host chạy `EvenstarApp.init()`
    /// mỗi lượt test, nên mỗi lượt test dựng một container thật. Trên máy CÓ
    /// đăng nhập iCloud, một container thật là một lượt đẩy lược đồ lên server —
    /// và lược đồ CloudKit chỉ thêm được, không sửa ngược. Một lượt
    /// `xcodebuild test` không được phép khoá vĩnh viễn hình dạng dữ liệu
    /// production.
    func testContainerDungTrongTestKhongDongBo() {
        XCTAssertNil(
            EvenstarStores.syncedConfiguration(cloudKit: !EvenstarStores.isRunningTests)
                .cloudKitContainerIdentifier,
            "container dựng lúc test phải không có CloudKit"
        )
    }

    /// Nhưng bản chạy thật thì vẫn khai, và đó là mặc định.
    ///
    /// Cặp với test trên: nếu ai đó "sửa" bằng cách cho `syncedConfiguration()`
    /// tự tắt CloudKit khi thấy mình đang bị test, thì test này đỏ — và nó phải
    /// đỏ, vì cách sửa ấy làm `testChiKhoThuVienKhaiCloudKit` mất hết ý nghĩa.
    func testMacDinhVanLaBanChayThat() {
        XCTAssertEqual(
            EvenstarStores.syncedConfiguration().cloudKitContainerIdentifier,
            EvenstarStores.cloudKitContainerIdentifier,
            "mặc định phải mô tả bản chạy thật, bất kể ai đang gọi"
        )
    }
}
