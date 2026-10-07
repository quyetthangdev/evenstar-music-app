# Liquid Glass native — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thay thanh tab, cú thu nhỏ khi cuộn, viên mini player và các nút tự vẽ của Evenstar bằng thành phần Liquid Glass native của iOS 26, giữ cú bung player theo ngón tay và thêm vuốt ngang để đổi bài.

**Architecture:** `RootView` dùng `TabView` native với `Tab(role: .search)`, `.tabBarMinimizeBehavior(.onScrollDown)` và `.tabViewBottomAccessory`. Viên kính accessory là của hệ thống; nội dung của nó (`MiniPlayerAccessory`) báo khung đo được lên `PlayerExpansion`. `PlayerCard` không tự tính chỗ viên pill nữa mà bung ra từ khung ấy, qua một hàm hình học thuần (`PlayerAnchor`), và đặc ngay từ khung đầu như Apple Music. Cử chỉ trên accessory đi vào thẻ qua `PlayerExpansion`: kéo dọc ghi thẳng một phần `progress` mỗi khung, còn chạm và thả là một `PlayerIntent` mà thẻ thực hiện bằng hàm `morph` của nó.

**Tech Stack:** Swift 6, SwiftUI iOS 26 SDK (Xcode 26.0.1), Observation, XCTest. Không thêm thư viện.

**Spec:** `docs/superpowers/specs/2026-10-06-native-liquid-glass-design.md`

## Global Constraints

- Deployment target **iOS 26.0** cho cả `Evenstar` và `EvenstarTests`. Người dùng tự đổi trong Xcode; agent **không bao giờ** sửa `project.pbxproj` hay `*.xcscheme`.
- Không thêm thư viện bên thứ ba.
- Không dùng `#available(iOS 26, *)`: target đã là 26.
- `\.tabViewBottomAccessoryPlacement` chỉ được đọc để ẩn/hiện nút ⏭ (mờ dần, như Apple Music), không cho kích thước hay bố cục nào khác. Spike thấy nó không ổn định trên simulator iOS 26.0; Task 6 kiểm trên máy thật.
- Thẻ player **đặc ngay từ khung đầu khi bung**, không có lớp kính. **Khi thu**, cú co mềm kiểu zoom trên lò xo không nảy, ở đoạn cuối mặt thẻ chuyển sang `.glassEffect` rồi nhường cho accessory bằng cú mờ ngắn (chốt 2026-10-07 — xem spec Phần 1).
- Chỉ **một** chỗ đọc `accessibilityReduceMotion`: `RootView`. Mọi chỗ khác đọc `BottomBarStyle.reduceMotion`.
- `RootView.body` không được đọc `playback.currentTrack` hay bất cứ thứ gì đổi theo bài, vì body ấy dựng lại `TabView` và năm tab.
- Mọi chuỗi hiển thị mới dùng chuỗi tiếng Việt làm khoá và đi qua String Catalog như phần còn lại của app.
- Bản Release phải build **không một cảnh báo**.
- Lệnh test chuẩn, chạy từ gốc repo (DerivedData đặt trong `build/`, đã được gitignore, để không phụ thuộc ổ ngoài):

  ```bash
  xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
    -destination 'platform=iOS Simulator,name=iPhone 17 test' \
    -derivedDataPath build/DerivedData -parallel-testing-enabled NO 2>&1 | tail -30
  ```

  Một lớp test: thêm `-only-testing:EvenstarTests/<TênLớp>`. Đếm test bằng `xcrun xcresulttool get test-results summary --path <.xcresult mới nhất>`, **không** bằng grep log (dự án từng đếm sai theo cách đó).

## Review Focus

1. **Chạm một bài trong danh sách lúc chưa có bài nào phát.** Accessory và cú bung xuất hiện cùng một lượt, nên khung accessory chưa từng được đo. Thẻ phải bung từ khung dự phòng ở đáy màn, không phải từ góc (0, 0). Ghim ở Task 1 (`resolve` với `.zero`) và Task 3 (`leaveRest` khi chưa đo).
2. **Chạm lại mini player ngay khi cú thu chưa xong.** Lúc ấy nội dung phía sau còn đang lùi (`scaleEffect`), nên khung đo được đang co. Điểm xuất phát không được lấy từ khung co ấy. Ghim ở Task 3: `reportAccessoryFrame` bị bỏ qua khi thẻ không nghỉ.
3. **Kéo mini player xuống, hoặc kéo chéo.** Không được làm thẻ hiện ra hay để lại trạng thái kéo dở. Ghim ở Task 2 (khoá trục) và Task 3 (kéo xuống kẹp `progress` ở 0).
4. **Vuốt ở hai đầu hàng đợi.** Không bao giờ dừng phát hay phát lại bài đang nghe. Ghim ở Task 11 và Task 12.
5. **Màn ngang.** Thẻ phải trùng khít khung accessory khi lề trái và lề phải khác nhau. Ghim ở Task 1 (ca màn ngang).

---

## Bản đồ file

| File | Việc | Task |
|---|---|---|
| `Evenstar/Evenstar/Features/Player/PlayerAnchor.swift` | **Tạo.** Hình học thẻ suy từ khung accessory | 1 |
| `Evenstar/Evenstar/Features/Player/AccessoryDragAxis.swift` | **Tạo.** Khoá trục cử chỉ | 2 |
| `Evenstar/Evenstar/Features/Shared/PlayerExpansion.swift` | **Sửa.** Thêm trạng thái accessory, `PlayerIntent`; bỏ `floatsOverPlayer` | 3, 5 |
| `Evenstar/Evenstar/Features/Shared/LibraryTab.swift` | **Tạo.** Enum `LibraryTab`, dời từ `FloatingTabBar.swift` | 4 |
| `Evenstar/Evenstar/App/RootView.swift` | **Sửa.** `TabView` native, accessory | 4, 5 |
| `Evenstar/Evenstar/Features/Search/SearchView.swift` | **Sửa.** `.searchable` | 4 |
| 9 màn (Songs, Albums, Artists, Account, AlbumDetail, ArtistDetail, JamendoDiscovery, JamendoSongsList, DriveSongsList) | **Sửa.** Bỏ `isMinimised`, `.minimisesBottomBar`, `.toolbar(.hidden, for: .tabBar)`, `.clearsBottomBar()` | 4 |
| `FloatingTabBar.swift`, `ScrollMinimise.swift`, `BottomBarClearance.swift` | **Xoá** | 4 |
| `Evenstar/Evenstar/Features/Player/MiniPlayerMetrics.swift` | **Tạo.** Kích thước chung của hàng mini player | 5 |
| `Evenstar/Evenstar/Features/Player/MiniPlayerChrome.swift` | **Viết lại.** Thành `MiniPlayerTitle`, `MiniPlayerControls`, `MiniPlayerRow` | 5 |
| `Evenstar/Evenstar/Features/Player/MiniPlayerAccessory.swift` | **Tạo.** Nội dung accessory và cử chỉ của nó | 5, 13 |
| `Evenstar/Evenstar/Features/Player/PlayerCard.swift` | **Sửa.** Neo theo `PlayerAnchor`, ẩn khi nghỉ, nhận `PlayerIntent` | 5 |
| `BottomBarMetrics.swift` | **Xoá** | 5 |
| 6 chỗ `.prominentAction` + `TrackMetadataEditor` | **Sửa.** `.glassProminent` | 9 |
| `ProminentActionButton.swift` | **Xoá** | 9 |
| `NowPlayingContent.swift`, `QueuePanel.swift` | **Sửa.** `.glass` + haptic | 10 |
| `Evenstar/Evenstar/Features/Shared/GlassToggleStyle.swift` | **Tạo.** Bật → `.glassProminent`, tắt → `.glass` | 10 |
| `TransportButtonStyle.swift`, `QueueToggleStyle.swift`, `TapHalo.swift`, `TouchDownButton.swift` | **Xoá** | 10 |
| `Evenstar/Evenstar/Services/PlaybackService.swift` | **Sửa.** `canGoPrevious`, `stepBack()` | 11 |
| `Evenstar/Evenstar/Features/Player/TrackSwipe.swift` | **Tạo.** Quyết định vuốt ngang | 12 |
| Test: `PlayerAnchorTests`, `AccessoryDragAxisTests`, `PlayerExpansionTests`, `PlaybackServiceStepBackTests`, `TrackSwipeTests` | **Tạo** | 1, 2, 3, 11, 12 |
| Test: `ReduceMotionTests`, `ReduceMotionSurfacesTests`, `PlayerCardCommitCostTests`, `PlayerCardClipShapeTests`, `ArtworkGeometryTests` | **Sửa** | 4, 5, 10 |

Mọi đường dẫn ở trên tính từ gốc repo. File `.swift` mới ghi vào `Evenstar/Evenstar/…` hoặc `Evenstar/EvenstarTests/…` sẽ tự vào build nhờ synced folders, không cần sửa project.

---

## Task 0: Điều kiện tiên quyết và mức nền

**Files:** không sửa file nào.

- [ ] **Step 1: Xác nhận người dùng đã đổi deployment target**

Run: `grep -c "IPHONEOS_DEPLOYMENT_TARGET = 26.0" Evenstar/Evenstar.xcodeproj/project.pbxproj; grep -c "IPHONEOS_DEPLOYMENT_TARGET = 18" Evenstar/Evenstar.xcodeproj/project.pbxproj`
Expected: số đầu ≥ 4 (Debug và Release của hai target), số sau là `0`.
Nếu chưa đạt thì **dừng**, và nhắn người dùng: Xcode → TARGETS → `Evenstar` rồi `EvenstarTests` → Build Settings → All → iOS Deployment Target → 26.0.

- [ ] **Step 2: Đứng trên nhánh đúng**

Run: `git branch --show-current`
Expected: `native-liquid-glass`.

- [ ] **Step 3: Chạy toàn bộ test để có mức nền**

Chạy lệnh test chuẩn ở Global Constraints.
Expected: `** TEST SUCCEEDED **`. Ghi lại số test (bằng `xcresulttool`) vào báo cáo của task. Nếu có test đỏ ngay từ đầu thì dừng và báo người dùng: đó không phải lỗi của plan này.

---

## Task 1: `PlayerAnchor`, hình học thẻ suy từ khung accessory

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/PlayerAnchor.swift`
- Test: `Evenstar/EvenstarTests/PlayerAnchorTests.swift`

**Interfaces:**
- Produces: `struct PlayerAnchor: Equatable { let frame: CGRect; let screen: CGSize }` cùng `leadingMargin`, `trailingMargin`, `bottomOffset`, `collapsedHeight`, `collapsedCornerRadius`, `dragTravel: CGFloat`, `func cardFrame(progress: Double) -> CGRect`, `static func dragTravel(for: CGRect) -> CGFloat`, `static func fallbackFrame(screen: CGSize) -> CGRect`, `static func resolve(measured: CGRect, screen: CGSize) -> CGRect`.

- [ ] **Step 1: Viết test đỏ**

```swift
import XCTest
@testable import Evenstar

