# I1 — Hoãn dựng `NowPlayingContent`: **cổng chặn trượt, đã vứt bản sửa**

**Trạng thái: `DONE_WITH_CONCERNS`. Không commit. `PlayerCard.swift` nguyên
trạng, cây làm việc sạch, `git diff HEAD` rỗng.**

Tổng chi phí một cú mở **giảm 27,3% / 21,8% / 26,6%** qua ba lần chạy xen kẽ —
vế thứ nhất của cổng chặn đạt thoải mái. Vế thứ hai trượt: cú dựng dồn vào **một
khung** ở cuối cú morph, **13–21ms trên mỗi lần mở**, và ở lần chạy thứ ba nó
**cao hơn cả đỉnh hiện tại** (17,876ms so với 16,117ms, tỉ lệ 1,11×).

Đó đúng là cái bẫy brief đã gọi tên. Đã làm theo brief: vứt bản sửa, báo số.

---

## 1. Điều phải kiểm trước: `NowPlayingContent` có luôn ở trong cây không?

**Có. Xác nhận được, và chú thích ở `RootView.swift` nói đúng.**

`Evenstar/Evenstar/Features/Player/PlayerCard.swift:1239` — trong `ZStack` của
`card(size:insets:)`:

```swift
expandedContent(size: cardSize, topInset: insets.top)
    .environment(\.colorScheme, .dark)
```

Không có `if`, không có `opacity`-gated branch, không có gì. Đếm bằng máy: khối
`ZStack` từ dòng 1213 tới 1242 có **0** lần xuất hiện của `if `. Thứ duy nhất gác
nó nằm ở `expandedContent` (dòng 1737–1738):

```swift
.opacity(max(0, (progress - 0.5) * 2))
.allowsHitTesting(progress > 0.9)
```

Cả hai đều là *modifier*, không phải cấu trúc. Nên `NowPlayingContent` — khối
chữ, `ScrubberBar`, hàng transport, `SystemVolumeSlider` (một `MPVolumeView` bọc
trong `UIViewRepresentable`), hàng repeat — **nằm trong cây view ở mọi
`progress`, kể cả khi thẻ đang thu gọn thành viên thuốc 54pt**. SwiftUI đánh giá
nó ở mọi lượt cập nhật, cho một thứ có độ mờ đúng bằng 0.

Suy ra của brief đúng: cái giá 26% ấy đang được trả cả ở trạng thái thu gọn.
Phép đo bên dưới xác nhận thêm — xem cột "after" ở các khung 33–59, nơi thẻ đã
đứng yên: 0,6–1,4ms so với 0,7–1,9ms, tức phần chi phí lúc rảnh cũng có thật.

---

## 2. Thiết kế, và những gì đã bác bỏ

### Tín hiệu "chưa tới đích"

Hai vế, vì hai đường đi có hai cơ chế khác nhau:

```swift
static func expandedChromeIsMounted(progress: Double, morphInFlight: Bool) -> Bool {
    guard !morphInFlight else { return false }
    return progress > expandedContentFadeStart   // 0.5
}
```

- `morphInFlight` — một `Bool` `@State`, bật trong `withAnimation` của
  `morph(to:curve:)`, hạ ở `completion:` của chính animation ấy. Lo **đường
  animation**, nơi `body` chạy đúng một lần và `progress` trong `body` đã là
  đích ngay từ khung đầu, nên mọi phép thử trên `progress` đều mù.
- `progress > 0.5` — lo **đường ngón tay**, nơi `dragDelta` được ghi mỗi khung
  nên `body` chạy thật. Mốc 0,5 trùng đúng chỗ `.opacity(max(0, (progress −
  0.5) × 2))` rời khỏi 0, nên chrome được dựng đúng khung nó bắt đầu hiện.

### Bốn thứ đã cân nhắc và bác bỏ

1. **`Animatable` để đọc giá trị đang vẽ** — brief cấm, và có lý do trong repo:
   `b8a94d6` làm đúng thế, thêm một lượt `body` mỗi khung, và đã bị revert ở
   `b14ad5d`. Không đụng tới.
2. **`progress > 0 && progress < 1`** — chỉ bắt được đường kéo. Đã nêu ở brief;
   xác nhận lại từ mã: `progress` là computed từ `settled`, mà `settled` nhảy
   thẳng tới đích trong `withAnimation`.
