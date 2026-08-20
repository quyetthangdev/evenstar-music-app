# Đồng bộ CloudKit — plan thi công

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thư viện Drive/Jamendo, trạng thái phát và siêu dữ liệu bài đi theo Apple Account giữa các máy của chính người dùng, không tài khoản riêng, không server riêng, không đồng bộ file nhạc.

**Architecture:** SwiftData nói chuyện thẳng với CloudKit qua `ModelConfiguration(cloudKitDatabase:)`. Toàn bộ việc chia làm ba phần: (1) làm mô hình hợp lệ với CloudKit — bỏ `unique`, thêm mặc định; (2) xử ba hệ quả của việc dữ liệu đến từ máy khác — hàng trùng, file vắng mặt, xoá lan sang máy khác; (3) bật CloudKit, chặn bởi một bước bàn giao Xcode.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, CloudKit, XCTest. iOS 18.0.

**Spec:** `docs/superpowers/specs/2026-08-20-cloudkit-sync-design.md`

## Global Constraints

- **iOS deployment target 18.0.** Không hạ.
- **Agent không được sửa `.pbxproj` hay `.xcscheme`.** Task 9 chặn bởi một bước người dùng tự làm trong Xcode.
- **Lệnh test:** `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`
- **`PlayerCardCommitCostControlTests` chập chờn khi máy tải nặng** — chạy lại một lần. **Không được hạ ngưỡng của nó.**
- **File mới trong plan này viết doc comment bằng tiếng Việt.**
- **String Catalog `Evenstar/Evenstar/Localizable.xcstrings` có `sourceLanguage: vi`.** Mỗi chuỗi mới phải điền **cả** `vi` và `en` bằng tay, `state: "translated"`. Không để Xcode tự sinh.
- **Cấm test mock chứng minh CloudKit đồng bộ.** Xem spec mục 5.
- Container CloudKit: **`iCloud.com.evenstar.app`** (bundle id là `com.evenstar.app`).
- Đĩa máy phát triển đang hẹp (~6GB trống). Không chạy Instruments trace trong plan này.

## Hai hiệu chỉnh so với spec — đọc trước khi làm

Spec viết trước khi tôi đọc kỹ `ImportService` và `PlaybackService`. Hai chỗ sai, cả hai làm việc **ít đi**:

**(1) `Track` KHÔNG được gộp trùng. Spec ghi khoá tự nhiên của nó là `relativePath` — sai.**

`ImportService` dựng `relativePath = "Music/\(id.uuidString).\(ext)"` với `id` là UUID của chính hàng đó. Nên hai máy nhập **cùng một file** sinh **hai `relativePath` khác nhau**: nó không phải khoá tự nhiên, nó là khoá riêng của máy.

Đổi sang khoá `title|artist|duration` (kiểu `findExistingTrack` đang dùng) còn **tệ hơn hẳn**, và đây là lý do phải viết ra: gộp hai hàng ấy làm hàng sống sót giữ **một** `relativePath`. Máy nào không phải chủ của đường dẫn đó thì file thật của nó vẫn nằm trên đĩa nhưng **không còn hàng nào trỏ tới** — mất quyền phát một bài mình đang có.

Nên: hai hàng `Track` cùng tên nhạc trên hai máy **không phải trùng lặp**. Chúng là hai file thật, ở hai chỗ thật, và mỗi máy chỉ phát được cái của mình. Để nguyên cả hai là đúng — mục 2 làm hàng của máy kia mờ đi, và người dùng thấy đúng sự thật: họ có hai bản, trên hai máy.

Giá phải trả, nói thẳng: người dùng **thấy bài ấy hai dòng**. Gộp hai dòng ở tầng hiển thị là một tính năng riêng, không thuộc plan này.

**(2) `DriveFolder` cũng không được gộp**, vì lý do khác: nó không có trường nào phân biệt được hai hàng cùng `folderID`. Không có tiêu chí cắt hoà **tất định**, hai máy có thể chọn giữ hai hàng khác nhau, mỗi máy xoá hàng kia, và cả hai lệnh xoá cùng đồng bộ lên — **mất sạch cả hai**. Một hàng thừa là chuyện thẩm mỹ; mất cả hai là mất dữ liệu.

**Kết quả: lượt gộp trùng chỉ chạy trên `DriveTrack` (khoá `fileID`) và `JamendoTrack` (khoá `jamendoID`)** — hai bảng mà danh tính là một id ở máy chủ người khác, nghĩa như nhau trên mọi máy, và gộp không làm mất quyền truy cập gì.

**(3) Bỏ qua bài vắng mặt khi tự chuyển bài đã có sẵn.** `PlaybackService.loadCurrentAndPlay()` đã có vòng ấy, có chặn trên `queue.count`. Task 8 chỉ ghim nó bằng test, không sửa mã sản phẩm.

**(4) Thứ tự trong spec sai ở bước 1.** Không kiểm được một migration chưa viết. Việc làm trước là *chuẩn bị*: có sẵn một bản cài mang dữ liệu thật. Lượt kiểm nằm ngay **sau** Task 1.

## Chuẩn bị trước Task 1 — người dùng làm

Trên máy thật hoặc simulator, cài bản **hiện tại** (`main`) và tạo dữ liệu: nhập vài bài, liên kết một thư mục Drive nếu có, lưu vài bài Jamendo, phát một bài để `PlaybackState` có nội dung. Giữ nguyên bản cài đó — Task 1 sẽ cài đè lên nó.

**Không kiểm trên máy sạch.** Máy sạch luôn qua, vì không có gì để migrate.

## Cấu trúc file

| File | Trách nhiệm |
|---|---|
| `Evenstar/Evenstar/Models/*.swift` (5 file) | Bỏ `unique`, thêm mặc định. Không đổi gì khác. |
| `Evenstar/Evenstar/Services/DuplicateMerge.swift` **(mới)** | Quy tắc gộp trùng, **hàm thuần**, không chạm SwiftData. |
| `Evenstar/Evenstar/Services/DuplicateSweep.swift` **(mới)** | Áp quy tắc lên hàng thật trong `ModelContext`. |
| `Evenstar/Evenstar/Services/TrackPresence.swift` **(mới)** | Quét thư mục `Music/`, và hai quy tắc thuần dựa trên kết quả quét. |
| `Evenstar/Evenstar/Services/LibraryStore.swift` | Giữ thêm tập đường dẫn có mặt. |
| `Evenstar/Evenstar/Features/Library/SongRow.swift` | Hiện mờ + nhãn cho hàng vắng mặt. |
| `Evenstar/Evenstar/Features/Library/SongsView.swift` | Chặn chạm hàng vắng mặt; cảnh báo khi xoá. |
| `Evenstar/Evenstar/App/EvenstarApp.swift` | Nạp tập có mặt lúc khởi động; bật CloudKit (Task 9). |
| `Evenstar/Evenstar/Localizable.xcstrings` | Chuỗi mới, cả `vi` và `en`. |
| `Evenstar/EvenstarTests/*` (5 file mới) | Test. |

---

### Task 1: Mô hình hợp lệ với CloudKit

CloudKit từ chối `@Attribute(.unique)`, và đòi mọi thuộc tính hoặc optional hoặc có giá trị mặc định. Task này bỏ 6 chỗ `unique` và thêm mặc định cho 33 thuộc tính.

**Files:**
- Modify: `Evenstar/Evenstar/Models/Track.swift`
- Modify: `Evenstar/Evenstar/Models/JamendoTrack.swift`
- Modify: `Evenstar/Evenstar/Models/DriveTrack.swift`
- Modify: `Evenstar/Evenstar/Models/DriveFolder.swift`
- Modify: `Evenstar/Evenstar/Models/PlaybackState.swift`
- Test: `Evenstar/EvenstarTests/ModelCloudKitConformanceTests.swift` (mới)

**Interfaces:**
- Consumes: không có.
- Produces: không đổi API nào. Mọi `init(...)` giữ nguyên chữ ký; chỉ khai báo thuộc tính đổi.

- [ ] **Step 1: Viết test thất bại**