/// Hai khung dưới là **số đo thật** từ spike 2026-10-06 (iPhone 17, iOS 26.0):
/// accessory ở `.expanded` và ở `.inline`. Ca màn ngang là khung giả định với
/// hai lề khác nhau — đúng ca từng làm viên pill lệch khỏi chỗ.
final class PlayerAnchorTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)
    private let expanded = CGRect(x: 20, y: 735, width: 360, height: 48)
    private let inline = CGRect(x: 84, y: 798, width: 234, height: 48)

    func testAtRestTheCardSitsExactlyOnTheAccessory() {
        for frame in [expanded, inline] {
            let anchor = PlayerAnchor(frame: frame, screen: screen)
            XCTAssertEqual(anchor.cardFrame(progress: 0), frame)
        }
    }

    func testFullyOpenTheCardFillsTheScreen() {
        for frame in [expanded, inline] {
            let anchor = PlayerAnchor(frame: frame, screen: screen)
            XCTAssertEqual(anchor.cardFrame(progress: 1), CGRect(origin: .zero, size: screen))
        }
    }

    /// Lỗi "thẻ trôi khỏi ngón tay" đã tái phát hai lần: quãng chia ra
    /// `progress` khác quãng mép trên thật sự đi.
    func testDragTravelIsExactlyHowFarTheTopEdgeMoves() {
        for frame in [expanded, inline] {
            let anchor = PlayerAnchor(frame: frame, screen: screen)
            let moved = anchor.cardFrame(progress: 0).minY - anchor.cardFrame(progress: 1).minY
            XCTAssertEqual(anchor.dragTravel, moved, accuracy: 0.0001)
        }
    }

    /// Đạo hàm mép trên theo `progress` là hằng số, nên một điểm ngón tay đi
    /// là một điểm thẻ đi, ở mọi điểm của cú bung chứ không chỉ hai đầu.
    func testTheTopEdgeMovesLinearly() {
        let anchor = PlayerAnchor(frame: expanded, screen: screen)
        let quarter = anchor.cardFrame(progress: 0.25).minY
        let half = anchor.cardFrame(progress: 0.5).minY
        let start = anchor.cardFrame(progress: 0).minY
        XCTAssertEqual(start - quarter, (start - half) / 2, accuracy: 0.0001)
    }

    func testLandscapeKeepsBothUnequalMarginsAtRest() {
        let wide = CGSize(width: 874, height: 402)
        let frame = CGRect(x: 120, y: 330, width: 560, height: 48)
        let anchor = PlayerAnchor(frame: frame, screen: wide)
        XCTAssertEqual(anchor.leadingMargin, 120)
        XCTAssertEqual(anchor.trailingMargin, 194)
        XCTAssertEqual(anchor.cardFrame(progress: 0), frame)
        XCTAssertEqual(anchor.cardFrame(progress: 1), CGRect(origin: .zero, size: wide))
    }

    func testTheCornerIsAFullPill() {
        XCTAssertEqual(PlayerAnchor(frame: inline, screen: screen).collapsedCornerRadius, 24)
    }

    func testProgressOutsideTheRangeIsClamped() {
        let anchor = PlayerAnchor(frame: expanded, screen: screen)
        XCTAssertEqual(anchor.cardFrame(progress: -0.3), anchor.cardFrame(progress: 0))
        XCTAssertEqual(anchor.cardFrame(progress: 1.4), anchor.cardFrame(progress: 1))
    }

    // MARK: - Review Focus 1: chưa từng đo

    func testAnUnmeasuredFrameFallsBackToTheBottomOfTheScreen() {
        let resolved = PlayerAnchor.resolve(measured: .zero, screen: screen)
        XCTAssertEqual(resolved, PlayerAnchor.fallbackFrame(screen: screen))
        XCTAssertEqual(resolved.maxY, screen.height - 91, "đáy như số đo .expanded")
        XCTAssertEqual(resolved.height, 48)
        XCTAssertEqual(resolved.minX, 20)
    }

    func testAFrameOffTheScreenIsNotTrusted() {
        let offscreen = CGRect(x: 20, y: 900, width: 360, height: 48)
        XCTAssertEqual(PlayerAnchor.resolve(measured: offscreen, screen: screen),
                       PlayerAnchor.fallbackFrame(screen: screen))
    }

    func testAMeasuredFrameIsUsedAsIs() {
        XCTAssertEqual(PlayerAnchor.resolve(measured: inline, screen: screen), inline)
    }

    func testTravelIsNeverZero() {
        XCTAssertEqual(PlayerAnchor.dragTravel(for: .zero), 1)
    }
}
```

- [ ] **Step 2: Chạy, xác nhận đỏ**

Run: lệnh test chuẩn với `-only-testing:EvenstarTests/PlayerAnchorTests`
Expected: FAIL, build lỗi `cannot find 'PlayerAnchor' in scope`.

- [ ] **Step 3: Viết code**

```swift
import CoreGraphics

/// Hình học của thẻ player, suy ra từ **khung accessory** mà hệ thống đặt.
///
/// Thay cho `collapsedSideMargin`, `collapsedBottomOffset` và `collapsedHeight`
/// cũ, vốn tự tính chỗ viên pill từ `BottomBarMetrics`. Chỗ ấy giờ là của hệ
/// thống, nên ta chỉ đọc lại nó. Mọi con số là toạ độ màn hình vật lý: cùng hệ
/// toạ độ thẻ dựng hình (thẻ `.ignoresSafeArea()`), và cùng hệ với
/// `.frame(in: .global)` mà accessory báo lên.
///
/// **Vị trí thẻ và quãng kéo nằm chung một chỗ.** Lỗi "thẻ trôi khỏi ngón tay"
/// đã tái phát hai lần khi hai thứ này được tính ở hai nơi.
struct PlayerAnchor: Equatable {
    let frame: CGRect
    let screen: CGSize

    var leadingMargin: CGFloat { frame.minX }
    var trailingMargin: CGFloat { screen.width - frame.maxX }
    var bottomOffset: CGFloat { screen.height - frame.maxY }
    var collapsedHeight: CGFloat { frame.height }
    var collapsedCornerRadius: CGFloat { frame.height / 2 }

    /// Quãng mép trên của thẻ đi từ `progress` 0 tới 1, cũng chính là
    /// `frame.minY`. Cả cú kéo trên thẻ lẫn trên accessory chia cho số này.
    var dragTravel: CGFloat { Self.dragTravel(for: frame) }

    static func dragTravel(for frame: CGRect) -> CGFloat { max(frame.minY, 1) }

    func cardFrame(progress: Double) -> CGRect {
        let p = CGFloat(min(max(progress, 0), 1))
        let leading = leadingMargin * (1 - p)
        let trailing = trailingMargin * (1 - p)
        let height = collapsedHeight + (screen.height - collapsedHeight) * p
        let bottom = screen.height - bottomOffset * (1 - p)
        return CGRect(x: leading, y: bottom - height,
                      width: screen.width - leading - trailing, height: height)
    }

    /// Khung dùng khi accessory chưa từng được đo, ví dụ chạm một bài lúc chưa
    /// có bài nào: accessory và cú bung xuất hiện cùng một lượt.
    ///
    /// Số đo trên iPhone 17, iOS 26.0, vị trí `.expanded` (spike 2026-10-06):
    /// lề 20, cao 48, đáy cách mép màn 91.
    static func fallbackFrame(screen: CGSize) -> CGRect {
        CGRect(x: 20, y: screen.height - 91 - 48, width: screen.width - 40, height: 48)
    }

    /// Khung đo được nếu nó có thật và nằm trong màn hình; ngược lại là
    /// `fallbackFrame`.
    static func resolve(measured: CGRect, screen: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: screen)
        guard measured.width > 0, measured.height > 0, bounds.contains(measured) else {
            return fallbackFrame(screen: screen)
        }
        return measured
    }
}
```

- [ ] **Step 4: Chạy, xác nhận xanh**

Run: lệnh test chuẩn với `-only-testing:EvenstarTests/PlayerAnchorTests`
Expected: 11 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Player/PlayerAnchor.swift Evenstar/EvenstarTests/PlayerAnchorTests.swift
git commit -m "feat: PlayerAnchor — hình học thẻ suy từ khung accessory"
```

---

## Task 2: `AccessoryDragAxis`, khoá trục cử chỉ

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/AccessoryDragAxis.swift`
- Test: `Evenstar/EvenstarTests/AccessoryDragAxisTests.swift`

**Interfaces:**
- Produces: `enum AccessoryDragAxis: Equatable { case vertical, horizontal }`, `static let lockDistance: CGFloat = 10`, `static func resolve(_ translation: CGSize) -> AccessoryDragAxis?`.

- [ ] **Step 1: Viết test đỏ**

```swift
import XCTest
@testable import Evenstar

final class AccessoryDragAxisTests: XCTestCase {
    func testNothingIsDecidedBeforeTheLockDistance() {
        XCTAssertNil(AccessoryDragAxis.resolve(CGSize(width: 3, height: -5)))
        XCTAssertNil(AccessoryDragAxis.resolve(.zero))
    }

    func testMostlyUpIsVertical() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: 4, height: -12)), .vertical)
    }

    func testMostlyDownIsAlsoVertical() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: -2, height: 15)), .vertical)
    }

    func testMostlySidewaysIsHorizontal() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: -14, height: 5)), .horizontal)
    }

    /// Đúng 45° thì nghiêng về ngang: kéo chéo không được làm thẻ hiện ra.
    func testAnExactDiagonalIsHorizontal() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: 10, height: -10)), .horizontal)
    }

    func testTheLockDistanceIsMeasuredAlongTheDiagonal() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: 8, height: -8)), .horizontal,
                       "hypot(8, 8) ≈ 11.3 ≥ 10")
    }
}
```

- [ ] **Step 2: Chạy, xác nhận đỏ**

Run: lệnh test chuẩn với `-only-testing:EvenstarTests/AccessoryDragAxisTests`
Expected: FAIL, `cannot find 'AccessoryDragAxis' in scope`.

- [ ] **Step 3: Viết code**

```swift
import CoreGraphics

/// Trục mà một cú kéo trên mini player khoá vào, quyết **một lần** sau
/// `lockDistance` rồi giữ tới khi nhấc tay.
///
/// Dọc lái thẻ player, ngang đổi bài. Khoá một lần vì một ngón tay trượt chéo
/// giữa chừng không được nhảy từ "đang bung player" sang "đang đổi bài".
enum AccessoryDragAxis: Equatable {
    case vertical
    case horizontal

    /// Cũng là `minimumDistance` của `DragGesture` trên accessory, và là ngưỡng
    /// mà `PlayerCard.dragOffset` trừ đi để thẻ không giật một đoạn lúc bắt đầu.
    static let lockDistance: CGFloat = 10

    /// `nil` khi ngón tay chưa đi đủ `lockDistance`. Hoà thì nghiêng về ngang.
    static func resolve(_ translation: CGSize) -> AccessoryDragAxis? {
        guard hypot(translation.width, translation.height) >= lockDistance else { return nil }
        return abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
    }
}
```

- [ ] **Step 4: Chạy, xác nhận xanh**

Expected: 6 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Player/AccessoryDragAxis.swift Evenstar/EvenstarTests/AccessoryDragAxisTests.swift
git commit -m "feat: AccessoryDragAxis — khoá trục cử chỉ trên mini player"
```

---

## Task 3: `PlayerExpansion` mang trạng thái accessory

**Files:**
- Modify: `Evenstar/Evenstar/Features/Shared/PlayerExpansion.swift`
- Test: `Evenstar/EvenstarTests/PlayerExpansionTests.swift`

**Interfaces:**
- Consumes: `PlayerAnchor.resolve`, `PlayerAnchor.dragTravel(for:)` (Task 1); `AccessoryDragAxis.lockDistance` (Task 2); `PlayerCard.dragOffset(translationHeight:threshold:)` (đã có, `static`, nội bộ).
- Produces, trên `PlayerExpansion` (giờ là `@MainActor`):
  - `private(set) var accessoryFrame: CGRect` (không quan sát), `var screenSize: CGSize` (không quan sát);
  - `private(set) var anchorFrame: CGRect`, `anchorIsInline: Bool`, `isCardResting: Bool`, `accessoryDragDelta: Double`, `accessoryDragging: Bool`, `intent: PlayerIntent?`;
  - `func reportAccessoryFrame(_ frame: CGRect, isInline: Bool)`, `leaveRest()`, `arriveAtRest()`, `requestExpand()`, `accessoryDragChanged(translationHeight:)`, `setAccessoryDragDelta(_:)`, `accessoryDragEnded(predictedTranslationHeight:verticalVelocity:)`, `takeAccessoryDrag() -> Double`.
- Produces: `struct PlayerIntent: Equatable { enum Kind: Equatable { case expand; case release(predictedProgress: Double, verticalVelocity: CGFloat) }; let id: UUID; let kind: Kind }`.

- [ ] **Step 1: Viết test đỏ**

```swift
import XCTest
@testable import Evenstar

@MainActor
final class PlayerExpansionTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)
    private let expanded = CGRect(x: 20, y: 735, width: 360, height: 48)

    private func make() -> PlayerExpansion {
        let e = PlayerExpansion()
        e.screenSize = screen
        return e
    }

    func testStartsAtRest() {
        let e = make()
        XCTAssertTrue(e.isCardResting)
        XCTAssertEqual(e.accessoryDragDelta, 0)
        XCTAssertNil(e.intent)
    }

    func testLeavingRestCapturesTheMeasuredFrame() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        XCTAssertFalse(e.isCardResting)
        XCTAssertEqual(e.anchorFrame, expanded)
    }

    /// Review Focus 1.
    func testLeavingRestBeforeAnyMeasurementUsesTheFallback() {
        let e = make()
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, PlayerAnchor.fallbackFrame(screen: screen))
    }

    /// Review Focus 2: trong lúc nội dung lùi lại, khung đo được đang co.
    func testFramesReportedAwayFromRestAreIgnored() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.reportAccessoryFrame(CGRect(x: 31, y: 743, width: 338, height: 45), isInline: false)
        e.arriveAtRest()
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, expanded)
    }

    /// Thẻ phải biết accessory đang ở vị trí nào lúc bung, để hàng mini player
    /// của nó ẩn ⏭ giống hệt accessory ở khung đầu.
    func testLeavingRestCapturesWhetherTheAccessoryWasInline() {
        let e = make()
        e.reportAccessoryFrame(CGRect(x: 84, y: 798, width: 234, height: 48), isInline: true)
        e.leaveRest()
        XCTAssertTrue(e.anchorIsInline)
    }

    func testLeavingRestTwiceKeepsTheFirstAnchor() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, expanded)
    }

    func testAnUpwardDragDrivesProgressOverTheAnchorsTravel() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        let expected = Double((100 - AccessoryDragAxis.lockDistance) / 735)
        XCTAssertTrue(e.accessoryDragging)
        XCTAssertFalse(e.isCardResting)
        XCTAssertEqual(e.accessoryDragDelta, expected, accuracy: 0.0001)
        XCTAssertEqual(e.progress, expected, accuracy: 0.0001)
    }

    /// Review Focus 3.
    func testADownwardDragClampsProgressAtZero() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: 60)
        XCTAssertEqual(e.progress, 0)
        XCTAssertLessThan(e.accessoryDragDelta, 0)
    }

    func testReleasingSendsThePredictedProgress() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        e.accessoryDragEnded(predictedTranslationHeight: -500, verticalVelocity: -900)
        guard case let .release(predicted, velocity)? = e.intent?.kind else {
            return XCTFail("expected a release intent")
        }
        XCTAssertEqual(predicted, Double((500 - AccessoryDragAxis.lockDistance) / 735), accuracy: 0.0001)
        XCTAssertEqual(velocity, -900)
    }

    func testTakingTheDragHandsOverTheDeltaAndClearsIt() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        let carried = e.takeAccessoryDrag()
        XCTAssertGreaterThan(carried, 0)
        XCTAssertEqual(e.accessoryDragDelta, 0)
        XCTAssertFalse(e.accessoryDragging)
    }

    func testArrivingAtRestWaitsForAnAccessoryDragToEnd() {
        let e = make()
        e.accessoryDragChanged(translationHeight: -100)
        e.arriveAtRest()
        XCTAssertFalse(e.isCardResting)
        _ = e.takeAccessoryDrag()
        e.arriveAtRest()
        XCTAssertTrue(e.isCardResting)
    }

    /// `onChange` chỉ nổ khi giá trị đổi; hai lần chạm liền nhau phải là hai
    /// ý định khác nhau.
    func testTwoExpandRequestsAreTwoDistinctIntents() {
        let e = make()
        e.requestExpand()
        let first = e.intent
        e.requestExpand()
        XCTAssertNotEqual(first, e.intent)
        XCTAssertEqual(e.intent?.kind, .expand)
    }
}
```

