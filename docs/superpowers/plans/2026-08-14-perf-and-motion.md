# Evenstar — kế hoạch tối ưu hiệu năng và chuyển động

> **Cho người thực thi:** mỗi việc là một checkbox. Làm xong một đợt thì **đo lại trước khi sang đợt sau** — thứ tự các đợt được xếp theo bằng chứng, và bằng chứng ấy có thể đổi sau mỗi lần đo.

**Mục tiêu:** đưa hitch từ **73.5 ms/giây** xuống **dưới 10** (ngưỡng "tệ" của Apple), và đưa chuyển động của mười bốn màn hình đang tĩnh hoàn toàn lên ngang chuẩn app hệ thống — mà không phá bất cứ thứ gì đã được đo là đúng.

**Hai audit nguồn:**
- [`audit-perf-2.md`](../audits/audit-perf-2.md) — 12 vấn đề hiệu năng, số đo từ 5 phiên Instruments
- [`audit-animation.md`](../audits/audit-animation.md) — 10 vấn đề chuyển động, đối chiếu Apple Music theo từng khung

---

## Ba nguyên tắc, rút từ những lần sai trong phiên điều tra

Đây không phải lời khuyên chung. Mỗi điều dưới đây đã hỏng một lần, và đã tốn thời gian thật.

**1. Đo trước khi sửa, và đo lại sau khi sửa.** Giả thuyết "bốn lớp blur làm GPU quá tải" đã dẫn tới suýt sửa nhầm chỗ; số đo cho thấy GPU giảm 65% khi sửa một cú ghi trên main thread mà không đụng blur nào. `audit-perf.md` (vòng một) kết luận `.shadow()` là thủ phạm chính — **kết luận ấy đã bị số đo bác bỏ**, và không được dùng làm căn cứ cho việc gì trong kế hoạch này.

**2. Chuẩn hoá theo số giây thật sự có vẽ.** Một phiên đo cho ra 11.1 ms/giây trông như đã đạt; app chỉ vẽ 6 trên 45 giây, chia đúng thì là 83. Luôn xuất bảng `displayed-surfaces-per-second` trước khi tin một con số nào.

**3. Một thay đổi, một lần đo.** Gộp năm thao tác vào một trace thì mọi giả thuyết đều khớp dữ liệu.

---

## Ràng buộc

- iOS 18.0, SwiftUI, `@Observable`. Không thư viện ngoài.
- **Chỉ đánh giá chuyển động trên bản Release** — `./device.sh --release`. Debug tắt tối ưu hoá, và với SwiftUI khoảng cách ấy không hề nhỏ.
- Test phải xanh sau mỗi việc: `xcodebuild -scheme Evenstar -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`.
- Không sửa `.pbxproj` hay `.xcscheme` từ agent.
- Không đụng vào những chỗ đã ghi trong mục "Đã vượt chuẩn" của audit chuyển động.

---

## Giao thức đo

Chạy trước Đợt 1 để có mốc, rồi sau mỗi đợt.

```
xcrun xctrace record --template 'Animation Hitches' \
  --device <UDID> --attach Evenstar --time-limit 45s --output <n>.trace
```

Thao tác trong lúc ghi: **chỉ một loại**, liên tục 45 giây, không rời app, không để màn tắt.

Bốn phiên riêng cho bốn thao tác: cuộn danh sách / mở-đóng player / mở-đóng playlist / kéo thả hàng đợi.

Đọc kết quả:

```
xctrace export --input <n>.trace --xpath '...table[@schema="displayed-surfaces-per-second"]'
xctrace export --input <n>.trace --xpath '...table[@schema="hitches-lifetime-interval"]'
xctrace export --input <n>.trace --xpath '...table[@schema="potential-hangs"]'
```

`ms/giây = tổng hitch-duration ÷ số giây có count > 0`.

**Nếu `xctrace` chạy quá hai phút:** kiểm `ps -o %cpu` của tiến trình. 0% nghĩa là treo, không phải đang lưu. Giết bằng `pkill` **chỉ khi đã chắc**, và biết rằng nó để lại một phiên chưa đóng ở phía máy làm treo lần ghi sau — muốn sạch thì cắm lại cáp.

---

## Đợt 1 — Chi phí lặp lại ngoài player

Rẻ nhất, và nhắm vào hai mục Nghiêm trọng. Không đụng tới một dòng nào trong `PlayerCard`.

