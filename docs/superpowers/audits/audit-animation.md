# Evenstar — tổng điều tra chuyển động

Phạm vi: toàn bộ `Evenstar/Evenstar/`, mọi màn hình, mọi thành phần có chuyển động. Đối chiếu với hành vi của app Apple (Music, Photos, Settings, Files) và với Human Interface Guidelines phần Motion.

Cơ sở: đọc mã, cộng với **số đo thật** — năm phiên Instruments `Animation Hitches` trên iPhone 12 bản Release, và phân tích từng khung ảnh quay màn hình Apple Music ở 30fps cho phần morph của player.

---

## Ấn tượng chung

Chuyển động ở đây được xây bởi người có đo. Từ vựng lò xo nằm tập trung một chỗ (`BottomBarStyle`) thay vì rải literal khắp nơi; mỗi hằng số có ghi chú nói vì sao nó là con số ấy; và ba trong số đó — `queue`, `queueContentSlide`, `queueTitleOut` — được suy ra bằng cách khớp đường cong với ảnh quay Apple Music chứ không phải chọn theo cảm giác. Rất ít codebase SwiftUI làm tới mức đó.

Chỗ yếu **không nằm ở phần đã làm, mà ở phần chưa chạm tới**. Toàn bộ chuyển động của app tập trung vào hai vùng: thanh tab nổi và thẻ player. Mười bốn màn hình còn lại — thư viện, album, nghệ sĩ, tìm kiếm, Drive, Jamendo, nhập nhạc, cài đặt — có **đúng ba** điểm chuyển động cộng lại. Đó là khoảng cách lớn nhất so với app Apple, và nó có hệ thống chứ không phải sót vài chỗ.

---

## Bản đồ chuyển động theo màn hình

| Vùng | Điểm chuyển động | Đánh giá |
|---|---|---|
| Thanh tab nổi | 16 | Vượt chuẩn |
| Thẻ player | 13 | Vượt chuẩn |
| Danh sách kéo thả hàng đợi | 12 | Đạt, có nợ kỹ thuật |
| Nội dung player mở rộng | 6 | Đạt |
| `RootView` | 5 | Đạt |
| Nút transport | 3 | Vượt chuẩn |
| Hàng Jamendo | 3 | Đạt |
| Thanh tua, viên thuốc mở hàng đợi | 4 | Đạt |
| **Thư viện / Album / Nghệ sĩ / Tìm kiếm** | **0** | **Chưa đạt** |
| **Drive / Jamendo (danh sách) / Nhập nhạc** | **0** | **Chưa đạt** |
| **Cài đặt / Tài khoản / Sửa metadata** | **0** | Chấp nhận được |

---

## Bảng phát hiện, xếp theo cấp độ

Cấp độ theo hậu quả người dùng thấy được, không theo công sức sửa.

| # | Cấp | Chỗ | Chưa đạt ở điểm nào | Apple làm gì |
|---|---|---|---|---|
| 1 | **Nghiêm trọng** | Toàn app | Không nơi nào đọc `accessibilityReduceMotion` | Mọi app hệ thống đổi sang mờ-dần khi bật Giảm chuyển động |
| 2 | **Nghiêm trọng** | Thư viện, Album, Nghệ sĩ, Tìm kiếm, Drive, Jamendo | Xoá/thêm/đổi hàng không có chuyển động | Music trượt hàng còn lại lên khi xoá |
| 3 | **Cao** | Toàn app | Không có `.transition()` nào; trạng thái rỗng và banner lỗi hiện/biến mất tức thì | Photos/Music mờ-và-nở `ContentUnavailableView` |
| 4 | **Cao** | `ReorderableStack` | Hai lò xo dùng `response:/dampingFraction:` trong khi cả app dùng `duration:/bounce:` | — (nhất quán nội bộ) |
| 5 | **Trung bình** | `PlayerCard` | `queueTitleOut`/`queueTitleIn` không đối xứng và không suy ra từ nhau | Apple Music: 0.10→0.17 mở, 0.23→0.33 đóng |
| 6 | **Trung bình** | `AlbumsView`, `ArtistsView` | Lưới không có chuyển cảnh khi mở chi tiết | Photos dùng `.navigationTransition(.zoom)` từ iOS 18 |
| 7 | **Trung bình** | `ImportProgressSheet` | Thanh tiến trình nhảy từng bước, không nội suy | Files nội suy mượt giữa hai lần cập nhật |
| 8 | **Thấp** | `TapHalo` | Vệt sáng cố định 0.52s, không theo thời gian giữ | UIKit co giãn theo độ dài cú chạm |
| 9 | **Thấp** | `JamendoResultRow` | `.snappy(duration: 0.25)` là literal duy nhất ngoài `BottomBarStyle` | — (nhất quán nội bộ) |
| 10 | **Thấp** | `ProminentActionButton` | `.easeOut(duration: 0.1)` literal, gần bằng `BottomBarStyle.press` (0.09) | — (nhất quán nội bộ) |