3. **Hoãn ở *mọi* hướng morph** — thử trên giấy rồi bỏ. Ba trường hợp hỏng:
   - *chiều đóng*: chrome bị tháo tức thì khi thẻ vẫn đang tràn màn hình → chớp.
   - *cú đáp về 1 từ nửa trên* (kéo xuống một đoạn rồi thả, thẻ bật lại): chrome
     đang nhìn thấy được ở độ mờ ~0,5, hoãn ở đây là tháo ra rồi gắn lại giữa
     màn hình.
   - *cú đáp về 0*: `progress` về 0 nên `if` tự tháo, đặt cờ không thêm gì.

   Bản đã đo vì thế chỉ hoãn khi `target > 0.5` **và** chrome đang chưa dựng.
   Chiều đóng để cú tháo nằm trong `withAnimation` và nhận transition mặc định,
   nên nó tan theo đúng đường cong — đóng player trông như cũ.
4. **Nhánh Giảm chuyển động** — không đụng một dòng. Ở đó hình học nhảy thẳng
   trong `Transaction(animation: nil)` nên `progress` đã là 1 ngay lập tức và
   `if` dựng chrome ngay; đặt `morphInFlight` ở đó sẽ tháo chrome ra suốt 0,37s
   của cú hoà mờ `cardOpacity` — đúng thứ nhánh ấy tồn tại để tránh.

### Một chi tiết phải làm đúng: con dấu thế hệ

`withAnimation(_:completion:)` gọi completion **cả khi animation bị cắt ngang**.
Không có con dấu thì completion của cú morph cũ hạ cờ của cú morph mới và chrome
dựng lại giữa đường. Bản đã đo dùng `morphGeneration` (`Int`, tăng dần, so
bằng); `drag(...).onChanged` cũng hạ cờ (có rào `if morphInFlight` giống hệt
`isDragging` ngay trên) để ngón tay thắng cú morph đang bay.

### Bộ đo

Một công tắc runtime tạm `PlayerCard.abDeferChrome` gác đúng một chỗ —
`expandedChromeIsMounted` trả `true` vô điều kiện khi tắt, tức hành vi cũ *chính
xác*, và `morph` cũng tự trung hoà theo vì nó gọi chính hàm ấy để tính
`deferChrome`. Một file test tạm `EvenstarTests/TempChromeDeferAB.swift` đo A/B
**đan xen trong một tiến trình** theo đúng bài học của h1 (vòng ngoài là lần
lặp, vòng trong là cấu hình), 9 lần mount mỗi cấu hình, và **đảo thứ tự hai cấu
hình ở các lần lặp lẻ** để một cú trôi kiểu "cái đo sau rẻ hơn" không đội lốt
được tác dụng.

**60 khung chứ không phải 40 của h1.** `BottomBarStyle.expandFull` là
`spring(duration: 0.52, bounce: 0.12)`; cửa sổ 40 khung = 667ms *có* chứa mốc
520ms, nhưng 60 khung = 1000ms cho thấy rõ cả phần đuôi sau cú dựng. Đây là điểm
mấu chốt: **một cửa sổ không nhìn thấy được cái gai thì không trả lời được câu
hỏi bộ đo này tồn tại để trả lời.**

Cả công tắc lẫn file test tạm **đã bị xoá**. Kiểm lại bằng `git status` (rỗng),
`git diff HEAD` (rỗng) và `grep` ba định danh `abDeferChrome` /
`morphInFlight` / `expandedChromeIsMounted` trong `PlayerCard.swift` (0 lần).

---

## 3. Ba lần chạy xen kẽ, verbatim

Ba lần gọi `xcodebuild` độc lập, `-parallel-testing-enabled NO` (mặc định
xcodebuild chạy trên một **clone** của simulator và container của clone bị xoá
mất cùng file log — lần chạy đầu tiên mất số vì lý do này).

### Tổng và đỉnh

```
[ab] TOTAL 60 frames: before 149.837ms, after 108.961ms, delta -27.3%
[ab] TOTAL 40 frames: before 126.992ms, after  83.765ms, delta -34.0%
[ab] PEAK before 15.205ms at frame 0; after 12.892ms at frame 0; ratio 0.85x
[ab] WORST single frame across all mounts: before 68.830ms, after 25.258ms

[ab] TOTAL 60 frames: before 162.378ms, after 127.013ms, delta -21.8%
[ab] TOTAL 40 frames: before 137.879ms, after 102.090ms, delta -26.0%
[ab] PEAK before 16.678ms at frame 0; after 15.206ms at frame 32; ratio 0.91x
[ab] WORST single frame across all mounts: before 55.867ms, after 23.075ms

[ab] TOTAL 60 frames: before 133.289ms, after  97.808ms, delta -26.6%
[ab] TOTAL 40 frames: before 105.213ms, after  75.853ms, delta -27.9%
[ab] PEAK before 16.117ms at frame 0; after 17.876ms at frame 32; ratio 1.11x
[ab] WORST single frame across all mounts: before 85.072ms, after 20.843ms
```

