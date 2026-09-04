# App Store Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đưa Evenstar qua được lượt duyệt App Store đầu tiên bằng cách bổ sung
bản kê quyền riêng tư, khai báo mã hoá xuất khẩu, và gỡ đường sập-khi-mở-app do
CloudKit.

**Architecture:** Ba nhóm thay đổi độc lập nhau. Hai nhóm đầu là tệp cấu hình
đi kèm test đọc `Bundle.main` để chứng minh chúng thật sự được đóng gói. Nhóm
thứ ba đổi `EvenstarStores.makeContainer()` — hiện ném lỗi và bị `fatalError`
bắt — thành một bộ mở kho theo tầng, hạ dần từ CloudKit xuống đĩa xuống bộ nhớ,
rồi cho `EvenstarApp` dùng nó và báo cho người dùng ở tầng thấp nhất.

**Tech Stack:** SwiftUI, SwiftData + CloudKit, XCTest, Xcode 16 synced folders.

**Spec:** `docs/superpowers/specs/2026-09-03-app-store-readiness.md`

## Global Constraints

- **Không sửa `project.pbxproj` hay bất kỳ `.xcscheme` nào.** Dự án dùng Xcode
  16 synced folders: tệp mới đặt trong `Evenstar/Evenstar/` hoặc
  `Evenstar/EvenstarTests/` được thêm vào target tự động. Nếu một task có vẻ
  cần sửa pbxproj thì task ấy đã sai — dừng lại và báo.
- **Ngôn ngữ nguồn của chuỗi giao diện là tiếng Việt.** `Localizable.xcstrings`
  có `sourceLanguage: vi`. Mọi `Text` mới viết tiếng Việt, rồi bổ sung bản dịch
  `en`.
- **Lệnh test duy nhất chạy được trên máy này**, chạy từ gốc repo
  `/Users/phanquyetthang/evenstar`:

  ```bash
  xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
    -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17 test' \
    -only-testing:EvenstarTests/<TênLớpTest> 2>&1 \
    | grep -E "Test Case|Executed|error:|\*\* TEST"
  ```

  `-configuration Debug` là **bắt buộc**: test action của scheme mặc định chạy
  Release, mà `ENABLE_TESTABILITY` chỉ bật ở Debug, nên thiếu cờ này thì build
  test hỏng với `Unable to find module dependency: 'Evenstar'`.

  `iPhone 17 test` là máy ảo iOS 26 được tạo riêng cho việc này. Deployment
  target là 18.6 còn runtime iOS 18 duy nhất trên máy là 18.5, nên không có máy
  ảo iOS 18 nào chạy được app. Nếu máy ảo biến mất, dựng lại bằng:

  ```bash
  xcrun simctl create "iPhone 17 test" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
    com.apple.CoreSimulator.SimRuntime.iOS-26-0
  ```

- **Tên test viết bằng tiếng Việt không dấu**, theo đúng lệ đang có trong
  `EvenstarTests` — ví dụ `testKhoDongBoKhongChuaPlaybackState`.
- **Commit sau mỗi task.** Nhánh hiện tại là `main`; tạo nhánh
  `app-store-readiness` trước task đầu tiên.

---

### Task 0: Nhánh làm việc

- [ ] **Step 1: Tạo nhánh**

```bash
cd /Users/phanquyetthang/evenstar
git switch -c app-store-readiness
```

- [ ] **Step 2: Xác nhận cây làm việc sạch**

```bash
git status --short
```

Expected: không có dòng nào ngoài các tệp spec/plan chưa commit.

- [ ] **Step 3: Commit spec và plan**

```bash
git add docs/superpowers/specs/2026-09-03-app-store-readiness.md \
        docs/superpowers/plans/2026-09-03-app-store-readiness.md
git commit -m "docs: spec và plan cho lượt nộp App Store đầu tiên"
```

---

### Task 1: Bản kê quyền riêng tư

Spec: S1.

**Files:**
- Create: `Evenstar/Evenstar/PrivacyInfo.xcprivacy`
- Test: `Evenstar/EvenstarTests/PrivacyManifestTests.swift`

**Interfaces:**
- Consumes: không gì.
- Produces: không API Swift nào. Sản phẩm là một tệp resource trong bundle,
  đọc được qua `Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")`.

**Vì sao test đọc `Bundle.main` chứ không đọc thư mục nguồn:** rủi ro thật ở đây
không phải "tệp viết sai" mà là "tệp không được đóng vào bundle". Synced folders
thêm tệp vào target một cách tự động và im lặng; một test đọc đĩa sẽ xanh kể cả
khi bản build không hề chứa manifest. Test target có `TEST_HOST` là `Evenstar.app`,
nên `Bundle.main` bên trong test **chính là bundle của app**.

- [ ] **Step 1: Viết test hỏng**

Tạo `Evenstar/EvenstarTests/PrivacyManifestTests.swift`:

```swift
import XCTest

/// Bản kê quyền riêng tư phải nằm **trong bundle đã dựng**, không chỉ nằm trong
/// thư mục nguồn.
///
/// Dự án dùng Xcode 16 synced folders: một tệp mới được thêm vào target một
/// cách tự động và không có dòng nào trong pbxproj để đọc lại mà xác nhận. Một
/// test đọc `#filePath` sẽ xanh kể cả khi bản build không chứa manifest — đúng
/// thứ hỏng mà nó phải bắt. `TEST_HOST` của bó test này là `Evenstar.app`, nên
/// `Bundle.main` ở đây là bundle của app thật.
final class PrivacyManifestTests: XCTestCase {

    private func loadManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy không được đóng vào bundle của app"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try XCTUnwrap(plist as? [String: Any], "Manifest không phải một dictionary")
    }

    func testManifestNamTrongBundleCuaApp() throws {
        _ = try loadManifest()
    }

    func testKhongTheoDoiVaKhongThuThapDuLieu() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertTrue(collected.isEmpty, "App không thu thập dữ liệu nào; đừng khai thừa")
    }

    /// `@AppStorage` ở `AppTheme`, `AppLanguage`, `JamendoLicencePolicy` và
    /// `RootView` đều đọc/ghi `UserDefaults`, thuộc nhóm API bắt buộc khai lý
    /// do. `CA92.1` là mã cho "chỉ đọc/ghi thiết lập của chính app này".
    func testKhaiLyDoDungUserDefaults() throws {
        let manifest = try loadManifest()
        let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let entry = try XCTUnwrap(
            apis.first { $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults" },
            "Chưa khai NSPrivacyAccessedAPICategoryUserDefaults"
        )
        XCTAssertEqual(entry["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận nó hỏng**

```bash
cd /Users/phanquyetthang/evenstar
xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 test' \
  -only-testing:EvenstarTests/PrivacyManifestTests 2>&1 \
  | grep -E "Test Case|Executed|error:|\*\* TEST"
```

Expected: `** TEST FAILED **`, cả ba test hỏng với
"PrivacyInfo.xcprivacy không được đóng vào bundle của app".

- [ ] **Step 3: Tạo manifest**

Tạo `Evenstar/Evenstar/PrivacyInfo.xcprivacy`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 4: Chạy test, xác nhận nó xanh**

Cùng lệnh ở Step 2. Expected: `** TEST SUCCEEDED **`, ba test chạy.

Nếu vẫn hỏng ở `XCTUnwrap` đầu tiên: synced folder chưa nhặt tệp. **Không sửa
pbxproj.** Xoá thư mục dẫn xuất rồi chạy lại:
`rm -rf /Volumes/Storage/DerivedData/Evenstar-*`. Nếu vẫn hỏng, dừng và báo.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/PrivacyInfo.xcprivacy \
        Evenstar/EvenstarTests/PrivacyManifestTests.swift
git commit -m "feat: khai bản kê quyền riêng tư cho UserDefaults"
```

---

### Task 2: Khai báo mã hoá xuất khẩu

Spec: S2.

**Files:**
- Modify: `Evenstar/Evenstar/Info.plist`
- Test: `Evenstar/EvenstarTests/InfoPlistTests.swift`

**Interfaces:**
- Consumes: không gì.
- Produces: khoá `ITSAppUsesNonExemptEncryption` trong Info.plist của bundle.

- [ ] **Step 1: Viết test hỏng**

Tạo `Evenstar/EvenstarTests/InfoPlistTests.swift`:

```swift
import XCTest

/// Những khoá Info.plist mà App Store Connect đọc, kiểm trên bundle đã dựng.
///
/// `Info.plist` của target không được đóng làm resource — nó là `INFOPLIST_FILE`,
/// và pbxproj liệt nó trong `membershipExceptions`. Bản trong bundle là bản
/// **đã trộn** với mọi build setting `INFOPLIST_KEY_*`, nên đọc `Bundle.main`
/// là cách duy nhất thấy được thứ Apple sẽ thấy.
final class InfoPlistTests: XCTestCase {

    /// Thiếu khoá này thì mỗi build lên App Store Connect đều treo lại chờ trả
    /// lời thủ công câu hỏi tuân thủ xuất khẩu. App không dùng mã hoá riêng nào
    /// ngoài HTTPS của hệ thống, nên `false` là câu trả lời đúng.
    func testKhaiKhongDungMaHoaNgoaiMienTru() throws {
        let value = Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption")
        XCTAssertEqual(value as? Bool, false,
                       "Info.plist thiếu ITSAppUsesNonExemptEncryption = false")
    }

    /// Nền `audio` cho phát nền, `remote-notification` cho push im lặng của
    /// đồng bộ SwiftData qua CloudKit. Khai một nền không dùng tới là lý do bị
    /// từ chối theo mục 2.5.4, nên danh sách này được ghim đúng bằng.
    func testChiKhaiHaiNenThucSuDung() throws {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertEqual(Set(modes ?? []), ["audio", "remote-notification"])
    }
}
```

- [ ] **Step 2: Chạy test, xác nhận nó hỏng**

```bash
cd /Users/phanquyetthang/evenstar
xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 test' \
  -only-testing:EvenstarTests/InfoPlistTests 2>&1 \
  | grep -E "Test Case|Executed|error:|\*\* TEST"
```

Expected: `testKhaiKhongDungMaHoaNgoaiMienTru` hỏng,
`testChiKhaiHaiNenThucSuDung` xanh.

- [ ] **Step 3: Thêm khoá vào Info.plist**

`Evenstar/Evenstar/Info.plist` thành đúng như sau:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
		<string>remote-notification</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 4: Chạy test, xác nhận nó xanh**

Cùng lệnh ở Step 2. Expected: `** TEST SUCCEEDED **`, hai test chạy.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Info.plist Evenstar/EvenstarTests/InfoPlistTests.swift
git commit -m "feat: khai ITSAppUsesNonExemptEncryption để build không treo ở ASC"
```

---

### Task 3: Mở kho theo tầng thay vì sập

Spec: S3, nửa thuộc về `EvenstarStores`.

**Files:**
- Modify: `Evenstar/Evenstar/App/EvenstarStores.swift`
- Test: `Evenstar/EvenstarTests/EvenstarStoresTests.swift` (thêm vào cuối lớp)

**Interfaces:**
- Consumes: `EvenstarStores.syncedModels`, `localOnlyModels`,
  `syncedConfiguration(cloudKit:)`, `localOnlyConfiguration()`,
  `isRunningTests` — tất cả đã có sẵn, không đổi chữ ký.
- Produces, cho Task 4 dùng:
  - `EvenstarStores.Tier` — `enum Tier: String { case synced, localOnly, inMemory }`
  - `EvenstarStores.Load` — `struct Load { let container: ModelContainer; let tier: Tier; let downgradeReason: String? }`
  - `EvenstarStores.container(for tier: Tier) throws -> ModelContainer`
  - `EvenstarStores.load(cloudKit: Bool, build: (Tier) throws -> ModelContainer) throws -> Load`
  - `EvenstarStores.StoreLoadError.allTiersFailed(String)`
  - `makeContainer()` **bị xoá**; Task 4 gỡ chỗ gọi duy nhất của nó.

**Vì sao có tham số `build`:** ba tầng phải kiểm được từng cái một, mà tầng
`synced` dựng một `NSPersistentCloudKitContainer` thật. Tiêm hàm dựng vào là
cách duy nhất kiểm được logic hạ tầng mà không chạm CloudKit — và ghi chú dài
ở đầu `EvenstarStores` giải thích vì sao chạm CloudKit trong test là chuyện
nguy hiểm, không phải chuyện chậm.

- [ ] **Step 1: Viết test hỏng**

Thêm vào cuối lớp `EvenstarStoresTests` trong
`Evenstar/EvenstarTests/EvenstarStoresTests.swift`:

```swift
    // MARK: - Mở kho theo tầng

    /// Một container thật, rẻ, không đĩa và không CloudKit — đủ để `load` có
    /// thứ trả về khi tầng đang thử được coi là mở thành công.
    private func containerGia() throws -> ModelContainer {
        let schema = Schema(EvenstarStores.syncedModels + EvenstarStores.localOnlyModels)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        )
    }

    private struct LoiGia: Error {}

    /// Dựng một hàm `build` chỉ thành công ở những tầng được liệt kê, và ghi
    /// lại thứ tự các tầng đã được thử.
    private func build(
        thanhCongO tangTot: Set<EvenstarStores.Tier>,
        daThu: @escaping (EvenstarStores.Tier) -> Void = { _ in }
    ) -> (EvenstarStores.Tier) throws -> ModelContainer {
        { tier in
            daThu(tier)
            guard tangTot.contains(tier) else { throw LoiGia() }
            return try self.containerGia()
        }
    }

    func testMoDuocTangDongBoThiKhongHaTang() throws {
        var thuTu: [EvenstarStores.Tier] = []
        let load = try EvenstarStores.load(
            cloudKit: true,
            build: build(thanhCongO: [.synced, .localOnly, .inMemory],
                         daThu: { thuTu.append($0) })
        )
        XCTAssertEqual(load.tier, .synced)
        XCTAssertNil(load.downgradeReason)
        XCTAssertEqual(thuTu, [.synced])
    }

    func testCloudKitHongThiHaVeKhoDia() throws {
        var thuTu: [EvenstarStores.Tier] = []
        let load = try EvenstarStores.load(
            cloudKit: true,
            build: build(thanhCongO: [.localOnly, .inMemory],
                         daThu: { thuTu.append($0) })
        )
        XCTAssertEqual(load.tier, .localOnly)
        XCTAssertNotNil(load.downgradeReason, "Phải giữ lại lý do đã bỏ tầng đồng bộ")
        XCTAssertEqual(thuTu, [.synced, .localOnly])
    }

    func testKhoDiaHongThiHaVeBoNho() throws {
        var thuTu: [EvenstarStores.Tier] = []
        let load = try EvenstarStores.load(
            cloudKit: true,
            build: build(thanhCongO: [.inMemory], daThu: { thuTu.append($0) })
        )
        XCTAssertEqual(load.tier, .inMemory)
        XCTAssertNotNil(load.downgradeReason)
        XCTAssertEqual(thuTu, [.synced, .localOnly, .inMemory])
    }

    /// Cả ba tầng hỏng nghĩa là chính lược đồ không dựng nổi. Ném ra, đừng
    /// giả vờ đã mở được kho.
    func testCaBaTangHongThiNem() {
        XCTAssertThrowsError(
            try EvenstarStores.load(cloudKit: true, build: build(thanhCongO: []))
        )
    }

    /// Dưới XCTest, `cloudKit` là `false` và tầng đồng bộ **không được thử**.
    /// Chạm CloudKit trong test là đẩy lược đồ chưa duyệt lên server thật —
    /// xem ghi chú ở đầu `EvenstarStores`.
    func testTatCloudKitThiKhongThuTangDongBo() throws {
        var thuTu: [EvenstarStores.Tier] = []
        let load = try EvenstarStores.load(
            cloudKit: false,
            build: build(thanhCongO: [.localOnly, .inMemory],
                         daThu: { thuTu.append($0) })
        )
        XCTAssertEqual(load.tier, .localOnly)
        XCTAssertNil(load.downgradeReason, "Bỏ qua tầng đồng bộ là chủ ý, không phải một cú hạ tầng")
        XCTAssertEqual(thuTu, [.localOnly], "Tầng đồng bộ không được chạm tới")
    }
```

- [ ] **Step 2: Chạy test, xác nhận nó hỏng**

```bash
cd /Users/phanquyetthang/evenstar
xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 test' \
  -only-testing:EvenstarTests/EvenstarStoresTests 2>&1 \
  | grep -E "Test Case|Executed|error:|\*\* TEST"
```

Expected: build hỏng với "cannot find 'Tier' in scope" / "type 'EvenstarStores'
has no member 'load'". Đó là kiểu hỏng đúng cho bước này.

- [ ] **Step 3: Viết phần cài đặt tối thiểu**

Trong `Evenstar/Evenstar/App/EvenstarStores.swift`, **xoá** `makeContainer()`
(hiện là hàm cuối cùng của enum) và thay bằng khối dưới đây. Giữ nguyên mọi
thứ phía trên nó. Thêm `import OSLog` vào đầu tệp, cạnh `import SwiftData`.

```swift
    // MARK: - Mở kho

    /// Ba mức mà app chấp nhận mở kho ở đó, từ đủ nhất xuống mức chống sập.
    ///
    /// Trước bản này chỉ có một mức: hoặc mở được kho có CloudKit, hoặc
    /// `EvenstarApp.init()` gọi `fatalError`. Nghĩa là lược đồ CloudKit chưa
    /// đẩy sang Production, container iCloud chưa gán cho App ID, hay một lượt
    /// migrate SwiftData hỏng trên máy đã có dữ liệu cũ — cả ba đều thành một
    /// cú sập ở màn hình đầu tiên. Máy của người duyệt App Store rơi vào hai
    /// nhóm đầu là chuyện thường.
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

    /// Dựng container cho đúng một tầng. Tách khỏi `load` để `load` kiểm được
    /// mà không chạm CloudKit.
    static func container(for tier: Tier) throws -> ModelContainer {
        let schema = Schema(syncedModels + localOnlyModels)
        switch tier {
        case .synced:
            return try ModelContainer(
                for: schema,
                configurations: syncedConfiguration(cloudKit: true),
                                localOnlyConfiguration()
            )
        case .localOnly:
            return try ModelContainer(
                for: schema,
                configurations: syncedConfiguration(cloudKit: false),
                                localOnlyConfiguration()
            )
        case .inMemory:
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema,
                                                   isStoredInMemoryOnly: true,
                                                   cloudKitDatabase: .none)
            )
        }
    }

    /// Mở kho ở tầng cao nhất mở được.
    ///
    /// - Parameters:
    ///   - cloudKit: `false` bỏ hẳn tầng `synced`. Mặc định tắt khi đang chạy
    ///     test, vì mỗi lượt test dựng một container thật sẽ **đẩy lược đồ lên
    ///     server** trên máy đã đăng nhập iCloud — xem ghi chú ở đầu kiểu.
    ///   - build: hàm dựng container cho một tầng. Tồn tại để test tiêm vào.
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
```

> **Khối trên có một lỗi, và bản đã ship khác nó.** Nhánh `inMemory` ở đây dùng
> **một** `ModelConfiguration` trên cả năm model — đúng cái bẫy mà ghi chú
> `HỆ QUẢ LÊN BÓ TEST` ở đầu `EvenstarStores` mô tả: mô hình trong đệm tiến
> trình đã mang sẵn hai configuration, nên một cấu hình đơn thêm một kho cho
> configuration mặc định, thứ không còn chứa `PlaybackState`, và lượt `insert`
> đầu tiên ném `NSInvalidArgumentException` — ngoại lệ ObjC, `try?` không bắt
> được. Tầng sinh ra để app khỏi sập hoá ra là tầng làm app sập, và không test
> nào chỉ đọc cấu hình bắt được chuyện đó; lượt review toàn nhánh mới tìm ra.
> Bản đã ship trả về **hai** cấu hình trong bộ nhớ, y hệt hình dạng
> `InMemoryLibrary.makeContainer()`, và `testTangBoNhoGhiDuocPlaybackState`
> ghim nó bằng một lượt `insert` thật.

- [ ] **Step 4: Chạy test, xác nhận nó xanh**

Cùng lệnh ở Step 2. Expected: `** TEST SUCCEEDED **`. Lưu ý build sẽ **vẫn
hỏng** ở `EvenstarApp.swift:33` vì `makeContainer` không còn nữa — sửa ngay
trong bước sau, đừng commit ở đây.

Nếu Step 4 hỏng vì `EvenstarApp.swift`, chuyển thẳng sang Task 4 rồi quay lại
chạy cả hai lớp test cùng lúc. Task 3 và Task 4 chia sẻ một lượt biên dịch;
đây là chỗ duy nhất trong plan mà hai task không tách rời được.

- [ ] **Step 5: Commit cùng Task 4**

Không commit riêng. Xem Task 4 Step 5.

---

### Task 4: `EvenstarApp` dùng bộ mở kho theo tầng

Spec: S3, nửa thuộc về app.

**Files:**
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift:26-37` và dòng `RootView()`
  ở `body` (khoảng dòng 124)

**Interfaces:**
- Consumes: `EvenstarStores.load()`, `EvenstarStores.Load`,
  `EvenstarStores.Tier` từ Task 3.
- Produces, cho Task 5 dùng: `RootView(storeUnavailable: Bool = false)` —
  `EvenstarApp` truyền `true` khi và chỉ khi tầng là `.inMemory`.

- [ ] **Step 1: Thay chỗ gọi `makeContainer`**

Trong `Evenstar/Evenstar/App/EvenstarApp.swift`, thay đoạn từ dòng `init() {`
(dòng 26) tới `modelContainer = container` (dòng 37) bằng khối dưới đây. Khối
này mở đầu bằng một thuộc tính mới, nên nó được chèn vào ngay **trên** `init`,
dưới `private let remoteCommands: RemoteCommandsBridge`.

```swift
    /// Kho đã tụt xuống bộ nhớ tạm: thư viện sẽ hiện ra trống dù dữ liệu trên
    /// máy vẫn còn. `RootView` nói cho người dùng biết — xem `Task 5`.
    private let storeUnavailable: Bool

    init() {
        // Một container, **hai** kho: bốn bảng thư viện đồng bộ qua CloudKit,
        // `PlaybackState` ở lại máy này. Toàn bộ lý lẽ — kể cả vì sao kho thư
        // viện phải giữ tên mặc định — nằm ở `EvenstarStores`.
        //
        // `load()` hạ tầng thay vì ném: một lược đồ CloudKit chưa đẩy sang
        // Production không được phép thành cú sập ở màn hình đầu tiên.
        let load: EvenstarStores.Load
        do {
            load = try EvenstarStores.load()
        } catch {
            // Tới đây nghĩa là cả kho bộ nhớ cũng không dựng nổi, tức chính
            // `Schema` sai — lỗi lập trình, không phải tình huống của người
            // dùng, và `ModelCloudKitConformanceTests` là chỗ bắt nó. Không có
            // container thì không có app.
            fatalError("Không dựng được ModelContainer ở bất kỳ tầng nào: \(error)")
        }
        let container = load.container
        storeUnavailable = load.tier == .inMemory
        modelContainer = container
```

Phần còn lại của `init()` — từ `let libService = LibraryService(...)` trở
xuống — giữ nguyên không đổi một chữ.

- [ ] **Step 2: Truyền cờ xuống `RootView`**

Trong `body`, đổi dòng `RootView()` thành:

```swift
            RootView(storeUnavailable: storeUnavailable)
```

Chưa đổi `RootView` — bước này cố tình để build hỏng, và Task 5 sửa.

- [ ] **Step 3: Xác nhận không còn chỗ nào gọi `makeContainer`**

```bash
cd /Users/phanquyetthang/evenstar
grep -rn "makeContainer" --include='*.swift' Evenstar
```

Expected: không có kết quả nào. Nếu còn, sửa chỗ đó sang `EvenstarStores.load().container`.

- [ ] **Step 4: Chạy test**

Build sẽ hỏng ở `RootView(storeUnavailable:)` cho tới khi Task 5 xong. Chuyển
sang Task 5 rồi quay lại đây.

- [ ] **Step 5: Commit sau khi Task 5 xanh**

```bash
git add Evenstar/Evenstar/App/EvenstarStores.swift \
        Evenstar/Evenstar/App/EvenstarApp.swift \
        Evenstar/Evenstar/App/RootView.swift \
        Evenstar/Evenstar/Localizable.xcstrings \
        Evenstar/EvenstarTests/EvenstarStoresTests.swift
git commit -m "fix: hạ tầng kho thay vì sập khi CloudKit không mở được"
```

---

### Task 5: Báo cho người dùng khi kho tụt xuống bộ nhớ

Spec: S4.

**Files:**
- Modify: `Evenstar/Evenstar/App/RootView.swift` (đầu `struct`, và cuối `body`)
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes: `RootView(storeUnavailable:)` do Task 4 gọi.
- Produces: `RootView.init(storeUnavailable: Bool = false)`. Mặc định `false`
  là **bắt buộc** — `ReduceMotionTests.swift:1379` dựng `RootView()` không
  tham số, và test ấy không được sửa.

**Vì sao chỉ cảnh báo ở `inMemory`:** tầng `localOnly` chỉ mất đồng bộ, không
mất dữ liệu — người dùng chưa đăng nhập iCloud mà bị một hộp thoại ở mỗi lần
mở app là quấy rầy vô cớ. Tầng `inMemory` thì thư viện hiện ra **trống**, và
người dùng thấy thế sẽ nhập lại toàn bộ nhạc; lần chạy sau khi kho đĩa mở lại
được, họ có một thư viện nhân đôi. Hộp thoại này tồn tại để chặn đúng chuyện đó.

- [ ] **Step 1: Thêm khởi tạo và trạng thái vào `RootView`**

Ngay dưới dòng `struct RootView: View {` trong
`Evenstar/Evenstar/App/RootView.swift`, thêm:

```swift
    /// Kho đã tụt xuống bộ nhớ tạm. Xem `EvenstarStores.Tier`.
    private let storeUnavailable: Bool

    /// Dựng từ `storeUnavailable` ngay trong `init` chứ không đặt trong một
    /// `.task`: `body` đã có một `.task` rồi, và hai `.task` anh em không được
    /// SwiftUI xếp thứ tự — xem ghi chú ở cuối `body` về đúng cái bẫy ấy.
    @State private var showingStoreWarning: Bool

    /// Mặc định `false` để `RootView()` không tham số vẫn dựng được:
    /// `ReduceMotionTests` dùng dạng ấy.
    init(storeUnavailable: Bool = false) {
        self.storeUnavailable = storeUnavailable
        _showingStoreWarning = State(initialValue: storeUnavailable)
    }
```

- [ ] **Step 2: Gắn hộp thoại vào cuối `body`**

`.id(language)` hiện là modifier cuối cùng của `body`, ngay trước khối ghi chú
dài về `.task` khôi phục hàng đợi. Thêm **sau** `.id(language)`:

```swift
        // Sau `.id(language)`: đổi ngôn ngữ dựng lại cả cây bên dưới, và một
        // hộp thoại đang mở không được biến mất vì chuyện đó.
        .alert("Không mở được thư viện", isPresented: $showingStoreWarning) {
            Button("Đã hiểu", role: .cancel) { }
        } message: {
            Text("Lần chạy này dùng bộ nhớ tạm, nên thư viện hiện ra trống dù nhạc trên máy vẫn còn nguyên. Đừng nhập lại — hãy đóng hẳn app rồi mở lại.")
        }
```

- [ ] **Step 3: Build và chạy toàn bộ test của ba lớp liên quan**

```bash
cd /Users/phanquyetthang/evenstar
xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 test' \
  -only-testing:EvenstarTests/EvenstarStoresTests \
  -only-testing:EvenstarTests/ReduceMotionTests 2>&1 \
  | grep -E "Test Case|Executed|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`. Nếu `ReduceMotionTests` hỏng vì chữ ký
`RootView`, tham số mặc định ở Step 1 bị viết sót.

- [ ] **Step 4: Bổ sung bản dịch tiếng Anh cho ba chuỗi mới**

Build ở Step 3 đã tự thêm ba khoá nguồn vào `Localizable.xcstrings` với bản
dịch `en` còn trống. Điền chúng:

```bash
cd /Users/phanquyetthang/evenstar
python3 - <<'PY'
import json, collections
path = "Evenstar/Evenstar/Localizable.xcstrings"
with open(path) as f:
    doc = json.load(f, object_pairs_hook=collections.OrderedDict)

english = {
    "Không mở được thư viện": "Couldn't open your library",
    "Đã hiểu": "OK",
    "Lần chạy này dùng bộ nhớ tạm, nên thư viện hiện ra trống dù nhạc trên máy vẫn còn nguyên. Đừng nhập lại — hãy đóng hẳn app rồi mở lại.":
        "This session is running in temporary memory, so your library looks empty even though the music on your device is still there. Don't re-import it — quit the app completely and open it again.",
}

missing = [k for k in english if k not in doc["strings"]]
assert not missing, f"Build chưa trích được các khoá này: {missing}"

for key, value in english.items():
    entry = doc["strings"][key]
    entry.setdefault("localizations", collections.OrderedDict())
    entry["localizations"]["en"] = collections.OrderedDict(
        [("stringUnit", collections.OrderedDict(
            [("state", "translated"), ("value", value)]))]
    )
    entry.pop("extractionState", None)

with open(path, "w") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("Đã điền", len(english), "bản dịch")
PY
```

Expected: `Đã điền 3 bản dịch`. Nếu assert nổ, chạy lại Step 3 trước — bản
dịch chỉ điền được sau khi một lượt build đã trích khoá ra.

- [ ] **Step 5: Xác nhận cả hai ngôn ngữ vẫn phủ kín**

```bash
cd /Users/phanquyetthang/evenstar
python3 - <<'PY'
import json
doc = json.load(open("Evenstar/Evenstar/Localizable.xcstrings"))
thieu = {l: [k for k, v in doc["strings"].items()
             if l not in v.get("localizations", {})] for l in ("en", "vi")}
print("thiếu en:", len(thieu["en"]), "| thiếu vi:", len(thieu["vi"]))
for l, ks in thieu.items():
    for k in ks[:5]:
        print(" ", l, repr(k)[:70])
PY
```

Expected: `thiếu en: 0 | thiếu vi: 0`.

- [ ] **Step 6: Commit**

Quay lại Task 4 Step 5 và chạy lệnh commit ở đó — Task 3, 4 và 5 đi chung một
commit vì chúng không biên dịch rời nhau được.

---

### Task 6: Dọn hai khoá dịch chết

Spec: S5.

**Files:**
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes: không gì. Produces: không gì. Task này độc lập hoàn toàn.

- [ ] **Step 1: Xác nhận hai khoá thật sự không còn ai dùng**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar/Evenstar
grep -rn 'Chế độ' --include='*.swift' .
grep -rn 'Ngôn ngữ được đổi trong Cài đặt' --include='*.swift' .
```

Expected: không kết quả nào. Nếu có kết quả, **dừng lại và báo** — khoá ấy
không chết, và trạng thái `stale` là dấu hiệu của chuyện khác.

- [ ] **Step 2: Xoá chúng**

```bash
cd /Users/phanquyetthang/evenstar
python3 - <<'PY'
import json, collections
path = "Evenstar/Evenstar/Localizable.xcstrings"
with open(path) as f:
    doc = json.load(f, object_pairs_hook=collections.OrderedDict)

chet = [k for k, v in doc["strings"].items() if v.get("extractionState") == "stale"]
print("sẽ xoá:", [repr(k)[:60] for k in chet])
assert len(chet) == 2, f"Chờ đúng 2 khoá chết, thấy {len(chet)}"
for k in chet:
    del doc["strings"][k]

with open(path, "w") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("còn lại", len(doc["strings"]), "khoá")
PY
```

Expected: in ra hai khoá `'Chế độ'` và khoá về Cài đặt iOS, rồi số khoá còn lại.

- [ ] **Step 3: Build lại và xác nhận không khoá nào bị trích lại**

```bash
cd /Users/phanquyetthang/evenstar
xcodebuild build -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 test' 2>&1 \
  | grep -E "error:|warning:|BUILD" | grep -v AppIntents
python3 -c "
import json
d = json.load(open('Evenstar/Evenstar/Localizable.xcstrings'))
stale = [k for k,v in d['strings'].items() if v.get('extractionState') == 'stale']
print('còn khoá chết:', len(stale))
"
```

Expected: `BUILD SUCCEEDED` và `còn khoá chết: 0`.

- [ ] **Step 4: Commit**

```bash
git add Evenstar/Evenstar/Localizable.xcstrings
git commit -m "chore: dọn hai khoá dịch không còn ai dùng"
```

---

### Task 7: Danh sách kiểm trước khi nộp, phần làm bằng tay

Spec: M1–M5. Đây là những việc tác nhân **không được** làm — chúng nằm trong
`project.pbxproj`, trong App Store Connect, hoặc trong Google Cloud Console.

**Files:**
- Create: `docs/superpowers/audits/2026-09-03-truoc-khi-nop.md`

**Interfaces:** không có mã.

- [ ] **Step 1: Viết tài liệu**

Tạo `docs/superpowers/audits/2026-09-03-truoc-khi-nop.md` với đúng nội dung sau:

```markdown
# Trước khi bấm nộp — việc phải làm bằng tay

Bốn việc dưới đây không có test nào bắt được, và không tác nhân nào được làm
thay. Tick từng dòng trước khi tải build lên.

## 1. Đẩy lược đồ CloudKit sang Production

Đây là **nửa còn lại** của bản sửa "không sập khi CloudKit hỏng". Bản sửa ấy
khiến app mở được; nó không làm đồng bộ chạy. Nếu lược đồ chỉ tồn tại ở
Development thì mọi người dùng App Store đều rơi xuống tầng `localOnly` và
không ai có đồng bộ.

- Mở CloudKit Console, container `iCloud.com.evenstar.app`.
- Development → Deploy Schema to Production.
- Kiểm rằng bốn kiểu bản ghi `CD_Track`, `CD_DriveTrack`, `CD_JamendoTrack`,
  `CD_DriveFolder` đều có mặt ở Production.

Lược đồ CloudKit **chỉ thêm được, không sửa ngược**. Đẩy nhầm là khoá vĩnh
viễn hình dạng dữ liệu, nên đọc lại lược đồ trước khi bấm.

## 2. Kiểm `aps-environment` trong bản đã export

`Evenstar/Evenstar.entitlements` ghi `development`. Nền `remote-notification`
là chính đáng — đồng bộ SwiftData qua CloudKit cần push im lặng. Xcode được
cho là tự thay giá trị này thành `production` khi export bản App Store, nhưng
"được cho là" không phải bằng chứng:

    unzip -p Evenstar.ipa 'Payload/Evenstar.app/embedded.mobileprovision' \
      | security cms -D | plutil -p - | grep -A2 aps-environment

Phải thấy `production`. Thấy `development` thì đừng nộp.

## 3. Giới hạn khoá Google Drive API

`DriveAPIKey.value` có giá trị thật và nó đi theo binary — ai cũng moi ra
được. Tệp đang được `skip-worktree` và khoá không nằm trong lịch sử git, nên
repo thì sạch; ranh giới thật nằm ở phía Google.

Trong Google Cloud Console, với khoá này:

- Application restrictions → iOS apps → thêm bundle ID `com.evenstar.app`.
- API restrictions → Restrict key → chỉ chọn Google Drive API.

Khoá không giới hạn là khoá bất kỳ ai cũng tiêu hết quota giúp bạn.

## 4. Ngôn ngữ chính của app

`developmentRegion` trong pbxproj là `en`, còn `sourceLanguage` trong
`Localizable.xcstrings` là `vi`. Cả hai ngôn ngữ đều phủ kín khoá nên app
không hỏng, nhưng App Store Connect sẽ lấy **English** làm ngôn ngữ chính.

Muốn tiếng Việt là ngôn ngữ chính thì đổi `developmentRegion` thành `vi` trong
Xcode, ở Project → Info → Localizations. Sửa bằng tay trong Xcode, không sửa
pbxproj bằng trình soạn thảo.

## 5. Ghi chú cho người duyệt

App phát nhạc từ Google Drive của chính người dùng và từ Jamendo. Mở app lần
đầu trên một máy sạch thì thư viện **trống rỗng** — người duyệt không có nhạc
nào để thử, và một màn hình trống là lý do từ chối 2.1 quen thuộc.

Trong ô App Review Information, dán:

- một liên kết thư mục Google Drive công khai có sẵn vài tệp mp3, kèm câu
  "dán liên kết này vào Tài khoản → Thư mục Drive";
- một câu về nguồn nội dung: nhạc đến từ tệp người dùng tự nhập, từ Drive của
  chính họ, và từ Jamendo theo giấy phép Creative Commons — app không lưu trữ
  hay phân phối nhạc của bên thứ ba nào.

Nhắc thêm cho người duyệt rằng nhạc nền và màn hình khoá đều hoạt động, và
rằng app hỗ trợ xoay ngang.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add docs/superpowers/audits/2026-09-03-truoc-khi-nop.md
git commit -m "docs: danh sách kiểm thủ công trước khi nộp App Store"
```

---

### Task 8: Kiểm chứng toàn bộ

**Files:** không sửa gì.

- [ ] **Step 1: Chạy toàn bộ bộ test**

```bash
cd /Users/phanquyetthang/evenstar
xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 test' 2>&1 \
  | grep -E "Executed|error:|failed|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`. Bất kỳ test nào hỏng đều phải sửa trước khi
task này được coi là xong — kể cả test không liên quan tới plan này.

- [ ] **Step 2: Build Release cho máy thật**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -cE "warning:"
```

Expected: `0`. Bản Release trước khi bắt đầu plan này không có cảnh báo nào, và
nó phải giữ nguyên như vậy.

- [ ] **Step 3: Xác nhận manifest và khoá Info.plist có trong bản Release**

```bash
APP=$(xcodebuild -scheme Evenstar -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Evenstar.app
ls "$APP/PrivacyInfo.xcprivacy"
/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$APP/Info.plist"
```

Expected: đường dẫn tệp manifest được in ra, và `false`.

- [ ] **Step 4: Chạy trên máy thật, thử xoay ngang**

```bash
cd /Users/phanquyetthang/evenstar
./device.sh
```

Kiểm bằng mắt, trên máy thật chứ không phải máy ảo:

- app mở được, thư viện hiện ra;
- xoay ngang: player, thanh tab nổi và mini player đều không tràn safe area;
- phát một bài rồi khoá máy: điều khiển ở màn khoá hiện đúng tên bài và ảnh bìa;
- không hộp thoại "Không mở được thư viện" nào hiện lên — nếu có, kho đĩa
  đang hỏng thật và đó là chuyện phải điều tra trước khi nộp.

- [ ] **Step 5: Commit nếu có gì thay đổi**

```bash
git status --short
```

Expected: sạch. Task này chỉ kiểm chứng, không sửa gì.
