# Liquid Glass native — spec

**Trạng thái:** thiết kế, chờ người dùng duyệt
**Ngày:** 2026-10-06
**Thay thế:** quyết định 2026-08-04 "ở lại 18.6, bỏ Đợt C". Quyết định ấy dựa trên
một tiền đề sai (xem "Bối cảnh").

## Mục tiêu

Bỏ thanh tab, cú thu nhỏ khi cuộn và viên mini player tự vẽ; thay bằng các thành
phần native của iOS 26 có Liquid Glass thật. Đổi các nút tự vẽ còn lại sang kiểu
nút kính native. Giữ nguyên cú bung player theo ngón tay — thứ Apple không cung
cấp API, kể cả cho chính Apple Music.

**Thành công nghĩa là:** trên iPhone chạy iOS 26, thanh tab, tab tìm kiếm, cú thu
nhỏ khi cuộn và viên mini player là của hệ thống; player vẫn bung từ viên mini
player và thu về đúng chỗ ấy; vuốt ngang mini player đổi bài; hiệu năng cú bung
không tệ hơn mức nền E2 (22,9 ms/giây).

## Bối cảnh

- **Liquid Glass đi theo SDK lúc build, không theo deployment target.** Máy dev
  dùng Xcode 26.0.1 / SDK 26.0 từ trước. Hồi tháng 8 ta tưởng phải nâng target
  lên 26 mới có Liquid Glass; sai.
- Dù vậy target vẫn **nâng lên iOS 26.0**: tháng 10/2026 iOS 26 đã ra hơn một
  năm, iOS 27 đã phát hành, và app chưa lên App Store nên không bỏ rơi người
  dùng iOS 18 nào. Một đường code, không cần `#available`.
- Spike `docs/prototypes/NativeAccessoryHandoff/` (2026-10-06) đã kiểm trên
  simulator iOS 26.0, bằng XCUITest chạy ngầm:
  - Khung accessory đo bằng `.onGeometryChange(… .frame(in: .global))` **trùng
    khít** viên kính: `.expanded` = 360×48 tại (20, 735), `.inline` = 234×48 tại
    (84, 798) trên iPhone 17.
  - Một thẻ phủ bung được từ khung ấy ở cả hai vị trí, thu về đúng chỗ, và cú
    kéo lên từ accessory lọt qua khung UIKit của hệ thống.
  - `.tabViewBottomAccessory { EmptyView() }` làm hệ thống **ẩn hẳn** viên kính.
    Khi có bài, nó trượt vào và giữ nguyên tab đang mở cùng vị trí cuộn. Không
    cần `tabViewBottomAccessory(isEnabled:)` (không có trong SDK 26.0).
  - Cú morph accessory/thanh tab khi cuộn là của hệ thống, ~200–270 ms, **không
    chỉnh được** đường cong hay độ co.
  - Hệ thống đổi `\.tabViewBottomAccessoryPlacement` không kèm animation và dựng
    nội dung ở cỡ cuối ngay khung đầu. `.id(placement)` + `.transition(.blurReplace)`
    **không có tác dụng**. Bố cục nội dung đổi theo vị trí sẽ nhảy.
  - Giá trị `placement` trên iOS 26.0 **không ổn định**: có lần báo `.inline`
    mà nội dung vẫn vẽ theo bố cục `.expanded`. (Mới thấy trên simulator.)
- Video Apple Music trên máy thật (2026-10-06, tách từng khung 33 ms):
  - Viên mini player trượt dần xuống giữa thanh tab trong ~300 ms rồi lắc nhẹ
    ~300 ms; nội dung đi theo viên kính, không nhảy. Tên bài **một dòng**.
  - Nút ⏭ **mờ dần rồi ẩn** khi thu nhỏ, hiện lại khi bung ra.
  - Bấm mini player: **ngay khung thứ hai viên kính thành một thẻ đặc**, không
    phải kính; hàng mini player dính mép trên thẻ và mờ dần; tràn màn ~360 ms.

## Ngoài phạm vi

- Lớp `.ultraThinMaterial` sau bìa ở player toàn màn hình — hiệu ứng làm mờ nền,
  không phải thành phần kính.
- Tab role `.prominent` của iOS 27 — cần SDK 27.
- UI test cho app chính — thêm target phải sửa `project.pbxproj`.
- Đổi tên `BottomBarStyle`.
- Port các prototype trong `Features/Prototypes/`.

## Điều kiện tiên quyết (người dùng làm trong Xcode)