Tạo `Evenstar/EvenstarTests/ModelCloudKitConformanceTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// Hai ràng buộc CloudKit áp lên `@Model`, và **cả hai đều không báo lỗi lúc
/// biên dịch**: không được có `@Attribute(.unique)`, và mọi thuộc tính lưu trữ
/// phải optional hoặc mang giá trị mặc định. Vi phạm chỉ lộ ra lúc chạy — hoặc
/// tệ hơn, chỉ lộ ở bản Release nói chuyện với môi trường Production.
///
/// Đây là test đọc **mã nguồn**, không phải test hành vi, và đó là chủ ý chứ
/// không phải chỗ lười. Test hành vi tương đương phải dựng một `ModelContainer`
/// mang `cloudKitDatabase`, thứ đòi entitlement iCloud mà bó test không có và
/// không nên có. Nên chỗ này đọc thẳng năm file trong `Models/`.
///
/// `throw XCTSkip` chứ không `XCTFail` khi không thấy thư mục nguồn: bó test
/// phải chạy được ở nơi mã nguồn không nằm cạnh nó.
final class ModelCloudKitConformanceTests: XCTestCase {

    /// `#filePath` là đường dẫn tuyệt đối lúc biên dịch, nên nó trỏ tới cây
    /// nguồn thật trên máy đang dịch — cách duy nhất để với tới `Models/` từ
    /// bên trong một bó test không mang mã nguồn.
    private static let modelsDirectory: URL? = {
        let here = URL(fileURLWithPath: #filePath)
        let dir = here
            .deletingLastPathComponent()            // EvenstarTests/
            .deletingLastPathComponent()            // Evenstar/ (thư mục dự án)
            .appendingPathComponent("Evenstar/Models", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }()

    private func modelSources() throws -> [URL] {
        guard let dir = Self.modelsDirectory else {
            throw XCTSkip("Không tìm thấy Models/ cạnh bó test — bỏ qua.")
        }
        return try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// CloudKit không chấp nhận ràng buộc duy nhất. Bỏ nó **không** tháo mất
    /// hàng rào chống trùng nào đang được dùng: doc comment của `JamendoTrack`
    /// ghi rằng dựa vào `unique` chính là lỗi đã phải sửa, và
    /// `JamendoLibraryService.inFlightSaves` mới là thứ chống trùng thật.
    func testNoModelDeclaresAUniqueAttribute() throws {
        for url in try modelSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                source.contains("@Attribute(.unique)"),
                "\(url.lastPathComponent) còn @Attribute(.unique). CloudKit từ chối nó."
            )
        }
    }

    /// Một thuộc tính không-optional, không mặc định là một cột mà CloudKit
    /// không đọc nổi khi bản ghi cũ chưa có nó. Bốn thuộc tính của
    /// `PlaybackState` đã mang mặc định từ trước vì đúng lý do ấy — doc comment
    /// của chúng nói rõ — nên mẫu để noi theo nằm sẵn trong repo.
    func testEveryStoredPropertyIsOptionalOrHasADefault() throws {
        var offenders: [String] = []
        for url in try modelSources() {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("@Model") else { continue }
            for line in source.components(separatedBy: .newlines) {
                // Thuộc tính ở tầng kiểu là thụt đúng 4 dấu cách. `{` loại ra
                // thuộc tính tính toán, thứ không có cột nào trong lược đồ.
                guard line.hasPrefix("    var "), !line.contains("{") else { continue }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let declaredType = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if declaredType.contains("=") { continue }        // có mặc định
                if declaredType.hasSuffix("?") { continue }       // optional
                offenders.append("\(url.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(
            offenders, [],
            "Các thuộc tính này phải optional hoặc mang giá trị mặc định thì CloudKit mới nhận."
        )
    }
}
```

- [ ] **Step 2: Chạy test để chắc nó thất bại**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/ModelCloudKitConformanceTests`

Expected: **FAIL** cả hai test. Test một báo `Track.swift còn @Attribute(.unique)`; test hai liệt kê 33 thuộc tính.

- [ ] **Step 3: Sửa `Track.swift`**

Thay nguyên khối khai báo thuộc tính (từ `@Attribute(.unique) var id: UUID` tới `var lastPlayedAt: Date?`) bằng:

```swift
    /// Mọi thuộc tính dưới đây hoặc optional hoặc mang giá trị mặc định, và
    /// **không được bỏ mặc định đi**: CloudKit đọc bản ghi do máy khác ghi, kể
    /// cả bản ghi cũ chưa có cột này, và một cột không-optional không mặc định
    /// là một bản ghi không giải mã được. Cùng lý do bốn thuộc tính của
    /// `PlaybackState` đã mang mặc định từ trước.
    ///
    /// Ràng buộc này được ghim bởi `ModelCloudKitConformanceTests`.
    var id: UUID = UUID()
    var title: String = ""
    var artistName: String = ""
    var albumTitle: String = ""
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double = 0
    var relativePath: String = ""
    var artworkRelativePath: String?
    var format: String = ""
    var sampleRate: Int?
    var bitDepth: Int?
    var dateAdded: Date = .now
    var playCount: Int = 0
    var lastPlayedAt: Date?
```

`init(...)` giữ nguyên không đổi một chữ.

- [ ] **Step 4: Sửa `JamendoTrack.swift`**

Thay khối thuộc tính bằng:

```swift
    /// Không còn ràng buộc duy nhất nào ở đây, và mặc định là bắt buộc — xem
    /// ghi chú tương ứng trong `Track`.
    var id: UUID = UUID()
    var jamendoID: String = ""
    var title: String = ""
    var artistName: String = ""
    var albumTitle: String = ""
    var durationSeconds: Double = 0
    var audioURLString: String = ""
    /// The licence this track is offered under. Shown to the user — CC-BY
    /// obliges visible credit — and `nil` only when the catalogue omitted it.
    var licenceURLString: String?
    /// The track's page on Jamendo, for the attribution link.
    var shareURLString: String?
    /// Documents-relative, downloaded when the track was saved. See
    /// `JamendoLibraryService.save`.
    var artworkRelativePath: String?
    var dateAdded: Date = Date()
    var playCount: Int = 0
    var lastPlayedAt: Date?
```

Rồi **sửa doc comment ở tầng kiểu**, vì nó đang mô tả một cơ chế không còn tồn tại. Thay hai đoạn nói về `@Attribute(.unique)` (từ ``/// `@Attribute(.unique)` on `jamendoID` and not on the title:`` tới hết đoạn `` `DriveTrack`'s type-level doc comment, for the same reason.``) bằng:

```swift
/// **Không còn ràng buộc duy nhất nào trên bảng này** — CloudKit không chấp
/// nhận `@Attribute(.unique)`. Trước đây nó cũng chưa bao giờ là hàng rào thật:
/// khi va chạm, SwiftData upsert, và `id` của hàng sống sót *không nhất thiết*
/// là `id` gốc. `PlaybackState` giữ thành viên hàng đợi bằng `UUID` trần không
/// có quan hệ ngược, nên một hàng đổi `id` làm hàng đợi mất bài trong im lặng.
///
/// Thứ chống trùng thật là `JamendoLibraryService.inFlightSaves`, gom mọi
/// `save()` đồng thời cho cùng một `jamendoID` về một `Task` duy nhất. Nó từng
/// là dây an toàn thứ hai; **giờ nó là dây duy nhất**, nên đừng gỡ.
///
/// Ca mà `inFlightSaves` không với tới là hai máy cùng lưu một bài khi ngoại
/// tuyến — không có `Task` chung để gom. Đó là việc của `DuplicateSweep`.
```

- [ ] **Step 5: Sửa `DriveTrack.swift`**

Thay khối thuộc tính bằng:

```swift
    /// Không còn ràng buộc duy nhất nào ở đây, và mặc định là bắt buộc — xem
    /// ghi chú tương ứng trong `Track`.
    var id: UUID = UUID()
    var fileID: String = ""
    var folderID: String = ""
    var fileName: String = ""
    var title: String = ""
    /// Stored optional, because "not read yet" is real and distinct from
    /// "read, and the file has no artist tag". `Playable` exposes non-optional
    /// `artistName`/`albumTitle` computed from these — see `Playable.swift`.
    var artistNameOrNil: String?
    var albumTitleOrNil: String?
    /// 0 until `metadataResolved`. Not optional: `Playable` needs a number, and
    /// two ways to say "unknown" in one row is one too many.
    var durationSeconds: Double = 0
    /// False until the track has been played once and its real tags read over
    /// the network. Scanning deliberately does not read tags — see the spec.
    var metadataResolved: Bool = false
    var dateAdded: Date = .now
    var playCount: Int = 0
    var lastPlayedAt: Date?
```

Rồi sửa doc comment ở tầng kiểu: thay đoạn bắt đầu bằng ``/// **Reconciling a scan against existing rows must fetch by `fileID``` tới hết đoạn ``reproduction.`` bằng:

```swift
/// **Mọi lượt quét lại phải fetch theo `fileID` rồi sửa tại chỗ — không bao giờ
/// dựng một `DriveTrack(fileID:...)` mới và insert cho một `fileID` có thể đã
/// tồn tại.** Trước đây `@Attribute(.unique)` giữ số hàng ở một dù làm cách nào;
/// **ràng buộc ấy đã bị bỏ** vì CloudKit không chấp nhận nó, nên giờ một lượt
/// insert lặp lại thực sự sinh ra hàng thứ hai.
///
/// Kể cả khi còn `unique` thì cách ấy vẫn sai: khi va chạm, chính `id` chứ
/// không phải người gọi quyết định hàng sống sót mang `id` nào, và nó không
/// nhất thiết là `id` gốc. `PlaybackState` giữ thành viên hàng đợi bằng `UUID`
/// trần không có quan hệ ngược, nên không ai nối lại hộ khi một hàng đổi `id` —
/// hàng đợi khôi phục xong mất bài trong im lặng. Xem
/// `testInsertingTheSameFileIDTwiceKeepsOneRow`.
```

Ghi chú cho người thi công: test `testInsertingTheSameFileIDTwiceKeepsOneRow` **sẽ đổ** sau bước này, vì nó ghim đúng hành vi upsert vừa bị bỏ. Bước 8 xử lý nó.

- [ ] **Step 6: Sửa `DriveFolder.swift`**

```swift
    var folderID: String = ""
    var displayName: String = ""
    var linkedAt: Date = .now
    /// `nil` until the first successful scan, which is what distinguishes
    /// "never scanned" from "scanned and empty".
    var lastScannedAt: Date?
```

- [ ] **Step 7: Sửa `PlaybackState.swift`**

Ba thuộc tính chưa có mặc định:

```swift
    var currentTrackID: UUID?
    var positionSeconds: Double = 0
    var queueTrackIDs: [UUID] = []
    var queueIndex: Int = 0
```

Bốn thuộc tính còn lại đã có mặc định và doc comment của chúng đã giải thích đúng lý do — **không đụng**.

- [ ] **Step 8: Sửa test đang ghim hành vi `unique`**

`Evenstar/EvenstarTests/` có ít nhất một test ghim hành vi upsert của `@Attribute(.unique)`. Tìm chúng:

```bash
cd /Users/phanquyetthang/evenstar && grep -rn "KeepsOneRow\|unique" Evenstar/EvenstarTests/ | grep -v "^Binary"
```

Với mỗi test tìm được, **đổi mục tiêu chứ không xoá**. Ràng buộc mất đi, nhưng *yêu cầu* thì không: không được có hai hàng cùng `fileID`. Thứ phải giữ đúng giờ là người gọi, nên test phải ghim người gọi.

Ví dụ, `testInsertingTheSameFileIDTwiceKeepsOneRow` đổi thành một test rằng lượt hoà giải quét lại (`DriveLibraryService`) fetch-rồi-sửa và không sinh hàng thứ hai. Nếu đường ấy không với tới từ test, đổi tên test thành `testTwoRawInsertsForOneFileIDNowProduceTwoRows` và ghim **hành vi mới**, kèm doc comment nói rõ vì sao đó là hành vi đúng và ai đang chịu trách nhiệm chống trùng thay cho nó.

**Không được để một test đổ mà bỏ qua, và không được xoá nó cho xanh bảng.**

- [ ] **Step 9: Chạy toàn bộ bó test**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`

Expected: PASS toàn bộ. Nếu `PlayerCardCommitCostControlTests` đổ, chạy lại một lần — nó chập chờn khi máy tải nặng. **Không hạ ngưỡng của nó.**

- [ ] **Step 10: Commit**

```bash
git add Evenstar/Evenstar/Models Evenstar/EvenstarTests
git commit -m "refactor: mô hình hợp lệ với CloudKit — bỏ sáu unique, thêm 33 mặc định"
```

---

## CỔNG THỦ CÔNG A — kiểm migration. Dừng ở đây.

**Người thi công không làm được bước này, và không được đi tiếp khi chưa có kết quả.**

Task 1 đổi lược đồ. Bỏ `unique` và thêm mặc định *nên* thuộc loại migration nhẹ mà SwiftData tự xử. "Nên" không phải "chắc chắn", và `EvenstarApp.init` có `fatalError("Failed to create ModelContainer: \(error)")` — migration hỏng nghĩa là **app crash ngay khi mở**, không đường phục hồi nào ngoài xoá app.

Người dùng làm:

1. Trên bản cài đã có dữ liệu (chuẩn bị từ trước Task 1), **cài đè** bản dựng từ nhánh này — không gỡ trước.
2. Mở app.
3. Kiểm: app mở được; danh sách bài còn nguyên; thư mục Drive còn liên kết; bài Jamendo còn; bài đang phát dở khôi phục đúng chỗ.

**Nếu app crash lúc mở:** dừng plan. Migration không nhẹ, và cần một `VersionedSchema` cùng `MigrationPlan` — đó là một plan khác, không phải một bước trong plan này.

---

### Task 2: Quy tắc gộp trùng — hàm thuần

Hai máy ngoại tuyến cùng lưu một bài sinh ra hai hàng cùng khoá tự nhiên. Task này viết quy tắc quyết định giữ hàng nào, **không chạm SwiftData**, nên test được thẳng.

**Files:**
- Create: `Evenstar/Evenstar/Services/DuplicateMerge.swift`
- Test: `Evenstar/EvenstarTests/DuplicateMergeTests.swift` (mới)

**Interfaces:**
- Consumes: không có.
- Produces:
  - `struct MergeCandidate: Equatable { let id: UUID; let dateAdded: Date; let playCount: Int; let lastPlayedAt: Date? }`
  - `struct GroupMerge: Equatable { let keepID: UUID; let removeIDs: [UUID]; let playCount: Int; let lastPlayedAt: Date? }`
  - `static func DuplicateMerge.merge(_ candidates: [MergeCandidate]) -> GroupMerge?`
  - `static func DuplicateMerge.repointing(_ ids: [UUID], through map: [UUID: UUID]) -> [UUID]`
  - `static func DuplicateMerge.repointing(_ id: UUID?, through map: [UUID: UUID]) -> UUID?`

- [ ] **Step 1: Viết test thất bại**

Tạo `Evenstar/EvenstarTests/DuplicateMergeTests.swift`:

```swift
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
    /// Khử trùng lặp thì phải ánh xạ `queueIndex` sang một mảng ngắn hơn, và
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
```

- [ ] **Step 2: Chạy test để chắc nó thất bại**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/DuplicateMergeTests`

Expected: FAIL lúc biên dịch — `cannot find 'MergeCandidate' in scope`.

- [ ] **Step 3: Viết `DuplicateMerge.swift`**

Tạo `Evenstar/Evenstar/Services/DuplicateMerge.swift`:

```swift
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
            // `nil` khi chưa máy nào phát — `.max()` trên mảng rỗng trả `nil`,
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
    /// lần liền. Khử trùng lặp thì phải ánh xạ `queueIndex` sang mảng ngắn hơn,
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
```

- [ ] **Step 4: Chạy test để chắc nó qua**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/DuplicateMergeTests`

Expected: PASS cả 10 test.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Services/DuplicateMerge.swift Evenstar/EvenstarTests/DuplicateMergeTests.swift
git commit -m "feat: quy tắc gộp trùng, tất định để hai máy không xoá mất của nhau"
```

---

### Task 3: Áp quy tắc gộp trùng lên hàng thật

Task 2 viết quy tắc; task này chạy nó trên `ModelContext` và trỏ lại `PlaybackState`.

**Chỉ hai bảng: `DriveTrack` (khoá `fileID`) và `JamendoTrack` (khoá `jamendoID`).** `Track` và `DriveFolder` bị loại, mỗi cái vì một lý do riêng — xem "Hai hiệu chỉnh so với spec" ở đầu plan, và doc comment dưới đây phải nói lại lý do ấy tại chỗ.

**Files:**
- Create: `Evenstar/Evenstar/Services/DuplicateSweep.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` (thêm `.task` gọi lượt quét)
- Test: `Evenstar/EvenstarTests/DuplicateSweepTests.swift` (mới)

**Interfaces:**
- Consumes: `MergeCandidate`, `GroupMerge`, `DuplicateMerge.merge(_:)`, `DuplicateMerge.repointing(_:through:)` từ Task 2.
- Produces: `@MainActor static func DuplicateSweep.run(context: ModelContext) throws -> Int` — trả số hàng đã xoá.

- [ ] **Step 1: Viết test thất bại**

Tạo `Evenstar/EvenstarTests/DuplicateSweepTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Evenstar

/// Lượt quét gộp trùng chạy trên hàng thật.
///
/// Ca sinh ra nó: hai máy ngoại tuyến cùng lưu một bài Jamendo. Không có `Task`
/// chung để gom như `JamendoLibraryService.inFlightSaves` làm trong một tiến
/// trình, và từ Task 1 thì cũng không còn `@Attribute(.unique)` nào để va vào.
/// Nên hai hàng cùng lên mây, và cái dọn chúng là chỗ này.
@MainActor
final class DuplicateSweepTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self, JamendoTrack.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func jamendo(_ id: UUID, jamendoID: String, added: TimeInterval, plays: Int) -> JamendoTrack {
        JamendoTrack(
            id: id,
            jamendoID: jamendoID,
            title: "Bài",
            artistName: "Nghệ sĩ",
            albumTitle: "Album",
            durationSeconds: 180,
            audioURLString: "https://example.invalid/\(jamendoID).mp3",
            dateAdded: Date(timeIntervalSince1970: added),
            playCount: plays
        )
    }

    func testTwoRowsWithOneJamendoIDCollapseToOne() throws {
        let context = try makeContext()
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 100, plays: 3))
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 200, plays: 4))
        try context.save()

        let removed = try DuplicateSweep.run(context: context)

        XCTAssertEqual(removed, 1)
        let rows = try context.fetch(FetchDescriptor<JamendoTrack>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.playCount, 7, "Lượt nghe của cả hai máy phải cộng lại.")
    }

    /// Hai bài **khác nhau** không được gộp chỉ vì cùng bảng.
    func testDistinctJamendoIDsAreLeftAlone() throws {
        let context = try makeContext()
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 100, plays: 1))
        context.insert(jamendo(UUID(), jamendoID: "j2", added: 100, plays: 1))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JamendoTrack>()).count, 2)
    }

    func testTwoRowsWithOneFileIDCollapseToOne() throws {
        let context = try makeContext()
        context.insert(DriveTrack(fileID: "f1", folderID: "d", fileName: "a.mp3",
                                  dateAdded: Date(timeIntervalSince1970: 100), playCount: 2))
        context.insert(DriveTrack(fileID: "f1", folderID: "d", fileName: "a.mp3",
                                  dateAdded: Date(timeIntervalSince1970: 200), playCount: 5))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 1)
        let rows = try context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.playCount, 7)
    }

    /// **Ghim một quyết định, không phải một chỗ sót.** Hai hàng `Track` cùng
    /// tên trên hai máy KHÔNG phải trùng lặp: `relativePath` của chúng chứa `id`
    /// của chính hàng ấy (xem `ImportService`), nên chúng là hai file thật ở hai
    /// chỗ thật. Gộp chúng làm hàng sống sót giữ **một** đường dẫn, và máy kia
    /// mất luôn hàng trỏ tới file nó đang có.
    func testLocalTracksAreNeverMerged() throws {
        let context = try makeContext()
        context.insert(Track(title: "Bài", artistName: "Nghệ sĩ", albumTitle: "Album",
                             durationSeconds: 180, relativePath: "Music/a.mp3", format: "mp3"))
        context.insert(Track(title: "Bài", artistName: "Nghệ sĩ", albumTitle: "Album",
                             durationSeconds: 180, relativePath: "Music/b.mp3", format: "mp3"))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Track>()).count, 2)
    }

    /// Cùng lý do tất định như `DuplicateMergeTests`: `DriveFolder` không có
    /// trường nào phân biệt hai hàng cùng `folderID`, nên không có tiêu chí cắt
    /// hoà tất định. Hai máy có thể chọn giữ hai hàng khác nhau, mỗi máy xoá
    /// hàng kia, và cả hai lệnh xoá cùng lên mây.
    func testDriveFoldersAreNeverMerged() throws {
        let context = try makeContext()
        context.insert(DriveFolder(folderID: "d1", displayName: "Nhạc"))
        context.insert(DriveFolder(folderID: "d1", displayName: "Nhạc"))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DriveFolder>()).count, 2)
    }

    /// Bước dễ quên nhất. Hàng đợi giữ `UUID` trần; nếu không trỏ lại, nó trỏ
    /// vào một hàng vừa bị xoá và bài ấy biến mất khỏi hàng đợi trong im lặng.
    func testThePlayingQueueIsRepointedAtTheSurvivor() throws {
        let context = try makeContext()
        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let other = UUID()
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        context.insert(jamendo(goneID, jamendoID: "j1", added: 200, plays: 0))
        context.insert(PlaybackState(
            currentTrackID: goneID,
            queueTrackIDs: [other, goneID],
            queueIndex: 1,
            unshuffledQueueTrackIDs: [goneID, other]
        ))
        try context.save()

        _ = try DuplicateSweep.run(context: context)

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<PlaybackState>()).first)
        XCTAssertEqual(state.currentTrackID, keptID)
        XCTAssertEqual(state.queueTrackIDs, [other, keptID])
        XCTAssertEqual(state.unshuffledQueueTrackIDs, [keptID, other])
        XCTAssertEqual(state.queueIndex, 1, "Độ dài mảng không đổi, nên chỉ số không được xê dịch.")
    }

    /// Chạy lại trên dữ liệu đã sạch không được đổi gì. Lượt quét chạy ở **mỗi**
    /// lần khởi động, nên nó phải rẻ và vô hại khi không có việc.
    func testASecondSweepChangesNothing() throws {
        let context = try makeContext()
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 100, plays: 3))
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 200, plays: 4))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 1)
        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JamendoTrack>()).first?.playCount, 7,
                       "Lượt thứ hai không được cộng dồn lần nữa.")
    }
}
```

- [ ] **Step 2: Chạy test để chắc nó thất bại**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/DuplicateSweepTests`

Expected: FAIL lúc biên dịch — `cannot find 'DuplicateSweep' in scope`.

- [ ] **Step 3: Viết `DuplicateSweep.swift`**

Tạo `Evenstar/Evenstar/Services/DuplicateSweep.swift`:

```swift
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
/// Một lượt lúc khởi động, từ `EvenstarApp`. Nghĩa là hàng trùng đến trong phiên
/// này chỉ được dọn ở **lần mở app sau**, và đó là đánh đổi có chủ ý: bám theo
/// `NSPersistentStoreRemoteChange` thì dọn sớm hơn nhưng thêm một luồng sự kiện
/// bắn liên tục vào một thao tác có xoá hàng. Hàng trùng nằm lại thêm một phiên
/// là chuyện chịu được.
@MainActor
enum DuplicateSweep {

    /// Trả về số hàng đã xoá.
    @discardableResult
    static func run(context: ModelContext) throws -> Int {
        var repointing: [UUID: UUID] = [:]

        repointing.merge(try sweep(
            DriveTrack.self, in: context,
            key: { $0.fileID },
            candidate: { MergeCandidate(id: $0.id, dateAdded: $0.dateAdded,
                                        playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt) },
            apply: { row, merged in
                row.playCount = merged.playCount
                row.lastPlayedAt = merged.lastPlayedAt
            }
        )) { existing, _ in existing }

        repointing.merge(try sweep(
            JamendoTrack.self, in: context,
            key: { $0.jamendoID },
            candidate: { MergeCandidate(id: $0.id, dateAdded: $0.dateAdded,
                                        playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt) },
            apply: { row, merged in
                row.playCount = merged.playCount
                row.lastPlayedAt = merged.lastPlayedAt
            }
        )) { existing, _ in existing }

        guard !repointing.isEmpty else { return 0 }

        // Fetch thẳng chứ không qua `LibraryService.playbackState`: cái đó tạo
        // một hàng mới khi chưa có, và một lượt dọn dẹp không có việc gì phải
        // tạo trạng thái phát cho một người chưa từng bấm play.
        if let state = try context.fetch(FetchDescriptor<PlaybackState>()).first {
            state.currentTrackID = DuplicateMerge.repointing(state.currentTrackID, through: repointing)
            state.queueTrackIDs = DuplicateMerge.repointing(state.queueTrackIDs, through: repointing)
            state.unshuffledQueueTrackIDs = DuplicateMerge.repointing(
                state.unshuffledQueueTrackIDs, through: repointing
            )
            // `queueIndex` không đụng: `repointing` thay giá trị chứ không đổi
            // độ dài mảng, nên chỉ số vẫn trỏ đúng vị trí cũ.
        }

        try context.save()
        AppLog.library.info("Gộp trùng: xoá \(repointing.count, privacy: .public) hàng.")
        return repointing.count
    }

    /// Trả về ánh xạ `id bị xoá → id được giữ`, thứ mà `PlaybackState` cần để
    /// trỏ lại.
    private static func sweep<M: PersistentModel>(
        _ type: M.Type,
        in context: ModelContext,
        key: (M) -> String,
        candidate: (M) -> MergeCandidate,
        apply: (M, GroupMerge) -> Void
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
                    context.delete(row)
                }
            }
        }
        return repointing
    }
}
```

- [ ] **Step 4: Chạy lượt quét lúc khởi động**

Trong `Evenstar/Evenstar/App/EvenstarApp.swift`, thêm `.task` vào `RootView()` trong `WindowGroup`, **sau** chuỗi `.environment(...)`:

```swift
                .task {
                    // Một lượt mỗi lần mở app. Hàng trùng đến trong phiên này
                    // được dọn ở lần mở sau — xem `DuplicateSweep`.
                    //
                    // Thất bại chỉ ghi log: một lượt dọn dẹp không chạy được
                    // không phải lý do để chặn người dùng nghe nhạc.
                    do {
                        try DuplicateSweep.run(context: modelContainer.mainContext)
                    } catch {
                        AppLog.library.error(
                            "Lượt gộp trùng thất bại: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
```

- [ ] **Step 5: Chạy toàn bộ bó test**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`

Expected: PASS toàn bộ. `PlayerCardCommitCostControlTests` đổ thì chạy lại một lần, **không hạ ngưỡng**.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Services/DuplicateSweep.swift Evenstar/Evenstar/App/EvenstarApp.swift Evenstar/EvenstarTests/DuplicateSweepTests.swift
git commit -m "feat: lượt gộp trùng lúc khởi động, chỉ trên hai bảng có khoá thật"
```

---

### Task 4: Bài nào có file trên máy này

**Files:**
- Create: `Evenstar/Evenstar/Services/TrackPresence.swift`
- Test: `Evenstar/EvenstarTests/TrackPresenceTests.swift` (mới)

**Interfaces:**
- Consumes: `FileLocation.musicFolderURL(_:)` — đã có.
- Produces:
  - `static func TrackPresence.scan(musicFolder: URL = FileLocation.musicFolderURL()) -> Set<String>`
  - `static func TrackPresence.isPresent(_ relativePath: String, in present: Set<String>) -> Bool`
  - `enum TrackPresence.DeleteAction: Equatable { case deleteNow, confirmFirst }`
  - `static func TrackPresence.deleteAction(isPresent: Bool) -> DeleteAction`

- [ ] **Step 1: Viết test thất bại**

Tạo `Evenstar/EvenstarTests/TrackPresenceTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// Bài nào thật sự có file trên máy này.
///
/// Nền của cả nhóm test: CloudKit đồng bộ *hàng dữ liệu* chứ không đồng bộ
/// *file nhạc*. Nên một máy nhận về hàng mô tả bài nó không có, và phải nói ra
/// điều đó thay vì chạm vào rồi im lặng không phát.
final class TrackPresenceTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("presence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    /// Tập trả về phải cùng dạng với `Track.relativePath` thì mới so thẳng
    /// được — `ImportService` dựng `"Music/\(id.uuidString).\(ext)"`.
    func testScanReportsPathsInTheSameShapeAsRelativePath() throws {
        try touch("a.mp3")
        try touch("b.flac")
        XCTAssertEqual(TrackPresence.scan(musicFolder: folder), ["Music/a.mp3", "Music/b.flac"])
    }

    /// Người dùng chưa nhập bài nào thì thư mục `Music/` chưa tồn tại. Đó là
    /// trạng thái bình thường của một bản cài mới, không phải lỗi — trả tập
    /// rỗng chứ không ném.
    func testAMissingFolderIsAnEmptySetRatherThanAnError() {
        let missing = folder.appendingPathComponent("không-có-thật", isDirectory: true)
        XCTAssertEqual(TrackPresence.scan(musicFolder: missing), [])
    }

    func testAnEmptyFolderIsAnEmptySet() {
        XCTAssertEqual(TrackPresence.scan(musicFolder: folder), [])
    }

    func testAPathIsPresentOnlyWhenTheScanFoundIt() {
        let present: Set<String> = ["Music/a.mp3"]
        XCTAssertTrue(TrackPresence.isPresent("Music/a.mp3", in: present))
        XCTAssertFalse(TrackPresence.isPresent("Music/b.mp3", in: present))
        XCTAssertFalse(TrackPresence.isPresent("Music/a.mp3", in: []))
    }

    /// Xoá một bài **có mặt** là chuyện thường ngày và không được hỏi lại —
    /// hỏi lại mọi lần làm người dùng bấm qua mà không đọc, và đúng lúc lời
    /// cảnh báo quan trọng thì họ cũng bấm qua nốt.
    func testDeletingAPresentTrackAsksNothing() {
        XCTAssertEqual(TrackPresence.deleteAction(isPresent: true), .deleteNow)
    }

    /// Xoá một bài **vắng mặt** trông như dọn một hàng rác, nhưng nó gỡ bài
    /// khỏi **mọi máy**, kể cả máy đang giữ file thật. Đó là chỗ duy nhất trong
    /// app mà một thao tác nhỏ có hậu quả trên máy khác.
    func testDeletingAnAbsentTrackMustBeConfirmed() {
        XCTAssertEqual(TrackPresence.deleteAction(isPresent: false), .confirmFirst)
    }
}
```

- [ ] **Step 2: Chạy test để chắc nó thất bại**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/TrackPresenceTests`

Expected: FAIL lúc biên dịch — `cannot find 'TrackPresence' in scope`.

- [ ] **Step 3: Viết `TrackPresence.swift`**

Tạo `Evenstar/Evenstar/Services/TrackPresence.swift`:

```swift
import Foundation

/// Bài nào thật sự có file trên **máy này**.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO KHÔNG PHẢI MỘT THUỘC TÍNH CỦA `@Model`
/// ─────────────────────────────────────────────────────────────────────────
/// Sự có mặt của file là thuộc tính của **máy**, không phải của bài. Lưu nó vào
/// `Track` là sai ngay từ định nghĩa: máy A ghi `true`, CloudKit đồng bộ sang
/// máy B, và B đọc `true` cho một file nó không hề có.
///
/// Nên nó được tính tại chỗ, không lưu, và không bao giờ đi qua CloudKit.
///
/// Chỉ áp cho `Track`. `DriveTrack` và `JamendoTrack` là URL mạng — chúng không
/// có khái niệm "có trên máy này".
enum TrackPresence {

    /// Mọi `Track.relativePath` bắt đầu bằng đúng chuỗi này: `ImportService`
    /// dựng `"Music/\(id.uuidString).\(ext)"`. Tập trả về phải cùng dạng thì
    /// mới so thẳng được với `relativePath` mà không phải cắt gọt hai đầu.
    private static let musicPrefix = "Music/"

    /// Một lượt đọc thư mục cho cả thư viện, không phải một `fileExists` cho
    /// mỗi hàng. Với một thư viện vài nghìn bài, cái sau là vài nghìn syscall
    /// trên luồng chính.
    ///
    /// Không đệ quy, vì `ImportService` để mọi file phẳng trong `Music/`.
    ///
    /// Thư mục chưa tồn tại trả tập rỗng chứ không ném: đó là trạng thái bình
    /// thường của một bản cài chưa nhập bài nào.
    ///
    /// - Parameter musicFolder: tham số hoá để test được với một thư mục tạm.
    static func scan(musicFolder: URL = FileLocation.musicFolderURL()) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: musicFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return Set(contents.map { musicPrefix + $0.lastPathComponent })
    }

    static func isPresent(_ relativePath: String, in present: Set<String>) -> Bool {
        present.contains(relativePath)
    }

    /// Xoá bài này có phải hỏi lại không.
    ///
    /// Mỏng, và cố ý mỏng — giá trị nằm ở **tên**, không ở phép tính. Ở chỗ gọi,
    /// `case .confirmFirst` đọc ra là một quyết định; `if !isPresent` đọc ra là
    /// một điều kiện, và điều kiện thì dễ bị đảo ngược trong một lần sửa vội mà
    /// không ai nhận ra.
    enum DeleteAction: Equatable {
        case deleteNow
        case confirmFirst
    }

    /// Xoá một bài vắng mặt trông như dọn một hàng rác, nhưng nó gỡ bài khỏi
    /// **mọi máy** — kể cả máy đang giữ file thật.
    static func deleteAction(isPresent: Bool) -> DeleteAction {
        isPresent ? .deleteNow : .confirmFirst
    }
}
```

- [ ] **Step 4: Chạy test để chắc nó qua**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/TrackPresenceTests`

Expected: PASS cả 7 test.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Services/TrackPresence.swift Evenstar/EvenstarTests/TrackPresenceTests.swift
git commit -m "feat: tính bài nào có file trên máy này, một lượt đọc thư mục"
```

---

### Task 5: `LibraryStore` giữ tập bài có mặt

**Files:**
- Modify: `Evenstar/Evenstar/Services/LibraryStore.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` (nạp tập lúc khởi động)
- Test: `Evenstar/EvenstarTests/LibraryStoreTests.swift` (thêm test, không sửa test cũ)

**Interfaces:**
- Consumes: `TrackPresence.scan(musicFolder:)`, `TrackPresence.isPresent(_:in:)` từ Task 4.
- Produces:
  - `LibraryStore.init(tracks: [Track] = [], presentRelativePaths: Set<String> = [])`
  - `var LibraryStore.presentRelativePaths: Set<String> { get }` (`private(set)`)
  - `func LibraryStore.isPresent(_ track: Track) -> Bool`

- [ ] **Step 1: Viết test thất bại**

Thêm vào cuối `final class LibraryStoreTests` trong `Evenstar/EvenstarTests/LibraryStoreTests.swift`:

```swift
    /// Hàng có file trên máy này thì phát được; hàng đến từ máy khác thì không.
    func testAtrackIsPresentOnlyWhenItsFileIsInTheScannedSet() throws {
        let here = InMemoryLibrary.makeTrack(relativePath: "Music/here.mp3")
        let elsewhere = InMemoryLibrary.makeTrack(relativePath: "Music/elsewhere.mp3")
        let store = LibraryStore(
            tracks: [here, elsewhere],
            presentRelativePaths: ["Music/here.mp3"]
        )
        XCTAssertTrue(store.isPresent(here))
        XCTAssertFalse(store.isPresent(elsewhere))
    }

    /// Vừa nhập xong một bài mà nó hiện mờ với chữ "không có trên máy này" là
    /// một lỗi nhìn thấy ngay, và nó xảy ra nếu tập có mặt chỉ được nạp một lần
    /// lúc khởi động. Nên nó được quét lại mỗi khi tập hàng đổi.
    func testTheScannedSetIsRefreshedWhenTheRowSetChanges() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = LibraryStore(musicFolder: folder)
        let imported = InMemoryLibrary.makeTrack(relativePath: "Music/new.mp3")
        XCTAssertFalse(store.isPresent(imported), "Chưa có file thì chưa có mặt.")

        try Data().write(to: folder.appendingPathComponent("new.mp3"))
        store.replace(with: [imported])

        XCTAssertTrue(store.isPresent(imported), "Sau khi tập hàng đổi, phải quét lại.")
    }
```

- [ ] **Step 2: Chạy test để chắc nó thất bại**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/LibraryStoreTests`

Expected: FAIL lúc biên dịch — `LibraryStore` chưa có `presentRelativePaths`, `isPresent(_:)` hay `init(musicFolder:)`.

- [ ] **Step 3: Sửa `LibraryStore`**

Thay `init` và `replace(with:)` hiện có, giữ nguyên `remove(_:)` và toàn bộ doc comment ở tầng kiểu:

```swift
    /// Đường dẫn tương đối của những file thật sự nằm trên máy này.
    ///
    /// **Không phải một thuộc tính của `Track`, và không bao giờ được thành
    /// một** — xem `TrackPresence` về lý do. Nó sống ở đây vì đây đã là chỗ
    /// duy nhất mọi màn hình đọc thư viện.
    private(set) var presentRelativePaths: Set<String>

    /// Thư mục để quét. Tham số hoá chỉ để test được với một thư mục tạm; ở
    /// bản chạy thật nó luôn là `FileLocation.musicFolderURL()`.
    private let musicFolder: URL

    init(tracks: [Track] = [],
         presentRelativePaths: Set<String> = [],
         musicFolder: URL = FileLocation.musicFolderURL()) {
        self.tracks = tracks
        self.presentRelativePaths = presentRelativePaths
        self.musicFolder = musicFolder
    }

    /// Bài này có phát được trên máy này không.
    func isPresent(_ track: Track) -> Bool {
        TrackPresence.isPresent(track.relativePath, in: presentRelativePaths)
    }

    /// Takes a fresh fetch, and ignores one that says nothing new.
    ///
    /// The guard matters because every assignment to an `@Observable` property
    /// wakes its readers whether or not the value moved, and the readers here
    /// are five screens. The comparison is by persistent identity — SwiftData
    /// rows are `Equatable` that way — so it answers "same rows, same order",
    /// which is exactly the question the screens care about.
    ///
    /// **Quét lại tập có mặt nằm sau cái chốt ấy, và chỗ đặt là có tính toán.**
    /// Đặt trước chốt thì mỗi lần lưu bất kỳ thuộc tính nào cũng tốn một lượt
    /// đọc thư mục. Đặt sau chốt thì nó chỉ chạy khi tập hàng thật sự đổi —
    /// nghĩa là lúc nhập và lúc xoá, đúng hai lúc file trên đĩa có thể đã khác.
    ///
    /// Cái nó **không** bắt được là file bị xoá từ ngoài app trong lúc app đang
    /// chạy: không hàng nào đổi nên không quét lại. Chịu được, vì vòng bỏ-qua
    /// trong `PlaybackService.loadCurrentAndPlay()` vẫn không cho nhạc dừng.
    func replace(with fetched: [Track]) {
        guard fetched != tracks else { return }
        tracks = fetched
        presentRelativePaths = TrackPresence.scan(musicFolder: musicFolder)
    }
```

- [ ] **Step 4: Nạp tập có mặt lúc khởi động**

Trong `Evenstar/Evenstar/App/EvenstarApp.swift`, đổi hai chỗ dựng `LibraryStore` trong `init()`:

```swift
        let store: LibraryStore
        // Cùng lượt quét mà `replace(with:)` sẽ chạy lại về sau, làm ngay ở đây
        // để khung hình đầu tiên vẽ đúng hàng nào mờ — không phải vẽ đủ rồi mờ
        // đi ở khung thứ hai.
        let present = TrackPresence.scan()
        do {
            store = LibraryStore(tracks: try libService.fetchAllTracks(),
                                 presentRelativePaths: present)
        } catch {
            AppLog.library.error("Initial library fetch failed: \(error.localizedDescription, privacy: .public)")
            store = LibraryStore(presentRelativePaths: present)
        }
```

- [ ] **Step 5: Chạy toàn bộ bó test**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`

Expected: PASS toàn bộ.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Services/LibraryStore.swift Evenstar/Evenstar/App/EvenstarApp.swift Evenstar/EvenstarTests/LibraryStoreTests.swift
git commit -m "feat: LibraryStore giữ tập file có trên máy này, quét lại khi tập hàng đổi"
```

---

### Task 6: Hàng vắng mặt hiện mờ, và chạm vào không phát

**Files:**
- Modify: `Evenstar/Evenstar/Features/Library/SongRow.swift`
- Modify: `Evenstar/Evenstar/Features/Library/SongsView.swift`
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes: `LibraryStore.isPresent(_:)` từ Task 5.
- Produces: `SongRow(track:subtitle:isAbsent:)` — `isAbsent` mặc định `false`, nên hai chỗ gọi hiện có (`DriveSongsList`, `JamendoSongsList`) không phải đổi.

- [ ] **Step 1: Thêm chuỗi vào String Catalog**

Chuỗi mới cần dùng: **`Không có trên máy này`** → en: **`Not on this device`**.

Trước hết kiểm nó chưa tồn tại:

```bash
cd /Users/phanquyetthang/evenstar/Evenstar/Evenstar && python3 -c "
import json; d=json.load(open('Localizable.xcstrings'))
print('Không có trên máy này' in d['strings'])"
```

Nếu in ra `False`, thêm bằng script (giữ nguyên thứ tự khoá và định dạng file):

```bash
cd /Users/phanquyetthang/evenstar/Evenstar/Evenstar && python3 - <<'PY'
import json, collections
path = 'Localizable.xcstrings'
with open(path) as f:
    doc = json.load(f, object_pairs_hook=collections.OrderedDict)
doc['strings']['Không có trên máy này'] = collections.OrderedDict([
    ('localizations', collections.OrderedDict([
        ('en', {'stringUnit': {'state': 'translated', 'value': 'Not on this device'}}),
        ('vi', {'stringUnit': {'state': 'translated', 'value': 'Không có trên máy này'}}),
    ]))
])
with open(path, 'w') as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write('\n')
print('ok')
PY
```

**Không sắp xếp lại `doc['strings']`.** Xcode giữ khoá theo thứ tự chữ cái của *nó*, và phép sắp xếp của Python trên chữ tiếng Việt có dấu cho thứ tự khác — một lệnh `sorted()` ở đây xáo lại cả 135 khoá và biến một chuỗi mới thành một diff không ai đọc nổi. Khoá mới nằm cuối file là được; Xcode tự đưa nó về đúng chỗ ở lần nó ghi file sau.

Kiểm ngay sau khi chạy:

```bash
cd /Users/phanquyetthang/evenstar && git diff --stat Evenstar/Evenstar/Localizable.xcstrings
```

Phải thấy khoảng **8 dòng thêm, 0 dòng bớt**. Nhiều hơn thế nghĩa là script đã động vào phần không phải của nó — `git checkout` file ấy rồi làm lại.

- [ ] **Step 2: Sửa `SongRow`**

Thêm thuộc tính và nhánh hiển thị:

```swift
    /// Bài này không có file trên máy đang chạy.
    ///
    /// Mặc định `false`, nên `DriveSongsList` và `JamendoSongsList` không phải
    /// đổi một chữ: một `DriveTrack` hay `JamendoTrack` là URL mạng, và "có
    /// trên máy này" không có nghĩa gì với chúng.
    ///
    /// Nhãn chữ chứ không chỉ làm mờ, và đó không phải trang trí: độ mờ một
    /// mình không đọc được bằng VoiceOver, và cũng không phân biệt được với
    /// một hàng đang bị vô hiệu vì lý do khác.
    var isAbsent: Bool = false
```

Trong `body`, thay `VStack` hiện có:

```swift
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                if isAbsent {
                    Label("Không có trên máy này", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(subtitle ?? track.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
```

Và ở cuối `body`, sau `.padding(.vertical, 4)`:

```swift
        .opacity(isAbsent ? 0.55 : 1)
```

- [ ] **Step 3: Sửa `SongsView` — truyền cờ và chặn chạm**

Trong `localContent`, thay khối `SongRow(track: track)` và `.onTapGesture`:

```swift
                SongRow(track: track, isAbsent: !store.isPresent(track))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Chạm vào hàng vắng mặt không làm gì, và **không** bật
                        // một hộp thoại giải thích: hàng đã mờ và đã mang chữ
                        // "Không có trên máy này" trước khi ngón tay chạm vào.
                        // Một hộp thoại cho mỗi cú chạm nhầm là tiếng ồn, và nó
                        // dạy người dùng bấm-qua-không-đọc đúng lúc lời cảnh
                        // báo lúc xoá cần được đọc.
                        guard store.isPresent(track) else { return }
                        playback.play(track, in: tracks)
                    }
```

Phần `.swipeActions` và `.contextMenu` phía dưới giữ nguyên.

- [ ] **Step 4: Dựng và chạy toàn bộ bó test**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`

Expected: PASS toàn bộ. Không có test mới ở task này — nó là hiển thị, và cái đo được của nó (`isPresent`) đã có test ở Task 4 và 5. **Cổng thủ công B** ở cuối plan kiểm phần nhìn.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Library Evenstar/Evenstar/Localizable.xcstrings
git commit -m "feat: hàng không có file trên máy này hiện mờ và không phát khi chạm"
```

---

### Task 7: Cảnh báo trước khi xoá một bài vắng mặt

Chỗ duy nhất trong app mà một thao tác nhỏ có hậu quả trên **máy khác**.

**Files:**
- Modify: `Evenstar/Evenstar/Features/Library/SongsView.swift`
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes: `TrackPresence.deleteAction(isPresent:)` từ Task 4, `LibraryStore.isPresent(_:)` từ Task 5.
- Produces: không có API mới.

- [ ] **Step 1: Thêm chuỗi vào String Catalog**

Ba chuỗi, thêm bằng cùng script như Task 6 Step 1:

| vi | en |
|---|---|
| `Xoá khỏi mọi máy?` | `Delete from all devices?` |
| `Bài này không có trên máy này. Xoá sẽ gỡ nó khỏi mọi máy.` | `This song isn't on this device. Deleting removes it from all your devices.` |
| `Huỷ` | `Cancel` |

Kiểm `Xoá` và `Huỷ` đã có chưa trước khi thêm:

```bash
cd /Users/phanquyetthang/evenstar/Evenstar/Evenstar && python3 -c "
import json; d=json.load(open('Localizable.xcstrings'))
for k in ['Xoá', 'Huỷ', 'Xoá khỏi mọi máy?']: print(k, k in d['strings'])"
```

**Chú ý câu chữ:** thông báo nói *"không có trên máy này"* chứ **không** nói *"có trên một máy khác"*. App không biết được điều thứ hai — một bài vắng mặt có thể là file bị xoá từ ngoài app trên một máy dùng đơn lẻ, và lúc ấy câu kia là nói dối. Câu đã chọn đúng trong cả hai trường hợp.

- [ ] **Step 2: Thêm trạng thái và tách đường xoá trong `SongsView`**

Thêm vào khối `@State` ở đầu `struct SongsView`:

```swift
    /// Bài đang chờ xác nhận xoá vì nó không có trên máy này. `nil` khi không
    /// có hộp thoại nào đang mở.
    ///
    /// Giữ chính hàng chứ không giữ `persistentModelID`: khác với
    /// `artworkTarget`, đường này không đi qua một picker của hệ thống có thể
    /// đóng mà không báo, và hàng vẫn sống suốt lúc hộp thoại mở.
    @State private var pendingAbsentDelete: Track?
```

Thay `deleteTrack(_:)` bằng hai hàm:

```swift
    /// Vào đây từ cú vuốt. Bài có mặt thì xoá luôn; bài vắng mặt thì hỏi trước.
    ///
    /// Xoá một bài vắng mặt trông như dọn một hàng rác nhưng nó gỡ bài khỏi
    /// **mọi máy**, kể cả máy đang giữ file thật. Xem `TrackPresence.deleteAction`.
    private func deleteTrack(_ track: Track) {
        switch TrackPresence.deleteAction(isPresent: store.isPresent(track)) {
        case .deleteNow:
            performDelete(track)
        case .confirmFirst:
            pendingAbsentDelete = track
        }
    }

    private func performDelete(_ track: Track) {
        // No `playback.handleTrackDeleted(track)` here any more, and its absence
        // is the fix rather than an omission: `LibraryService.delete(_:)` now
        // announces the row itself, so the ordering this view used to be
        // responsible for cannot be got wrong by the next caller. See
        // `LibraryService.onTrackWillBeDeleted`.
        do {
            try library.delete(track)
        } catch {
            // 2a: log only. A polished alert is part of 2d.
            AppLog.library.error("Delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
```

- [ ] **Step 3: Thêm hộp thoại**

Sau `.alert("Không mở được file", ...)` hiện có, thêm:

```swift
        .alert(
            "Xoá khỏi mọi máy?",
            isPresented: Binding(
                get: { pendingAbsentDelete != nil },
                set: { isPresented in
                    if !isPresented { pendingAbsentDelete = nil }
                }
            ),
            presenting: pendingAbsentDelete
        ) { track in
            Button("Xoá", role: .destructive) { performDelete(track) }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("Bài này không có trên máy này. Xoá sẽ gỡ nó khỏi mọi máy.")
        }
```

`presenting:` chứ không đọc `pendingAbsentDelete` trong closure: nó đưa hàng vào closure như một tham số, nên nút "Xoá" không đọc một `@State` có thể đã bị dọn về `nil` trước khi hành động chạy.

- [ ] **Step 4: Chạy toàn bộ bó test**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`

Expected: PASS toàn bộ.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Library/SongsView.swift Evenstar/Evenstar/Localizable.xcstrings
git commit -m "feat: hỏi lại trước khi xoá một bài không có trên máy này"
```

---

### Task 8: Ghim hành vi bỏ qua bài vắng mặt

**Không sửa một dòng mã sản phẩm nào.** `PlaybackService.loadCurrentAndPlay()` đã bỏ qua bài không mở được, và cả thiết kế này dựa vào đó. Task này làm cho một lần sửa vô ý ở đó thành một test đỏ thay vì một lần nhạc dừng trong im lặng.

**Files:**
- Test: `Evenstar/EvenstarTests/AbsentTrackPlaybackTests.swift` (mới)

**Interfaces:**
- Consumes: `MockAudioPlayer.failingURLs` (đã có), `InMemoryLibrary.make()` (đã có).
- Produces: không có.

- [ ] **Step 1: Viết test**

Tạo `Evenstar/EvenstarTests/AbsentTrackPlaybackTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// Hàng đợi gặp một bài không có file trên máy này thì **đi tiếp**, không dừng.
///
/// Đây là test ghim một hành vi **đã có sẵn**, không phải test cho mã mới, và
/// lý do nó tồn tại đáng được viết ra: từ khi có CloudKit, một máy nhận về hàng
/// mô tả những bài nó không có file. Chúng nằm lẫn trong mọi hàng đợi dựng từ
/// thư viện. `loadCurrentAndPlay()` bỏ qua chúng vì `AVAudioPlayer(contentsOf:)`
/// ném lỗi với file vắng mặt — một cơ chế viết cho "file hỏng hoặc đã bị xoá",
/// giờ gánh thêm một ca thường xuyên hơn hẳn.
///
/// Không có test này thì một lần dọn dẹp `loadCurrentAndPlay()` làm nhạc dừng
/// giữa chừng ở đúng những máy có nhiều bài vắng mặt nhất, và không gì đỏ lên.
@MainActor
final class AbsentTrackPlaybackTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        var out: [Track] = []
        for i in 0..<count {
            let t = Track(
                title: "Track \(i)",
                artistName: "Artist",
                albumTitle: "Album",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3",
                format: "mp3"
            )
            try library.insert(t)
            out.append(t)
        }
        return out
    }

    /// Bài giữa hàng đợi vắng mặt: nhảy qua nó, phát bài sau, và hàng đợi
    /// **không** bị cắt gọt — bài ấy có thể phát được trên máy khác.
    func testAnAbsentTrackInTheMiddleIsSkipped() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        player.failingURLs = [all[1].playbackURL()]

        service.play(all[0], in: all)
        service.next()

        XCTAssertEqual(player.loadedURL, all[2].playbackURL(),
                       "Phải nhảy qua bài vắng mặt và phát bài sau nó.")
        XCTAssertEqual(service.queue.count, 3, "Hàng đợi không được cắt bớt.")
    }

    /// **Ca phải chặn vòng lặp vô hạn.** Mọi bài còn lại đều vắng mặt — điều
    /// hoàn toàn bình thường trên một máy vừa đồng bộ xong mà chưa nhập file
    /// nào. Vòng lặp phải dừng hẳn, không quay vòng.
    ///
    /// Bó test treo cứng ở đây thì đó chính là lỗi cần bắt, và nó bắt được vì
    /// vòng lặp có chặn trên `queue.count`.
    func testAQueueOfEntirelyAbsentTracksStopsRatherThanLooping() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        player.failingURLs = Set(all.map { $0.playbackURL() })

        service.play(all[0], in: all)

        XCTAssertFalse(service.isPlaying, "Không mở được bài nào thì phải dừng.")
    }

    /// Cùng ca trên nhưng có repeat bật. `loadCurrentAndPlay()` quay về đầu
    /// hàng đợi khi hết, nên đây là đường dễ lặp vô hạn nhất — và nó vẫn dừng
    /// vì mỗi lần thử đều tăng bộ đếm, kể cả lần quay vòng.
    func testRepeatAllDoesNotLoopForeverOverAbsentTracks() throws {
        let (service, player, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)
        service.repeatMode = .all
        player.failingURLs = Set(all.map { $0.playbackURL() })

        service.next()

        XCTAssertFalse(service.isPlaying)
    }
}
```

**Ghi chú cho người thi công:** ba tên có thể khác trong mã thật — `service.queue`, `service.repeatMode` (có thể là `cycleRepeatMode()`), và `Track.playbackURL()`. Đọc `PlaybackServiceRepeatTests.swift` và `Playable.swift` rồi dùng đúng tên đang có; **không** thêm API mới vào `PlaybackService` chỉ để test gọi được.

Nếu một trong ba test này **qua ngay mà không cần sửa gì** — đó là kết quả mong đợi, vì hành vi đã có sẵn. Nếu một test **đỏ**, dừng lại và báo: nghĩa là giả định nền của cả thiết kế sai, và các Task 6/7 phải xem lại.

- [ ] **Step 2: Chạy**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test -only-testing:EvenstarTests/AbsentTrackPlaybackTests`

Expected: PASS cả 3 test **không cần sửa mã sản phẩm**.

- [ ] **Step 3: Commit**

```bash
git add Evenstar/EvenstarTests/AbsentTrackPlaybackTests.swift
git commit -m "test: ghim vòng bỏ qua bài vắng mặt, thứ cả thiết kế đồng bộ dựa vào"
```

---

## CỔNG BÀN GIAO — bật iCloud trong Xcode. Dừng ở đây.

**Người thi công không làm được bước này**: nó sửa `.pbxproj`, và ràng buộc của dự án cấm agent chạm vào file đó.

Người dùng làm trong Xcode:

1. Chọn target **Evenstar** → tab **Signing & Capabilities**
2. **+ Capability** → **iCloud** → tick **CloudKit**
3. Thêm container: **`iCloud.com.evenstar.app`**
4. **+ Capability** → **Background Modes** → tick **Remote notifications**

**Bước 4 dễ sót và hậu quả im lặng:** thiếu nó thì đồng bộ chỉ chạy khi app đang mở, máy kia không cập nhật cho tới lần mở app tiếp theo, và nó trông y hệt như đồng bộ hỏng.

Xong bước này Xcode sẽ tạo `Evenstar/Evenstar/Evenstar.entitlements` và thêm nó vào `.pbxproj`. Xác nhận:

```bash
cd /Users/phanquyetthang/evenstar && git status --short && cat Evenstar/Evenstar/Evenstar.entitlements
```

Phải thấy `com.apple.developer.icloud-container-identifiers` chứa `iCloud.com.evenstar.app`, và `com.apple.developer.icloud-services` chứa `CloudKit`.

---

### Task 9: Bật CloudKit

**Chặn bởi cổng bàn giao ngay trên.** Không bắt đầu khi `Evenstar.entitlements` chưa tồn tại.

**Files:**
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift`

**Interfaces:**
- Consumes: không có.
- Produces: không có API mới.

- [ ] **Step 1: Kiểm entitlements đã có**

```bash
cd /Users/phanquyetthang/evenstar && test -f Evenstar/Evenstar/Evenstar.entitlements && grep -q "iCloud.com.evenstar.app" Evenstar/Evenstar/Evenstar.entitlements && echo "SẴN SÀNG" || echo "DỪNG — chưa bật capability trong Xcode"
```

In ra `DỪNG` thì dừng và báo lại; không đi tiếp.

- [ ] **Step 2: Đổi cách dựng container**

Trong `EvenstarApp.init()`, thay khối `do { container = try ModelContainer(...) }`:

```swift
        let container: ModelContainer
        do {
            // `.private` chứ không `.automatic`: `.automatic` chọn container
            // theo entitlement, thứ đọc được từ file nhưng không đọc được từ
            // đây. Viết thẳng tên ra làm một cấu hình sai thành lỗi lúc chạy
            // ngay lần đầu, thay vì thành một app đồng bộ vào nhầm chỗ.
            //
            // Đổi tên này thì phải đổi cả trong Signing & Capabilities của
            // target, và phải Deploy Schema to Production lại.
            let configuration = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.evenstar.app")
            )
            container = try ModelContainer(
                for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self, JamendoTrack.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
```

`fatalError` giữ nguyên và đó là quyết định: một app không mở được kho dữ liệu thì không có gì để hiện. Nhưng nó cũng là lý do **Cổng thủ công A** phải đã qua trước khi tới đây — nếu migration hỏng, đây là chỗ nó thành một cú crash lúc mở app.

- [ ] **Step 3: Chạy toàn bộ bó test**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`

Expected: PASS toàn bộ, **không đổi con số nào**. Bó test dựng `ModelConfiguration(isStoredInMemoryOnly: true)` riêng của nó trong `EvenstarTests/InMemoryLibrary.swift` và trong `DuplicateSweepTests`, nên container CloudKit của app không đi vào đường ấy.

Nếu bó test **bắt đầu** đòi entitlement iCloud, nghĩa là có một test nào đó đang dùng container của app thay vì dựng container riêng. Tìm nó và cho nó dựng container riêng; **không** thêm entitlement vào target test.

- [ ] **Step 4: Commit**

```bash
git add Evenstar/Evenstar/App/EvenstarApp.swift
git commit -m "feat: bật CloudKit cho container chính"
```

---

## CỔNG THỦ CÔNG B — kiểm bằng tay. Không có test tự động nào thay được.

Bốn mục. Ba mục đầu cần **một** máy; mục cuối cần **hai**.

- [ ] **B1 — Hàng vắng mặt trông đúng.** Nhập vài bài. Đóng app, xoá thủ công một file trong `Music/` của bản cài (qua Files hoặc qua container simulator), mở lại app. Hàng ấy phải mờ và mang chữ "Không có trên máy này". Chạm vào: **không** phát, **không** có hộp thoại nào bật lên.

- [ ] **B2 — Cảnh báo lúc xoá.** Vuốt xoá đúng hàng ấy. Phải hiện "Xoá khỏi mọi máy?". Bấm **Huỷ**: hàng còn nguyên. Vuốt xoá một hàng **có mặt**: xoá luôn, **không** hỏi.

- [ ] **B3 — VoiceOver.** Bật VoiceOver, vuốt tới hàng vắng mặt. Phải nghe được chữ "Không có trên máy này" — độ mờ một mình không nói gì.

- [ ] **B4 — Đồng bộ thật, hai máy.** Hai máy cùng đăng nhập một Apple Account, cả hai cài bản này. Trên máy A lưu một bài Jamendo. Trong vòng ~30 giây máy B phải thấy nó. Trên máy B, bài ấy phát được (là URL mạng, không phải file). Nhập một bài **file** trên máy A: máy B phải thấy hàng ấy **mờ**.

**Chuyện Development / Production, làm trước mỗi lần phát hành:**

CloudKit có hai môi trường tách biệt. Schema tự sinh ở **Development** từ lần chạy đầu. Bản **Release** nói chuyện với **Production**, và schema ở đó **không tự có** — triệu chứng là bản Debug đồng bộ tốt, bản phát hành không đồng bộ gì cả, và **không một thông báo lỗi nào**.

Vào CloudKit Console → **Deploy Schema to Production** trước mỗi lần phát hành có đổi model. Đây là việc thường trực, không phải việc một lần.

---

## Sau khi xong

Dùng `superpowers:finishing-a-development-branch`.

Hai việc còn treo ngoài plan này:

- Nhánh `onboarding` vẫn chưa gộp, với hai bước kiểm tay chưa làm.
- Gộp hai hàng `Track` cùng bài ở **tầng hiển thị** — người dùng thấy bài ấy hai dòng khi nó có trên hai máy. Không thuộc plan này, và cần một thiết kế riêng vì hai dòng ấy là hai file thật.