- [ ] **Step 2: Chạy, xác nhận đỏ**

Run: lệnh test chuẩn với `-only-testing:EvenstarTests/PlayerExpansionTests`
Expected: FAIL, `value of type 'PlayerExpansion' has no member 'screenSize'`.

- [ ] **Step 3: Viết code**

Trong `PlayerExpansion.swift`, thêm `@MainActor` lên khai báo lớp:

```swift
@MainActor
@Observable
final class PlayerExpansion {
```

Rồi chèn khối sau vào thân lớp, ngay sau hàm `set(progress:animation:)`:

```swift
    // MARK: - Accessory

    /// Khung accessory mới nhất đo được **lúc thẻ đang nghỉ**, toạ độ global.
    ///
    /// Không quan sát: hệ thống dời accessory mỗi lần thanh tab thu nhỏ, và
    /// không view nào cần dựng lại vì chuyện đó. Chỉ `leaveRest()` đọc nó.
    @ObservationIgnored private(set) var accessoryFrame: CGRect = .zero
    @ObservationIgnored private(set) var accessoryIsInline = false

    /// Cỡ màn hình vật lý, do `PlayerCard` ghi từ `GeometryReader` của nó.
    @ObservationIgnored var screenSize: CGSize = .zero

    /// Khung thẻ bung ra từ đó, chụp **lúc thẻ rời trạng thái nghỉ** và giữ
    /// nguyên tới khi thẻ về nghỉ. Không đọc thẳng `accessoryFrame` trong lúc
    /// bung, vì nội dung phía sau lùi lại làm khung đo được co theo.
    private(set) var anchorFrame: CGRect = .zero
    /// Accessory có đang ở `.inline` lúc thẻ rời nghỉ không. Hàng mini player
    /// trong thẻ đọc nó để ẩn ⏭ giống hệt accessory ở khung đầu.
    private(set) var anchorIsInline = false

    /// Thẻ đang nằm yên ở 0 và vô hình, còn accessory đang hiện nội dung của nó.
    private(set) var isCardResting = true

    /// Phần `progress` do cú kéo trên accessory đóng góp; 0 khi không kéo.
    /// `PlayerCard` cộng nó vào `progress` của mình mỗi khung. Không đi qua
    /// `onChange`, vì mỗi `onChange` là thêm một lượt cập nhật.
    private(set) var accessoryDragDelta: Double = 0
    private(set) var accessoryDragging = false

    /// Ý định gửi từ accessory sang thẻ. Chỉ thẻ thực hiện được cú bung có
    /// animation, vì `morph` và trạng thái `settled` là của riêng nó.
    private(set) var intent: PlayerIntent?

    func reportAccessoryFrame(_ frame: CGRect, isInline: Bool) {
        guard isCardResting else { return }
        accessoryFrame = frame
        accessoryIsInline = isInline
    }

    func leaveRest() {
        guard isCardResting else { return }
        anchorFrame = PlayerAnchor.resolve(measured: accessoryFrame, screen: screenSize)
        anchorIsInline = accessoryIsInline
        isCardResting = false
    }

    func arriveAtRest() {
        guard !accessoryDragging else { return }
        isCardResting = true
    }

    func requestExpand() {
        intent = PlayerIntent(kind: .expand)
    }

    func accessoryDragChanged(translationHeight: CGFloat) {
        leaveRest()
        accessoryDragging = true
        let offset = PlayerCard.dragOffset(translationHeight: translationHeight,
                                           threshold: AccessoryDragAxis.lockDistance)
        setAccessoryDragDelta(-Double(offset / PlayerAnchor.dragTravel(for: anchorFrame)))
    }

    /// Tách riêng để `PlayerCardCommitCostTests` ghi được đúng đầu vào mà một
    /// cú kéo thật ghi, mỗi khung.
    func setAccessoryDragDelta(_ delta: Double) {
        accessoryDragDelta = delta
        set(progress: min(max(delta, 0), 1), animation: nil)
    }

    func accessoryDragEnded(predictedTranslationHeight: CGFloat, verticalVelocity: CGFloat) {
        let offset = PlayerCard.dragOffset(translationHeight: predictedTranslationHeight,
                                           threshold: AccessoryDragAxis.lockDistance)
        let predicted = -Double(offset / PlayerAnchor.dragTravel(for: anchorFrame))
        intent = PlayerIntent(kind: .release(predictedProgress: predicted,
                                             verticalVelocity: verticalVelocity))
    }

    /// Thẻ gọi lúc nhận `.release`: chuyển phần kéo sang `dragDelta` của nó
    /// trong cùng một transaction, nên `progress` không nhảy.
    func takeAccessoryDrag() -> Double {
        let carried = accessoryDragDelta
        accessoryDragDelta = 0
        accessoryDragging = false
        return carried
    }
```

Và thêm vào cuối file, ngoài lớp:

```swift
/// Một việc accessory nhờ thẻ làm. `id` riêng cho mỗi lần gửi, để hai lần chạm
/// liền nhau vẫn là hai giá trị khác nhau và `onChange` nổ cả hai.
struct PlayerIntent: Equatable {
    enum Kind: Equatable {
        case expand
        case release(predictedProgress: Double, verticalVelocity: CGFloat)
    }

    let id = UUID()
    let kind: Kind
}
```

- [ ] **Step 4: Chạy, xác nhận xanh**

Run: lệnh test chuẩn với `-only-testing:EvenstarTests/PlayerExpansionTests`
Expected: 12 test PASS. Rồi chạy **toàn bộ** suite, vì `@MainActor` có thể làm vỡ chỗ dùng `PlayerExpansion` từ ngữ cảnh không cô lập. Nếu một test hay một `#Preview` báo lỗi cô lập, đánh dấu chỗ gọi đó `@MainActor`; **không** gỡ `@MainActor` khỏi lớp.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Shared/PlayerExpansion.swift Evenstar/EvenstarTests/PlayerExpansionTests.swift
git commit -m "feat: PlayerExpansion mang khung accessory, cú kéo và ý định gửi sang thẻ"
```

---

## Task 4: Khung app native — `TabView`, tab tìm kiếm, thu nhỏ khi cuộn

Sau task này app chạy với thanh tab native. **Trạng thái tạm:** `PlayerCard` vẫn là bản cũ với `minimised: 0`, nên viên pill cũ nổi ở chỗ cũ, trên thanh tab native. Task 5 sửa chỗ ấy. Đừng sửa `PlayerCard` trong task này.

**Files:**
- Create: `Evenstar/Evenstar/Features/Shared/LibraryTab.swift`
- Modify: `Evenstar/Evenstar/App/RootView.swift`, `Evenstar/Evenstar/Features/Search/SearchView.swift`, chín màn ở Bản đồ file, `Evenstar/Evenstar/Features/Shared/PlayerExpansion.swift` (bỏ `floatsOverPlayer`)
- Delete: `Evenstar/Evenstar/Features/Shared/FloatingTabBar.swift`, `ScrollMinimise.swift`, `BottomBarClearance.swift`
- Test: `Evenstar/EvenstarTests/ReduceMotionTests.swift`, `Evenstar/EvenstarTests/ReduceMotionSurfacesTests.swift`

**Interfaces:**
- Produces: `enum LibraryTab: String, Identifiable { case songs, albums, artists, account, search }` cùng `label: String` và `symbol: String`, không đổi so với bản cũ, chỉ bỏ `pillTabs`.
- Produces: `SearchView(query: Binding<String>)`. Các màn thư viện mất tham số `isMinimised:`, ví dụ `SongsView()`, `AlbumDetailView(album:)`, `DriveSongsList()`, `JamendoDiscoveryView()`.

- [ ] **Step 1: Dời `LibraryTab` ra file riêng**

Tạo `LibraryTab.swift`, chép nguyên si khối `enum LibraryTab` (dòng 3–47 của `FloatingTabBar.swift`), gồm `label` và `symbol` cùng các ghi chú của chúng. Bỏ `static let pillTabs` cùng đoạn ghi chú về `CaseIterable` phía trên nó. Thay ghi chú đầu enum bằng:

```swift
/// Năm điểm đến của app. Search là một tab thường của hệ thống
/// (`Tab(role: .search)`), không còn là nút tròn riêng như thời thanh tab tự vẽ.
```

- [ ] **Step 2: Viết lại phần khai báo và body của `RootView`**

Trong `RootView.swift`:
- Xoá các `@State`: `isSearching`, `query` (tạo lại bên dưới), `isEditing`, `tabBeforeSearch`, `isMinimised`, `bottomSafeAreaInset`, cùng thuộc tính tính toán `isMinimisedActive` và mọi ghi chú của chúng.
- Giữ nguyên: `storeUnavailable`, `showingStoreWarning`, ba chuỗi `storeWarning*`, `playback`, `tab`, `expansion`, `theme`, `reduceMotion`, `language`, `hasWarmedPlayerChrome`, và toàn bộ chuỗi modifier sau `ZStack` (`.onChange(of: reduceMotion…)`, `.task`, `.preferredColorScheme`, `.environment(\.locale…)`, `.id(language)`, `.alert`).

Thêm `@State private var query = ""` cạnh `tab`, rồi thay toàn bộ `ZStack(alignment: .bottom) { … }` bằng:

```swift
        ZStack {
            // The app's one `@Query` on `Track`, in a view that draws nothing.
            // See `LibraryStore` — a `@Query` here would invalidate this body,
            // which rebuilds the `TabView` and all five tabs.
            LibraryQueryBridge()

            TabView(selection: $tab) {
                Tab(LibraryTab.songs.label, systemImage: LibraryTab.songs.symbol, value: LibraryTab.songs) {
                    SongsView()
                }
                Tab(LibraryTab.albums.label, systemImage: LibraryTab.albums.symbol, value: LibraryTab.albums) {
                    AlbumsView()
                }
                Tab(LibraryTab.artists.label, systemImage: LibraryTab.artists.symbol, value: LibraryTab.artists) {
                    ArtistsView()
                }
                Tab(LibraryTab.account.label, systemImage: LibraryTab.account.symbol, value: LibraryTab.account) {
                    AccountView()
                }
                Tab(value: LibraryTab.search, role: .search) {
                    SearchView(query: $query)
                }
            }
            // Thanh tab, cú thu nhỏ khi cuộn và tab tìm kiếm tách riêng đều là
            // của hệ thống — thay cho `FloatingTabBar` và `ScrollMinimise`.
            .tabBarMinimizeBehavior(.onScrollDown)
            // The content recedes as the player opens. The transform lives in
            // the modifier, not here — see `PlayerExpansion.swift`.
            .recedesBehindPlayer(expansion)

            // Trả trước hoá đơn vẽ-lần-đầu của chrome mở rộng: xem ghi chú cũ
            // ở bản trước của file này (git log) — lý lẽ không đổi.
            if !hasWarmedPlayerChrome {
                NowPlayingContent(playback: playback, showingQueue: .constant(false))
                    .padding(.horizontal, 24)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(-1)
            }

            // Tạm cho tới Task 5: thẻ cũ, không bao giờ thu nhỏ.
            PlayerCard(playback: playback, minimised: 0, expansion: expansion)
        }