Ba lần: **−27,3% / −21,8% / −26,6%** trên cửa sổ 60 khung, **−34,0% / −26,0% /
−27,9%** trên cửa sổ 40 khung của h1. Sàn nhiễu đo được của bộ đo này là ±5 điểm
phần trăm, nên phần giảm là **thật và phân giải rõ** — và nó khớp đẹp với con số
−26,2/−23,1/−30,5% mà h1 đo được khi *tắt hẳn* `NowPlayingContent`. Tức việc hoãn
dựng thu về gần trọn phần chi phí ấy.

---

## 4. Đường cong theo từng khung — và cái gai

### Lần chạy 1, verbatim

```
[ab] === per-frame commit, median of 9 mounts, ms ===
[ab] frame 00  t=   0.0ms  before 15.205ms  after 12.892ms
[ab] frame 01  t=  16.7ms  before 0.901ms  after 0.872ms
[ab] frame 02  t=  33.3ms  before 1.642ms  after 1.487ms
[ab] frame 03  t=  50.0ms  before 1.681ms  after 1.825ms
[ab] frame 04  t=  66.7ms  before 1.673ms  after 2.335ms
[ab] frame 05  t=  83.3ms  before 3.099ms  after 2.374ms
[ab] frame 06  t= 100.0ms  before 2.742ms  after 1.972ms
[ab] frame 07  t= 116.7ms  before 1.705ms  after 1.980ms
[ab] frame 08  t= 133.3ms  before 2.112ms  after 1.694ms
[ab] frame 09  t= 150.0ms  before 2.227ms  after 1.988ms
[ab] frame 10  t= 166.7ms  before 2.531ms  after 2.115ms
[ab] frame 11  t= 183.3ms  before 2.954ms  after 2.305ms
[ab] frame 12  t= 200.0ms  before 2.114ms  after 2.256ms
[ab] frame 13  t= 216.7ms  before 3.595ms  after 2.010ms
[ab] frame 14  t= 233.3ms  before 3.882ms  after 1.822ms
[ab] frame 15  t= 250.0ms  before 3.427ms  after 2.150ms
[ab] frame 16  t= 266.7ms  before 3.892ms  after 1.857ms
[ab] frame 17  t= 283.3ms  before 3.744ms  after 1.678ms
[ab] frame 18  t= 300.0ms  before 3.081ms  after 1.761ms
[ab] frame 19  t= 316.7ms  before 2.566ms  after 1.506ms
[ab] frame 20  t= 333.3ms  before 2.664ms  after 1.879ms
[ab] frame 21  t= 350.0ms  before 2.337ms  after 1.865ms
[ab] frame 22  t= 366.7ms  before 2.320ms  after 2.060ms
[ab] frame 23  t= 383.3ms  before 2.570ms  after 1.846ms
[ab] frame 24  t= 400.0ms  before 2.449ms  after 1.710ms
[ab] frame 25  t= 416.7ms  before 2.268ms  after 1.645ms
[ab] frame 26  t= 433.3ms  before 2.380ms  after 1.933ms
[ab] frame 27  t= 450.0ms  before 2.366ms  after 1.621ms
[ab] frame 28  t= 466.7ms  before 1.929ms  after 1.505ms
[ab] frame 29  t= 483.3ms  before 2.502ms  after 1.213ms
[ab] frame 30  t= 500.0ms  before 2.687ms  after 1.692ms
[ab] frame 31  t= 516.7ms  before 2.093ms  after 0.969ms
[ab] frame 32  t= 533.3ms  before 1.768ms  after 10.697ms   <<<
[ab] frame 33  t= 550.0ms  before 1.548ms  after 1.482ms
[ab] frame 34  t= 566.7ms  before 1.637ms  after 0.789ms
[ab] frame 35  t= 583.3ms  before 1.597ms  after 0.840ms
[ab] frame 36  t= 600.0ms  before 1.865ms  after 0.926ms
[ab] frame 37  t= 616.7ms  before 1.625ms  after 1.600ms
[ab] frame 38  t= 633.3ms  before 1.667ms  after 1.294ms
[ab] frame 39  t= 650.0ms  before 1.819ms  after 2.023ms
[ab] frame 40  t= 666.7ms  before 1.706ms  after 1.826ms
[ab] frame 41  t= 683.3ms  before 1.458ms  after 1.412ms
[ab] frame 42  t= 700.0ms  before 2.046ms  after 1.142ms
[ab] frame 43  t= 716.7ms  before 2.125ms  after 0.975ms
[ab] frame 44  t= 733.3ms  before 2.105ms  after 1.075ms
[ab] frame 45  t= 750.0ms  before 1.734ms  after 1.209ms
[ab] frame 46  t= 766.7ms  before 1.980ms  after 1.591ms
[ab] frame 47  t= 783.3ms  before 1.846ms  after 1.419ms
[ab] frame 48  t= 800.0ms  before 2.118ms  after 1.736ms
[ab] frame 49  t= 816.7ms  before 1.478ms  after 1.854ms
[ab] frame 50  t= 833.3ms  before 1.323ms  after 1.919ms
[ab] frame 51  t= 850.0ms  before 1.624ms  after 1.819ms
[ab] frame 52  t= 866.7ms  before 1.206ms  after 1.183ms
[ab] frame 53  t= 883.3ms  before 1.153ms  after 1.038ms
[ab] frame 54  t= 900.0ms  before 1.113ms  after 1.070ms
[ab] frame 55  t= 916.7ms  before 0.904ms  after 1.013ms
[ab] frame 56  t= 933.3ms  before 0.911ms  after 0.987ms
[ab] frame 57  t= 950.0ms  before 0.578ms  after 0.941ms
[ab] frame 58  t= 966.7ms  before 0.684ms  after 1.058ms
[ab] frame 59  t= 983.3ms  before 0.761ms  after 1.132ms
```