---

## Chi tiết

### 1. Giảm chuyển động không được tôn trọng ở bất kỳ đâu — cấp Nghiêm trọng

`grep -r accessibilityReduceMotion` trả về **0 kết quả** trên toàn bộ 17.422 dòng.

Đây là yêu cầu của HIG, không phải tuỳ chọn. Người bật Giảm chuyển động thường bật vì chuyển động lớn gây chóng mặt hoặc buồn nôn — và app này có đúng loại chuyển động ấy: thẻ player phóng từ viên thuốc lên toàn màn hình, nội dung phía sau thu nhỏ 8% cùng lúc, tấm bìa tràn màn hình bay chéo về ô 60pt ở góc.

Quy ước của Apple: khi cờ bật, thay chuyển động vị trí/tỉ lệ bằng mờ dần. Cụ thể ở đây:

- `PlayerCard` — cú morph nên thành mờ dần giữa hai trạng thái, bỏ `recedeScale`
- `FloatingTabBar` — cú thu gọn nên bỏ `matchedGeometryEffect`, chỉ đổi opacity
- `TapHalo`, `TransportButtonStyle` — vệt sáng và cú nảy nên tắt
- `ReorderableStack` — cú đáp đàn hồi nên thành tuyến tính

**Chi phí sửa:** một `@Environment(\.accessibilityReduceMotion)` đọc ở `RootView`, đưa xuống qua environment, và mỗi hằng số trong `BottomBarStyle` có một biến thể phẳng. Khoảng nửa ngày.

### 2. Danh sách không có chuyển động khi dữ liệu đổi — cấp Nghiêm trọng

`SongsView.swift:237` dựng `List(tracks)` với `tracks` là `@Query`. `deleteTrack(_:)` ở dòng 342 gọi `library.delete(track)` **ngoài mọi transaction**. Không có `withAnimation` nào trên đường đi ấy, và không có `.animation(_:value:)` trên `List`.

Hệ quả: vuốt xoá một bài thì hàng biến mất và mọi hàng dưới nhảy lên trong một khung. Trong Music của Apple, hàng bị xoá co lại và những hàng dưới trượt lên theo — đó là thứ nói cho mắt biết *cái gì vừa xảy ra với cái gì*.

Cùng vấn đề ở: `DriveFoldersView.swift:204,212` (vuốt xoá thư mục), `JamendoSongsList.swift:54` (bỏ lưu), `SongsView` khi nhập nhạc xong (hàng mới xuất hiện tức thì), `SearchView.swift:56` (kết quả đổi theo từng ký tự gõ — nhảy khung một, trong khi Spotlight của Apple mờ-chuyển).

**Chi phí sửa:** một dòng cho mỗi chỗ. `withAnimation(BottomBarStyle.content) { try library.delete(track) }`, và `.animation(.default, value: results.count)` cho tìm kiếm.

### 3. Không có `.transition()` nào — cấp Cao

`grep -r "\.transition("` ngoài thư mục Prototypes: **0 kết quả**.

Mọi view xuất hiện có điều kiện đều bật/tắt tức thì. Đáng kể nhất:

- `EmptyLibraryView` ↔ danh sách bài (`SongsView.swift:235`) — nhập bài đầu tiên thì màn hình rỗng biến mất trong một khung
- `ContentUnavailableView` ở `JamendoDiscoveryView.swift:279,290,301` — ba trạng thái (đang tải / lỗi / rỗng) thay nhau tức thì
- `PlayerSubtitle` — thông báo lỗi phát nhạc thay chỗ dòng metadata không có chuyển tiếp