```

Sửa ghi chú đầu struct (dòng 3–12) thành:

```swift
/// The app's root: the five destinations in a native `TabView`, with the player
/// card on top.
///
/// The tab bar, its scroll-minimise and the detached search tab are the
/// system's (iOS 26). The mini player lives in the bar's bottom accessory; the
/// full player is `PlayerCard`, which grows out of that accessory's frame.
```

- [ ] **Step 3: `SearchView` nhận binding và tự gắn `.searchable`**

Trong `SearchView.swift`:
- đổi `let query: String` thành `@Binding var query: String`;
- trong `body`, xoá `.toolbar(.hidden, for: .tabBar)` và `.clearsBottomBar()` cùng ghi chú của chúng;
- thêm `.searchable(text: $query, prompt: Text("Bài hát, nghệ sĩ, album"))` ngay sau `.navigationTitle("Tìm kiếm")`. Chuỗi prompt này trùng khoá với ô tìm kiếm cũ nên đã có bản dịch trong catalogue.
- `#Preview` ở cuối file: đổi `SearchView(query: …)` thành `SearchView(query: .constant(…))`, giữ nguyên chuỗi đang có.

- [ ] **Step 4: Gỡ `isMinimised` và phần chừa đáy khỏi chín màn**

Với mỗi file dưới đây, làm đúng bốn việc:
1. xoá `@Binding var isMinimised: Bool` cùng ghi chú của nó;
2. xoá mọi dòng `.minimisesBottomBar($isMinimised)`;
3. xoá mọi dòng `.toolbar(.hidden, for: .tabBar)` và `.clearsBottomBar()`, cùng các dòng ghi chú `//` nằm ngay trên và chỉ nói về chúng;
4. ở mọi chỗ dựng một màn con, bỏ đối số `isMinimised: $isMinimised` hoặc `isMinimised: .constant(false)`.

| File | Dòng cần sửa (theo bản hiện tại) |
|---|---|
| `Features/Library/SongsView.swift` | 34, 130, 161, 333, 335, 336, 338, 339, 395 |
| `Features/Library/AlbumsView.swift` | 20, 83, 87, 88, 115, 220 |
| `Features/Library/ArtistsView.swift` | 19, 52, 56, 57, 84, 144 |
| `Features/Library/AlbumDetailView.swift` | 12, 80, 85, 86, 126 |
| `Features/Library/ArtistDetailView.swift` | 12, 39, 44, 45, 85 |
| `Features/Account/AccountView.swift` | 23, 93, 97, 98, 232 |
| `Features/Jamendo/JamendoSongsList.swift` | 23, 36, 64 |
| `Features/Jamendo/JamendoDiscoveryView.swift` | 28, 143, 215 |
| `Features/Drive/DriveSongsList.swift` | 15, 124 |

Màn chi tiết album và nghệ sĩ giờ **giữ** thanh tab khi được đẩy vào, như Apple Music.

Kiểm còn sót gì không:
Run: `grep -rnE "isMinimised|minimisesBottomBar|clearsBottomBar|toolbar\(\.hidden, for: \.tabBar\)|bottomSafeAreaInset" Evenstar/Evenstar --include='*.swift' | grep -v "Features/Player/PlayerCard.swift" | grep -v "Features/Shared/\(FloatingTabBar\|ScrollMinimise\|BottomBarClearance\|BottomBarMetrics\)"`
Expected: không có dòng nào.

- [ ] **Step 5: Xoá thanh tab tự vẽ và `floatsOverPlayer`**

```bash
git rm Evenstar/Evenstar/Features/Shared/FloatingTabBar.swift \
       Evenstar/Evenstar/Features/Shared/ScrollMinimise.swift \
       Evenstar/Evenstar/Features/Shared/BottomBarClearance.swift
```

Trong `PlayerExpansion.swift`, xoá `FloatOverPlayer`, `PresentedFloat`, hàm `floatsOverPlayer(_:)` trong `extension View`, cùng ghi chú của chúng. Giữ `RecedeBehindPlayer` và `recedesBehindPlayer(_:)`.

`BottomBarMetrics.swift` **giữ lại** tới Task 5, vì `PlayerCard` cũ còn đọc nó. Xoá các hàm `clearance…` trong đó nếu chúng tham chiếu thứ vừa bị xoá và làm vỡ build.

- [ ] **Step 6: Build app, sửa chỗ tham chiếu còn sót trong mã app**

Run: `xcodebuild build -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17 test' -derivedDataPath build/DerivedData 2>&1 | grep -E "error:|warning:|BUILD"`
Expected: `** BUILD SUCCEEDED **`, không có `warning:` nào.

Lỗi hay gặp, và cách sửa đúng:
- `BottomBarStyle` còn thành viên chỉ `FloatingTabBar` dùng (`collapsedChromeScale`, `collapsedChromeInset`, `chromeSettle`…): để nguyên ở bước này; Step 8 dọn.
- File trong `Features/Prototypes/` tham chiếu thứ đã xoá: **xoá cả file prototype đó** bằng `git rm` (quyết định của spec).

- [ ] **Step 7: Sửa test**

Xoá **nguyên hàm** của các test sau (chúng ghim thứ đã bị xoá):
- `ReduceMotionTests`: `testTheRightmostTabLeavesFirstAndReturnsLast`, `testTheCascadeIsShorterThanTheCurveItRidesOn`, `testEveryTabDriftsIncludingTheLeftmost`, `testTheLeftwardDriftGoesToZeroWhenMotionIsReduced`, `testTheCascadeTimingSurvivesReducedMotion`, `testTheCollapsedChromeShrinksButStaysTappable`, `testTheChromeShrinkHasItsOwnBouncierCurve`, `testTheBounceFlattensWhenMotionIsReduced`, `testTheChromeShrinkGoesToZeroWhenMotionIsReduced`.
- `ReduceMotionSurfacesTests`: `testAtRestTheTwoModesAreIndistinguishable`.

Sửa, không xoá:
- `ReduceMotionSurfacesTests.testEveryDistanceInTheQueueTransitionGoesToZero`: chỉ xoá hai dòng `XCTAssertEqual(FloatingTabBar.tabRevealScale, …)`.
- `ReduceMotionSurfacesTests.testThePressScalesFlattenAndTheDimAppears`: xoá các dòng tham chiếu `FloatingTabBar`; giữ phần về `QueueToggleStyle` (Task 10 mới xoá nó).

Giữ nguyên ba test dựng `RootView()` trong `ReduceMotionTests`: `init(storeUnavailable:)` không đổi.

Run: lệnh test chuẩn.
Expected: `** TEST SUCCEEDED **`. Số test = mức nền + 29 (Task 1–3) − 10 (vừa xoá).

- [ ] **Step 8: Dọn `BottomBarStyle` và test của thành viên chết**

Liệt kê các thành viên không còn ai trong mã app gọi:

```bash
for m in $(grep -oE "static (let|var|func) [a-zA-Z]+" Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift | awk '{print $3}' | sort -u); do
  n=$(grep -rn "BottomBarStyle\.$m\b\|\.$m\b" Evenstar/Evenstar --include='*.swift' | grep -v "Features/Shared/BottomBarStyle.swift" | wc -l)
  [ "$n" -eq 0 ] && echo "$m"
done
```

Với mỗi tên in ra:
- xoá nó khỏi `BottomBarStyle.swift`, cùng biến thể `…Full`/`…Flat` và ghi chú của nó, **trừ khi** một thành viên còn sống trong cùng file đọc tới nó;
- xoá các dòng test chỉ ghim nó (`grep -n "<tên>" Evenstar/EvenstarTests/*.swift`). Nếu một hàm test chỉ còn lại những dòng như vậy thì xoá cả hàm.

Chạy lại lệnh test chuẩn. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 9: Xem bằng mắt trên simulator**

```bash
./run.sh "iPhone 17 test"
```

Kiểm: có 4 tab và kính lúp tách riêng; cuộn danh sách thì thanh tab thu nhỏ; tab Search mở ô tìm kiếm và gõ thì ra kết quả; vào chi tiết album thì thanh tab vẫn còn. Viên pill cũ nổi lệch chỗ là **đúng dự kiến** ở task này.

- [ ] **Step 10: Commit**

```bash
git add -A Evenstar/
git commit -m "feat: thanh tab native — TabView, tab tìm kiếm, thu nhỏ khi cuộn; xoá thanh tab tự vẽ"
```

---

## Task 5: Mini player trong accessory, và `PlayerCard` bung từ khung ấy

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/MiniPlayerMetrics.swift`, `Evenstar/Evenstar/Features/Player/MiniPlayerAccessory.swift`
- Modify: `Evenstar/Evenstar/Features/Player/MiniPlayerChrome.swift` (viết lại), `Evenstar/Evenstar/Features/Player/PlayerCard.swift`, `Evenstar/Evenstar/App/RootView.swift`
- Delete: `Evenstar/Evenstar/Features/Shared/BottomBarMetrics.swift`
- Test: `ArtworkGeometryTests.swift`, `PlayerCardClipShapeTests.swift`, `PlayerCardCommitCostTests.swift`, `ReduceMotionTests.swift`

**Interfaces:**
- Consumes: Task 1–3.
- Produces: `PlayerCard(playback: PlaybackService, expansion: PlayerExpansion)` (tham số `minimised` biến mất); `MiniPlayerAccessory(playback:expansion:)`; `MiniPlayerTitle(playback:)`, `MiniPlayerControls(playback:showsNext:)`, `MiniPlayerRow(playback:showsNext:)`; `enum MiniPlayerMetrics`.
- Produces, đổi chữ ký: `PlayerCard.artworkGeometry(…, collapsedHeight: CGFloat)` (tham số mới, đặt cuối); `PlayerCard.cardTopCornerRadius(progress:collapsedRadius:)`, `PlayerCard.cardBottomCornerRadius(progress:collapsedRadius:)`.

- [ ] **Step 1: `MiniPlayerMetrics`**

```swift
import CoreGraphics

/// Kích thước hàng mini player, dùng chung cho **hai** nơi vẽ nó: nội dung
/// accessory (`MiniPlayerAccessory`) và thẻ player ở `progress` 0.
///
/// Hai nơi phải trùng khít từng điểm. Ở khung đầu cú bung, thẻ phủ đúng lên
/// accessory rồi accessory ẩn đi; lệch một điểm là thấy nhảy.
enum MiniPlayerMetrics {
    static let artworkSide: CGFloat = 30
    /// Viên kính cao 48, bán kính 24. Ở mép trên ô bìa (y = 9) đường cong đã
    /// lùi vào ~5,3pt, nên lề 12 cho khe hẹp nhất ~6,7pt. Chỉnh trên máy thật.
    static let artworkLeadingInset: CGFloat = 12
    static let artworkTitleGap: CGFloat = 10
    static let trailingInset: CGFloat = 14
    static let buttonSize: CGFloat = 32
    static let buttonGap: CGFloat = 4
    /// Chữ bắt đầu sau ô bìa và khe hở.
    static var titleLeadingInset: CGFloat { artworkLeadingInset + artworkSide + artworkTitleGap }
}
```

- [ ] **Step 2: Viết lại `MiniPlayerChrome.swift`**

Thay toàn bộ nội dung file bằng:

```swift
import SwiftUI

/// Tên bài, một dòng. Khi bài đang kẹt thì dòng báo lỗi màu đỏ thay vào chỗ
/// ấy, vì đây là chỗ duy nhất trên màn thư viện báo được chuyện đó.
///
/// Một dòng ở **cả hai** vị trí của accessory. Spike 2026-10-06: hệ thống đổi
/// vị trí mà không kèm animation, nên bố cục nào đổi theo vị trí đều nhảy.
struct MiniPlayerTitle: View {
    let playback: PlaybackService