### Lần chạy 2, quanh cái gai

```
[ab] frame 28  t= 466.7ms  before 2.554ms  after 1.892ms
[ab] frame 29  t= 483.3ms  before 3.283ms  after 1.625ms
[ab] frame 30  t= 500.0ms  before 2.700ms  after 2.106ms
[ab] frame 31  t= 516.7ms  before 2.569ms  after 1.407ms
[ab] frame 32  t= 533.3ms  before 2.197ms  after 15.206ms   <<<
[ab] frame 33  t= 550.0ms  before 2.123ms  after 0.963ms
[ab] frame 34  t= 566.7ms  before 2.743ms  after 1.071ms
[ab] frame 35  t= 583.3ms  before 2.833ms  after 1.080ms
[ab] frame 36  t= 600.0ms  before 2.560ms  after 1.664ms
[ab] frame 37  t= 616.7ms  before 2.452ms  after 1.436ms
[ab] frame 38  t= 633.3ms  before 1.753ms  after 1.595ms
```

### Lần chạy 3, verbatim

```
[ab] === per-frame commit, median of 9 mounts, ms ===
[ab] frame 00  t=   0.0ms  before 16.117ms  after 10.143ms
[ab] frame 01  t=  16.7ms  before 0.658ms  after 1.219ms
[ab] frame 02  t=  33.3ms  before 2.220ms  after 1.527ms
[ab] frame 03  t=  50.0ms  before 1.698ms  after 1.411ms
[ab] frame 04  t=  66.7ms  before 2.074ms  after 1.202ms
[ab] frame 05  t=  83.3ms  before 2.074ms  after 1.425ms
[ab] frame 06  t= 100.0ms  before 2.704ms  after 1.644ms
[ab] frame 07  t= 116.7ms  before 2.048ms  after 1.344ms
[ab] frame 08  t= 133.3ms  before 2.535ms  after 1.269ms
[ab] frame 09  t= 150.0ms  before 2.191ms  after 1.476ms
[ab] frame 10  t= 166.7ms  before 2.558ms  after 1.286ms
[ab] frame 11  t= 183.3ms  before 2.177ms  after 1.240ms
[ab] frame 12  t= 200.0ms  before 2.275ms  after 1.369ms
[ab] frame 13  t= 216.7ms  before 2.280ms  after 1.171ms
[ab] frame 14  t= 233.3ms  before 2.060ms  after 1.380ms
[ab] frame 15  t= 250.0ms  before 2.549ms  after 1.397ms
[ab] frame 16  t= 266.7ms  before 2.520ms  after 1.447ms
[ab] frame 17  t= 283.3ms  before 2.271ms  after 1.305ms
[ab] frame 18  t= 300.0ms  before 2.510ms  after 1.331ms
[ab] frame 19  t= 316.7ms  before 2.187ms  after 1.125ms
[ab] frame 20  t= 333.3ms  before 2.185ms  after 1.552ms
[ab] frame 21  t= 350.0ms  before 2.327ms  after 1.584ms
[ab] frame 22  t= 366.7ms  before 2.194ms  after 1.479ms
[ab] frame 23  t= 383.3ms  before 2.342ms  after 1.329ms
[ab] frame 24  t= 400.0ms  before 2.829ms  after 1.372ms
[ab] frame 25  t= 416.7ms  before 2.620ms  after 1.558ms
[ab] frame 26  t= 433.3ms  before 3.036ms  after 1.459ms
[ab] frame 27  t= 450.0ms  before 2.759ms  after 1.466ms
[ab] frame 28  t= 466.7ms  before 2.102ms  after 1.398ms
[ab] frame 29  t= 483.3ms  before 2.240ms  after 1.588ms
[ab] frame 30  t= 500.0ms  before 2.289ms  after 1.873ms
[ab] frame 31  t= 516.7ms  before 2.287ms  after 1.320ms
[ab] frame 32  t= 533.3ms  before 1.877ms  after 17.876ms   <<<
[ab] frame 33  t= 550.0ms  before 1.868ms  after 1.022ms
[ab] frame 34  t= 566.7ms  before 1.718ms  after 1.048ms
[ab] frame 35  t= 583.3ms  before 1.939ms  after 1.393ms
[ab] frame 36  t= 600.0ms  before 1.687ms  after 1.372ms
[ab] frame 37  t= 616.7ms  before 1.672ms  after 1.355ms
[ab] frame 38  t= 633.3ms  before 1.564ms  after 1.435ms
[ab] frame 39  t= 650.0ms  before 1.847ms  after 1.660ms
[ab] frame 40  t= 666.7ms  before 1.774ms  after 1.270ms
[ab] frame 41  t= 683.3ms  before 1.671ms  after 1.149ms
[ab] frame 42  t= 700.0ms  before 1.807ms  after 1.243ms
[ab] frame 43  t= 716.7ms  before 1.658ms  after 1.152ms
[ab] frame 44  t= 733.3ms  before 1.697ms  after 1.143ms
[ab] frame 45  t= 750.0ms  before 1.671ms  after 1.214ms
[ab] frame 46  t= 766.7ms  before 1.592ms  after 1.221ms
[ab] frame 47  t= 783.3ms  before 1.585ms  after 1.170ms
[ab] frame 48  t= 800.0ms  before 1.591ms  after 1.220ms
[ab] frame 49  t= 816.7ms  before 1.670ms  after 1.149ms
[ab] frame 50  t= 833.3ms  before 1.683ms  after 1.097ms
[ab] frame 51  t= 850.0ms  before 1.679ms  after 1.158ms
[ab] frame 52  t= 866.7ms  before 1.058ms  after 0.603ms
[ab] frame 53  t= 883.3ms  before 0.870ms  after 0.614ms
[ab] frame 54  t= 900.0ms  before 0.952ms  after 0.536ms
[ab] frame 55  t= 916.7ms  before 0.908ms  after 0.615ms
[ab] frame 56  t= 933.3ms  before 0.676ms  after 0.580ms
[ab] frame 57  t= 950.0ms  before 0.683ms  after 0.615ms
[ab] frame 58  t= 966.7ms  before 0.684ms  after 0.618ms
[ab] frame 59  t= 983.3ms  before 0.722ms  after 0.631ms
```