**TARGETS** → `Evenstar` và `EvenstarTests` → Build Settings → All → iOS
Deployment Target → **26.0**. Agent không sửa `project.pbxproj`.

## Cách triển khai

Một nhánh riêng, bốn giai đoạn. Giai đoạn nào xong app cũng build, chạy và qua
toàn bộ test; mỗi giai đoạn được kiểm bằng tay trên iPhone thật trước khi sang
giai đoạn sau.

| Giai đoạn | Nội dung |
|---|---|
| 1 | `TabView` native, tab tìm kiếm, thu nhỏ khi cuộn, accessory; neo lại `PlayerCard`; xoá thanh tab tự vẽ |
| 2 | Nút hành động chính → `.glassProminent` |
| 3 | Nút trong player → `.glass` + haptic |
| 4 | Vuốt ngang mini player để đổi bài |

## Phần 1 — Kiến trúc khung app (giai đoạn 1)

### Native thay thế

Trong `RootView`:

```swift
TabView(selection: $tab) {
    Tab(LibraryTab.songs.label, systemImage: LibraryTab.songs.symbol, value: .songs) { SongsView() }
    // … albums, artists, account
    Tab(value: .search, role: .search) { SearchView(query: $query) }
}
.tabBarMinimizeBehavior(.onScrollDown)
.tabViewBottomAccessory {
    if playback.currentTrack != nil { MiniPlayerAccessory(…) } else { EmptyView() }
}
```

`.searchable(text:)` đặt trên `NavigationStack` **bên trong** `SearchView` — cách
spike đã dùng và chạy đúng. `query` vẫn do `RootView` giữ và truyền xuống bằng
binding.

`LibraryTab` vẫn là enum chọn tab; `pillTabs` và lời giải thích "search nằm ngoài
pill" không còn đúng.

### Xoá

- `FloatingTabBar.swift` (cùng `TabPressStyle`), `ScrollMinimise.swift`.
- `isMinimised`, `isMinimisedActive` và binding `isMinimised:` trên chín màn:
  Songs, Albums, Artists, Account, AlbumDetail, ArtistDetail, JamendoDiscovery,
  JamendoSongsList, DriveSongsList.
- `isSearching`, `isEditing`, `tabBeforeSearch`, `onOpenSearch`, `onCloseSearch`,
  `onRestore`.
- `.toolbar(.hidden, for: .tabBar)` ở mọi màn.
- `BottomBarClearance.swift` và `\.bottomSafeAreaInset`, cùng lớp đo inset trong
  `RootView`: hệ thống tự đẩy nội dung tránh thanh tab và accessory.
- Phần `BottomBarMetrics` không còn ai đọc; `floatsOverPlayer`.

### Thêm mới

**`MiniPlayerAccessory`** — nội dung của accessory; kính là của hệ thống.

- Bìa nhỏ, **một dòng** tên bài, nút play và next.
- **Bố cục giống nhau ở `.expanded` và `.inline`, trừ nút ⏭**: ở `.inline` nó mờ
  dần và co về 0 như Apple Music. `placement` chỉ được dùng cho việc ấy. Vì spike
  thấy `placement` không ổn định trên simulator, việc này được kiểm trên iPhone
  thật; nếu vẫn không ổn định thì ⏭ hiện ở cả hai vị trí.
- Báo khung của mình lên `RootView` bằng `.onGeometryChange` trong toạ độ global.
- Ẩn nội dung (opacity 0) trong lúc thẻ player đang hiện.

**`PlayerCard`** — `minimised: Double` đổi thành `anchor: CGRect`.

- `anchor` là khung accessory, **chụp lại lúc bắt đầu bung** và giữ nguyên suốt
  cú bung: nội dung lùi lại phía sau (`recedesBehindPlayer`) làm khung đo được co
  theo, nên đọc trực tiếp giá trị đang đo sẽ làm điểm xuất phát trôi.
- Lề trái, lề phải, khoảng cách đáy, chiều cao lúc thu gọn, bán kính góc và
  `dragTravel` đều suy ra từ `anchor`, qua **một hàm thuần** (xem Phần 4). Không
  công thức nào được viết lại ở hai chỗ — bài học R2 về `dragTravel` lệch padding.
- Lúc nghỉ (`progress` 0) thẻ **vẫn nằm trong cây view**, ẩn và không nhận chạm.
  Không dựng/huỷ thẻ theo từng cú bung: E2 cho thấy cú bung đầu sau một quãng
  nghỉ đã gánh 57% hitch còn lại, và dựng thẻ từ đầu sẽ làm nặng thêm đúng cú đó.