    var body: some View {
        if let current = playback.currentTrack {
            let line = PlayerSubtitle.collapsedLine(track: current,
                                                    error: playback.stalledPlaybackError)
            Text(line.isFailure ? line.text : current.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(line.isFailure ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
        }
    }
}

/// Play và next. Glyph trần, không `.glass`: accessory đã là kính, và kính lồng
/// trong kính là điều Apple khuyên tránh. Mini player của Apple Music cũng vậy.
///
/// `showsNext` false khi accessory thu nhỏ vào thanh tab: ⏭ mờ dần và co về 0,
/// như Apple Music (video 2026-10-06).
struct MiniPlayerControls: View {
    let playback: PlaybackService
    let showsNext: Bool

    @State private var playPauseTaps = 0
    @State private var nextTaps = 0

    var body: some View {
        HStack(spacing: MiniPlayerMetrics.buttonGap) {
            Button {
                playPauseTaps += 1
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .symbolReplace()
                    .frame(width: MiniPlayerMetrics.buttonSize, height: MiniPlayerMetrics.buttonSize)
                    .contentShape(Rectangle())
            }
            .sensoryFeedback(.impact(weight: .light), trigger: playPauseTaps)

            Button {
                nextTaps += 1
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .frame(width: MiniPlayerMetrics.buttonSize, height: MiniPlayerMetrics.buttonSize)
                    .contentShape(Rectangle())
            }
            .disabled(!playback.canGoNext)
            .sensoryFeedback(.impact(weight: .light), trigger: nextTaps)
            .frame(width: showsNext ? MiniPlayerMetrics.buttonSize : 0)
            .opacity(showsNext ? 1 : 0)
            .clipped()
            .allowsHitTesting(showsNext)
            .padding(.leading, showsNext ? 0 : -MiniPlayerMetrics.buttonGap)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: showsNext)
    }
}

/// Hàng mini player bên trong thẻ, ở `progress` 0. Không có ô bìa: thẻ tự vẽ
/// bìa để nó lớn liên tục suốt cú bung.
struct MiniPlayerRow: View {
    let playback: PlaybackService
    let showsNext: Bool

    var body: some View {
        HStack(spacing: 0) {
            MiniPlayerTitle(playback: playback)
            Spacer(minLength: MiniPlayerMetrics.artworkTitleGap)
            MiniPlayerControls(playback: playback, showsNext: showsNext)
        }
        .padding(.leading, MiniPlayerMetrics.titleLeadingInset)
        .padding(.trailing, MiniPlayerMetrics.trailingInset)
    }
}
```

- [ ] **Step 3: `MiniPlayerAccessory`**

```swift
import SwiftUI

/// Nội dung của `tabViewBottomAccessory`. Viên kính là của hệ thống.
///
/// Ba việc:
/// - vẽ hàng mini player trùng khít hàng mà `PlayerCard` vẽ ở `progress` 0;
/// - báo khung của mình lên `PlayerExpansion`, để thẻ biết bung ra từ đâu;
/// - nhận chạm và cú kéo lên trên vùng thông tin bài, rồi chuyển sang thẻ.
///   Nút play/next nằm ngoài vùng ấy, nên bấm nút không bao giờ thành kéo.
///
/// Ẩn đi (opacity 0) khi thẻ rời trạng thái nghỉ: lúc ấy chính thẻ đang vẽ
/// hàng này, ở đúng chỗ này.
struct MiniPlayerAccessory: View {
    let playback: PlaybackService
    let expansion: PlayerExpansion

    /// Chỉ đọc để ẩn ⏭ khi thu nhỏ — xem Global Constraints của plan.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @State private var axis: AccessoryDragAxis?
    @State private var drivesCard = false

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: 0) {
            info
            Spacer(minLength: MiniPlayerMetrics.artworkTitleGap)
            MiniPlayerControls(playback: playback, showsNext: !isInline)
        }
        .padding(.trailing, MiniPlayerMetrics.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(expansion.isCardResting ? 1 : 0)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            expansion.reportAccessoryFrame(frame, isInline: isInline)
        }
    }