### Đọc ba đường cong này

**Hình dạng đúng như hy vọng, ở mọi khung trừ một khung.** Từ khung 1 tới khung
31 đường "after" nằm dưới đường "before" gần như đều đặn — 1,1–1,6ms so với
2,0–3,0ms ở lần chạy 3 — và nó *còn thấp hơn* ở phần đuôi sau khi thẻ đã đứng
yên, tức phần chi phí ở trạng thái nghỉ mà mục 1 nói tới cũng biến mất thật.

**Rồi có khung 32.**

| lần chạy | khung 32, before | khung 32, after | so với hàng xóm (after) | so với đỉnh before |
|---|---|---|---|---|
| 1 | 1,768ms | **10,697ms** | 6,0× khung 31 | 0,70× |
| 2 | 2,197ms | **15,206ms** | 10,8× khung 31 | 0,91× |
| 3 | 1,877ms | **17,876ms** | 13,5× khung 31 | **1,11×** |

Khung 32 là t = 533,3ms. `BottomBarStyle.expandFull` là
`spring(duration: 0.52, bounce: 0.12)`. Cái gai rơi vào đúng khung đầu tiên sau
khi `withAnimation`'s completion nổ, xuất hiện ở **cả ba lần chạy**, ở **cả chín
lần mount của mỗi lần chạy**, và **không có ở một lần mount nào** của cấu hình
cũ. Đó là cú dựng `NowPlayingContent` bị dồn vào một khung. Không còn gì phải
suy đoán.