- **Khi bung: thẻ đặc ngay từ khung đầu, không có lớp kính**, như Apple Music.
  Lớp `.thinMaterial` cũ của viên pill bị xoá. Lúc nghỉ, khung ấy là viên kính
  của hệ thống; lúc bung, thẻ đặc phủ lên.
- **Khi thu (sửa 2026-10-06 sau QA trên máy):** ở đoạn cuối, lúc thẻ còn lớn hơn
  viên kính một chút, mặt thẻ chuyển từ đặc sang `.glassEffect`; thẻ **lún quá
  chỗ ~10pt rồi nảy lại** (không bẹp hình) như Apple Music; chỉ sau cú nảy mới
  nhường cho accessory — kính nhường cho kính, không đổi màu. Video Apple Music:
  thẻ thành kính ~66–100ms trước khi chạm đáy, lún ~132–200ms, nảy về ~200–500ms.

### Thay đổi hành vi

- **Đóng tìm kiếm không còn tự quay về tab trước đó.** Search là một tab thường
  của hệ thống, như Apple Music.
- **Lệnh của nút transport chạy lúc nhấc tay** thay vì lúc chạm xuống (hệ quả của
  việc bỏ `TouchDownButton` ở Phần 3).

## Phần 2 — Cử chỉ trên mini player (giai đoạn 1 và 4)

Một `DragGesture` gắn trên **vùng thông tin bài** (bìa + tên bài). Nút play và
next nằm ngoài vùng ấy. Sau khoảng 10 pt, cử chỉ **khoá trục** theo thành phần
trội hơn và giữ trục ấy tới khi nhấc tay.

| Cử chỉ | Hành vi | Giai đoạn |
|---|---|---|
| Chạm | Bung player (`expand()` hiện có) | 1 |
| Kéo lên (trục dọc) | Thẻ hiện tại `anchor`, bám ngón tay; thả ra tự bung hoặc thu theo vị trí và vận tốc (logic `drag(travel:)` hiện có) | 1 |
| Kéo xuống | Không làm gì | 1 |
| Vuốt ngang | Đổi bài | 4 |

### Vuốt ngang đổi bài

- Trong lúc kéo, chỉ bìa và tên bài trượt theo ngón tay và mờ dần; nút đứng yên.
- Thả quá ~30% bề ngang, hoặc vận tốc đủ lớn: nội dung cũ trượt hẳn ra, nội dung
  bài mới trượt vào từ phía đối diện, kèm một nhịp haptic. Chưa đủ: nảy về.
- **Trái → bài tiếp.** Chỉ khi `canGoNext`; ngược lại rubber band rồi nảy về,
  **không** gọi `next()` (ở cuối hàng đợi khi tắt repeat, `next()` dừng phát).
- **Phải → bài trước, luôn lùi hẳn một bài**, bỏ qua ngưỡng "phát lại từ đầu sau
  3 giây" của nút ⏮ — hình bài cũ trượt vào mà kết quả là phát lại bài hiện tại
  thì sai với điều mắt thấy. Ở đầu hàng đợi khi tắt repeat: rubber band. Khi
  repeat bật: vòng về bài cuối, như `previous()`.
- Cần thêm vào `PlaybackService`: `canGoPrevious` và một hàm lùi bài bỏ qua ngưỡng.
- **Reduce Motion:** không trượt; mờ chéo giữa hai bài.
- **Rủi ro, thử đầu tiên ở giai đoạn 4:** spike mới kiểm kéo dọc trong khung
  UIKit của accessory, chưa kiểm kéo ngang.

## Phần 3 — Nút kính, Reduce Motion, dọn dẹp (giai đoạn 2 và 3)

### Giai đoạn 2 — nút hành động chính

- Sáu chỗ dùng `.prominentAction` và nút `.borderedProminent` ở
  `TrackMetadataEditor` → `.buttonStyle(.glassProminent)`.
- Xoá `ProminentActionButton.swift`.
- **Đặt `.tint` rõ ràng ở mỗi chỗ.** `.glassProminent` mặc định tô màu accent,
  mà accent của app là trắng — đúng lỗi "nút trắng trên nền sáng" mà ghi chú của
  `ProminentActionButtonStyle` ghi lại. Kiểm bằng mắt ở cả sáng lẫn tối.

### Giai đoạn 3 — nút trong player