Apple mờ-và-nở nhẹ những chỗ này. Chưa có chuyển tiếp thì mỗi lần đổi trạng thái đọc ra như một cú giật màn hình, không như một sự thay thế.

### 4. `ReorderableStack` dùng từ vựng lò xo khác cả app — cấp Cao

`ReorderableStack.swift:150,157`:

```swift
static let part = Animation.spring(response: 0.28, dampingFraction: 0.68)
static let settleSpring = Spring(response: 0.34, dampingRatio: 0.76)
```

Cả `BottomBarStyle` dùng `duration:`/`bounce:`, và có ghi chú giải thích vì sao: cặp ấy *gọi tên thứ nó làm* — `bounce` 0 là dừng khi tới nơi, cao hơn là vọt qua rồi lùi về — còn cặp cũ đảo trục ấy, vì damping cao nghĩa là ít nảy.

Hai file dùng hai hệ đơn vị cho cùng một khái niệm. Quy đổi: `response: 0.28, dampingFraction: 0.68` ≈ `duration: 0.28, bounce: 0.32`. Không sai về hình, nhưng người đọc sau phải quy đổi trong đầu để biết cú nhường chỗ có nảy hơn `morph` (0.24) hay không — nó có, và điều đó đáng ra phải đọc thấy ngay.

### 5. Hai chiều của cú tan chữ không suy ra từ nhau — cấp Trung bình

`BottomBarStyle.swift:274,286`:

```swift
static let queueTitleOut = Animation.easeIn(duration: 0.06).delay(0.04)
static let queueTitleIn  = Animation.easeOut(duration: 0.10).delay(0.13)
```

Bốn con số độc lập cho hai chiều của **một** chuyển động. Số đo Apple Music là 0.10→0.17 khi mở và 0.23→0.33 khi đóng — bất đối xứng có chủ ý, và ghi chú trong mã nói đúng điều đó. Nhưng bản hiện tại đã trôi khỏi số đo (`delay 0.04` thay vì `0.10`), và không có gì trong mã ràng buộc chiều này với chiều kia.

Thứ tự giữa hai khối chữ đã được `completion` bảo đảm về mặt cấu trúc — đó là chỗ làm đúng. Nhưng bốn con số vẫn chỉnh tay được lệch nhau mà không ai biết.

### 6. Lưới Album/Nghệ sĩ không có chuyển cảnh sang màn chi tiết — cấp Trung bình

`AlbumsView.swift:88` và `ArtistsView.swift:66` là `LazyVGrid` trong `ScrollView`, mở chi tiết bằng `NavigationLink` mặc định — đẩy ngang.

Từ iOS 18, Photos và Music dùng `.matchedTransitionSource(id:in:)` cộng `.navigationTransition(.zoom(sourceID:in:))`: ô lưới nở ra thành màn chi tiết, và người dùng biết mình vừa mở *ô nào*. Đẩy ngang không nói điều đó.

App này đã có sẵn một bản thử của đúng API ấy — `Features/Prototypes/PlayerZoomDemoView.swift`. Nó dựng cho player rồi không dùng; chỗ nó thật sự hợp là hai lưới này.

### 7. Thanh tiến trình nhập nhạc nhảy từng bước — cấp Trung bình

`ImportProgressSheet.swift:18` là `ProgressView(value:total:)` không có `.animation(_:value:)`. Nhập 40 bài thì thanh nhảy 40 bậc rời rạc.

Apple nội suy giữa hai lần cập nhật, nên thanh trôi đều kể cả khi nguồn số nhảy cóc. Sửa bằng một dòng: `.animation(.linear(duration: 0.2), value: completed)`.

### 8. `TapHalo` không theo thời gian giữ — cấp Thấp

`TapHalo.swift:38-51` chạy một chuỗi keyframe cố định 0.52 giây bất kể ngón tay còn trên nút hay đã rời. Giữ nút Next hai giây thì vệt sáng vẫn tan sau nửa giây, để lại một nút đang bị nhấn mà không có dấu hiệu gì.

UIKit giữ vệt sáng suốt thời gian chạm rồi mới tan khi nhả. Khác biệt nhỏ, nhưng nó là loại khác biệt người ta cảm thấy mà không chỉ ra được.

