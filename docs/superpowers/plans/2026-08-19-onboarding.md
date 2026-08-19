# Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lần chạy đầu có một màn giới thiệu một trang kèm chọn ngôn ngữ, và hai gợi ý tại chỗ dạy hai cử chỉ không tự phát hiện được.

**Architecture:** `RootView` vẫn được gắn ngay từ đầu và màn giới thiệu phủ lên trên trong `EvenstarApp.body`, để lớp làm nóng cùng cú seed `LibraryStore` không bị dời sang sau lúc người dùng bấm "Bắt đầu". `RootView.body` không đọc cờ onboarding nào — hai gợi ý là hai view con tự đọc trạng thái bên trong thân của chúng, đúng khuôn `FloatOverPlayer`. Quyết định "có hiện không" là hai hàm thuần trong `OnboardingFlags`.

**Tech Stack:** SwiftUI, iOS 18.0, `@AppStorage`/`UserDefaults`, String Catalog (`Localizable.xcstrings`, `sourceLanguage: vi`), XCTest.

**Spec:** [`docs/superpowers/specs/2026-08-19-onboarding-design.md`](../specs/2026-08-19-onboarding-design.md)

## Global Constraints

- **Không sửa `.pbxproj` hay `.xcscheme`.** Dự án dùng Xcode 16 synced folders nên file mới tự vào target. Loại một file khỏi target đòi sửa `.pbxproj` — bị cấm. Dùng `#if DEBUG` thay vì loại file.
- **Test phải xanh sau mỗi task:** `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test`. Suite hiện tại: **549 test, 6 skip, 0 fail**.
- **`PlayerCardCommitCostControlTests` flake dưới tải.** Nếu chỉ nó đỏ, chạy lại suite trước khi kết luận. **Không hạ ngưỡng của nó.**
- **Chú thích tiếng Việt** trong `PlayerCard`, `BottomBarStyle`, `RootView`, và mọi file mới của onboarding. Khớp hàng xóm, không đồng bộ hoá cả repo.
- **`sourceLanguage` của catalogue là `vi`.** Chuỗi nguồn viết tiếng Việt; tiếng Anh là bản dịch phải thêm tay vào `Localizable.xcstrings`.
- **Không sửa `PlayerCard.swift`** ngoài đúng một việc ở Task 4: nâng hai hằng số grabber từ `private static` lên `static`.
- **Giảm chuyển động** đọc qua `BottomBarStyle.reduceMotion`. Mọi hằng số chuyển động mới phải có hai nhánh và phải được liệt kê trong `ReduceMotionTests` — test ở đó khẳng định **từng hằng số có tên**, nó không tự quét file.
- **Đường dẫn trong plan này tính từ gốc repo** (`/Users/phanquyetthang/evenstar`). Lệnh `xcodebuild` chạy từ `Evenstar/`.

---

### Task 1: `OnboardingFlags` — khoá lưu trữ và hai hàm thuần

**Files:**
- Create: `Evenstar/Evenstar/Features/Onboarding/OnboardingFlags.swift`
- Test: `Evenstar/EvenstarTests/OnboardingFlagsTests.swift`

**Interfaces:**
- Consumes: không gì.
- Produces:
  - `OnboardingFlags.introFinishedKey: String` = `"onboardingIntroFinished"`
  - `OnboardingFlags.playerCloseHintSeenKey: String` = `"onboardingPlayerCloseHintSeen"`
  - `OnboardingFlags.tabBarHintSeenKey: String` = `"onboardingTabBarHintSeen"`
  - `OnboardingFlags.playerFullyOpen: Double` = `0.99`
  - `OnboardingFlags.showsPlayerCloseHint(introFinished: Bool, alreadySeen: Bool, presentedProgress: Double) -> Bool`
  - `OnboardingFlags.showsTabBarHint(introFinished: Bool, alreadySeen: Bool, isMinimised: Bool) -> Bool`

- [ ] **Step 1: Viết test đỏ**

Tạo `Evenstar/EvenstarTests/OnboardingFlagsTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// Hai hàm quyết định của onboarding.
///
/// Chúng thuần và nhận đủ đầu vào qua tham số, đúng khuôn
/// `PlayerCard.morphNeedsFade(from:to:)` và
/// `PlayerCard.source(hasArtwork:loaded:)` — hai hàm mà repo này đã trả giá để
/// học rằng một quy tắc nằm trong thân view thì không kiểm được.
///
/// Cách hỏng mà file này canh là cách hỏng **im lặng**: một gợi ý hiện lại sau
/// khi đã xem, hoặc không bao giờ hiện, hoặc hiện lúc màn giới thiệu còn đó.
/// Không có cái nào trong ba cái đó làm app crash.
final class OnboardingFlagsTests: XCTestCase {

    // MARK: - Gợi ý đóng player

    func testThePlayerHintWaitsForTheIntroToFinish() {
        XCTAssertFalse(
            OnboardingFlags.showsPlayerCloseHint(
                introFinished: false, alreadySeen: false, presentedProgress: 1
            ),
            "gợi ý hiện trong lúc màn giới thiệu còn phủ lên"
        )
    }

    func testThePlayerHintNeverReturnsOnceSeen() {
        XCTAssertFalse(
            OnboardingFlags.showsPlayerCloseHint(
                introFinished: true, alreadySeen: true, presentedProgress: 1
            ),
            "gợi ý hiện lại sau khi đã xem"
        )
    }

    func testThePlayerHintWaitsForTheCardToArrive() {
        XCTAssertFalse(
            OnboardingFlags.showsPlayerCloseHint(
                introFinished: true, alreadySeen: false, presentedProgress: 0.98
            ),
            "gợi ý hiện khi tấm thẻ còn đang bung"
        )
        XCTAssertTrue(
            OnboardingFlags.showsPlayerCloseHint(
                introFinished: true, alreadySeen: false, presentedProgress: 1
            )
        )
    }

    /// Ngưỡng đọc từ hằng số, không gõ lại 0,99 — nếu hằng số đổi thì test đi
    /// theo thay vì đỏ vì một lý do sai.
    func testThePlayerHintThresholdIsTheOneTheConstantNames() {
        XCTAssertFalse(
            OnboardingFlags.showsPlayerCloseHint(
                introFinished: true,
                alreadySeen: false,
                presentedProgress: OnboardingFlags.playerFullyOpen
            ),
            "ngưỡng dùng >= thay vì >"
        )
        XCTAssertTrue(
            OnboardingFlags.showsPlayerCloseHint(
                introFinished: true,
                alreadySeen: false,
                presentedProgress: OnboardingFlags.playerFullyOpen + 0.001
            )
        )
    }

    // MARK: - Gợi ý thanh tab

    func testTheTabBarHintWaitsForTheIntroToFinish() {
        XCTAssertFalse(
            OnboardingFlags.showsTabBarHint(
                introFinished: false, alreadySeen: false, isMinimised: true
            )
        )
    }

    func testTheTabBarHintNeverReturnsOnceSeen() {
        XCTAssertFalse(
            OnboardingFlags.showsTabBarHint(
                introFinished: true, alreadySeen: true, isMinimised: true
            )
        )
    }

    func testTheTabBarHintOnlyShowsOnceTheBarHasActuallyShrunk() {
        XCTAssertFalse(
            OnboardingFlags.showsTabBarHint(
                introFinished: true, alreadySeen: false, isMinimised: false
            )
        )
        XCTAssertTrue(
            OnboardingFlags.showsTabBarHint(
                introFinished: true, alreadySeen: false, isMinimised: true
            )
        )
    }

    // MARK: - Khoá lưu trữ

    /// Ba khoá phải khác nhau. Hai khoá trùng nhau nghĩa là xem một gợi ý tắt
    /// luôn gợi ý kia, và không có gì báo.
    func testTheThreeStorageKeysAreDistinct() {
        let keys = Set([
            OnboardingFlags.introFinishedKey,
            OnboardingFlags.playerCloseHintSeenKey,
            OnboardingFlags.tabBarHintSeenKey
        ])
        XCTAssertEqual(keys.count, 3)
    }
}
```