    private var info: some View {
        HStack(spacing: MiniPlayerMetrics.artworkTitleGap) {
            ArtworkThumbnail(relativePath: playback.currentTrack?.artworkRelativePath,
                             size: MiniPlayerMetrics.artworkSide)
            MiniPlayerTitle(playback: playback)
        }
        .padding(.leading, MiniPlayerMetrics.artworkLeadingInset)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { expansion.requestExpand() }
        .gesture(drag)
        .contextMenu {
            Button(role: .destructive) {
                playback.stop()
            } label: {
                Label("Dừng phát", systemImage: "stop.fill")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { expansion.requestExpand() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: AccessoryDragAxis.lockDistance, coordinateSpace: .global)
            .onChanged { value in
                if axis == nil {
                    axis = AccessoryDragAxis.resolve(value.translation)
                    // Chỉ một cú kéo **lên** mới lái thẻ. Kéo xuống thì không
                    // làm gì (Review Focus 3); kéo ngang để dành cho Task 13.
                    drivesCard = axis == .vertical && value.translation.height < 0
                }
                guard drivesCard else { return }
                expansion.accessoryDragChanged(translationHeight: value.translation.height)
            }
            .onEnded { value in
                defer {
                    axis = nil
                    drivesCard = false
                }
                guard drivesCard else { return }
                expansion.accessoryDragEnded(
                    predictedTranslationHeight: value.predictedEndTranslation.height,
                    verticalVelocity: value.velocity.height
                )
            }
    }
}
```

- [ ] **Step 4: `PlayerCard`, phần khai báo**

Trong `PlayerCard.swift`, xoá các khai báo sau cùng toàn bộ ghi chú của chúng: `let minimised: Double`, `collapsedHeight`, `pillSideMargin`, `collapsedCornerRadius`, `collapsedArtwork`, `pillMinimisedScale`, `pillMinimisedRelief`, `collapsedArtworkInset`, `collapsedArtworkGap`, `collapsedSideMargin`, `pillShrink`, `collapsedBottomOffset`, và struct lồng `BottomHitRegion`.

Thay định nghĩa `progress`:

```swift
    /// Cộng thêm phần kéo đến từ accessory. Một cú kéo bắt đầu trên mini player
    /// lái thẻ qua `expansion` chứ không qua `dragDelta`, vì cử chỉ ấy thuộc về
    /// view khác. Lúc thả, thẻ chuyển phần ấy sang `dragDelta` — xem
    /// `handle(_:)`.
    private var progress: Double {
        min(max(settled + dragDelta + expansion.accessoryDragDelta, 0), 1)
    }
```

- [ ] **Step 5: `PlayerCard`, `body`**

Trên `GeometryReader { outer in … }`, ngay sau `.ignoresSafeArea()` của `card(...)`, thêm:

```swift
                .onGeometryChange(for: CGSize.self) { _ in
                    CGSize(width: outer.size.width + outer.safeAreaInsets.leading + outer.safeAreaInsets.trailing,
                           height: outer.size.height + outer.safeAreaInsets.top + outer.safeAreaInsets.bottom)
                } action: { size in
                    expansion.screenSize = size
                }
```

Trong chuỗi modifier của `body`:
- Ngay sau `.opacity(playback.currentTrack == nil ? 0 : 1)`, thêm:

```swift
        // Lúc nghỉ, chỗ của thẻ là viên kính accessory của hệ thống, và chính
        // accessory vẽ hàng mini player. Thẻ chỉ hiện khi rời trạng thái nghỉ.
        .opacity(expansion.isCardResting ? 0 : 1)
```

- Thay `.allowsHitTesting(playback.currentTrack != nil)` bằng:

```swift
        // Theo `progress` và cú kéo đang dở, không theo `isCardResting`: lúc thả
        // để thu về, `progress` đã là 0 ngay khi nhấc tay, nên thư viện phía sau
        // nhận chạm lại ngay chứ không phải đợi lò xo chạy xong.
        .allowsHitTesting(playback.currentTrack != nil && (progress > 0 || isDragging))
```

- Thay `.accessibilityHidden(playback.currentTrack == nil)` bằng `.accessibilityHidden(playback.currentTrack == nil || expansion.isCardResting)`.
- Thêm, ngay trước `.onChange(of: playback.explicitSelections)`:

```swift
        .onChange(of: expansion.intent) { _, intent in
            if let intent { handle(intent) }
        }
```

- [ ] **Step 6: `PlayerCard`, `card(size:insets:)`**

Thay hai dòng:

```swift
        let travel = max(fullHeight - Self.collapsedHeight, 1)
        let height = Self.collapsedHeight + travel * progress
```

bằng:

```swift
        let anchor = PlayerAnchor(
            frame: expansion.anchorFrame == .zero
                ? PlayerAnchor.fallbackFrame(screen: fullSize) : expansion.anchorFrame,
            screen: fullSize
        )
        let cardRect = anchor.cardFrame(progress: progress)
        let height = cardRect.height
```

Thay khối năm dòng `collapsedLeadingMargin … cardWidth` bằng:

```swift
        let leadingMargin = cardRect.minX
        let cardWidth = cardRect.width
```

Ghi chú dài phía trên khối ấy (về safe area và `FloatingTabBar`) không còn đúng: thay bằng `// Lề lấy thẳng từ khung accessory — xem PlayerAnchor.`

Thay `let dragTravel = max(fullHeight - Self.collapsedHeight - collapsedBottomOffset, 1)` bằng `let dragTravel = anchor.dragTravel`, và xoá đoạn ghi chú dẫn giải `top(p)` phía trên nó. Phép dẫn giải ấy giờ là `PlayerAnchorTests.testDragTravelIsExactlyHowFarTheTopEdgeMoves`.

Trong `ZStack` của `card`:
- `artworkView(size: cardSize, artworkSide: artworkSide, topInset: insets.top)` → thêm đối số `collapsedHeight: anchor.collapsedHeight`;
- `miniChrome(width: cardWidth)` → `miniChrome(width: cardWidth, height: anchor.collapsedHeight)`.

Trong chuỗi modifier sau `ZStack`:
- `.modifier(CardClip(progress: progress, insets: insets))` → `.modifier(CardClip(progress: progress, insets: insets, collapsedRadius: anchor.collapsedCornerRadius))`;
- xoá `.scaleEffect(pillShrink, anchor: .center)` và `.floatingBarShadow()` cùng ghi chú của chúng;
- thay toàn bộ `.contentShape(BottomHitRegion(...))` cùng khối ghi chú dài phía trên nó bằng:

```swift
        // Toàn màn hình, và chỉ nhận chạm khi `allowsHitTesting` trong `body`
        // cho phép (thẻ đang mở hoặc đang kéo). Lúc nghỉ thẻ không nhận chạm
        // nào: accessory của hệ thống nhận thay.
        .contentShape(Rectangle())
```

- `.padding(.bottom, collapsedBottomOffset * (1 - progress))` → `.padding(.bottom, anchor.bottomOffset * (1 - progress))`.

- [ ] **Step 7: `PlayerCard`, mini chrome, bìa và mặt nền**

Thay `miniChrome(width:)` bằng:

```swift
    private func miniChrome(width: CGFloat, height: CGFloat) -> some View {
        MiniPlayerRow(playback: playback, showsNext: !expansion.anchorIsInline)
            .frame(width: width, height: height)
            .opacity(max(0, 1 - progress * 3))
            .allowsHitTesting(progress < 0.1)
    }
```

(`.contextMenu` "Dừng phát" đã dời sang `MiniPlayerAccessory`.)

Trong `artworkView`, thêm tham số `collapsedHeight: CGFloat` và truyền nó vào **cả hai** chỗ gọi `Self.artworkGeometry(` (dòng ~1835 và ~1909) dưới dạng đối số cuối `collapsedHeight: collapsedHeight`. Nếu chỗ gọi ở ~1835 nằm ngoài `artworkView`, lần theo hàm chứa nó và thêm cùng tham số ấy, truyền xuống từ `card(size:insets:)`.

Trong `static func artworkGeometry(`, thêm tham số cuối `collapsedHeight: CGFloat`, rồi thay:
- `Self.collapsedArtworkInset` → `MiniPlayerMetrics.artworkLeadingInset`;
- `Self.collapsedArtwork` → `MiniPlayerMetrics.artworkSide` (ba chỗ);
- `y: Self.collapsedHeight / 2` → `y: collapsedHeight / 2`.

Đổi hai hàm bán kính:

```swift
    static func cardTopCornerRadius(progress: Double, collapsedRadius: CGFloat) -> CGFloat {
        collapsedRadius + (expandedCornerRadius - collapsedRadius) * progress
    }

    static func cardBottomCornerRadius(progress: Double, collapsedRadius: CGFloat) -> CGFloat {
        collapsedRadius * (1 - progress)
    }
```

Trong `CardClip`, thêm `let collapsedRadius: CGFloat` và truyền nó vào cả ba chỗ gọi hai hàm trên.

Trong `CardSurface`, thay **toàn bộ** `ZStack { … }` trong `body` bằng:

```swift
        // Đặc ngay từ khung đầu, như Apple Music (video 2026-10-06): viên kính
        // thành thẻ đặc ở khung thứ hai, không có kính chồng kính. Lớp dưới đặc
        // sẵn; lớp trên là nền của player mở rộng, lên dần theo `progress`.
        ZStack {
            Color(.secondarySystemBackground)
            Color(.systemGroupedBackground)
                .opacity(min(1, progress * PlayerCard.opaqueBaseRamp))
        }
```

Rồi xoá `static let materialCutoff` cùng ghi chú của nó (dòng ~350–371), cùng các đoạn ghi chú khác trong `PlayerCard.swift` nói về `.thinMaterial` của viên pill (`grep -n "thinMaterial\|materialCutoff" Evenstar/Evenstar/Features/Player/PlayerCard.swift`); sửa chúng thành một dòng "thẻ đặc từ khung đầu — xem `CardSurface`" nếu đoạn văn xung quanh cần câu nối.

- [ ] **Step 8: `PlayerCard`, cử chỉ, `morph` và trạng thái nghỉ**

Trong `drag(travel:threshold:)`, ở `onChanged`, thay `if !isDragging { isDragging = true }` bằng:

```swift
                if !isDragging {
                    isDragging = true
                    expansion.leaveRest()
                }
```

Thay `morph(to:curve:)` bằng bản giữ nguyên cả hai nhánh nhưng thêm điểm rời và điểm về trạng thái nghỉ:

```swift
    private func morph(to target: Double, curve: Animation) {
        if target > 0 { expansion.leaveRest() }
        guard BottomBarStyle.reduceMotion else {
            withAnimation(curve) {
                settled = target
                dragDelta = 0
                expansion.set(progress: target, animation: curve)
            } completion: {
                arriveAtRestIfCollapsed()
            }
            return
        }
        let needsFade = Self.morphNeedsFade(from: progress, to: target)
        withTransaction(Transaction(animation: nil)) {
            settled = target
            dragDelta = 0
            expansion.set(progress: target, animation: nil)
            if needsFade { cardOpacity = 0 }
        }
        if needsFade {
            withAnimation(curve) { cardOpacity = 1 }
        }
        // Giảm chuyển động: hình học đã ở đích ngay, nên về nghỉ ngay.
        arriveAtRestIfCollapsed()
    }

    /// Hỏi lại trạng thái **hiện tại** chứ không tin vào đích lúc đăng ký: một
    /// cú kéo mới có thể đã bắt đầu trước khi lò xo cũ chạy xong.
    private func arriveAtRestIfCollapsed() {
        guard settled == 0, dragDelta == 0, !isDragging else { return }
        expansion.arriveAtRest()
    }

    private func handle(_ intent: PlayerIntent) {
        switch intent.kind {
        case .expand:
            expand()
        case let .release(predictedProgress, verticalVelocity):
            // Chuyển phần kéo của accessory sang `dragDelta` trong cùng một
            // transaction không animation: tổng `progress` không đổi, thẻ không
            // nhảy, rồi `morph` lo cú đáp như mọi cú thả khác.
            let carried = expansion.takeAccessoryDrag()
            withTransaction(Transaction(animation: nil)) { dragDelta = carried }
            let target: Double = predictedProgress > 0.5 ? 1 : 0
            let travel = PlayerAnchor.dragTravel(for: expansion.anchorFrame)
            let curve = BottomBarStyle.settle(
                initialVelocity: Self.settleVelocity(
                    verticalVelocity: verticalVelocity,
                    travel: travel,
                    from: progress,
                    to: target
                )
            )
            morph(to: target, curve: curve)
        }
    }
```

Giữ nguyên phần ghi chú dài phía trên `morph`. Thêm một đoạn ở cuối: "Rời trạng thái nghỉ ở đầu hàm khi đích > 0; về nghỉ trong `completion` (hoặc ngay lập tức khi giảm chuyển động) — xem `arriveAtRestIfCollapsed()`."

- [ ] **Step 9: `RootView` gắn accessory và dựng thẻ mới**

Trong `RootView.swift`, thay `PlayerCard(playback: playback, minimised: 0, expansion: expansion)` cùng dòng ghi chú "Tạm cho tới Task 5" bằng:

```swift
            PlayerCard(playback: playback, expansion: expansion)
```

Thêm `.miniPlayerAccessory(playback: playback, expansion: expansion)` ngay sau `.tabBarMinimizeBehavior(.onScrollDown)`. Ở cuối file, ngoài struct:

```swift
/// Gắn accessory. Đây là chỗ **duy nhất** đọc `currentTrack` cho nó, và nằm
/// trong một modifier chứ không trong `RootView.body`: body ấy dựng lại
/// `TabView` cùng năm tab, còn body của modifier này chỉ bọc `content` đã dựng
/// sẵn. Cùng mẫu với `RecedeBehindPlayer`.
///
/// `EmptyView()` khi không có bài: spike 2026-10-06 xác nhận hệ thống khi ấy ẩn
/// hẳn viên kính, rồi cho nó trượt vào khi có bài, giữ nguyên tab đang mở và
/// vị trí cuộn.
private struct MiniPlayerAccessoryModifier: ViewModifier {
    let playback: PlaybackService
    let expansion: PlayerExpansion

    func body(content: Content) -> some View {
        content.tabViewBottomAccessory {
            if playback.currentTrack != nil {
                MiniPlayerAccessory(playback: playback, expansion: expansion)
            } else {
                EmptyView()
            }
        }
    }
}

private extension View {
    func miniPlayerAccessory(playback: PlaybackService, expansion: PlayerExpansion) -> some View {
        modifier(MiniPlayerAccessoryModifier(playback: playback, expansion: expansion))
    }
}
```

- [ ] **Step 10: Xoá `BottomBarMetrics` và build**

```bash
git rm Evenstar/Evenstar/Features/Shared/BottomBarMetrics.swift
```

Run: lệnh build ở Task 4 Step 6.
Expected: `** BUILD SUCCEEDED **`, không cảnh báo. Lỗi còn sót thường là một tham chiếu `BottomBarMetrics.` hay `PlayerCard.collapsedHeight` trong `BottomBarStyle.swift` hoặc `Features/Prototypes/`. Với `BottomBarStyle`, xoá thành viên ấy nếu nó chỉ phục vụ thanh tab hay viên pill cũ. Với Prototypes, xoá cả file prototype.

- [ ] **Step 11: Sửa test**

`ArtworkGeometryTests`:
- helper `geometry(progress:queueFactor:fullBleed:)` và chỗ gọi ở dòng ~205: thêm `collapsedHeight: 48`;
- `testTheCollapsedPillKeepsItsOwnSizeAndPlace`: thay bốn dòng kỳ vọng bằng:

```swift
        XCTAssertEqual(g.width, 30, accuracy: 0.001, "MiniPlayerMetrics.artworkSide")
        XCTAssertEqual(g.height, 30, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, 27, accuracy: 0.001, "inset 12 + half of 30")
        XCTAssertEqual(g.centre.y, 24, accuracy: 0.001, "half of the accessory's 48")
```

`ReduceMotionSurfacesTests` dòng ~2014 (`PlayerCard.artworkGeometry(`): thêm `collapsedHeight: 48`.

`PlayerCardCommitCostTests`: xoá **cả lớp** `PlayerCardTranslucencyTests` (dòng ~1183 tới hết lớp). Nó ghim "thẻ nhìn xuyên được trong lúc bung", và người dùng đã quyết ngược lại: thẻ đặc ngay khung đầu như Apple Music. Thay bằng một dòng ghi chú ở chỗ cũ: `// PlayerCardTranslucencyTests đã xoá 2026-10-06: thẻ giờ đặc từ khung đầu — xem CardSurface.`

`PlayerCardClipShapeTests`: mọi lời gọi `cardTopCornerRadius(progress: x)` / `cardBottomCornerRadius(progress: x)` thêm `collapsedRadius: 24`. Ý nghĩa các khẳng định không đổi.

`PlayerCardCommitCostTests`:
- `CardHarness`: xoá `@State private var minimised`, dựng `PlayerCard(playback: playback, expansion: expansion)`, và thay `.onAppear { Drive.minimised = { minimised = $0 } }` bằng `.onAppear { Drive.accessoryDrag = { expansion.setAccessoryDragDelta($0) } }`.
- Đổi tên `static var minimised: ((Double) -> Void)?` trong `Drive` thành `static var accessoryDrag: ((Double) -> Void)?`, và đổi mọi `Drive.minimised` thành `Drive.accessoryDrag` (các `tearDown` và dòng ~1105).
- Viết lại khối ghi chú "WHAT `minimised` STANDS FOR, AND WHERE IT FALLS SHORT" (dòng ~1043–1059) thành:

```swift
/// ─────────────────────────────────────────────────────────────────────────
/// THE DRAG INPUT
/// ─────────────────────────────────────────────────────────────────────────
/// A drag that starts on the mini player writes
/// `PlayerExpansion.accessoryDragDelta` once per frame, and `PlayerCard` folds
/// it into `progress`. The harness writes that same value through
/// `setAccessoryDragDelta(_:)` — the real per-frame input, not a stand-in. The
/// earlier version had to model the drag with `minimised`, which fed fewer
/// downstream attributes than `progress`; that caveat no longer applies.
```

- `testWhereTheCardIsAtEachSample`: thay phép tính `rest` bằng `let rest = Int(PlayerAnchor.fallbackFrame(screen: CGSize(width: 390, height: 844)).minY)`. 390×844 là cỡ cửa sổ của rig (dòng ~83). Rig không có accessory, nên thẻ bung từ khung dự phòng. Thẻ vô hình lúc nghỉ, nên mẫu đầu (trước khi `tapToOpen` có hiệu lực) có thể là `nil`; nếu test đang khẳng định mẫu đầu bằng `rest`, đổi thành khẳng định cho mẫu **đầu tiên khác `nil`**.
- `testTheProbeSeparatesARectangleFromALayerStackFromTheRealCard` và `testWhereTheCoverIsOnTheFrameItArrives`: chỉ đổi chỗ dựng `PlayerCard`/`Drive` như trên. Nếu khẳng định của chúng phụ thuộc vào thẻ hiện ra lúc nghỉ, gọi `rig.expansion.leaveRest()` trước khi đo, và ghi lý do bằng một dòng ghi chú.

Run: lệnh test chuẩn.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 12: Xem bằng mắt trên simulator**

```bash
./run.sh "iPhone 17 test"
```

Kiểm, theo thứ tự:
1. Chưa có bài: không có viên kính trên thanh tab.
2. Chạm một bài: thẻ bung ra từ đáy màn hình (khung dự phòng), không từ góc trên.
3. Kéo thẻ xuống để thu: thẻ về **đúng** viên kính accessory, rồi accessory hiện lại, không chớp hai lớp.
4. Chạm viên kính: bung. Kéo viên kính lên: thẻ bám theo ngón tay.
5. Cuộn danh sách cho thanh tab thu nhỏ, rồi lặp 3–4 từ viên kính hẹp.
6. Kéo viên kính xuống, và kéo ngang: không có gì xảy ra.
7. Bấm play/next trên viên kính: chạy, không bung player. Cuộn cho thanh tab thu nhỏ: ⏭ mờ dần và biến mất; cuộn lên: hiện lại.
7b. Khung đầu cú bung: viên kính thành thẻ **đặc**, không thấy danh sách xuyên qua.
8. Giữ lâu trên viên kính: menu "Dừng phát".

Chụp ảnh ở hai vị trí bằng `xcrun simctl io booted screenshot` và đính vào báo cáo task.

- [ ] **Step 13: Commit**

```bash
git add -A Evenstar/
git commit -m "feat: mini player trong accessory native; PlayerCard bung từ khung accessory"
```

---

## Task 6: Kiểm giai đoạn 1 trên iPhone thật (người dùng làm)

**Files:** không sửa file nào. Agent soạn checklist và nhận kết quả.

- [ ] **Step 1: Nhắn người dùng checklist sau và đợi kết quả**

Cài bằng `./device.sh` hoặc Xcode ⌘R lên iPhone (iOS 26), rồi kiểm:
- sáng và tối; màn ngang; Cài đặt → Trợ năng → Chuyển động → **Giảm chuyển động**; chữ cỡ lớn nhất (Dynamic Type);
- chưa có bài → có bài; tab Search;
- bung và thu player từ viên kính rộng và viên kính hẹp; **khung đầu tiên có chớp hay có hai lớp kính không**;
- đang phát mà bấm "Dừng phát": player thu về, viên kính biến mất;
- cuộn lên xuống chục lần: **⏭ có lúc nào kẹt sai không** (đang thu nhỏ mà còn ⏭, hoặc đang bung mà mất ⏭).

- [ ] **Step 2: Ghi kết quả**

Lỗi nào người dùng báo thì sửa theo `superpowers:systematic-debugging`, mỗi lỗi một commit.

Nếu ⏭ kẹt sai: `placement` không đáng tin trên máy thật. Khi ấy đổi `MiniPlayerControls(playback: playback, showsNext: !isInline)` trong `MiniPlayerAccessory` thành `showsNext: true`, và `MiniPlayerRow(playback: playback, showsNext: !expansion.anchorIsInline)` trong `PlayerCard` thành `showsNext: true`. Commit riêng, ghi lý do. Nếu kết luận là chỗ nối giữa kính accessory và thẻ không chấp nhận được, **dừng plan** và quay lại brainstorming với đường lui trong spec (zoom transition native).

---

## Task 7: Đo hiệu năng cú bung (người dùng làm, agent hỗ trợ)

**Files:**
- Create: `docs/superpowers/audits/2026-10-06-e3-trace.md`

- [ ] **Step 1: Chuẩn bị**

Kiểm còn ≥ 10 GB trống: `df -h ~`. Theo `docs/superpowers/audits/2026-08-19-e2-trace.md`, lặp lại đúng quy trình E2: `Animation Hitches`, iPhone 12, bản **Release**, cùng kịch bản mở/đóng player trong 35 giây. `xctrace` ở chế độ Deferred đứng ở 0% CPU khoảng 2 phút lúc lưu; **không** kill nó.

- [ ] **Step 2: So với mức nền**

Mức nền E2: **22,9 ms/giây**. Ghi số mới, cùng phân bổ commit / commit-to-render / GPU, vào file audit. Qua khi **không tệ hơn**. Nếu tệ hơn, nghi phạm đầu tiên là lượt `onChange(of: expansion.intent)` và việc thẻ luôn nằm trong cây view lúc nghỉ. Ghi lại rồi hỏi người dùng trước khi sửa.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/audits/2026-10-06-e3-trace.md
git commit -m "docs: trace E3 — cú bung sau khi chuyển sang accessory native"
```

---

## Task 8: Điểm dừng giai đoạn 1

- [ ] **Step 1:** Chạy lệnh test chuẩn và build Release không cảnh báo:

```bash
xcodebuild build -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData 2>&1 | grep -E "warning:|error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`, không có `warning:`.

- [ ] **Step 2:** Báo người dùng giai đoạn 1 xong, kèm số test, kết quả Task 6 và Task 7. Đợi đồng ý rồi mới sang giai đoạn 2.

---

## Task 9: Nút hành động chính → `.glassProminent`

**Files:**
- Modify: `Features/Jamendo/JamendoSongsList.swift:38`, `Features/Jamendo/JamendoDiscoveryView.swift:285`, `Features/Library/EmptyLibraryView.swift:25`, `Features/Drive/DriveSongsList.swift:75`, `Features/Import/ImportProgressSheet.swift:55`, `Features/Library/TrackMetadataEditor.swift:84` (tất cả dưới `Evenstar/Evenstar/`)
- Delete: `Evenstar/Evenstar/Features/Shared/ProminentActionButton.swift`

- [ ] **Step 1: Đổi kiểu nút**

Ở mỗi dòng trên, thay `.buttonStyle(.prominentAction)` (hoặc `.buttonStyle(.borderedProminent)` ở `TrackMetadataEditor`) bằng:

```swift
                .buttonStyle(.glassProminent)
                // Đặt màu rõ ràng: mặc định là màu accent, mà accent của app là
                // trắng — nút trắng trên nền sáng thì không ai thấy.
                .tint(Color(.label))
```

Xoá các dòng ghi chú cũ nói về `.prominentAction` ngay trên mỗi chỗ (ví dụ `JamendoSongsList.swift:32`).

- [ ] **Step 2: Xoá style cũ và build**

```bash
git rm Evenstar/Evenstar/Features/Shared/ProminentActionButton.swift
```

Run: lệnh build ở Task 4 Step 6. Expected: thành công, không cảnh báo.

- [ ] **Step 3: Kiểm độ tương phản ở cả hai chế độ**

```bash
./run.sh "iPhone 17 test"
xcrun simctl ui booted appearance light
```

Mở màn thư viện trống (nút "Nhập nhạc" của `EmptyLibraryView`), chụp `xcrun simctl io booted screenshot /tmp/glass-light.png`. Rồi `xcrun simctl ui booted appearance dark` và chụp `/tmp/glass-dark.png`. Đọc cả hai ảnh.
Expected: ở cả hai chế độ, chữ trên nút đọc rõ trên nền nút. Nếu chữ chìm (cùng màu với nền nút), thêm `.foregroundStyle(Color(.systemBackground))` lên **label** của nút ở cả sáu chỗ, rồi chụp lại.

- [ ] **Step 4: Chạy test, commit**

Run: lệnh test chuẩn. Expected: `** TEST SUCCEEDED **`.

```bash
git add -A Evenstar/
git commit -m "feat: nút hành động chính dùng .glassProminent native"
```

---

## Task 10: Nút trong player → `.glass` + haptic

**Files:**
- Create: `Evenstar/Evenstar/Features/Shared/GlassToggleStyle.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, `Evenstar/Evenstar/Features/Player/QueuePanel.swift`
- Delete: `Features/Shared/TransportButtonStyle.swift`, `QueueToggleStyle.swift`, `TapHalo.swift`, `TouchDownButton.swift`
- Test: `Evenstar/EvenstarTests/ReduceMotionSurfacesTests.swift`

**Interfaces:**
- Produces: `extension View { func glassToggleStyle(isOn: Bool) -> some View }`.

- [ ] **Step 1: `GlassToggleStyle`**

```swift
import SwiftUI

extension View {
    /// Nút bật/tắt bằng kính native: bật → `.glassProminent`, tắt → `.glass`.
    /// Trạng thái phải nhìn ra được, vì glyph của shuffle và repeat vẽ giống
    /// hệt nhau dù bật hay tắt.
    @ViewBuilder
    func glassToggleStyle(isOn: Bool) -> some View {
        if isOn {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}
```

- [ ] **Step 2: Hàng transport trong `NowPlayingContent`**

Thay `private var transport: some View { … }` bằng:

```swift
    private var transport: some View {
        HStack(spacing: 40) {
            Button {
                previousTaps += 1
                playback.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .light), trigger: previousTaps)
            .disabled(playback.currentTrack == nil)

            Button {
                playPauseTaps += 1
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Self.playGlyphSize))
                    .symbolReplace()
                    .frame(width: Self.playGlyphSize * 1.4, height: Self.playGlyphSize * 1.4)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .medium), trigger: playPauseTaps)
            .disabled(playback.currentTrack == nil)

            Button {
                nextTaps += 1
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .light), trigger: nextTaps)
            .disabled(!playback.canGoNext)
        }
        .padding(.top, 8)
    }