- Player toàn màn hình: ⏮ ⏯ ⏭, nút hàng đợi → `.buttonStyle(.glass)`.
- Shuffle/repeat: **bật** → `.glassProminent`, **tắt** → `.glass`.
- Mỗi nút: `.sensoryFeedback(.impact(weight: .light), trigger:)`.
- Nút play/next **trong accessory: glyph trần**, không phải `.glass` — accessory
  đã là kính; kính lồng kính là điều Apple khuyên tránh, và mini player của Apple
  Music cũng dùng glyph trần. Vẫn có haptic.
- Xoá `TransportButtonStyle.swift`, `QueueToggleStyle.swift`, `TapHalo.swift`,
  `TouchDownButton.swift`; 14 chỗ dùng `TouchDownButton` về `Button` thường.

### `BottomBarStyle`

Giữ, không đổi tên. Player và hàng đợi vẫn dùng `morph`, `settle`, `expand`,
`queue*`, `recedeScale`, `reduceMotion`… Thành viên nào hết người gọi sau mỗi
giai đoạn thì xoá cùng giai đoạn ấy.

### Reduce Motion

Phần native tự tuân theo cài đặt hệ thống. Phần tự viết vẫn đọc qua
`BottomBarStyle.reduceMotion`; giữ bất biến **chỉ một chỗ đọc
`accessibilityReduceMotion`**, ở `RootView`.

### Prototype trong target app

`Features/Prototypes/` (chỉ build ở DEBUG, không màn nào gọi). File nào còn tham
chiếu thứ bị xoá thì xoá luôn file đó.

## Phần 4 — Kiểm thử

### Test hiện có

- Test logic thuần (playback, library, Drive, Jamendo, CloudKit…) không đổi và
  phải xanh suốt mọi giai đoạn.
- `ReduceMotionTests`: giữ phần ghim các hằng số `BottomBarStyle` còn sống; xoá
  test của hằng số đã xoá.
- `ReduceMotionSurfacesTests`: xoá test của bề mặt đã xoá (thanh tab, nút
  transport); giữ cú bung player và hàng đợi.
- `PlayerCardCommitCostTests`: đổi `minimised:` → `anchor:`, giữ lại — đây là
  thước đo chi phí commit của cú bung.
- `PlayerCardClipShapeTests`: sửa theo API mới.

### Test mới (viết trước code)

1. **`PlaybackService.canGoPrevious` và hàm lùi bài:** đầu/giữa/cuối hàng đợi ×
   ba chế độ repeat; khẳng định không có nhánh "phát lại từ đầu".
2. **Hình học neo — hàm thuần** `(anchor: CGRect, screen: CGSize, insets) →` lề,
   đáy, chiều cao, bán kính, `dragTravel`.
   - Ca kiểm: 360×48 tại (20, 735); 234×48 tại (84, 798); một khung màn ngang.
   - Bất biến: ở `progress` 0 thẻ **trùng khít** `anchor`; `dragTravel` **bằng**
     quãng mép trên của thẻ di chuyển từ 0 tới 1.
3. **Quyết định vuốt ngang — hàm thuần** `(translation, velocity, width,
   canGoNext, canGoPrevious) → .next / .previous / .cancel / .rubberBand`, cùng
   logic khoá trục.

### Kiểm tay trên iPhone thật, sau mỗi giai đoạn

Sáng và tối; màn ngang; Reduce Motion; Dynamic Type lớn; chưa có bài → có bài;
tab Search; bung và thu player từ cả `.expanded` lẫn `.inline`; (giai đoạn 4)
vuốt đổi bài ở cả hai vị trí, ở đầu và cuối hàng đợi.

### Hiệu năng

Sau giai đoạn 1, chạy lại trace E2 (`Animation Hitches`, iPhone 12, Release) và
so với **22,9 ms/giây**. Qua khi **không tệ hơn**. Cần ~10 GB đĩa trống; khi
lưu, `xctrace` đứng ở 0% CPU khoảng 2 phút — không kill.

## Rủi ro

| Rủi ro | Cách xử lý |
|---|---|
| Chỗ nối viên kính → thẻ đặc nhìn ra chớp | Thẻ đặc ngay khung đầu như Apple Music, không có kính chồng kính; người dùng kiểm trên máy thật ở giai đoạn 1. Đường lui: zoom transition native |
| Vuốt ngang bị khung UIKit của accessory nuốt | Thử đầu tiên ở giai đoạn 4 |
| `placement` không ổn định trên 26.0 | Chỉ dùng nó cho nút ⏭; kiểm trên máy thật, không ổn thì bỏ |
| Cú bung đầu nặng hơn sau khi đổi cấu trúc | Thẻ luôn nằm trong cây view; đo E2 sau giai đoạn 1 |