- [ ] **Step 2: Chạy để chắc nó đỏ**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EvenstarTests/OnboardingFlagsTests test 2>&1 | grep -E "error:|Executed"`

Expected: lỗi biên dịch, `cannot find 'OnboardingFlags' in scope`.

- [ ] **Step 3: Viết bản cài đặt nhỏ nhất**

Tạo `Evenstar/Evenstar/Features/Onboarding/OnboardingFlags.swift`:

```swift
import Foundation

/// Ba cờ của onboarding, và hai hàm quyết định đọc chúng.
///
/// Khoá giữ ở đây chứ không rải chuỗi vào view, cùng lý do
/// `AppLanguage.storageKey` và `AppTheme.storageKey` tồn tại: một chuỗi gõ hai
/// lần là hai chuỗi phải bằng nhau bằng niềm tin, và khi chúng lệch thì cờ ghi
/// vào một chỗ rồi đọc từ chỗ khác — im lặng.
///
/// Hai hàm dưới **thuần**, nhận đủ đầu vào qua tham số, không đọc
/// `UserDefaults` hay môi trường. Đó là điều kiện để kiểm được chúng, và repo
/// này đã trả giá để học điều ấy hai lần: xem `PlayerCard.morphNeedsFade` và
/// `PlayerCard.source(hasArtwork:loaded:)`.
enum OnboardingFlags {

    static let introFinishedKey = "onboardingIntroFinished"
    static let playerCloseHintSeenKey = "onboardingPlayerCloseHintSeen"
    static let tabBarHintSeenKey = "onboardingTabBarHintSeen"

    /// Trên mức này thì tấm thẻ coi như đã bung xong.
    ///
    /// **Đây phải là giá trị đang được *vẽ*, không phải giá trị trong `body`.**
    /// `expansion.progress` đọc trong `body` đã là 1 ngay khung đầu của một
    /// `withAnimation`, nên gác gợi ý vào nó sẽ làm nhãn hiện khi tấm thẻ còn
    /// bé — chưa bung xong đã bảo "vuốt xuống để đóng". `PlayerCloseHint` vì thế
    /// là một view `Animatable`, cùng khuôn `CardSurface` và `PresentedFloat`.
    static let playerFullyOpen: Double = 0.99

    /// Gợi ý "vuốt xuống để đóng" có được hiện không.
    static func showsPlayerCloseHint(
        introFinished: Bool,
        alreadySeen: Bool,
        presentedProgress: Double
    ) -> Bool {
        guard introFinished, !alreadySeen else { return false }
        return presentedProgress > playerFullyOpen
    }

    /// Gợi ý "thanh tab thu lại khi bạn cuộn" có được hiện không.
    ///
    /// Khác gợi ý trên ở bản chất: nó **giải thích một việc đã xảy ra**, không
    /// hướng dẫn một cử chỉ. Cuộn là phản xạ tự nhiên; thứ không tự hiểu được là
    /// kết quả. Nên nó gác vào `isMinimised` đã thành `true`, không gác vào một
    /// dấu hiệu nào trước đó.
    static func showsTabBarHint(
        introFinished: Bool,
        alreadySeen: Bool,
        isMinimised: Bool
    ) -> Bool {
        guard introFinished, !alreadySeen else { return false }
        return isMinimised
    }
}
```

- [ ] **Step 4: Chạy để chắc nó xanh**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EvenstarTests/OnboardingFlagsTests test 2>&1 | grep -E "error:|Executed"`

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Kiểm đột biến — ba rào, ba lần đỏ**

Sửa tạm rồi hoàn nguyên từng cái, mỗi lần chạy lại lệnh ở Step 4:

1. Bỏ `introFinished` khỏi `guard` của `showsPlayerCloseHint` → phải đỏ ở `testThePlayerHintWaitsForTheIntroToFinish`.
2. Bỏ `!alreadySeen` khỏi `guard` của `showsTabBarHint` → phải đỏ ở `testTheTabBarHintNeverReturnsOnceSeen`.
3. Đổi `>` thành `>=` ở `showsPlayerCloseHint` → phải đỏ ở `testThePlayerHintThresholdIsTheOneTheConstantNames`.

Rào nào không đỏ được là rào không có tác dụng — dừng và báo, đừng đi tiếp.

- [ ] **Step 6: Chạy toàn bộ suite**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "Executed 5[0-9][0-9]|TEST SUCCEEDED|TEST FAILED"`

Expected: `Executed 557 tests, with 6 tests skipped and 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Evenstar/Evenstar/Features/Onboarding/OnboardingFlags.swift Evenstar/EvenstarTests/OnboardingFlagsTests.swift
git commit -m "feat: OnboardingFlags — ba khoá lưu trữ và hai hàm quyết định thuần

Hai hàm nhận đủ đầu vào qua tham số, không đọc UserDefaults hay môi trường —
điều kiện để kiểm được chúng, theo khuôn morphNeedsFade và source(hasArtwork:loaded:).

Cách hỏng được canh là cách hỏng im lặng: gợi ý hiện lại sau khi đã xem, không bao
giờ hiện, hoặc hiện lúc màn giới thiệu còn phủ lên. Không cái nào làm crash.