---

## 5. Áp cổng chặn

Cổng chặn có hai vế, nối bằng **và**:

> tổng chi phí một cú mở giảm ít nhất 15% qua ít nhất ba lần chạy xen kẽ, **và**
> đường cong theo khung không có gai nào cao hơn đỉnh hiện tại.

- **Vế 1: ĐẠT.** −27,3% / −21,8% / −26,6%, cả ba đều trên 15%, cả ba đều vượt
  xa sàn nhiễu ±5pp.
- **Vế 2: TRƯỢT.** Lần chạy 3: gai ở khung 32 = **17,876ms**, đỉnh hiện tại =
  **16,117ms** (khung 0). Tỉ lệ **1,11×**. Một gai cao hơn đỉnh hiện tại.

**Và đọc chặt hơn thì nó trượt ở cả ba lần chạy.** "Đỉnh hiện tại" ở lần 1 và
lần 2 là **khung 0** — khung đầu tiên sau cú chạm, nơi `currentTrack` chuyển
khỏi `nil`, thẻ bắt đầu hoà vào, `.task` giải mã bìa nổ, và cây view của thẻ
được dựng lần đầu. Nó đắt vì lý do riêng của nó, không phải vì cú morph. Nếu so
cái gai với **đỉnh của phần morph** — tức max của các khung 1…59 ở đường
"before", là 3,892 / 3,283 / 3,036ms — thì cái gai cao hơn **2,7× / 4,6× /
5,9×**. Bản sửa này chỉ "không tạo đỉnh mới" nhờ mượn một khung đắt sẵn vì
chuyện khác làm mốc so sánh, và ở lần chạy thứ ba thì cái cớ ấy cũng hết.

Không chỉnh cổng chặn. Không đi tìm thiết kế thứ hai để lách qua. **Đã vứt bản
sửa.**

### Vì sao không có thiết kế thứ hai để thử

Brief cho phép thử bản thứ hai nếu nói rõ và đo nó. Đã cân nhắc và **không thử**,
vì cả ba lối đều đã bị chặn từ trước:

- **Dựng sớm hơn, giữa cú morph** — cần biết cú morph đang ở đâu, mà trên đường
  chạm chỉ có `animatableData` nói được điều đó. Brief cấm, và repo đã revert
  đúng cách ấy một lần (`b14ad5d`).
- **Dựng theo một đồng hồ riêng** (`asyncAfter` ở ~40% đường cong) — chỉ *dời*
  cái gai vào giữa cú morph, nơi ngân sách cũng chặt y hệt, và thêm một đồng hồ
  thứ hai trên cùng một vật — đúng cái mà `queueTitleTravel` và `queueFactor` đã
  ghi lại là sai lầm.
- **Chẻ `NowPlayingContent` để chỉ hoãn phần đắt** — phải sửa
  `NowPlayingContent.swift`, ngoài phạm vi brief cho phép, và là một đợt riêng.

Cái gai **là** chi phí dựng. Hoãn dựng thì phải trả nó ở đâu đó, và chỉ có một
khung để trả. Đây không phải một bản cài đặt vụng; nó là hình dạng của chính ý
tưởng.

---

## 6. Lớp làm nóng: hoá đơn 56ms có quay lại không?

**Không. Đo, không đoán.** Cột "after" của cửa sổ completion, tách theo từng lần
mount, lần chạy 3:

```
[ab] completion-window max, mount 0: before 2.511ms  after 15.937ms
[ab] completion-window max, mount 1: before 2.226ms  after 20.843ms
[ab] completion-window max, mount 2: before 3.274ms  after 14.237ms
[ab] completion-window max, mount 3: before 3.126ms  after 19.814ms
[ab] completion-window max, mount 4: before 3.389ms  after 15.756ms
[ab] completion-window max, mount 5: before 2.372ms  after 20.598ms
[ab] completion-window max, mount 6: before 3.368ms  after 19.248ms
[ab] completion-window max, mount 7: before 3.560ms  after 17.876ms
[ab] completion-window max, mount 8: before 4.252ms  after 13.115ms
```