- [ ] **1.1 — `AccountView` thôi gom nhóm trong `body`**

  `Features/Account/AccountView.swift:31,32` gọi `LibraryGrouping.albums(from:)` và `.artists(from:)` ngay trong thân view, chỉ để lấy hai con số. Mỗi lượt là một `Dictionary(grouping:)` toàn thư viện cộng bốn lượt sắp xếp có bản địa hoá.

  Dời vào `.task(id: tracks.count)` sẵn có ở dòng 74, cất `albumCount`/`artistCount` vào `@State`. `AlbumsView.swift:52` và `ArtistsView.swift:32` đã là mẫu hình đúng — theo đúng chúng.

  *Xong khi:* `body` của `AccountView` không còn gọi `LibraryGrouping`.

- [ ] **1.2 — Năm `@Query` gộp còn một**

  `SongsView:10`, `AlbumsView:9`, `ArtistsView:9`, `SearchView:6`, `AccountView:14` — cùng một truy vấn toàn bảng `Track`. `TabView` giữ tab đã dựng, nên cả năm sống song song; mỗi lần chèn/xoá/sửa là năm lượt fetch, năm lượt sắp xếp có bản địa hoá, năm cây view dựng lại.

  Một `@Query` ở `RootView`, đưa xuống qua `\.environment`. Nếu việc ấy làm `RootView.body` đọc mảng và tự dựng lại — điều mà `PlayerExpansion` có cả một ghi chú giải thích vì sao phải tránh — thì thay bằng một `@Observable` `LibraryStore` giữ mảng, và các màn đọc từ nó.

  *Xong khi:* đúng một `@Query` trên `Track` trong toàn bộ mã.

  *Cảnh giác:* đây là việc có rủi ro cao nhất Đợt 1. Làm riêng một commit, chạy đủ test, và thử tay cả năm màn hình.

- [ ] **1.3 — `NowPlayingContent` thôi dựng lại hai lần mỗi giây**

  `NowPlayingContent.swift:318` đọc `playback.position` trong `body`. `PlaybackService.swift:1140` ghi nó 0.5 giây một lần. Với `@Observable`, cả thân view — tiêu đề, thanh tua, ba nút transport, thanh âm lượng, hàng nút hàng đợi — dựng lại hai lần mỗi giây khi đang phát, **kể cả khi player đóng**.

  Bọc phần đọc vào một view con chỉ nhận `position`/`duration`. Mẫu hình đã có: `Slot` trong `ReorderableStack.swift` tồn tại chỉ để thu hẹp phạm vi theo dõi, và ghi chú ở đó giải thích nguyên lý.

  *Xong khi:* `grep -n "playback.position" NowPlayingContent.swift` chỉ trả về dòng nằm trong view con ấy.

- [ ] **1.4 — `displayedArtwork` thôi tra cache mỗi khung**

  `PlayerCard.swift:743` là computed property gọi `ArtworkStore.anyCachedImage`, và `NSCache` có khoá bên trong. Nó chạy mỗi lần `body` chạy, tức mỗi khung suốt cú kéo, cho một kết quả không đổi trong cả cú kéo ấy.

  Phân giải một lần khi `artworkIdentity` đổi, cất vào `@State`.

  *Xong khi:* `anyCachedImage` không còn được gọi từ một computed property.

- [ ] **1.5 — `SearchView` thôi lọc trong `body`**

  `SearchView.swift:39` quét toàn thư viện mỗi ký tự gõ, trên đường đi của bàn phím.

  `.task(id: query)` với chờ 150ms, kết quả vào `@State`.

  *Xong khi:* `body` không còn gọi `LibraryGrouping.search`.

**Đo lại sau Đợt 1.** Kỳ vọng: dưới 30 ms/giây. Nếu không tụt đáng kể thì giả thuyết "chi phí lặp lại ngoài player" sai, và Đợt 4 phải lên trước Đợt 2.

---

## Đợt 2 — Chuyển động cho mười bốn màn hình đang tĩnh

Không phải tối ưu — đây là phần app đang thiếu so với chuẩn Apple. Rẻ, và thấy được ngay.