Kiểm đột biến ba rào: bỏ introFinished, bỏ alreadySeen, đổi > thành >= — cả ba đỏ."
```

---

### Task 2: Hai hằng số chuyển động, và cái bẫy của test liệt kê

**Files:**
- Modify: `Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift`
- Test: `Evenstar/EvenstarTests/ReduceMotionTests.swift`

**Interfaces:**
- Consumes: `BottomBarStyle.reduceMotion` (đã có).
- Produces:
  - `BottomBarStyle.hint: Animation` — cú hiện/tan của nhãn gợi ý và của màn giới thiệu.
  - `BottomBarStyle.hintArrowTravel: CGFloat` — biên độ nhấp của mũi chỉ; **0** khi giảm chuyển động.

- [ ] **Step 1: Viết test đỏ**

Trong `Evenstar/EvenstarTests/ReduceMotionTests.swift`:

(a) Thêm `BottomBarStyle.hint` vào **cả hai** danh sách của `testTheAlreadyFlatCurvesAreUnchanged` — đó là test liệt kê các curve giống nhau ở hai nhánh, nơi `press`, `control`, `queueContentIn` đang nằm (khoảng dòng 119–140).

(b) Thêm một test mới ngay sau `testNeitherBranchScalesTheContentBehindThePlayer`:

```swift
    /// `hintArrowTravel` là một **khoảng cách**, không phải một curve — nên nó
    /// đi đường mà `recedeScale` và `pressedScale` đã đi: về 0 chứ không chạy
    /// phẳng hơn. Mũi chỉ của gợi ý nhấp nhẹ để mắt bắt được nó; khi giảm
    /// chuyển động thì nó đứng im, và nhãn vẫn đọc được vì chữ mới là thứ dạy.
    func testTheHintArrowStopsMovingWhenMotionIsReduced() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(BottomBarStyle.hintArrowTravel, 6)

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(BottomBarStyle.hintArrowTravel, 0)
    }
```

- [ ] **Step 2: Chạy để chắc nó đỏ**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EvenstarTests/ReduceMotionTests test 2>&1 | grep -E "error:|Executed"`

Expected: lỗi biên dịch, `type 'BottomBarStyle' has no member 'hint'`.

- [ ] **Step 3: Thêm hai hằng số**

Trong `BottomBarStyle.swift`, thêm ngay sau khối `press` (`pressFull`/`pressFlat`):

```swift
    /// Nhãn gợi ý onboarding hiện ra và tan đi, và màn giới thiệu tan khi bấm
    /// "Bắt đầu".
    ///
    /// Reduced: **không đổi**, và đó là chủ ý chứ không phải một chỗ sót. HIG
    /// cho phép giữ cú mờ dần — thứ phải bỏ là dịch chuyển, phóng to, xoay,
    /// nảy. Một nhãn mờ vào trong 0,22s không có cái nào trong bốn thứ ấy. Cái
    /// *có* dịch chuyển là mũi chỉ, và nó bị bỏ ở `hintArrowTravel` ngay dưới.
    @MainActor static var hint: Animation { reduceMotion ? hintFlat : hintFull }
    private static let hintFull = Animation.easeOut(duration: 0.22)
    private static let hintFlat = hintFull

    /// Mũi chỉ của gợi ý nhấp lên xuống bao nhiêu điểm.
    ///
    /// Reduced: **0**, không nhấp gì. Đây là một *khoảng cách* chứ không phải
    /// một curve, nên nó đi đường mà `recedeScale` và `pressedScale` đã đi: đưa
    /// biên độ về 0 làm cả biểu thức thành hằng số, và đường đi qua
    /// `.animation(_:value:)` không cần nhánh thứ hai.
    ///
    /// Nhãn vẫn đọc được khi mũi đứng im, vì **chữ** là thứ dạy — mũi chỉ chỉ để
    /// mắt bắt được nhãn ở góc màn hình.
    @MainActor static var hintArrowTravel: CGFloat {
        reduceMotion ? hintArrowTravelFlat : hintArrowTravelFull
    }
    private static let hintArrowTravelFull: CGFloat = 6
    private static let hintArrowTravelFlat: CGFloat = 0
```

- [ ] **Step 4: Sửa câu chú thích giờ đã sai ở `recedeScale`**

Doc của `recedeScale` có câu *"The only constant outside the `Animation` group that has to branch"*. Sau task này nó là câu thứ ba, không phải duy nhất. Sửa thành lời nói đúng số lượng, nêu cả `pressedScale` và `hintArrowTravel`. Một chú thích nói sai sẽ dẫn người sau đi lạc.

- [ ] **Step 5: Chạy để chắc nó xanh**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EvenstarTests/ReduceMotionTests test 2>&1 | grep -E "error:|Executed"`

Expected: `0 failures`.

- [ ] **Step 6: Kiểm đột biến**

Đổi `hintArrowTravelFlat` thành `6` → `testTheHintArrowStopsMovingWhenMotionIsReduced` phải đỏ. Hoàn nguyên.

Đổi `hintFlat` thành `Animation.easeOut(duration: 0.4)` → `testTheAlreadyFlatCurvesAreUnchanged` phải đỏ. Hoàn nguyên.

- [ ] **Step 7: Chạy toàn bộ suite và commit**

```bash
cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "Executed 5[0-9][0-9]|TEST SUCCEEDED|TEST FAILED"
cd .. && git add Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift Evenstar/EvenstarTests/ReduceMotionTests.swift
git commit -m "feat: hai hằng số chuyển động cho gợi ý onboarding

hint: cú mờ 0,22s, không đổi khi giảm chuyển động — HIG cho phép giữ cú mờ dần;
thứ phải bỏ là dịch chuyển, phóng to, xoay, nảy.

hintArrowTravel: biên độ nhấp của mũi chỉ, về 0 khi giảm chuyển động. Là một
khoảng cách chứ không phải curve, nên đi đường recedeScale và pressedScale đã đi.

Thêm cả hai vào ReduceMotionTests, vì test ở đó khẳng định TỪNG hằng số có tên và
không tự quét file — thêm hằng số mà quên test thì nhánh giảm chuyển động của nó
không có ai canh, và test vẫn xanh.

Sửa câu 'the only constant outside the Animation group that has to branch' ở
recedeScale: giờ là câu thứ ba, không phải duy nhất."
```

---

### Task 3: Màn giới thiệu, cổng ở tầng app, và chuỗi hai ngôn ngữ

**Files:**
- Create: `Evenstar/Evenstar/Features/Onboarding/OnboardingIntroView.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift:115-127`
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`
- Test: `Evenstar/EvenstarTests/OnboardingStringsTests.swift`

**Interfaces:**
- Consumes: `OnboardingFlags.introFinishedKey`, `BottomBarStyle.hint`, `AppLanguage` (`allCases`, `label`, `storageKey`, `resolvedBundle`, `resolvedLocale`), `ButtonStyle.prominentAction`.
- Produces: `OnboardingIntroView(onFinish: @escaping () -> Void)`.

- [ ] **Step 1: Viết test đỏ cho chuỗi hai ngôn ngữ**