Lần mount **0** (13–16ms) không lớn hơn các lần sau (13–21ms). Nếu hoá đơn
vẽ-lần-đầu quay lại thì mount 0 phải nổi hẳn lên. Nó không. Kết luận: cái giá
15–20ms/lần mở là **chi phí dựng lại cây view, không phải chi phí rasterize lần
đầu** — glyph cache, material cache và `ArtworkStore` đều là cache theo *tiến
trình* và sống sót qua việc tháo/gắn view.

Cùng câu trả lời từ phía khác — khung 0 theo từng lần mount, lần chạy 3:

```
[ab] frame 0, mount 0: before 85.072ms  after 10.143ms
[ab] frame 0, mount 1: before 14.722ms  after  9.799ms
[ab] frame 0, mount 2: before 18.829ms  after  6.386ms
[ab] frame 0, mount 3: before 12.181ms  after  6.887ms
[ab] frame 0, mount 4: before 16.422ms  after 11.159ms
[ab] frame 0, mount 5: before  8.991ms  after 13.124ms
[ab] frame 0, mount 6: before 16.117ms  after 11.071ms
[ab] frame 0, mount 7: before 14.403ms  after 12.219ms
[ab] frame 0, mount 8: before 17.151ms  after  5.911ms
```

85,072ms ở mount 0 của cấu hình cũ là hoá đơn một-lần của cả tiến trình (chữ ký
giống hệt con số 56ms mà `RootView` ghi lại), và nó xuất hiện đúng một lần.

**Hệ quả cho `RootView`:** nếu bản sửa này từng được nhận, lớp làm nóng ở
`RootView.swift:318` sẽ **quan trọng hơn** chứ không kém đi — vì `PlayerCard` sẽ
không còn giữ `NowPlayingContent` trong cây lúc nghỉ, nên nó là chỗ *duy nhất*
trả hoá đơn ấy. Đã giữ nguyên, không sửa `RootView.swift` một dòng nào.

---

## 7. Kiểm tra đột biến

Không có test nào được thêm vào bản commit, vì **không có bản commit**. Test
tạm `TempChromeDeferABTests` không phải một test kiểm tính đúng — nó là một bộ
đo — nhưng nó *đã* được kiểm đúng cái nó cần được kiểm:

- **Nó có phân biệt được hai cấu hình không?** Có, và bằng số: hai cột lệch nhau
  22–27% trên tổng, và lệch một trời một vực ở khung 32 (1,8 so với 17,9ms).
  Đây đúng là cách hỏng mà h1 mô tả — "một bộ đo đã ngừng nhìn thấy sẽ báo mọi
  cấu hình rẻ như nhau" — và nó không hỏng theo cách ấy.
- **Công tắc có thật sự tắt được không?** Có. `PlayerCard.abDeferChrome = false`
  làm `expandedChromeIsMounted` trả `true` vô điều kiện, và cái gai ở khung 32
  **biến mất hoàn toàn** ở mọi lần mount của cấu hình ấy. Nếu công tắc không nối
  vào gì, hai cột phải giống nhau. Chúng không giống nhau.
- **Đảo thứ tự có đổi kết quả không?** Không. Thứ tự hai cấu hình đảo ở các lần
  lặp lẻ, và dấu của kết quả giữ nguyên qua cả ba lần chạy.

Nếu bản sửa từng được commit, test kiểm tính đúng đi kèm sẽ là test cho hàm
thuần `expandedChromeIsMounted(progress:morphInFlight:)` (theo đúng khuôn
`morphNeedsFade`, cũng là `static` thuần vì cùng lý do) — nó đỏ được bằng cách
đổi `>` thành `>=` ở mốc 0,5, bằng cách bỏ `guard !morphInFlight`, hoặc bằng
cách trả `true` vô điều kiện. Không viết, vì mã sản phẩm mà nó kiểm không tồn
tại nữa.

---

## 8. Toàn bộ suite, trên cây đã hoàn nguyên