```

Xoá `acknowledge(_:)` nếu không còn ai gọi. Kiểm: `grep -n "acknowledge" Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`.

- [ ] **Step 3: Nút hàng đợi**

Trong `queueToggleRow`, thay `TouchDownButton { … } label: { … }` cùng các modifier tới hết `.buttonStyle(.queueToggle)` bằng:

```swift
            Button {
                queueTaps += 1
                withAnimation(BottomBarStyle.queue) {
                    showingQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: Self.queueGlyphFrame, height: Self.queueGlyphFrame)
            }
            .glassToggleStyle(isOn: showingQueue)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .light), trigger: queueTaps)
```

Giữ nguyên `.disabled`, `.accessibilityLabel`, `.accessibilityAddTraits` phía dưới. Thêm `@State private var queueTaps = 0` cạnh các bộ đếm khác. Xoá `queueBadgeScale`, `queueBadgeScaleFull`, `queueBadgeScaleFlat` cùng ghi chú của chúng: mảng nền cũ đã được kính thay thế. Mục 5 trong danh sách "NĂM CHỖ" ở `PlayerCard.setQueueFactor` nhắc tới `queueBadgeScale`, nên sửa mục ấy thành "Mảng nền nút hàng đợi — không còn; nút giờ là kính native."

- [ ] **Step 4: Viên shuffle/repeat trong `QueuePanel`**

Trong `pill(systemImage:isOn:label:trigger:action:)`, thay từ `TouchDownButton(action: action) {` tới hết `.buttonStyle(.transportPill(trigger: trigger))` bằng:

```swift
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolReplace()
                .frame(width: pillWidth, height: Self.pillHeight)
        }
        .glassToggleStyle(isOn: isOn && enabled)
        .buttonBorderShape(.capsule)
        .sensoryFeedback(.impact(weight: .light), trigger: trigger)
```

Giữ `.disabled`, `.accessibilityLabel`, `.accessibilityAddTraits`. Tham số `tint` của hàm và ghi chú về fill (dòng ~349–354) không còn dùng: xoá tham số ở định nghĩa và ở mọi chỗ gọi, và sửa ghi chú thành "Trạng thái bật/tắt nói bằng kiểu kính — xem `glassToggleStyle`."

- [ ] **Step 5: Xoá bốn file style cũ và build**

```bash
git rm Evenstar/Evenstar/Features/Shared/TransportButtonStyle.swift \
       Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift \
       Evenstar/Evenstar/Features/Shared/TapHalo.swift \
       Evenstar/Evenstar/Features/Shared/TouchDownButton.swift
```

Run: lệnh build ở Task 4 Step 6. Expected: thành công, không cảnh báo. Rồi chạy lại vòng dọn `BottomBarStyle` ở Task 4 Step 8, vì `pressedScale`, `pressedOpacity`, `press`… có thể vừa hết người gọi.

- [ ] **Step 6: Sửa test**

Xoá nguyên hàm trong `ReduceMotionSurfacesTests`:
`testTheActiveGlyphStillCrossesThatBarWithTheSettingOff`, `testThePressScalesFlattenAndTheDimAppears`, `testTheReducedPressIsStillVisibleAndNotADisabledLook`, `testTheTransportKickLosesEveryDisplacement`, `testAHeldPressDimsTheGlyphWithNoCommandSentWhenMotionIsReduced`, `testTheSamePressDoesNotDimWithTheSettingOff`, `testTheEffectIsSuppressedByDisablingAnimationsAndByAnOpacityTransition`.

Sửa, không xoá:
- `testNoProductionSiteCallsTheReplaceTransitionDirectly`: bỏ `MiniPlayerChrome`/`TransportButtonStyle` khỏi danh sách file nó quét nếu có; giữ khẳng định chính.
- `testTheDragArithmeticIgnoresReduceMotion`: bỏ các dòng về `TransportButtonStyle`/`transportSkip`/`pressedOpacity`; giữ phần về phép tính kéo của `PlayerCard`.

Run: lệnh test chuẩn. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Xem bằng mắt**

`./run.sh "iPhone 17 test"`, mở player, chụp màn hình. Kiểm: ba nút transport là kính tròn; nút hàng đợi đổi kiểu kính khi bật; shuffle/repeat đọc ra được bật/tắt ở cả sáng và tối.

- [ ] **Step 8: Commit**

```bash
git add -A Evenstar/
git commit -m "feat: nút trong player dùng kính native và haptic; xoá các ButtonStyle tự viết"
```

---

## Task 11: `PlaybackService.canGoPrevious` và `stepBack()`

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` (cạnh `canGoNext` dòng ~100 và `previous()` dòng ~540)
- Test: `Evenstar/EvenstarTests/PlaybackServiceStepBackTests.swift`

**Interfaces:**
- Produces: `var canGoPrevious: Bool`, `func stepBack()`.

- [ ] **Step 1: Viết test đỏ**

```swift
import XCTest
@testable import Evenstar

/// Cú vuốt phải trên mini player **luôn lùi hẳn một bài**, khác nút ⏮ ở chỗ bỏ
/// qua ngưỡng "phát lại từ đầu sau 3 giây". Hình bài cũ trượt vào mà kết quả
/// là phát lại bài hiện tại thì sai với điều mắt thấy.
@MainActor
final class PlaybackServiceStepBackTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: MockNowPlayingPublisher(), library: library)
        return (service, player, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        try (0..<count).map { i in
            let t = Track(title: "Track \(i)", artistName: "Artist", albumTitle: "Album",
                          durationSeconds: 100, relativePath: "Music/\(UUID().uuidString).mp3",
                          format: "mp3")
            try library.insert(t)
            return t
        }
    }

    func testPastTheRestartThresholdItStillStepsBack() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        player.currentTime = 30
        service.tickForTesting()

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
    }

    func testAtTheHeadWithRepeatOffThereIsNowhereToGo() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        XCTAssertFalse(service.canGoPrevious)

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 0, "không lùi, và không phát lại từ đầu")
        XCTAssertEqual(service.currentTrack?.id, list[0].id)
    }

    func testAtTheHeadWithRepeatAllItWrapsToTheLast() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()  // .all
        XCTAssertTrue(service.canGoPrevious)

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 2)
    }

    func testAtTheHeadWithRepeatOneItAlsoWraps() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        service.cycleRepeatMode()
        service.cycleRepeatMode()  // .one

        service.stepBack()

        XCTAssertEqual(service.queueIndex, 2)
    }

    func testMidQueueCanGoPreviousWhateverTheRepeatMode() throws {
        let (service, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        XCTAssertTrue(service.canGoPrevious)
        service.cycleRepeatMode()
        XCTAssertTrue(service.canGoPrevious)
    }

    func testAnEmptyQueueCannotGoPrevious() throws {
        let (service, _, _) = try makeStack()
        XCTAssertFalse(service.canGoPrevious)
        service.stepBack()  // không sập
        XCTAssertNil(service.currentTrack)
    }

    /// `previous()` không được đổi hành vi.
    func testThePreviousButtonStillRestartsPastTheThreshold() throws {
        let (service, player, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[1], in: list)
        player.currentTime = 30
        service.tickForTesting()

        service.previous()

        XCTAssertEqual(service.queueIndex, 1)
    }
}
```

- [ ] **Step 2: Chạy, xác nhận đỏ**

Run: lệnh test chuẩn với `-only-testing:EvenstarTests/PlaybackServiceStepBackTests`
Expected: FAIL, `value of type 'PlaybackService' has no member 'stepBack'`.

- [ ] **Step 3: Viết code**

Ngay sau `canGoNext`:

```swift
    /// Whether a swipe back has a track to land on. Unlike the Previous button
    /// — which is never a no-op, because it can always restart — a swipe means
    /// "the track before this one", and at the head of an unrepeated queue
    /// there is none.
    var canGoPrevious: Bool {
        !queue.isEmpty && (queueIndex > 0 || repeatMode != .off)
    }
```

Ngay sau `previous()`:

```swift
    /// Steps back one track, ignoring `restartThreshold`. For the mini player's
    /// swipe: the previous track's artwork slides in, so restarting the current
    /// one would contradict what the user just watched. At the head of the
    /// queue it wraps when a repeat mode is armed, like `previous()`, and does
    /// nothing otherwise — `canGoPrevious` is false there and the swipe
    /// rubber-bands instead of calling this.
    func stepBack() {
        guard canGoPrevious else { return }
        advance(to: queueIndex > 0 ? queueIndex - 1 : queue.count - 1)
    }
```

- [ ] **Step 4: Chạy, xác nhận xanh**

Expected: 7 test PASS. Chạy toàn bộ `PlaybackService*Tests` để chắc `previous()` không đổi.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Services/PlaybackService.swift Evenstar/EvenstarTests/PlaybackServiceStepBackTests.swift
git commit -m "feat: PlaybackService.stepBack — lùi một bài cho cú vuốt, bỏ qua ngưỡng phát lại"
```

---

## Task 12: `TrackSwipe`, quyết định của cú vuốt ngang

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/TrackSwipe.swift`
- Test: `Evenstar/EvenstarTests/TrackSwipeTests.swift`

**Interfaces:**
- Produces: `enum TrackSwipe { enum Outcome: Equatable { case next, previous, cancel }`, `static func outcome(translation: CGFloat, predictedTranslation: CGFloat, width: CGFloat, canGoNext: Bool, canGoPrevious: Bool) -> Outcome`, `static func displayedOffset(translation: CGFloat, canGoNext: Bool, canGoPrevious: Bool) -> CGFloat`, `static let commitFraction: CGFloat = 0.3`, `static let rubberBandFactor: CGFloat = 0.25 }`.

- [ ] **Step 1: Viết test đỏ**

```swift
import XCTest
@testable import Evenstar

final class TrackSwipeTests: XCTestCase {
    private let width: CGFloat = 234

    func testPastThirtyPercentLeftIsNext() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -80, predictedTranslation: -80, width: width,
                                          canGoNext: true, canGoPrevious: true), .next)
    }

    func testPastThirtyPercentRightIsPrevious() {
        XCTAssertEqual(TrackSwipe.outcome(translation: 80, predictedTranslation: 80, width: width,
                                          canGoNext: true, canGoPrevious: true), .previous)
    }

    func testAShortSlowSwipeCancels() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -30, predictedTranslation: -40, width: width,
                                          canGoNext: true, canGoPrevious: true), .cancel)
    }

    /// Một cú búng ngắn nhưng nhanh: dự đoán quá ngưỡng thì vẫn đổi bài.
    func testAShortFastFlickCommits() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -30, predictedTranslation: -200, width: width,
                                          canGoNext: true, canGoPrevious: true), .next)
    }

    /// Review Focus 4: ở cuối hàng đợi không bao giờ gọi `next()`, vì khi tắt
    /// repeat nó dừng phát.
    func testNoNextNeverCommitsNext() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -200, predictedTranslation: -400, width: width,
                                          canGoNext: false, canGoPrevious: true), .cancel)
    }

    func testNoPreviousNeverCommitsPrevious() {
        XCTAssertEqual(TrackSwipe.outcome(translation: 200, predictedTranslation: 400, width: width,
                                          canGoNext: true, canGoPrevious: false), .cancel)
    }

    func testTheContentFollowsTheFingerWhenThereIsSomewhereToGo() {
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: -60, canGoNext: true, canGoPrevious: true), -60)
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: 60, canGoNext: true, canGoPrevious: true), 60)
    }

    func testTheContentRubberBandsWhenThereIsNowhereToGo() {
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: -60, canGoNext: false, canGoPrevious: true),
                       -60 * TrackSwipe.rubberBandFactor)
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: 60, canGoNext: true, canGoPrevious: false),
                       60 * TrackSwipe.rubberBandFactor)
    }
}
```

- [ ] **Step 2: Chạy, xác nhận đỏ**

Expected: FAIL, `cannot find 'TrackSwipe' in scope`.

- [ ] **Step 3: Viết code**

```swift
import CoreGraphics

/// Cú vuốt ngang trên mini player: trái là bài tiếp, phải là bài trước.
///
/// Quyết theo vị trí **dự đoán** lúc thả chứ không theo vị trí hiện tại, nên
/// một cú búng ngắn mà nhanh vẫn đổi bài, giống cú thả thẻ player.
enum TrackSwipe {
    enum Outcome: Equatable {
        case next
        case previous
        case cancel
    }

    /// Phần bề ngang phải vượt qua để đổi bài.
    static let commitFraction: CGFloat = 0.3
    /// Nội dung chỉ đi theo ngón tay chừng này khi không có bài để tới.
    static let rubberBandFactor: CGFloat = 0.25

    static func outcome(translation: CGFloat, predictedTranslation: CGFloat, width: CGFloat,
                        canGoNext: Bool, canGoPrevious: Bool) -> Outcome {
        let threshold = width * commitFraction
        let reach = abs(predictedTranslation) > abs(translation) ? predictedTranslation : translation
        if reach <= -threshold { return canGoNext ? .next : .cancel }
        if reach >= threshold { return canGoPrevious ? .previous : .cancel }
        return .cancel
    }

    static func displayedOffset(translation: CGFloat, canGoNext: Bool, canGoPrevious: Bool) -> CGFloat {
        let blocked = translation < 0 ? !canGoNext : !canGoPrevious
        return blocked ? translation * rubberBandFactor : translation
    }
}
```

- [ ] **Step 4: Chạy, xác nhận xanh**

Expected: 8 test PASS.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Player/TrackSwipe.swift Evenstar/EvenstarTests/TrackSwipeTests.swift
git commit -m "feat: TrackSwipe — quyết định vuốt ngang đổi bài"
```

---

## Task 13: Nối vuốt ngang vào accessory

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/MiniPlayerAccessory.swift`

**Interfaces:**
- Consumes: `TrackSwipe` (Task 12), `PlaybackService.canGoPrevious` và `stepBack()` (Task 11), `AccessoryDragAxis` (Task 2), `BottomBarStyle.reduceMotion`, `BottomBarStyle.settle`.

- [ ] **Step 1: Kiểm rủi ro trước: hệ thống có nuốt cú kéo ngang không**

Thêm tạm vào nhánh `onChanged` của `drag`, ngay sau khi gán `axis`:

```swift
                    AppLog.playback.debug("accessory axis \(String(describing: axis))")
```

Chạy `./run.sh "iPhone 17 test"`, kéo ngang trên viên kính ở cả hai vị trí, rồi đọc log:
`xcrun simctl spawn booted log show --last 2m --predicate 'eventMessage CONTAINS "accessory axis"' | tail`
Expected: thấy `horizontal`. Nếu **không** thấy (hệ thống nuốt cú kéo ngang), **dừng task**, gỡ dòng log và báo người dùng; không tự tìm đường vòng.
Gỡ dòng log trước khi sang bước sau.

- [ ] **Step 2: Thêm trạng thái và hiệu ứng trượt**

Trong `MiniPlayerAccessory`, thêm:

```swift
    /// Nội dung bìa + tên bài lệch đi bao nhiêu theo cú vuốt ngang.
    @State private var swipeOffset: CGFloat = 0
    /// Bề rộng vùng thông tin bài, để quy ngưỡng 30% ra điểm.
    @State private var infoWidth: CGFloat = 1
    @State private var swipeCommits = 0
```

Trong `info`, ngay sau `HStack { … }` (trước `.padding(.leading, …)`), thêm:

```swift
        .offset(x: swipeOffset)
        .opacity(1 - min(abs(swipeOffset) / max(infoWidth, 1), 1) * 0.6)
```

và ngay sau `.frame(maxHeight: .infinity)`:

```swift
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { infoWidth = $0 }
        .sensoryFeedback(.impact(weight: .light), trigger: swipeCommits)
```

- [ ] **Step 3: Nhánh ngang trong cử chỉ**

Thay `drag` bằng:

```swift
    private var drag: some Gesture {
        DragGesture(minimumDistance: AccessoryDragAxis.lockDistance, coordinateSpace: .global)
            .onChanged { value in
                if axis == nil {
                    axis = AccessoryDragAxis.resolve(value.translation)
                    drivesCard = axis == .vertical && value.translation.height < 0
                }
                if drivesCard {
                    expansion.accessoryDragChanged(translationHeight: value.translation.height)
                } else if axis == .horizontal {
                    swipeOffset = TrackSwipe.displayedOffset(
                        translation: value.translation.width,
                        canGoNext: playback.canGoNext,
                        canGoPrevious: playback.canGoPrevious
                    )
                }
            }
            .onEnded { value in
                defer {
                    axis = nil
                    drivesCard = false
                }
                if drivesCard {
                    expansion.accessoryDragEnded(
                        predictedTranslationHeight: value.predictedEndTranslation.height,
                        verticalVelocity: value.velocity.height
                    )
                } else if axis == .horizontal {
                    finishSwipe(TrackSwipe.outcome(
                        translation: value.translation.width,
                        predictedTranslation: value.predictedEndTranslation.width,
                        width: infoWidth,
                        canGoNext: playback.canGoNext,
                        canGoPrevious: playback.canGoPrevious
                    ))
                }
            }
    }

    /// Bài cũ trượt hẳn ra, bài mới trượt vào từ phía đối diện. Giảm chuyển
    /// động: không trượt, chỉ mờ chéo — nội dung đổi khi đang ở độ mờ thấp.
    private func finishSwipe(_ outcome: TrackSwipe.Outcome) {
        guard outcome != .cancel else {
            withAnimation(BottomBarStyle.settle) { swipeOffset = 0 }
            return
        }
        let direction: CGFloat = outcome == .next ? -1 : 1
        let change = {
            swipeCommits += 1
            if outcome == .next { playback.next() } else { playback.stepBack() }
        }
        if BottomBarStyle.reduceMotion {
            swipeOffset = 0
            withAnimation(.easeOut(duration: 0.12)) { swipeOffsetFade = true } completion: {
                change()
                withAnimation(.easeIn(duration: 0.12)) { swipeOffsetFade = false }
            }
            return
        }
        withAnimation(.easeIn(duration: 0.16)) {
            swipeOffset = direction * infoWidth
        } completion: {
            change()
            withTransaction(Transaction(animation: nil)) { swipeOffset = -direction * infoWidth }
            withAnimation(BottomBarStyle.settle) { swipeOffset = 0 }
        }
    }
```

Thêm `@State private var swipeOffsetFade = false` cạnh các trạng thái ở Step 2. Đổi dòng `.opacity(…)` của Step 2 thành:

```swift
        .opacity(swipeOffsetFade ? 0.15 : 1 - min(abs(swipeOffset) / max(infoWidth, 1), 1) * 0.6)
```

- [ ] **Step 4: Build và chạy toàn bộ test**

Run: lệnh build ở Task 4 Step 6, rồi lệnh test chuẩn.
Expected: build sạch không cảnh báo; `** TEST SUCCEEDED **`.

- [ ] **Step 5: Xem bằng mắt trên simulator**

`./run.sh "iPhone 17 test"`, phát một hàng đợi 3 bài. Kiểm:
- vuốt trái giữa hàng đợi → bài tiếp; vuốt phải → bài trước, kể cả khi bài đã chạy quá 3 giây;
- ở bài cuối khi tắt repeat, vuốt trái → kéo bị nặng rồi nảy về, nhạc vẫn phát;
- ở bài đầu khi tắt repeat, vuốt phải → nảy về;
- vuốt ở cả viên kính rộng lẫn hẹp;
- kéo lên vẫn bung player; nút play/next vẫn bấm được;
- bật Giảm chuyển động (`xcrun simctl` không bật được; dùng app Cài đặt trong simulator): vuốt thì mờ chéo, không trượt.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Features/Player/MiniPlayerAccessory.swift
git commit -m "feat: vuốt ngang mini player để đổi bài"
```

---

## Task 14: Kiểm cuối trên iPhone thật và khép nhánh

- [ ] **Step 1:** Lặp checklist Task 6 cùng phần vuốt đổi bài của Task 13 Step 5, trên iPhone thật. Người dùng làm; agent ghi kết quả.
- [ ] **Step 2:** Build Release không cảnh báo (lệnh ở Task 8 Step 1) và chạy lệnh test chuẩn. Báo số test cuối.
- [ ] **Step 3:** Cập nhật memory `project_ios26_deferred.md`: Đợt C đã ship trên nhánh `native-liquid-glass`, kèm số E3.
- [ ] **Step 4:** Dùng `superpowers:finishing-a-development-branch` để chọn cách gộp nhánh.