Tạo `Evenstar/EvenstarTests/OnboardingStringsTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// Chuỗi của onboarding có thật trong **cả hai** ngôn ngữ.
///
/// `sourceLanguage` của `Localizable.xcstrings` là `vi`, nên một chuỗi mới xuất
/// hiện trong catalogue với bản tiếng Việt ngay khi build, và bản tiếng Anh thì
/// **không** — nó phải được điền tay. Bỏ sót thì bản tiếng Anh rơi về tiếng
/// Việt, và không có gì trong một bản build nói ra điều đó. Đây là cái bẫy
/// `developmentRegion` mà kế hoạch bản địa hoá đã ghi lại.
///
/// Theo khuôn `AppLanguageTests`: chọn ngôn ngữ qua `UserDefaults` rồi giải
/// chuỗi qua `AppLanguage.resolvedBundle`. **Bundle** mới là thứ chọn bảng
/// chuỗi; locale chỉ định dạng giá trị nội suy — xem doc của `resolvedBundle`.
final class OnboardingStringsTests: XCTestCase {

    private static let sources = [
        "Nhạc của bạn, trên máy của bạn.",
        "Bắt đầu",
        "Vuốt xuống để đóng",
        "Thanh tab thu lại khi bạn cuộn. Bấm để mở lại."
    ]

    private var saved: String??

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        if let saved, let value = saved {
            UserDefaults.standard.set(value, forKey: AppLanguage.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        }
        saved = nil
        super.tearDown()
    }

    private func resolve(_ source: String, as language: AppLanguage) -> String {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        return String(
            localized: String.LocalizationValue(source),
            bundle: AppLanguage.resolvedBundle,
            locale: AppLanguage.resolvedLocale
        )
    }

    /// Nguồn là tiếng Việt, nên phép thử là "bản tiếng Anh phải **khác** bản
    /// nguồn" — bằng nhau nghĩa là ô tiếng Anh trong catalogue còn trống.
    func testEveryOnboardingStringHasAnEnglishTranslation() {
        for source in Self.sources {
            XCTAssertNotEqual(
                resolve(source, as: .english), source,
                "\"\(source)\" chưa có bản dịch tiếng Anh trong Localizable.xcstrings"
            )
        }
    }

    /// Và bản tiếng Việt phải đúng là chuỗi nguồn — khác nghĩa là có ai đã sửa ô
    /// `vi`, và chỗ gọi trong mã giờ trỏ vào một khoá không tồn tại.
    func testEveryOnboardingStringStillResolvesInVietnamese() {
        for source in Self.sources {
            XCTAssertEqual(resolve(source, as: .vietnamese), source)
        }
    }
}
```

- [ ] **Step 2: Chạy để chắc nó đỏ**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EvenstarTests/OnboardingStringsTests test 2>&1 | grep -E "error:|XCTAssert|Executed"`

Expected: `testEveryOnboardingStringHasAnEnglishTranslation` đỏ — chưa có chuỗi nào trong catalogue.

- [ ] **Step 3: Thêm bốn chuỗi vào `Localizable.xcstrings`**

File là JSON. Thêm bốn khoá vào object `strings`, theo đúng hình dạng các khoá đang có, giữ thứ tự alphabet như file đang làm:

```json
"Bắt đầu" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Get started" } },
    "vi" : { "stringUnit" : { "state" : "translated", "value" : "Bắt đầu" } }
  }
},
"Nhạc của bạn, trên máy của bạn." : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Your music, on your own device." } },
    "vi" : { "stringUnit" : { "state" : "translated", "value" : "Nhạc của bạn, trên máy của bạn." } }
  }
},
"Thanh tab thu lại khi bạn cuộn. Bấm để mở lại." : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "The tab bar shrinks as you scroll. Tap to bring it back." } },
    "vi" : { "stringUnit" : { "state" : "translated", "value" : "Thanh tab thu lại khi bạn cuộn. Bấm để mở lại." } }
  }
},
"Vuốt xuống để đóng" : {
  "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Swipe down to close" } },
    "vi" : { "stringUnit" : { "state" : "translated", "value" : "Vuốt xuống để đóng" } }
  }
}
```

Kiểm JSON còn hợp lệ:

```bash
python3 -c "import json; json.load(open('Evenstar/Evenstar/Localizable.xcstrings')); print('JSON hợp lệ')"
```

- [ ] **Step 4: Viết `OnboardingIntroView`**

Tạo `Evenstar/Evenstar/Features/Onboarding/OnboardingIntroView.swift`:

```swift
import SwiftUI