### 9–10. Ba literal ngoài từ vựng chung — cấp Thấp

- `JamendoResultRow.swift:95` — `.snappy(duration: 0.25)`
- `ProminentActionButton.swift:34` — `.easeOut(duration: 0.1)`, trong khi `BottomBarStyle.press` là 0.09

Không ai thấy được chênh lệch 0.01 giây. Vấn đề là chúng nằm ngoài chỗ tập trung, nên một lần chỉnh nhịp toàn app sẽ bỏ sót chúng — đúng cách mà `BottomBarStyle` được lập ra để tránh.

---

## Những chỗ đã vượt chuẩn, giữ nguyên

Ghi lại để lần sửa sau không vô tình phá.

**Cú morph của player theo số đo, không theo cảm giác.** `BottomBarStyle.queue` là `Spring(duration: 0.31, bounce: 0)`, khớp `1 − (1+ωt)·e^(−ωt)` với ω ≈ 20.3 rad/s trong hai phần trăm ở cả bảy khung đo được từ Apple Music. Rất hiếm khi thấy một hằng số animation có xuất xứ như vậy.

**Thứ tự hai pha bảo đảm bằng cấu trúc.** `PlayerCard` nối cú tan của khối chữ lớn với cú hiện của panel bằng `withAnimation(_:completion:)` thay vì bằng hai `delay` phải cộng cho khớp. Bất đẳng thức `delay₂ ≥ delay₁ + duration₁` không nằm ở đâu trong mã được thì nó sẽ vỡ, và nó đã vỡ vài lần trước khi được nối lại như vậy.

**Cử chỉ kéo thả chạy bằng recogniser UIKit.** `ReorderableStack` dùng hai `UILongPressGestureRecognizer` cho cả danh sách thay vì `LongPressGesture.sequenced(before:)` trên từng hàng. `allowableMovement` là thứ SwiftUI không phơi ra, và nó mới là cái quyết định cú giữ có ổn định hay không.

**Thứ tự chỉ đổi sau khi hàng đã bay tới nơi.** Đổi mảng ngay lúc thả thì `LazyVStack` dời hàng *đồng thời* `dragOffset` tan về 0 — hai đại lượng cộng vào nhau, và đo được là hàng giật ngược 24 điểm ở khung ngay sau khi nhả tay.

**Vệt sáng mang hình của chính cái nút.** `TapHalo` nhận một `AnyShape` thay vì luôn dùng `Circle`, nên vệt sáng dưới viên thuốc shuffle là hình viên thuốc.

---

## Thứ tự đề xuất

1. **Giảm chuyển động** (#1) — yêu cầu accessibility, và là thứ duy nhất trong bảng có thể chặn duyệt App Store.
2. **Chuyển động cho danh sách** (#2, #3) — tác động lớn nhất trên mỗi dòng mã sửa. Mười bốn màn hình đang tĩnh hoàn toàn.
3. **Thống nhất từ vựng** (#4, #9, #10) — rẻ, và nó là điều kiện để lần chỉnh nhịp sau không sót chỗ nào.
4. **Chuyển cảnh zoom cho lưới** (#6) — bản thử đã có sẵn.
5. Phần còn lại theo thứ tự tiện tay.

---

## Ghi chú về phương pháp

Hai kết luận trong tài liệu này đến từ số đo chứ không từ đọc mã, và cả hai đều **ngược với** giả thuyết ban đầu của người viết:

- Giả thuyết "bốn lớp blur sống làm GPU quá tải" **sai**. Sửa một cú ghi SwiftData đồng bộ trên main thread làm thời gian GPU giảm 65% mà không đụng tới lớp blur nào — GPU không tự quá tải, nó đang chạy theo main thread.
- Con số hitch tính trên 45 giây ghi hình **sai lệch nặng** nếu app có lúc không vẽ. Một phiên đo cho ra 11.1 ms/giây trông như đã đạt, trong khi app chỉ vẽ 6 trên 45 giây; chuẩn hoá theo số giây thật sự có vẽ thì con số là 83.

Bất kỳ ai đọc tiếp tài liệu này nên chuẩn hoá theo bảng `displayed-surfaces-per-second` trước khi tin một con số hitch nào.