- [ ] **2.1 — Tôn trọng Giảm chuyển động**

  `grep -r accessibilityReduceMotion` hiện trả về **0** trên 17.422 dòng. Đây là yêu cầu HIG, và là mục duy nhất trong hai audit có thể chặn duyệt App Store.

  Đọc `@Environment(\.accessibilityReduceMotion)` ở `RootView`, đưa xuống. Mỗi hằng số trong `BottomBarStyle` có một biến thể phẳng (mờ dần, không lò xo, không dời chỗ). Cụ thể phải đổi hành vi: cú morph của `PlayerCard` thành mờ dần; `recedeScale` thành 1; `matchedGeometryEffect` của thanh tab thành đổi opacity; `TapHalo` và cú nảy của `TransportButtonStyle` tắt; cú đáp của `ReorderableStack` thành tuyến tính.

  *Xong khi:* bật Giảm chuyển động trong Cài đặt → Trợ năng, mở player không còn thấy phóng to hay thu nhỏ nền.

- [ ] **2.2 — Danh sách có chuyển động khi dữ liệu đổi**

  `SongsView.swift:342` `deleteTrack` chạy ngoài mọi transaction, nên hàng biến mất và mọi hàng dưới nhảy lên trong một khung.

  Bọc: `withAnimation(BottomBarStyle.content) { try library.delete(track) }`. Cùng việc ở `DriveFoldersView.swift:204,212`, `JamendoSongsList.swift:54`, và đường nhập nhạc trong `ImportService`.

  *Xong khi:* vuốt xoá một bài, hàng co lại và các hàng dưới trượt lên.

- [ ] **2.3 — `.transition()` cho các trạng thái đổi chỗ nhau**

  `grep -r "\.transition("` ngoài Prototypes hiện trả về **0**.

  Thêm `.transition(.opacity.combined(with: .scale(scale: 0.96)))` cho: `EmptyLibraryView` ↔ danh sách (`SongsView.swift:235`), ba `ContentUnavailableView` ở `JamendoDiscoveryView.swift:279,290,301`, và `PlayerSubtitle` khi thông báo lỗi thay chỗ dòng metadata.

  *Xong khi:* nhập bài đầu tiên, màn hình rỗng mờ đi thay vì biến mất.

---

## Đợt 3 — Thống nhất từ vựng chuyển động

Rẻ, và là điều kiện để lần chỉnh nhịp sau không sót chỗ nào.

- [ ] **3.1 — `ReorderableStack` đổi sang `duration:`/`bounce:`**

  `ReorderableStack.swift:150,157` dùng `response:`/`dampingFraction:` trong khi cả app dùng `duration:`/`bounce:`. Quy đổi: `response: 0.28, dampingFraction: 0.68` ≈ `duration: 0.28, bounce: 0.32`.

  Đây là đổi cách viết, không đổi hình. Xác nhận bằng mắt sau khi đổi.

- [ ] **3.2 — Ba literal về `BottomBarStyle`**

  `JamendoResultRow.swift:95` (`.snappy(duration: 0.25)`) và `ProminentActionButton.swift:34` (`.easeOut(duration: 0.1)`, gần bằng `BottomBarStyle.press` 0.09). Không ai thấy chênh lệch 0.01 giây — vấn đề là chúng nằm ngoài chỗ tập trung.

- [ ] **3.3 — Hai chiều cú tan chữ suy ra từ nhau**

  `BottomBarStyle.swift:274,286` là bốn con số độc lập cho hai chiều của một chuyển động, và đã trôi khỏi số đo Apple (0.10→0.17 mở, 0.23→0.33 đóng).

  Thứ tự giữa hai khối chữ **đã** được `completion` bảo đảm — giữ nguyên cơ chế ấy. Chỉ đưa bốn con số về một chỗ có ghi rõ chúng đến từ đâu, và đặt lại theo số đo.

---

## Đợt 4 — Chỉ làm nếu số đo sau Đợt 1 còn đòi

Không làm trước. Mỗi việc dưới đây đắt hoặc rủi ro, và có thể trở nên không cần thiết.

- [ ] **4.1 — Tách `PlayerCard`**

  2.332 dòng, 47 thành viên, 12 `@State`. Ba trong số đó đổi mỗi khung khi kéo, và mỗi lần là cả thân dựng lại — kèm tấm bìa, chrome thu nhỏ, nội dung mở rộng, grabber.

  Tách theo **trục thay đổi**, không theo chức năng: tấm bìa chỉ cần `progress`/`queueFactor`; chrome thu nhỏ chỉ cần `progress`; nội dung mở rộng cần `progress` cộng ba con số hàng đợi.

  Việc lớn nhất trong kế hoạch. Làm từng view một, đo sau mỗi lần tách.