```
xcodebuild -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

```
Executed 540 tests, with 6 tests skipped and 0 failures (0 unexpected) in 131.091 (131.259) seconds
** TEST SUCCEEDED **
```

540 test, 534 pass, 0 fail, 6 skip — **đúng bằng con số h1 ghi lại**, tức cây đã
về đúng chỗ cũ.

```
$ git status --short
$ git diff --stat HEAD
$ grep -c "abDeferChrome\|morphInFlight\|expandedChromeIsMounted" .../PlayerCard.swift
0
```

---

## 9. Những thứ để ý mà không sửa

1. **Bảng xếp hạng của h1 đúng, và mạnh hơn h1 dám nói.** h1 đo "tắt hẳn
   `NowPlayingContent`" ra −26,2/−23,1/−30,5%. Ở đây, chỉ *hoãn dựng* nó — vẫn
   dựng, chỉ muộn hơn — đã thu về −27,3/−21,8/−26,6%. Hai bộ đo khác nhau, hai
   cơ chế khác nhau, cùng một khoảng. Điều đó **xác nhận độc lập** rằng
   `NowPlayingContent` là ~25% chi phí một cú mở, và nó không phải chi phí *vẽ*
   mà là chi phí **giữ trong cây và đánh giá lại**.

2. **Phần chi phí lúc thẻ đứng yên là có thật và đo được.** h1 để ngỏ câu này
   ("có thứ vẫn đang được tính lại sau khi cú morph đã kết thúc"; giới hạn 2 nói
   nó là chi phí biên của một lượt cập nhật bị ép, không phải chi phí lúc rảnh).
   Ở đây các khung 40–59 — thẻ đã đứng yên ở `progress = 1` từ lâu — đo ra
   1,6–1,8ms cũ so với 1,1–1,2ms mới ở lần chạy 3, đều đặn qua 20 khung. Tức
   `NowPlayingContent` chiếm **~30% chi phí một lượt cập nhật của tấm thẻ đang
   đứng yên**. Vẫn là chi phí biên, không phải chi phí lúc rảnh — nhưng nó nói
   rằng thứ đắt không gắn với chuyển động.

3. **Khung 0 là khung đắt nhất của cả cú mở, và chưa ai đo nó.** 12–18ms trung
   vị, gấp 6–8 lần khung đắt thứ nhì, ở **cả hai** cấu hình. Trên thiết bị ngân
   sách là 16,67ms. Đó có thể là khung rớt đầu tiên và không thành phần nào
   trong bảng của h1 giải thích nó — nó là cú dựng cây view lần đầu cộng cú hoà
   `cardOpacity` cộng `.task` giải mã bìa, tất cả trong một lượt. Nếu có đợt
   sau, đây là chỗ đáng đo trước bảy lớp gradient còn lại.

4. **`spring(duration: 0.52)` nhưng thẻ tới đích ở ~367ms** (bảng travel của
   h1), rồi completion nổ ở 533ms. Tức có **166ms** mà thẻ đã đứng yên trên màn
   hình nhưng animation chưa "xong" theo SwiftUI. Bất kỳ thiết kế nào sau này
   treo việc vào `completion:` đều thừa hưởng độ trễ ấy — và với `.removed` (mặc
   định) nó có thể còn dài hơn. `.logicallyComplete` sẽ sớm hơn, nhưng không đủ
   sớm để cứu bản sửa này: nó chỉ dời cái gai vào giữa cú morph.

5. **Bộ đo của h1 chạy trên clone simulator thì mất file log.** `xcodebuild`
   mặc định bật parallel testing, chạy trên "Clone 1 of iPhone 17 Pro", và
   container của clone bị xoá cùng file. Cần `-parallel-testing-enabled NO` để
   đọc được `commit-cost-measurements.txt`. Đây là một cái bẫy sẽ cắn người
   tiếp theo dùng bộ đo ấy; đáng thêm một dòng vào doc của `CommitProbe.log`,
   nhưng đợt này không được sửa file đó nên chỉ ghi ra đây.

---

## 10. Nếu ai đó muốn thử lại khu vực này

Đường đi hứa hẹn **không phải** hoãn dựng. Số đo nói rõ: giữ
`NowPlayingContent` trong cây tốn ~25% một cú mở và ~30% một lượt cập nhật lúc
đứng yên, còn dựng nó tốn ~15–20ms trong một khung. Cả hai đều thật. Việc phải
làm là **làm cho chính nó rẻ đi**, chứ không phải chọn xem trả tiền lúc nào —
tức mở `NowPlayingContent.swift` ra và hỏi cái gì trong đó tốn 15ms để dựng
(`SystemVolumeSlider` bọc một `MPVolumeView`, `ScrubberBar`, và bốn `@State`
đếm chạm là những chỗ đáng nhìn trước). Đó là một đợt khác, với một phạm vi
khác.

Đây là lần thứ năm ở khu vực này mà một giả thuyết nghe rất hợp lý hoá ra sai.
Khác biệt lần này: nó chết trước khi tới tay người dùng, và chết bằng số.