/// Màn giới thiệu ở lần chạy đầu: một trang, một câu, một bộ chọn ngôn ngữ, một
/// nút.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO CHỈ MỘT TRANG, VÀ VÌ SAO KHÔNG DẠY CỬ CHỈ Ở ĐÂY
/// ─────────────────────────────────────────────────────────────────────────
/// Các cử chỉ đáng dạy — vuốt player xuống để đóng, thanh tab thu lại khi cuộn —
/// **chỉ tồn tại khi đã có nhạc**. Ở lần chạy đầu thư viện rỗng, nên dạy chúng
/// ngay đây là dạy thứ người dùng không thể thử, và đó là cách nhanh nhất để
/// onboarding bị bỏ qua. Chúng được dạy sau, đúng lúc dùng được, bởi
/// `PlayerCloseHint` và `TabBarMinimiseHint`.
///
/// Nên màn này chỉ còn hai việc: nói app là gì, và cho chọn ngôn ngữ.
///
/// ─────────────────────────────────────────────────────────────────────────
/// BỘ CHỌN NGÔN NGỮ DÙNG LẠI `AppLanguage`, KHÔNG DỰNG CƠ CHẾ THỨ HAI
/// ─────────────────────────────────────────────────────────────────────────
/// Ghi thẳng vào `AppLanguage.storageKey`, cùng khoá mà Cài đặt ghi. Ba nhánh
/// **tự gọi tên mình** theo chú thích của chính kiểu ấy: ai đang có app ở một
/// ngôn ngữ họ không đọc được vẫn phải tìm được ngôn ngữ của mình trong danh
/// sách.
///
/// Lựa chọn ghi **ngay khi bấm**, không đợi "Bắt đầu" — nên nó vẫn giữ nếu app
/// bị kill ở màn này. Cờ hoàn tất thì chỉ ghi khi bấm "Bắt đầu", nên ai bị kill
/// giữa màn giới thiệu sẽ thấy lại nó, đã chọn sẵn ngôn ngữ họ vừa chọn.
///
/// ─────────────────────────────────────────────────────────────────────────
/// KHÔNG CÓ NÚT "BỎ QUA"
/// ─────────────────────────────────────────────────────────────────────────
/// Một trang, một nút. Thêm đường thoát thứ hai là thêm một trạng thái để sai,
/// cho một màn hình mà đường thoát duy nhất đã là một cú bấm.
struct OnboardingIntroView: View {
    let onFinish: () -> Void

    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    var body: some View {
        ZStack {
            // Đục hẳn, và ăn chạm. `RootView` chạy phía sau màn này để làm nóng
            // — xem `EvenstarApp.body` — nên nó phải không nhận được cú chạm
            // nào. `contentShape` ở dưới là vế thứ hai của cùng một việc.
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // `verbatim`: tên app không dịch, và một khoá "Evenstar" trong
                // String Catalog là một khoá chết ngay từ lúc sinh ra.
                Text(verbatim: "Evenstar")
                    .font(.largeTitle.weight(.bold))

                Text("Nhạc của bạn, trên máy của bạn.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { option in
                        Button {
                            language = option
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                if language == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if option != AppLanguage.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button("Bắt đầu") {
                    withAnimation(BottomBarStyle.hint) { onFinish() }
                }
                .buttonStyle(.prominentAction)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        // Vế thứ hai của "không cho chạm xuyên qua": nền đục vẽ ra một hình,
        // `contentShape` làm hình ấy ăn chạm trên cả những chỗ `Spacer` chiếm.
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 5: Gắn cổng vào `EvenstarApp`**

Trong `Evenstar/Evenstar/App/EvenstarApp.swift`, thêm vào danh sách thuộc tính, ngay trên `private let remoteCommands`:

```swift
    /// Người dùng đã qua màn giới thiệu chưa.
    ///
    /// Đọc ở **đây** chứ không trong `RootView`, và đó là ràng buộc chịu lực
    /// chứ không phải sở thích: một cú đọc trong `RootView.body` dựng lại
    /// `TabView` cùng cả năm tab, và đó đúng là thứ `PlayerExpansion` cùng
    /// `FloatOverPlayer` phải tránh bằng cách đọc giá trị bên trong thân
    /// modifier của chính chúng. Ở đây nó đổi đúng một lần trong đời app.
    @AppStorage(OnboardingFlags.introFinishedKey) private var introFinished = false
```

Thay thân `WindowGroup` (dòng 116–125) bằng:

```swift
        WindowGroup {
            // **`RootView` được gắn ngay từ đầu; màn giới thiệu phủ lên trên.**
            //
            // Không phải thay thế, và lý do là hai việc `RootView` làm ở 500ms
            // đầu: lớp làm nóng trả trước hoá đơn vẽ-lần-đầu của chrome player,
            // và `LibraryStore` được seed đồng bộ trong `init` để khung đầu
            // không nháy màn hình rỗng. Thay `RootView` bằng màn giới thiệu sẽ
            // dời cả hai sang *sau* lúc người dùng bấm "Bắt đầu" — tức rơi đúng
            // vào lúc họ bắt đầu dùng app. Phủ lên thì `RootView` làm nóng trong
            // lúc người dùng đang đọc.
            ZStack {
                RootView()
                    // Không có nó thì VoiceOver đọc xuyên qua màn giới thiệu và
                    // đọc ra cả một thư viện người dùng chưa nhìn thấy.
                    .accessibilityHidden(!introFinished)
                if !introFinished {
                    OnboardingIntroView(onFinish: { introFinished = true })
                }
            }
            .environment(library)
            .environment(importService)
            .environment(playback)
            .environment(driveLibrary)
            .environment(jamendoLibrary)
            .environment(libraryStore)
            .environment(searchResults)
        }
```

- [ ] **Step 6: Chạy test, rồi kiểm bằng mắt**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO -only-testing:EvenstarTests/OnboardingStringsTests test 2>&1 | grep -E "error:|Executed"`

Expected: `0 failures`.

Rồi chạy app trên simulator sạch (xoá app trước) và kiểm bốn thứ:
1. Màn giới thiệu hiện ra ở lần chạy đầu.
2. Chọn "English" → chữ trên chính màn ấy đổi sang tiếng Anh ngay.
3. Bấm "Bắt đầu" → màn giới thiệu tan, vào app.
4. Kill app rồi mở lại → **không** thấy màn giới thiệu nữa.

- [ ] **Step 7: Chạy toàn bộ suite và commit**

```bash
cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "Executed 5[0-9][0-9]|TEST SUCCEEDED|TEST FAILED"
cd .. && git add Evenstar/Evenstar/Features/Onboarding/OnboardingIntroView.swift Evenstar/Evenstar/App/EvenstarApp.swift Evenstar/Evenstar/Localizable.xcstrings Evenstar/EvenstarTests/OnboardingStringsTests.swift
git commit -m "feat: màn giới thiệu một trang, và cổng ở tầng app

RootView vẫn gắn ngay từ đầu và màn giới thiệu phủ lên trên, chứ không thay thế:
RootView làm hai việc ở 500ms đầu — lớp làm nóng chrome player, và cú seed
LibraryStore đồng bộ — và thay nó sẽ dời cả hai sang sau lúc bấm Bắt đầu, tức rơi
đúng vào lúc người dùng bắt đầu dùng app.

Cờ đọc ở EvenstarApp, không ở RootView.body: một cú đọc ở đó dựng lại TabView
cùng năm tab, đúng thứ PlayerExpansion và FloatOverPlayer phải tránh.

Bộ chọn ngôn ngữ ghi thẳng vào AppLanguage.storageKey, không dựng cơ chế thứ hai.
Ghi ngay khi bấm nên vẫn giữ nếu app bị kill ở màn này; cờ hoàn tất chỉ ghi khi
bấm Bắt đầu.

Bốn chuỗi vào Localizable.xcstrings cả vi và en, kèm test canh rằng ô tiếng Anh
không để trống — sourceLanguage là vi nên bỏ sót thì bản tiếng Anh rơi về tiếng
Việt và không có gì trong một bản build nói ra."
```

---

### Task 4: Nhãn gợi ý dùng chung, và gợi ý đóng player

**Files:**
- Create: `Evenstar/Evenstar/Features/Onboarding/OnboardingHint.swift`
- Create: `Evenstar/Evenstar/Features/Onboarding/PlayerCloseHint.swift`
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift:1653,1655`
- Modify: `Evenstar/Evenstar/App/RootView.swift:361`

**Interfaces:**
- Consumes: `OnboardingFlags.showsPlayerCloseHint(introFinished:alreadySeen:presentedProgress:)`, `OnboardingFlags.playerCloseHintSeenKey`, `OnboardingFlags.introFinishedKey`, `BottomBarStyle.hint`, `BottomBarStyle.hintArrowTravel`, `PlayerExpansion`.
- Produces:
  - `OnboardingHint(text: LocalizedStringKey, arrow: OnboardingHint.Arrow)`, với `enum Arrow { case down, up }`
  - `PlayerCloseHint(expansion: PlayerExpansion)`
  - `PlayerCard.grabberTopGap: CGFloat`, `PlayerCard.grabberHeight: CGFloat` — đổi từ `private static` sang `static`

- [ ] **Step 1: Nâng hai hằng số grabber**

Trong `PlayerCard.swift` dòng 1653, đổi

```swift
    private static let grabberTopGap: CGFloat = 8
```

thành

```swift
    /// Nội bộ chứ không `private`: `PlayerCloseHint` định vị theo grabber và
    /// phải đọc con số này thay vì gõ lại. Gõ lại là dựng hai con số phải bằng
    /// nhau bằng niềm tin — đúng loại lỗi mà chú thích của `artworkSide` và
    /// `queueThumbCentre` đã ghi lại là đã hỏng một lần ở file này.
    static let grabberTopGap: CGFloat = 8
```

Và ở dòng 1655 bỏ `private` khỏi `grabberHeight`, **giữ nguyên** chú thích đang có của nó.

**Không đổi gì khác trong file này.**

- [ ] **Step 2: Viết `OnboardingHint`**

Tạo `Evenstar/Evenstar/Features/Onboarding/OnboardingHint.swift`:

```swift
import SwiftUI

/// Nhãn gợi ý onboarding: một mũi chỉ, một câu, nền mờ.
///
/// **Không chắn chạm** — `allowsHitTesting(false)` đặt ở chỗ gọi, vì chỗ gọi là
/// nơi biết nó nằm trên cái gì. Người dùng vẫn dùng được app trong lúc nhãn còn
/// đó, và đó là toàn bộ lý do hình thức này được chọn thay cho một lớp tối có
/// nút "Đã hiểu": lớp tối buộc đọc, nhãn nổi thì không chặn đường ai.
///
/// Mũi chỉ nhấp nhẹ để mắt bắt được nhãn ở góc màn hình. Biên độ đọc từ
/// `BottomBarStyle.hintArrowTravel`, về **0** khi giảm chuyển động — **chữ** mới
/// là thứ dạy, mũi chỉ chỉ để bị nhìn thấy.
struct OnboardingHint: View {
    enum Arrow {
        case down
        case up

        var symbol: String {
            switch self {
            case .down: "arrow.down"
            case .up: "arrow.up"
            }
        }

        /// Mũi nhấp về phía nó đang chỉ.
        var sign: CGFloat {
            switch self {
            case .down: 1
            case .up: -1
            }
        }
    }

    let text: LocalizedStringKey
    let arrow: Arrow

    @State private var nudged = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: arrow.symbol)
                .font(.footnote.weight(.semibold))
                .offset(y: nudged ? BottomBarStyle.hintArrowTravel * arrow.sign : 0)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: nudged
                )
            Text(text)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .task { nudged = true }
    }
}
```

- [ ] **Step 3: Viết `PlayerCloseHint`**

Tạo `Evenstar/Evenstar/Features/Onboarding/PlayerCloseHint.swift`:

```swift
import SwiftUI

/// Gợi ý "vuốt xuống để đóng", hiện một lần khi player mở hết lần đầu.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO NÓ Ở `RootView` MÀ KHÔNG Ở `PlayerCard`
/// ─────────────────────────────────────────────────────────────────────────
/// Player mở hết thì tràn màn hình, nên "ngay dưới grabber" là một khoảng tính
/// được từ safe area đỉnh — không cần ở trong tấm thẻ để biết chỗ. Đổi lại là
/// 3.000 dòng của `PlayerCard` không phải mở ra, và một chỗ nữa không thể lỡ tay
/// làm chậm.
///
/// Con số đọc từ `PlayerCard.grabberTopGap` và `PlayerCard.grabberHeight`, không
/// gõ lại.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO HAI TẦNG, VÀ VÌ SAO TẦNG TRONG LÀ `Animatable`
/// ─────────────────────────────────────────────────────────────────────────
/// Tầng ngoài đọc `expansion.progress` **bên trong thân của chính nó**, không ở
/// chỗ gọi — cùng lý do `FloatOverPlayer` làm thế: cú kéo tay ghi giá trị ấy mỗi
/// khung, và đọc nó trong `RootView.body` sẽ dựng lại `TabView` cùng năm tab.
///
/// Tầng trong là `Animatable` vì `expansion.progress` đọc trong `body` **đã là 1
/// ngay khung đầu** của một `withAnimation` — `settled` nhảy thẳng tới đích. Gác
/// gợi ý vào nó sẽ làm nhãn hiện khi tấm thẻ còn bé: chưa bung xong đã bảo "vuốt
/// xuống để đóng". Cùng khuôn `CardSurface` và `PresentedFloat`, cả hai sinh ra
/// từ đúng cái bẫy này.
///
/// `Animatable` trên một view **lá** không phải cách mà `b8a94d6` làm rồi
/// `b14ad5d` hoàn nguyên: ở đó nó bắt cả `PlayerCard.body` chạy lại mỗi khung;
/// ở đây chỉ thân của chính kiểu này chạy lại.
struct PlayerCloseHint: View {
    let expansion: PlayerExpansion

    @AppStorage(OnboardingFlags.introFinishedKey) private var introFinished = false
    @AppStorage(OnboardingFlags.playerCloseHintSeenKey) private var seen = false

    var body: some View {
        PresentedPlayerCloseHint(
            progress: expansion.progress,
            introFinished: introFinished,
            seen: seen,
            onShown: { seen = true }
        )
        .animation(expansion.animation, value: expansion.progress)
    }
}

/// Đọc giá trị đang được **vẽ**. Xem `PlayerCloseHint`.
private struct PresentedPlayerCloseHint: View, Animatable {
    var progress: Double
    let introFinished: Bool
    let seen: Bool
    let onShown: () -> Void

    /// Nhãn tự tắt sau 6 giây kể cả khi người dùng không làm gì.
    @State private var expired = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var shows: Bool {
        guard !expired else { return false }
        return OnboardingFlags.showsPlayerCloseHint(
            introFinished: introFinished,
            alreadySeen: seen,
            presentedProgress: progress
        )
    }

    var body: some View {
        VStack {
            if shows {
                OnboardingHint(text: "Vuốt xuống để đóng", arrow: .down)
                    // Ghi cờ ngay lúc hiện, không lúc tắt. Ai vuốt ngay lập tức
                    // thì coi như chưa đọc — nhưng đúng ca ấy họ *đã làm được cử
                    // chỉ*, nên không còn gì để dạy. Đổi lại: không phải lo cú
                    // ghi bị mất khi app bị kill giữa lúc nhãn còn hiện.
                    //
                    // Đồng hồ 6 giây gắn cùng `.task` nên nó bị huỷ khi nhãn
                    // biến mất — người dùng vuốt xong thì nó không nổ muộn.
                    .task {
                        onShown()
                        try? await Task.sleep(for: .seconds(6))
                        expired = true
                    }
                    .transition(.opacity)
            }
            Spacer()
        }
        // Ngay dưới grabber. Con số từ `PlayerCard`, không gõ lại.
        .padding(.top, PlayerCard.grabberTopGap + PlayerCard.grabberHeight + 12)
        .allowsHitTesting(false)
        .animation(BottomBarStyle.hint, value: shows)
    }
}
```

- [ ] **Step 4: Gắn vào `RootView`**

Trong `Evenstar/Evenstar/App/RootView.swift`, ngay sau dòng 361 (`.animation(BottomBarStyle.morph, value: isMinimisedActive)`) và **trước** dấu `}` đóng `ZStack` ở dòng 362, thêm:

```swift
            // Gợi ý onboarding, trên tất cả. `RootView.body` chỉ dựng ra chúng —
            // mỗi view tự đọc cờ và tự đọc `expansion.progress` bên trong thân
            // của chính nó, cùng lý do `FloatOverPlayer` làm thế.
            PlayerCloseHint(expansion: expansion)
                .zIndex(2)
```

- [ ] **Step 5: Chạy toàn bộ suite**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "Executed 5[0-9][0-9]|TEST SUCCEEDED|TEST FAILED|error:"`

Expected: `0 failures`. Nếu chỉ `PlayerCardCommitCostControlTests` đỏ, chạy lại một lần trước khi kết luận.

- [ ] **Step 6: Kiểm bằng mắt**

Xoá app trên simulator, chạy lại, nhập một bài, và kiểm năm thứ:
1. Qua màn giới thiệu → **chưa** thấy nhãn nào.
2. Mở player → nhãn "Vuốt xuống để đóng" hiện ra **sau khi** tấm thẻ đã bung xong, không phải lúc nó còn bé.
3. Vuốt xuống → nhãn tan cùng cú thu nhỏ.
4. Mở player lại → **không** thấy nhãn nữa.
5. Bật Cài đặt → Trợ năng → Giảm chuyển động, xoá app, làm lại: nhãn vẫn hiện và đọc được, mũi chỉ **đứng im**.

- [ ] **Step 7: Commit**

```bash
git add Evenstar/Evenstar/Features/Onboarding/OnboardingHint.swift Evenstar/Evenstar/Features/Onboarding/PlayerCloseHint.swift Evenstar/Evenstar/Features/Player/PlayerCard.swift Evenstar/Evenstar/App/RootView.swift
git commit -m "feat: gợi ý 'vuốt xuống để đóng', hiện một lần khi player mở hết lần đầu

Ở RootView chứ không trong PlayerCard: player mở hết thì tràn màn hình nên 'ngay
dưới grabber' là một khoảng tính được từ safe area đỉnh. Đổi lại là 3.000 dòng
không phải mở ra. Con số đọc từ PlayerCard.grabberTopGap và grabberHeight — hai
hằng số nâng từ private lên nội bộ — chứ không gõ lại.

Tầng trong là Animatable và đọc giá trị đang được VẼ. expansion.progress đọc trong
body đã là 1 ngay khung đầu của một withAnimation, nên gác vào nó sẽ làm nhãn hiện
khi tấm thẻ còn bé. Cùng khuôn CardSurface và PresentedFloat, cả hai sinh ra từ
đúng cái bẫy này.

Ghi cờ lúc hiện chứ không lúc tắt: ai vuốt ngay lập tức thì đã làm được cử chỉ,
nên không còn gì để dạy — và không phải lo cú ghi mất khi app bị kill."
```

---

### Task 5: Gợi ý thanh tab thu lại

**Files:**
- Create: `Evenstar/Evenstar/Features/Onboarding/TabBarMinimiseHint.swift`
- Modify: `Evenstar/Evenstar/App/RootView.swift` — thêm ngay sau `PlayerCloseHint`

**Interfaces:**
- Consumes: `OnboardingHint`, `OnboardingFlags.showsTabBarHint(introFinished:alreadySeen:isMinimised:)`, `OnboardingFlags.tabBarHintSeenKey`, `OnboardingFlags.introFinishedKey`, `BottomBarStyle.hint`, `BottomBarMetrics.clearanceTabBarOnly(bottomSafeAreaInset:)`, `EnvironmentValues.bottomSafeAreaInset`.
- Produces: `TabBarMinimiseHint(isMinimised: Bool)`

- [ ] **Step 1: Viết view**

Tạo `Evenstar/Evenstar/Features/Onboarding/TabBarMinimiseHint.swift`:

```swift
import SwiftUI

/// Gợi ý "thanh tab thu lại khi bạn cuộn", hiện một lần sau khi nó thu lần đầu.
///
/// **Nó không dạy một cử chỉ, nó giải thích một việc đã xảy ra.** Cuộn danh sách
/// là phản xạ tự nhiên — người dùng vẫn cuộn dù không ai bảo. Thứ không tự hiểu
/// được là **kết quả**: thanh tab tự thu lại, và lần đầu nó xảy ra thì dễ bị đọc
/// là lỗi, hoặc người dùng không biết bấm để mở lại.
///
/// Vì thế nó gác vào `isMinimised` đã thành `true`, không gác vào một dấu hiệu
/// nào trước đó. Đây là chỗ khác nhau duy nhất về bản chất giữa hai gợi ý, và nó
/// quyết định thời điểm.
///
/// Không `Animatable` như `PlayerCloseHint`: `isMinimised` là một `Bool`, không
/// có giá trị trung gian nào để đọc sai.
struct TabBarMinimiseHint: View {
    let isMinimised: Bool

    @AppStorage(OnboardingFlags.introFinishedKey) private var introFinished = false
    @AppStorage(OnboardingFlags.tabBarHintSeenKey) private var seen = false
    @State private var expired = false
    @Environment(\.bottomSafeAreaInset) private var bottomSafeAreaInset

    private var shows: Bool {
        guard !expired else { return false }
        return OnboardingFlags.showsTabBarHint(
            introFinished: introFinished,
            alreadySeen: seen,
            isMinimised: isMinimised
        )
    }

    var body: some View {
        VStack {
            Spacer()
            if shows {
                OnboardingHint(
                    text: "Thanh tab thu lại khi bạn cuộn. Bấm để mở lại.",
                    arrow: .down
                )
                .padding(.horizontal, 24)
                // Ghi cờ ngay lúc hiện — cùng lý lẽ ở `PlayerCloseHint`: ai bấm
                // mở lại ngay lập tức thì đã tìm được nút, nên không còn gì để
                // giải thích.
                .task {
                    seen = true
                    try? await Task.sleep(for: .seconds(6))
                    expired = true
                }
                .transition(.opacity)
            }
        }
        // Ngay trên thanh tab. Khoảng cách đọc từ `BottomBarMetrics`, chỗ duy
        // nhất trong app biết thanh tab cao bao nhiêu và cách mép dưới bao xa —
        // xem doc của `clearanceTabBarOnly(bottomSafeAreaInset:)`.
        .padding(.bottom, BottomBarMetrics.clearanceTabBarOnly(
            bottomSafeAreaInset: bottomSafeAreaInset
        ) + 12)
        .allowsHitTesting(false)
        .animation(BottomBarStyle.hint, value: shows)
    }
}
```

- [ ] **Step 2: Gắn vào `RootView`**

Ngay sau khối `PlayerCloseHint(expansion: expansion).zIndex(2)` đã thêm ở Task 4:

```swift
            TabBarMinimiseHint(isMinimised: isMinimisedActive)
                .zIndex(2)
```

`isMinimisedActive` là giá trị `RootView.body` **đã đọc** để truyền cho `FloatingTabBar` và `PlayerCard`, nên không thêm cú đọc mới nào.

- [ ] **Step 3: Chạy toàn bộ suite**

Run: `cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "Executed 5[0-9][0-9]|TEST SUCCEEDED|TEST FAILED|error:"`

Expected: `0 failures`.

- [ ] **Step 4: Kiểm bằng mắt**

Xoá app, chạy lại, nhập vài bài để danh sách đủ dài cuộn được, rồi kiểm:
1. Cuộn danh sách → thanh tab thu lại → nhãn hiện ra **sau đó**, ngay trên thanh tab.
2. Bấm nút mở lại → nhãn tan.
3. Cuộn lại → thanh tab vẫn thu, **không** thấy nhãn nữa.
4. Nhãn **không** che nút nào — bấm xuyên qua chỗ nhãn đang nằm, cú bấm phải tới được thứ phía dưới.

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/Onboarding/TabBarMinimiseHint.swift Evenstar/Evenstar/App/RootView.swift
git commit -m "feat: gợi ý 'thanh tab thu lại khi bạn cuộn'

Nó không dạy một cử chỉ, nó giải thích một việc đã xảy ra. Cuộn là phản xạ tự
nhiên; thứ không tự hiểu được là kết quả — thanh tab tự thu, và lần đầu thì dễ bị
đọc là lỗi. Nên nó gác vào isMinimised đã thành true, không gác vào dấu hiệu nào
trước đó. Đó là chỗ khác nhau về bản chất giữa hai gợi ý.

Không Animatable như PlayerCloseHint: isMinimised là một Bool, không có giá trị
trung gian để đọc sai.

Khoảng cách tới thanh tab đọc từ BottomBarMetrics, chỗ duy nhất trong app biết
thanh tab cao bao nhiêu và cách mép dưới bao xa.

isMinimisedActive là giá trị RootView.body đã đọc để truyền cho FloatingTabBar và
PlayerCard, nên không thêm cú đọc mới nào."
```

---

### Task 6: Dòng đặt lại onboarding, chỉ trong bản Debug

**Files:**
- Modify: `Evenstar/Evenstar/Features/Account/SettingsView.swift` — thêm nút vào `Section` `#if DEBUG` đang có (khối bắt đầu ở dòng 119)

**Interfaces:**
- Consumes: `OnboardingFlags.introFinishedKey`, `OnboardingFlags.playerCloseHintSeenKey`, `OnboardingFlags.tabBarHintSeenKey`.
- Produces: không gì.

- [ ] **Step 1: Thêm nút**

Trong `SettingsView.swift`, bên trong `Section` đã bọc `#if DEBUG`, thêm sau bốn nút bản thử đang có:

```swift
                // `verbatim` như bốn nút trên, cùng lý do đã ghi ở đầu mục:
                // `Text("…")` là `LocalizedStringKey` nên chuỗi sẽ bị trích vào
                // `Localizable.xcstrings` rồi nằm lại thành khoá chết khi mục
                // Debug này đi.
                //
                // Xoá cả ba khoá cùng lúc, không phải ba nút: onboarding là một
                // trạng thái, và đặt lại một nửa nó cho ra một tình huống không
                // người dùng nào gặp được.
                Button {
                    UserDefaults.standard.removeObject(forKey: OnboardingFlags.introFinishedKey)
                    UserDefaults.standard.removeObject(forKey: OnboardingFlags.playerCloseHintSeenKey)
                    UserDefaults.standard.removeObject(forKey: OnboardingFlags.tabBarHintSeenKey)
                } label: {
                    Text(verbatim: "Đặt lại onboarding")
                }
```

**Không** thêm dòng nào tương tự vào bản phát hành. Một màn giới thiệu một trang thì xem lại chẳng để làm gì, và mỗi lối vào là một trạng thái phải bảo trì.

- [ ] **Step 2: Kiểm bằng mắt**

Chạy bản Debug: Cài đặt → mục "Bản thử" → "Đặt lại onboarding" → kill app → mở lại → màn giới thiệu hiện lại, và cả hai gợi ý hiện lại lần nữa.

- [ ] **Step 3: Chạy toàn bộ suite và commit**

```bash
cd Evenstar && xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test 2>&1 | grep -E "Executed 5[0-9][0-9]|TEST SUCCEEDED|TEST FAILED"
cd .. && git add Evenstar/Evenstar/Features/Account/SettingsView.swift
git commit -m "feat: đặt lại onboarding, chỉ trong bản Debug

Không có nó thì mỗi lần xem lại onboarding phải xoá app và nhập lại nhạc. Bọc
#if DEBUG theo tiền lệ Đợt C1 với bốn bản thử, nên nó không có mặt trong bản phát
hành và không phải một tính năng phải bảo trì.

Xoá cả ba khoá cùng lúc chứ không ba nút: onboarding là một trạng thái, và đặt lại
một nửa nó cho ra một tình huống không người dùng nào gặp được."
```

---

## Sau khi xong

Chạy tay trên **thiết bị thật, bản Release** — `./device.sh --release` — và kiểm ba thứ mà simulator không nói được:

1. Cú tan của màn giới thiệu có mượt không, hay nó rơi vào đúng lúc `RootView` đang làm nóng.
2. Nhãn gợi ý player có hiện **sau khi** tấm thẻ bung xong không. Đây là chỗ dễ sai nhất, và là chỗ `presentedProgress` tồn tại để giữ.
3. Bật Giảm chuyển động và làm lại cả hai: không có gì dịch chuyển, nhãn vẫn đọc được.

Nếu cú tan của màn giới thiệu vấp, **đừng đoán** — chụp Color Offscreen-Rendered Yellow và đo, theo đúng bài học ghi ở [`2026-08-19-e2-trace.md`](../audits/2026-08-19-e2-trace.md).