- [ ] **4.2 — `Material` của thanh tab: đo A/B trước khi động vào**

  `FloatingTabBar.swift:448,561,805` — ba `.regularMaterial` luôn trên màn hình.

  **Không sửa mù.** Ghi 15 giây chỉ cuộn danh sách, một lần như hiện tại, một lần thay bằng màu đặc. Chênh lệch nói thẳng nó đáng bao nhiêu. Nếu dưới 3 ms/giây thì giữ nguyên — chúng là thứ làm thanh tab trông đúng.

- [ ] **4.3 — Lớp làm nóng dời ra sau khung hình đầu**

  `RootView.swift:290` vẽ `NowPlayingContent` thật ở opacity 0.02 trong 500ms đầu. Ý tưởng đúng và có đo (56ms cho khung đầu của cú bung đầu tiên), nhưng nó chạy song song với lượt fetch `@Query` và lượt mở store — chi phí bị dời vào chỗ đông nhất.

  Dời sang sau khi khung hình đầu tiên đã vẽ xong.

---

## Đợt 5 — Chuẩn Apple còn thiếu

Không phải hiệu năng. Làm sau cùng, hoặc xen vào khi rảnh.

- [ ] **5.1 — Chuyển cảnh zoom cho lưới Album/Nghệ sĩ**

  `AlbumsView.swift:88` và `ArtistsView.swift:66` mở chi tiết bằng đẩy ngang mặc định. Từ iOS 18, Photos và Music dùng `.matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))` — ô lưới nở thành màn chi tiết, và người dùng biết mình vừa mở ô nào.

  Bản thử của đúng API ấy đã có sẵn: `Features/Prototypes/PlayerZoomDemoView.swift`. Nó dựng cho player rồi không dùng; chỗ nó thật sự hợp là hai lưới này.

- [ ] **5.2 — Thanh tiến trình nhập nhạc thôi nhảy bậc**

  `ImportProgressSheet.swift:18` — thêm `.animation(.linear(duration: 0.2), value: completed)`. Một dòng.

- [ ] **5.3 — `TapHalo` theo thời gian giữ**

  `TapHalo.swift:38-51` chạy chuỗi keyframe cố định 0.52 giây bất kể ngón tay còn trên nút. Giữ nút Next hai giây thì vệt sáng tan sau nửa giây, để lại một nút đang bị nhấn mà không có dấu hiệu gì.

---

## Không làm

Ghi ra để không ai làm lại vì đọc audit cũ.

- **Đừng gỡ `.shadow()` khỏi `PlayerCard`.** `audit-perf.md` chỉ nó là thủ phạm chính; số đo bác bỏ. GPU giảm 65% khi sửa main thread mà không đụng shadow nào.
- **Đừng đổi `deferPersist` thành hoãn thêm một vòng.** Nó vẫn trên main thread, và cái tên không hứa gì khác. Nếu `persistImmediately` còn hiện trong trace sau Đợt 1 thì bước đúng là một `@ModelActor` nền.
- **Đừng gọi `context.converter.location(in:)` từ callback của recogniser UIKit.** Nó bắt AttributeGraph tính lại chuỗi thuộc tính hình học và `abort()` khi hỏi ngoài lượt cập nhật view. Đã crash thật: `Evenstar-2026-08-14-090115.ips`.
- **Đừng đổi lò xo `queue`.** `Spring(duration: 0.31, bounce: 0)` khớp số đo Apple Music trong hai phần trăm ở cả bảy khung.
- **Đừng thay hai `UILongPressGestureRecognizer` bằng cử chỉ SwiftUI.** `allowableMovement` là thứ SwiftUI không phơi ra, và nó mới là cái quyết định cú giữ có ổn định hay không.

---

## Đích đến

| | hiện tại | sau Đợt 1 | đích |
|---|---|---|---|
| hitch | 73.5 ms/giây | < 30 | **< 10** |
| lần chặn main thread / 28s | 17 | < 8 | **< 3** |
| cú chặn dài nhất | 122 ms | < 100 | **< 50** |
| màn hình có chuyển động | 5/19 | 5/19 | **19/19** |
| tôn trọng Giảm chuyển động | không | không | **có** |

Bốn hàng đầu đo được bằng giao thức ở trên. Hàng cuối kiểm bằng tay.
