# Evenstar — thực thi lộ trình audit kiến trúc

> **Cho người thực thi:** mỗi việc là một checkbox với tiêu chí *Xong khi* kiểm được bằng lệnh. Làm xong một đợt thì chạy test rồi mới sang đợt sau.

**Nguồn:** audit kiến trúc ngày 2026-08-16 (81/100). Kế hoạch này đóng 9 trong 10 mục của lộ trình; mục 10 (tách `PlayerCard`) bị **chặn bởi số đo** và không nằm ở đây.

**Kỳ vọng:** 81 → 91. Con số là ước lượng, không phải số đo — thứ đo được chỉ có hitch ở Đợt A.

---

## Ba ràng buộc, và một cái mới

1. **Không sửa `.pbxproj` hay `.xcscheme` từ agent.** Ràng buộc cũ, vẫn giữ.
2. **Chỉ đánh giá chuyển động trên bản Release** — `./device.sh --release`.
3. **Test phải xanh sau mỗi việc:**
   `xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
4. **Mới:** ba việc trong lộ trình gốc cần đổi build setting, tức cần `.pbxproj`. Cách xử lý nằm ở Đợt D và Đợt E — **không** agent nào được đụng vào file ấy, kể cả khi thấy đường sửa hiển nhiên.

**Ngôn ngữ chú thích:** theo file đang sửa. `BottomBarStyle`, `PlayerCard`, `ReorderableStack` chú thích tiếng Việt; `LibraryStore`, `SystemVolumeSlider`, `EvenstarApp` tiếng Anh. Không đồng bộ hoá — khớp hàng xóm.

---

## Đợt A — Bốn việc rẻ, không rủi ro

Tổng dưới hai giờ. Đóng vấn đề Critical nặng nhất và ba Warning.

- [x] **A1 — Chốt bản C: gỡ ba cái bóng khỏi thanh tab**

  Working tree đang có thay đổi thử nghiệm với chú thích `// A/B: tam thoi bo bong` ở [FloatingTabBar.swift](../../../Evenstar/Evenstar/Features/Shared/FloatingTabBar.swift) dòng 375, 455, 567. **Hoàn tác nó trước** (`git checkout`), rồi làm lại tử tế.

  Ba chỗ bỏ `.floatingBarShadow()`, mỗi chỗ thay bằng một chú thích nêu số đo. Đo trên thiết bị, cùng cửa sổ cuộn trên danh sách Bài hát:

  | Bản | hitch (ms/s) | commit | render | GPU |
  |---|---|---|---|---|
  | Material + bóng | 87.6 | 12.1 | 33.3 | 41.8 |
  | Màu đặc + bóng | 6.9 | 2.0 | 2.9 | 1.4 |
  | Material, không bóng | **0.0** | 0.0 | 0.0 | 0.0 |

  Cơ chế: bóng SwiftUI đè lên `Material` buộc rasterize ngoài màn hình mỗi khung, vì hình bóng phải suy ra từ nội dung đã blur nên không cache được. Giữ Material và bỏ bóng là bản tốt nhất — nó cũng là bản giữ được vẻ ngoài.

  `BottomBarStyle.floatingShadow` và `floatingBarShadow()` **vẫn giữ**: `PlayerCard:1176` còn dùng, và Đợt E sẽ quyết định số phận chỗ ấy bằng số đo chứ không bằng suy luận.

  Sửa luôn chú thích ở [BottomBarStyle.swift:290-302](../../../Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift#L290-L302): nó đã cảnh báo đúng — *"nếu bar hay player rớt khung, đây là thứ đầu tiên cần gỡ"* — nên giờ ghi thêm rằng cảnh báo ấy đã thành sự thật, đã đo, và thanh tab đã gỡ.

  *Xong khi:* `grep -c floatingBarShadow FloatingTabBar.swift` trả về `0`, và chú thích ở `BottomBarStyle` nêu con số 87.6 → 0.0.

- [x] **A2 — `displayScale` thay `UIScreen.main.scale`**

  Ba chỗ: [ArtworkThumbnail.swift:73](../../../Evenstar/Evenstar/Features/Library/ArtworkThumbnail.swift#L73), [JamendoResultRow.swift:209](../../../Evenstar/Evenstar/Features/Jamendo/JamendoResultRow.swift#L209), [PlayerCard.swift:2401](../../../Evenstar/Evenstar/Features/Player/PlayerCard.swift#L2401).

  `UIScreen.main` trả về màn hình *chính*, không phải màn hình đang vẽ. Sai trên màn hình ngoài và dưới Stage Manager, và Apple đã đánh dấu là sẽ bỏ.

  ~~`@Environment(\.displayScale)` là API đúng. Lưu ý ở `ArtworkThumbnail`: `pixels(for:)` hiện là `static func` được gọi từ hai chỗ (seed và `.task`), nên nó phải nhận scale làm tham số.~~

  **Chỉ định trên đã sai và bản thi công không theo nó.** `@Environment` rỗng trong `init`, mà cả hai thumbnail đều seed cache từ `init`. Đo được: `UITraitCollection.current.displayScale` đọc đúng màn đang vẽ trong `init` (2.0 khi ép trait, màn chính 3x) nhưng **trả về 3.0 trong `.task`** — nên giữ một `static func` đọc trait ở cả hai chỗ sẽ làm seed và task hỏi cache hai câu khác nhau, đúng trên loại màn hình mà thay đổi này sinh ra để phục vụ. Bản đã làm: tính một lần trong `init`, cất vào `private let maxPixel`. `PlayerCard` không có ràng buộc ấy nên đọc thẳng `@Environment`.

  *Xong khi:* `grep -rn "UIScreen.main" Evenstar/Evenstar` trả về rỗng.

- [x] **A3 — Sửa bug target chết câm, xoá mã chết trong `SystemVolumeSlider`**

  Hai việc trong một file, làm chung vì cùng chạm một vùng.

  **Bug:** [SystemVolumeSlider.swift:214-219](../../../Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift#L214-L219) gắn target vào `UISlider` rồi bật `isObservingSliderTouches = true` vĩnh viễn. Doc comment của chính lớp ấy (dòng 179-183) nói `MPVolumeView` dựng slider **lười** và dựng lại khi hierarchy đổi. Nếu xảy ra, cờ vẫn `true` còn slider mới không có target — haptic và cú phồng chết câm, không lỗi, không log.

  Thay `Bool` bằng `private weak var observedSlider: UISlider?`, so sánh `!==`, gỡ target cũ trước khi gắn mới.

  **Mã chết:** `static let trackImage` (dòng 153-169) không được tham chiếu ở đâu — đã grep cả test target. Doc comment 22 dòng của nó (130-152) nói ảnh vẽ dạng **template** lấy tint động, **mâu thuẫn trực tiếp** với doc comment của `trackImage(color:height:)` đang thật sự chạy (dòng 100-114), vốn nói màu phải nằm trong bitmap vì `UISlider` tint cả hai đầu như nhau. Xoá cả hằng số lẫn chú thích sai.

  Test: `SystemVolumeSliderTests` đã dựng được `TintedVolumeView` (lớp `internal` chính vì lý do đó). Thêm một test cho `observedSlider`.

  *Xong khi:* `grep -n "isObservingSliderTouches\|static let trackImage" SystemVolumeSlider.swift` trả về rỗng, và có test mới đỏ trước khi sửa.

- [x] **A4 — `Logger` thay năm chỗ `print`**

  `grep "import os|Logger(|os_log"` hiện trả về **0**. `print()` không tới được Console.app trên máy người dùng, cũng không vào sysdiagnose — nghĩa là lỗi ngoài thực địa không truy được.

  Năm chỗ — audit ghi "bảy" là sai, tôi đếm nhầm cả `fatalError` vào: [EvenstarApp.swift:62](../../../Evenstar/Evenstar/App/EvenstarApp.swift#L62), [SongsView.swift:404](../../../Evenstar/Evenstar/Features/Library/SongsView.swift#L404), [JamendoSongsList.swift:93](../../../Evenstar/Evenstar/Features/Jamendo/JamendoSongsList.swift#L93), [JamendoClient.swift:197](../../../Evenstar/Evenstar/Services/JamendoClient.swift#L197), [PlaybackService.swift:1349](../../../Evenstar/Evenstar/Services/PlaybackService.swift#L1349).

  Một file `Utilities/AppLog.swift` giữ các `Logger` theo category (`library`, `playback`, `jamendo`, `drive`). Subsystem lấy từ bundle id, không viết cứng chuỗi.

  **Quyền riêng tư:** `Logger` mặc định che chuỗi động thành `<private>`. Tên bài và tên nghệ sĩ **để nguyên mặc định** — đó là dữ liệu của người dùng. Chỉ `error.localizedDescription` mới đánh `privacy: .public`, vì đó là thứ cần đọc được khi chẩn đoán.

  Sáu `fatalError` trong `#Preview` **giữ nguyên** — chúng chỉ chạy trong Xcode preview, và một preview hỏng thì nên hỏng to.

  `fatalError` ở [EvenstarApp.swift:32](../../../Evenstar/Evenstar/App/EvenstarApp.swift#L32) (`ModelContainer` không mở được) cũng giữ: không có app nào để chạy khi kho dữ liệu không mở được. Đường lỗi người dùng cho chuyện đó thuộc phạm vi khác.

  *Xong khi:* `grep -rn "print(" Evenstar/Evenstar --include='*.swift'` chỉ còn các file trong `Prototypes/`.

**Chạy test. Commit riêng từng việc.**

---

## Đợt B — Giảm chuyển động

Việc lớn nhất về giá trị trong cả kế hoạch, và là mục duy nhất có thể bị App Review chặn. `grep -r accessibilityReduceMotion` hiện trả về **0** trên 17.400 dòng.

HIG đòi nhiều hơn "làm animation ngắn lại": phải tắt **dịch chuyển, phóng to, xoay, nảy**. Mờ dần (cross-fade) là thứ được phép giữ.

- [x] **B1 — Đường dẫn đọc, một chỗ duy nhất**

  `@Environment(\.accessibilityReduceMotion)` đọc ở [RootView](../../../Evenstar/Evenstar/App/RootView.swift), ghi vào một chỗ mà `BottomBarStyle` đọc được.

  **Không** để mỗi view tự đọc environment: `BottomBarStyle` là một `enum` không phải `View`, các `ButtonStyle` cũng vậy, và một hằng số chuyển động phải cho ra cùng một câu trả lời ở mọi chỗ gọi. Một chỗ đọc thì không lệch được — cùng lý do `isMinimisedActive` tồn tại ở `RootView`.

  Cảnh giác: viết vào một `static var` từ `body` là ghi trong lúc dựng view. Dùng `.onChange(of:initial: true)` chứ không viết thẳng trong `body`.

  *Xong khi:* bật/tắt Giảm chuyển động trong Cài đặt → Trợ năng, giá trị đổi mà không cần khởi động lại app.

- [x] **B2 — Biến thể phẳng cho mọi hằng số trong `BottomBarStyle`**

  Mười hằng số chuyển động ở [BottomBarStyle.swift:37-286](../../../Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift#L37-L286): `morph`, `selection`, `press`, `content`, `settle`, `expand`, `control`, `queue`, `queueContentIn/Slide/Out`, `queueTitleIn/Out`.

  Mỗi cái đổi từ `static let` thành `static var` có nhánh. Lò xo → `easeInOut` cùng độ dài xấp xỉ, bounce → 0.

  `settle(initialVelocity:)` là hàm: ở chế độ giảm chuyển động bỏ hẳn vận tốc ban đầu và trả về curve phẳng — vận tốc ban đầu chính là thứ tạo ra cảm giác vọt.

  **Giữ nguyên toàn bộ doc comment hiện có.** Chúng ghi số đo từ Apple Music theo từng khung hình và là tài sản của dự án; thêm nhánh phẳng vào, đừng thay thế lời giải thích.

  *Xong khi:* mọi hằng số chuyển động trong file có hai nhánh.

- [x] **B3 — `PlayerCard`: cú morph thành mờ dần**

  Đây là chỗ khó nhất và cũng là chỗ người dùng nhạy cảm chuyển động thấy rõ nhất — mở player hiện phóng từ viên thuốc ra toàn màn hình, và nền thụt lùi sau nó.

  Hai việc:
  - `recedeScale` ([BottomBarStyle:150](../../../Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift#L150), dùng ở [PlayerExpansion:90](../../../Evenstar/Evenstar/Features/Shared/PlayerExpansion.swift#L90)) về `1` — nền không thu nhỏ nữa.
  - Cú morph của thẻ: ở chế độ giảm chuyển động, thay vì nội suy hình dạng và vị trí, cho hai trạng thái chồng lên nhau và mờ vào nhau.

  **Cử chỉ kéo vẫn phải chạy.** Giảm chuyển động không có nghĩa là bỏ cách điều khiển — người dùng vẫn vuốt xuống để đóng player, chỉ là phần *đi kèm* không phóng nữa. Đừng vô hiệu hoá `drag(...)`.

  *Xong khi:* bật Giảm chuyển động, mở player không thấy phóng to, không thấy nền thu nhỏ, và vuốt đóng vẫn hoạt động.

- [x] **B4 — Bốn chỗ còn lại**

  - `matchedGeometryEffect` của vệt tab đang chọn — [FloatingTabBar.swift:505, 631, 673](../../../Evenstar/Evenstar/Features/Shared/FloatingTabBar.swift#L505). Vệt *trượt* giữa các tab; ở chế độ giảm chuyển động nó phải **đổi opacity tại chỗ**, không trượt.
  - `TapHalo` ([TapHalo.swift:32](../../../Evenstar/Evenstar/Features/Shared/TapHalo.swift#L32)) — vòng sáng phóng ra từ điểm chạm. Tắt hẳn; nó thuần trang trí.
  - `TransportButtonStyle` cú nảy ([dòng 135](../../../Evenstar/Evenstar/Features/Shared/TransportButtonStyle.swift#L135)) và `QueueToggleStyle` cú co ([dòng 47](../../../Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift#L47)) — đổi thành phản hồi bằng opacity. **Phải còn phản hồi gì đó**: nút không báo hiệu là nút hỏng, không phải nút dễ tiếp cận hơn.
  - Cú đáp của `ReorderableStack` ([dòng 466](../../../Evenstar/Evenstar/Features/Shared/ReorderableStack.swift#L466), `ReorderTuning.part`/`settleSpring`) — thành tuyến tính, không nảy. Cử chỉ kéo giữ nguyên.

  *Xong khi:* bật Giảm chuyển động, đi hết bốn tab, mở player, mở hàng đợi, kéo một hàng — không thấy chỗ nào phóng, trượt hay nảy.

**Chạy test. Thử tay trên máy thật với Giảm chuyển động bật, rồi tắt, kiểm cả hai đường.**

---

## Đợt C — Prototype ra khỏi bản Release

- [x] **C1 — `#if DEBUG` bọc bốn bản thử và bốn lối vào**

  `Features/Prototypes/` chứa 2.393 dòng: `PlayerMorphDemoView` (1.144), `PlayerMorphUIKitView` (505), `PlayerZoomDemoView` (273), `PlaylistReorderDemo` (471). Cả bốn đang biên dịch vào binary sản phẩm và mở được từ [SettingsView.swift:142-159](../../../Evenstar/Evenstar/Features/Account/SettingsView.swift#L142-L159) qua bốn `fullScreenCover`.

  **Dùng `#if DEBUG`, không đổi target membership.** Dự án dùng Xcode 16 synced folders, nên bỏ file khỏi target phải ghi exception vào `.pbxproj` — ràng buộc 1 cấm. `#if DEBUG` là mã Swift thuần, đạt cùng kết quả cho bản Release, và không ai phải mở Xcode.

  Bọc cả bốn file **và** bốn `fullScreenCover` **và** các `@State` cùng hàng bấm trong `SettingsView` sinh ra chúng. Bỏ sót một cái là lỗi biên dịch ở Release — mà đó là cách tốt để biết mình sót.

  Không xoá: các bản thử là hồ sơ so sánh của những quyết định chuyển động và có giá trị tra cứu.

  *Xong khi:* `xcodebuild -configuration Release build` xanh, và `grep -c "Prototypes" ` trong bản Release không còn symbol nào. Kiểm bằng cách so kích thước binary trước/sau.

---

## Đợt D — Ngôn ngữ Swift 6

`SWIFT_VERSION = 5.0` hiện tại, dù `SWIFT_APPROACHABLE_CONCURRENCY = YES` và `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` đã bật. Nghĩa là toàn bộ kỷ luật `@MainActor` trong dự án là **thủ công, không được compiler kiểm**. Chú thích ở [PlaybackService.swift:121](../../../Evenstar/Evenstar/Services/PlaybackService.swift#L121) thừa nhận đúng điều đó: *"safe by construction rather than by assertion"*.

- [x] **D1 — Sửa cho sạch dưới Swift 6, không đụng `.pbxproj`**

  Chìa khoá: `xcodebuild` nhận build setting đè từ dòng lệnh, nên tìm và sửa được hết lỗi mà không sửa file dự án nào.

  ```
  xcodebuild -scheme Evenstar -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    SWIFT_VERSION=6.0 build
  ```

  Chỗ nhiều khả năng nổ:
  - `nonisolated(unsafe) var sessionObservers` ([PlaybackService:131](../../../Evenstar/Evenstar/Services/PlaybackService.swift#L131)) — đọc từ `deinit`.
  - Các closure `[weak self]` trong `RemoteCommandsBridge`, `StreamingAudioPlayer`, `RoutingAudioPlayer` băng qua ranh giới actor.
  - `Coordinator` trong `ReorderLongPress` — `@MainActor` với một method `nonisolated`.
  - `MetadataReading: Sendable` và các kiểu đi qua nó.

  **Nguyên tắc khi sửa:** lỗi Swift 6 là chỉ dấu, không phải phiền toái. Chỗ nào compiler kêu, hỏi *"tại sao chỗ này an toàn"* trước, và nếu câu trả lời là "vì tôi cẩn thận" thì đó là bug chờ xảy ra. Không rắc `@unchecked Sendable` để dập lỗi.

  *Xong khi:* lệnh trên xanh, không warning, và test cũng chạy được với cùng cờ đè.

- [ ] **D2 — Bàn giao: một dòng cho người dùng**

  Sau khi D1 xanh, người dùng mở Xcode → target Evenstar → Build Settings → Swift Language Version → **6**. Cho cả ba target (app, test, và bất kỳ target nào khác).

  Agent **không** làm việc này.

---

## Đợt E — Cần người dùng, không tự làm được

- [x] **E1 — Deployment target cấp dự án `26.0` → `18.6`**

  `.pbxproj` dòng 270 và 328 đặt `IPHONEOS_DEPLOYMENT_TARGET = 26.0` ở cấp **dự án**; ba target đè xuống `18.6`. Target mới thêm sau này sẽ thừa kế 26.0 và không chạy trên máy người dùng — một quả mìn hẹn giờ, hiện chưa gây hại.

  Xcode → chọn **PROJECT** (không phải TARGET) → Build Settings → iOS Deployment Target → `18.6`.

- [x] **E2 — Đo ba thao tác chưa từng đo riêng** — *xong cho thao tác mở/đóng player, ngày 2026-08-19. Kết quả và số đo: [`2026-08-19-e2-trace.md`](../audits/2026-08-19-e2-trace.md). Hai thao tác còn lại (mở/đóng playlist, kéo thả hàng đợi) chưa đo.*

  Mở/đóng player, mở/đóng playlist, kéo thả hàng đợi. Mỗi cái một trace, mỗi trace một loại thao tác liên tục.

  Đây là **điều kiện chặn** của mục 10 lộ trình (tách `PlayerCard`, 3–5 ngày). Nếu số đo cho thấy `PlayerCard` chỉ đang trả giá cho `.floatingBarShadow()` ở dòng 1176 — cùng loại lỗi thanh tab vừa sửa — thì cả việc tách kia có thể không cần làm.

  Cách nhanh trước, hai phút: Cài đặt → Nhà phát triển → **Color Offscreen-Rendered Yellow**, rồi chụp bốn màn hình (danh sách + thanh tab, player mở, player đang vuốt đóng, playlist đang nhấc hàng). Vùng vàng = rasterize ngoài màn hình. Nó chỉ *chỗ nào*; trace mới nói *bao nhiêu*.

  Giao thức trace, và bốn cách nó đã hỏng trong phiên trước:
  ```
  xcrun xctrace record --template 'Animation Hitches' \
    --device <UDID> --launch com.evenstar.app --time-limit 35s --output <n>.trace
  ```
  - **Kiểm dung lượng đĩa trước.** Đĩa đầy làm xctrace ghi trace rỗng mà vẫn in "Recording completed". Ba trace mất vì cái này. Chừa ít nhất 2GB.
  - **`--launch`, không `--attach`.** Attach hỏng câm trên máy này.
  - **Bấm ghi khi tay đã đang thao tác.**
  - **Đọc `displayed-surfaces-per-second` trước con số hitch**, rồi chỉ tính trên đoạn liền mạch có vẽ.

---

## Không làm, và vì sao

- **Tách `PlayerCard`** (mục 10) — **E2 đã chạy, và nó không mở cổng cho việc này**. Trace nói chi phí nằm ở main thread khi SwiftUI dựng và so cây view (commit 45%, commit-to-render 47%, GPU chỉ 7,3%), nên tách view đúng là đường nhắm vào đó. Nhưng **57% phần hitch còn lại nằm trong một cú duy nhất** — cú bung đầu tiên sau một quãng nghỉ — nên đo cú ấy trước rẻ hơn nhiều so với 3–5 ngày tách một view 3.000 dòng để giảm chi phí mỗi khung. Xem [`2026-08-19-e2-trace.md`](../audits/2026-08-19-e2-trace.md) §4.
- **Swift Testing thay XCTest** — 47 file, 469 hàm. Lợi ích thật nhưng không đóng vấn đề nào đã tìm ra.
- **Dynamic Type** — chưa ai kiểm ở cỡ chữ trợ năng. Cần khảo sát trước, không phải sửa mù.
- **Họ crash `DriveFolder`** — `DriveLibraryService.scan` giữ `folder` qua `await` không có hook. Cùng loại với bốn chỗ đã đóng ở Đợt 1 trước; một việc riêng.
- **Đợt 2–5 của kế hoạch ngày 2026-08-14** — chuyển động cho 14 màn hình tĩnh. Đợt B ở đây **giao nhau** với mục 2.1 của kế hoạch ấy và thay thế nó; phần còn lại chưa động tới.
