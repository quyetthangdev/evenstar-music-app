# H1 — Bộ đo chi phí commit của `PlayerCard`, và bảng xếp hạng

**Trạng thái:** xong. Bộ đo ở `Evenstar/EvenstarTests/PlayerCardCommitCostTests.swift`,
commit `5043d08` (chỉ file test). Cây làm việc sạch; `PlayerCard.swift` không đổi
một dòng nào. Toàn bộ suite: 540 test, 534 pass, 0 fail, 6 skip.

Không có đề xuất sửa nào trong báo cáo này. Chỉ số đo.

---

## 1. Bộ đo đo cái gì, và bằng chứng nó đo đúng

### Cái được đo

Mỗi mẫu là **một lượt cập nhật đầy đủ**: từ lúc state đã đổi tới lúc cây `CALayer`
đã theo kịp và đã giao cho render server.

```
setNeedsLayout() → layoutIfNeeded() → CATransaction.flush()
```

Một cú mở được lấy mẫu 40 lần, mỗi 16,67ms, tức 667ms phủ trọn cú morph 520ms.
Phần rảnh của mỗi khung được tiêu bằng `RunLoop.main.run(until:)`, **không tính
giờ**; chỉ ba dòng trên được bấm giờ.

Vì sao chia như vậy: `LivePixels` (trong `ReduceMotionSurfacesTests`) đã đo và ghi
lại rằng trong một tiến trình unit test, **run loop đẩy phần nội suy của SwiftUI đi
tới, nhưng cây layer thì không bao giờ tự cập nhật** — nó ghi một animation mà lớp
màu nằm nguyên ở khung xuất phát suốt mười ba mẫu cho tới khi ép `layoutIfNeeded()`.
Chính sự tách đôi ấy là thứ làm phép đo này khả thi: run loop lo phần "giá trị đã
đổi", `layoutIfNeeded` lo phần "layer đã đổi", nên phần sau bấm giờ được.

Cách dựng view lấy nguyên hai chi tiết chịu lực của `LivePixels.host` — cửa sổ cỡ
điện thoại thật (cửa sổ nhỏ vẫn thừa hưởng safe-area inset của màn hình và đẩy nội
dung ra khỏi chính nó) và `isHidden = false` (SwiftUI không chạy animation cho cửa
sổ không ai xem, và mọi đường cong ở đây sẽ dẹp thành giá trị đích). Copy chứ không
dùng lại, vì `LivePixels` là `private` trong file kia và mở rộng nó là sửa một file
đợt này không được đụng.

Thẻ được đo là thẻ mà trace trên máy ghi: **một bài có ảnh bìa thật** — harness ghi
một JPEG 600×600 vào Documents rồi trỏ `artworkRelativePath` vào đó, nên `hasArtwork`
đúng và mọi lớp bị nó gác (mặt nạ tan, lớp frost, dải màu trội) đều sống. Thẻ không
bìa đi một đường khác và rẻ hơn hẳn.

Mở bằng đúng đường người dùng tap: `playback.play(track, in:)` → `explicitSelections`
tăng → `expand()`. Không còn đường nào khác vào: `settled` và `dragDelta` là
`private @State`, còn `PlayerExpansion` chỉ phát ra ngoài.

### Đối chứng — và nó đã bắt được một bộ đo hỏng

Đối chứng là lớp **đầu tiên** trong file, có chủ ý: cách hỏng của một bộ đo kiểu này
không phải một con số sai mà là một con số *đều* — mọi cấu hình đều rẻ như nhau, mọi
thành phần tắt đi đều miễn phí.

Ba view qua đúng cùng một bộ đo, cùng một cú morph 40 khung:

| view | tổng 40 khung | trung vị/khung |
|---|---|---|
| `Color.blue` co giãn | 14,18ms | 0,331ms |
| 6 lớp: gradient 7 chặng + `.ultraThinMaterial` có mask + dải tint | 50,43ms | 1,105ms |
| **`PlayerCard` thật** | **124,90ms** | **3,054ms** |

3,6× rồi 2,5×. Bộ đo tách được cả ba, và nấc giữa là thứ chặn khả năng "bộ đo chỉ
đếm số lượng view" — `LayeredMorph` có sáu lớp, thẻ có hàng trăm, mà khoảng cách chỉ
2,5×.

**Bản đầu của bộ đo trượt đối chứng này, và đó là giá trị của nó.** Thiết kế đầu
tiên tiêu phần rảnh bằng vòng lặp bận (`spin(until:)`) thay vì bơm run loop, đúng
theo lý lẽ "đừng để ai lặng lẽ commit sau lưng phép đo". Kết quả: **6,751ms cho
`Color` so với 5,783ms cho sáu lớp — hình chữ nhật *chậm hơn*.** Mọi mẫu là một cú
no-op: không có run loop thì animation không nhích, nên tới lúc bấm giờ không còn gì
để cập nhật. Nếu không có đối chứng, cả bảng xếp hạng đã là một bảng số ngẫu nhiên
trông rất hợp lý. Lý lẽ ấy được giữ nguyên trong doc của `spin(until:)`.

### Trục `progress` được đo, không phải suy ra

`testWhereTheCardIsAtEachSample` đọc mép trên của thẻ từ pixel (nền đen, cột 195) và
đảo bằng chính số học của thẻ (`top(p) = H − B(1−p) − C − (H−C)p`, tuyến tính theo
`p`, `top(1) = 0`):

| t (ms) | mép trên | progress |
|---|---|---|
| 0–67 | *chưa hiện* | — |
| 83 | 515pt | 0,26 |
| 117 | 371pt | 0,47 |
| 150 | 249pt | 0,64 |
| 200 | 107pt | 0,85 |
| 250 | 38pt | 0,95 |
| 300 | 10pt | 0,99 |
| ≥367 | 0pt | 1,00 |

Hai điều đọc ra từ đây, cả hai đều đáng ghi:

- **Năm khung đầu thẻ chưa nhìn thấy được.** `body` mờ cả thẻ vào bằng
  `.opacity(currentTrack == nil ? 0 : 1)` trên `BottomBarStyle.settle`. Bản đầu của
  test này đọc "mép nghỉ" ngay sau cú tap và nhận về trang trắng, mọi lần.
- **Thẻ tới đích ở ~367ms, nhưng chi phí mỗi khung không hạ theo.** Đường cong
  baseline giữ ~4,0ms/khung tới khung 31 (517ms) rồi mới xuống ~3,0ms — tức là sau
  khi thẻ đã đứng yên ở `progress = 1` được 150ms, một lượt cập nhật vẫn tốn 3ms,
  gần bằng lúc đang bay.

---

## 2. Bảng xếp hạng

### Cách đo, và vì sao phải làm lại một lần

Vòng đầu làm đúng như brief mô tả: sửa tạm → chạy `xcodebuild` → hoàn nguyên → sửa
cái tiếp theo. **Cách ấy không đo được gì và đã bị vứt.** Hai lần chạy baseline liên
tiếp trên đúng cùng một build cho 151,3ms rồi 129,8ms — 16,5% trôi giữa hai lần chạy,
lớn hơn phần lớn thứ cần xếp hạng. Chuẩn hoá theo một view tham chiếu đo trong cùng
lần chạy chỉ hạ được xuống ~5%. Tệ hơn: máy trôi *nhanh dần* theo thứ tự các lần
chạy, nên các thành phần đo sau trông rẻ hơn chỉ vì chúng được đo sau — "tắt
`QueuePanel`" (code chết trong kịch bản này, không thể có tác dụng gì) đo ra −40%.

Vòng hai đổi sang **A/B đan xen trong một tiến trình**: thêm tạm một công tắc runtime
`PlayerCard.costOff: Set<String>` gác từng thành phần, vòng ngoài là lần lặp, vòng
trong là cấu hình. Mọi cấu hình được đo dưới cùng điều kiện máy như mọi cấu hình
khác. Ba lần chạy độc lập, mỗi lần 9–21 lần lặp × 11 cấu hình × 40 khung.

Công tắc và file test tạm ấy **đã bị xoá**; `PlayerCard.swift` nguyên trạng, đã kiểm
lại bằng `git status` và `grep`.

### Sàn nhiễu, đo bằng một null control có sẵn

`QueuePanel` **không được gắn vào cây** trong một cú mở/đóng — nó nằm sau
`if showingQueue || queueFactor > 0`, và cả hai đều bằng 0 suốt kịch bản này. Tắt nó
là tắt code chết, nên tác dụng thật phải là 0. Ba lần chạy đo ra **+1,3%, +1,6%,
+4,3%**. Đó là sàn nhiễu, đo được chứ không phải giả định: **±5 điểm phần trăm**.
Bất cứ mục nào dưới ngưỡng ấy là *chưa phân giải được*, không phải là "nhỏ".

### Bảng

Δ tính trên tổng 40 khung của một cú mở, trung vị các lần lặp. Ba cột là ba lần chạy
độc lập.

| # | thành phần tắt đi | lần 1 | lần 2 | lần 3 | kết luận |
|---|---|---|---|---|---|
| 1 | **`NowPlayingContent` (toàn bộ chrome mở rộng)** | **−26,2%** | **−23,1%** | **−30,5%** | **phân giải rõ; ~26% của cú mở** |
| 2 | lớp `.overlay` `.ultraThinMaterial` có mask | −7,4% | −13,5% | −3,0% | dấu ổn định, độ lớn không; ~7% |
| 3 | dải `tintStops(...)` ở `background` | +1,8% | −9,4% | −4,6% | chưa phân giải |
| 4 | `MiniPlayerChrome` | −2,6% | −6,9% | −3,5% | chưa phân giải (dấu ổn định) |
| 5 | ảnh bìa (bitmap) | −5,2% | −6,0% | +4,3% | chưa phân giải |
| 6 | `dissolveStops(progress:)` | −3,9% | −5,3% | +1,7% | chưa phân giải |
| 7 | dải `LinearGradient` tối dần của thẻ | −3,3% | −6,6% | +3,5% | chưa phân giải |
| 8 | bóng đổ của tấm bìa | −4,7% | +2,2% | +5,0% | không có tác dụng đo được |
| 9 | `QueuePanel` (null control) | +1,3% | +1,6% | +4,3% | **0 — không nằm trong cây** |
| — | **tắt cả tám thứ trên cùng lúc** | **−70,9%** | **−64,3%** | **−71,2%** | **~69%** |

### Đọc bảng này

**Chỉ một thành phần vượt hẳn sàn nhiễu, và nó không nằm trong danh sách nghi phạm
đầu của brief.** `NowPlayingContent` — khối chữ, scrubber, hàng transport, thanh âm
lượng, hàng repeat — chiếm **~26%** chi phí một cú mở, một mình, và ổn định qua cả
ba lần chạy. Nó đắt trong khi `.opacity(max(0, (progress − 0,5) × 2))` giữ nó vô
hình suốt nửa đầu cú morph.

**Phần còn lại thì phân tán, không tập trung.** Tám thứ kia cộng lại ra 69%, mà
không thứ nào riêng lẻ vượt được ±5pp một cách chắc chắn. Tức là 43 điểm phần trăm
còn lại **rải đều trên tám lớp**, mỗi lớp vài phần trăm. Đây là kết luận có sức nặng
hơn bất kỳ dòng nào ở trên: không có một thủ phạm để gỡ ra. Tổng còn *siêu cộng* —
tắt hết rẻ hơn tổng các phần — nên một phần chi phí thuộc về việc *hợp thành* các
lớp chứ không thuộc lớp nào.

**Hai ứng viên đầu bảng của brief đều không phân giải được.** `dissolveStops` và
`tintStops` là hai cái tên brief đặt lên đầu; đo ra chúng lẫn trong nhiễu, và ở lần
chạy dài nhất (21 lần lặp) `dissolveStops` ra **+1,7%**. Bảy `Gradient.Stop` dựng lại
mỗi khung là một cấp phát object mỗi khung, đúng, nhưng nó không phải thứ nhìn thấy
được ở đây.

---

## 3. Câu mâu thuẫn: chạm hay kéo?

**Trả lời: đường chạm. Cú kéo chỉ đắt hơn 1,34×, và cái giá ấy không tăng theo tần
suất ghi state.**

Sáu cấu hình, cùng cú morph, cùng số khung, trung vị 9 lần mount:

| đường | write | commit | tổng | so với chạm |
|---|---|---|---|---|
| chạm — 1 lần đổi state cho cả cú morph | 0,5ms | 141,2ms | **141,7ms** | 1,00× |
| kéo — 1 lần ghi/khung | 4,7ms | 184,9ms | 189,6ms | **1,34×** |
| kéo — 4 lần ghi/khung, gộp | 5,1ms | 143,7ms | 148,8ms | 1,05× |
| kéo — 4 lần ghi/khung, có run loop xen giữa | 160,7ms | 29,1ms | 189,9ms | **1,34×** |
| kéo — 4 lần ghi *lớn*/khung, gộp | 4,7ms | 145,6ms | 150,3ms | 1,06× |
| kéo — 4 lần ghi *lớn*/khung, có run loop xen giữa | 160,9ms | 29,0ms | 189,9ms | **1,34×** |

Ba điều đọc ra:

1. **Bốn lần ghi trong một khung tốn đúng bằng một lần.** Gộp hay để run loop chạy
   giữa từng lần, ghi nhỏ hay ghi lớn — vẫn rơi vào đúng 1,34×. Nếu thật sự có bốn
   lượt dựng lại mỗi khung, con số phải là 141,7 + 4×48 ≈ 333ms. Nó không phải.
   SwiftUI gộp; một lần ghi `@State` chỉ là một cú làm-mất-hiệu-lực, và mỗi khung
   chỉ có một lượt cập nhật.

   Trong bảng, hai dòng "có run loop xen giữa" chỉ **dời** công việc từ cột `commit`
   sang cột `write` (29ms + 161ms), không thêm việc. Tổng không đổi.

2. **Cú chạm — nơi `body` chạy đúng một lần — đã ngốn 75% chi phí của một khung
   kéo.** Nghĩa là thứ đắt vẫn đắt trong khi `body` đứng yên.

3. **Vậy khả năng 1 của brief đúng, khả năng 2 sai.** Chi phí nằm ở việc đánh giá
   lại các *thuộc tính động* mỗi khung, không ở tần suất `DragGesture.onChanged` ghi
   `@State`. Ngân sách 16ms mỗi khung của pha commit không được giải thích bằng
   đường kéo.

**Ghi chú ở đầu `Features/Prototypes/PlayerMorphUIKitView.swift` không mô tả thứ đo
được ở đây.** Nó viết: "mỗi khung hình màn hình có khoảng bốn lượt dựng lại cây view,
ba trong số đó bị vứt đi". Bốn lần ghi trong một khung đo ra bằng đúng một lần ghi,
ở mọi biến thể thử được. Cả một quyết định lớn — port player sang UIKit,
`UIViewPropertyAnimator`, 1855 dòng — được nêu ra dựa trên chẩn đoán ấy. Chẩn đoán
ấy chưa được đo, và ở đây nó không đứng.

Giới hạn thành thật của kết luận này ở mục 4.

---

## 4. Giới hạn — chỗ nào simulator có thể nói dối

1. **Con số tuyệt đối sai, và sai theo cách đã biết.** Trung vị 3–4ms một khung ở
   đây, so với 16,06ms trên iPhone 12 bản Release. Máy Mac, Debug, không display
   link, và render server của simulator không phải pipeline GPU mà trace đã đo. Chỉ
   **thứ tự** được nêu ra, và mọi assertion trong file test là assertion thứ tự với
   biên rộng.

2. **Bộ đo ép một lượt layout ở mỗi mẫu.** Nó báo **chi phí biên của một lượt cập
   nhật**, không phải chi phí của một thẻ đang đứng yên. Đúng đại lượng cho việc xếp
   hạng — đó là thứ một khung của cú morph phải trả — nhưng con số "3ms/khung sau khi
   thẻ đã tới đích" ở mục 1 **không** có nghĩa là thẻ tốn 3ms/khung khi rảnh.

3. **Đường kéo là mô hình, không phải cú kéo thật.** `dragDelta` là `private @State`
   và không có cách nào gửi một touch tới `DragGesture` từ unit test, nên cú kéo được
   mô phỏng bằng `minimised` — input `let` của thẻ, ghi từ view cha. Nó dựng lại
   `body` thật, nhưng nó nuôi ít thuộc tính hạ nguồn hơn `progress`. Hai biên độ
   (0,002 và 0,5) được đo để kẹp sai số ấy và chênh nhau dưới 1%, nên khoảng kẹp
   hẹp — nhưng 1,34× vẫn là **cận dưới**, không phải ước lượng.

   Điều này **không** làm yếu kết luận chính: kết luận là "gộp xảy ra, không có bốn
   lượt dựng lại", và nó rút ra từ việc *4 lần ghi = 1 lần ghi*, một so sánh chỉ
   dùng đúng một cơ chế ghi nên không bị lệch bởi việc `minimised` rẻ hơn `progress`.

4. **Sàn nhiễu ±5pp là thật và đã được đo, không phải ước.** Tám trong mười thành
   phần rơi dưới ngưỡng ấy. Chúng được ghi là *chưa phân giải*, không phải "nhỏ".
   Muốn xếp hạng bên trong nhóm ấy cần một bộ đo khác, không phải chạy lại cái này
   lâu hơn: độ tản trong mỗi cấu hình (90–140ms trên trung vị 133ms) là độ tản
   *mount-to-mount*, không phải nhiễu máy, nên tăng số lần lặp không thu hẹp nó bao
   nhiêu.

5. **Chỉ đo một chiều: chiều mở.** Không có cách nào đóng thẻ từ test mà không đổi
   luôn thứ đang vẽ (`collapse()` chỉ chạy khi `currentTrack` về `nil`, mà thẻ không
   bài thì vô hình). Trace trên máy gồm cả hai chiều. Nếu chiều đóng có tính chất
   khác, phép đo này không thấy.

6. **`ArtworkStore` cache theo tiến trình**, nên chỉ lần mount đầu giải mã thật. Trên
   máy, đổi bài là giải mã lại. Không ảnh hưởng bảng xếp hạng (mọi cấu hình cùng
   điều kiện) nhưng có ảnh hưởng con số tuyệt đối.

---

## 5. Những chỗ mâu thuẫn với brief

Brief viết từ suy luận trên số đo thiết bị và nói rõ: nếu bộ đo nói khác, số đo
thắng. Bốn chỗ.

**1. Hai ứng viên đầu danh sách không phân giải được.** Brief xếp `dissolveStops`
(7 chặng gradient) và `tintStops` lên đầu, với lập luận "cấp phát object mỗi khung
khớp với 38% libobjc/malloc". Đo ra cả hai lẫn trong sàn nhiễu ±5pp, và ở lần chạy
21 lần lặp `dissolveStops` ra +1,7%. Lập luận có thể vẫn đúng trên máy thật với
Release; ở đây nó không đứng riêng ra được.

**2. Thứ đắt nhất không có trong lý lẽ của brief.** `NowPlayingContent` có trong
danh sách ứng viên nhưng brief không dành cho nó dòng lập luận nào — cả phần "một
mâu thuẫn phải giải" xoay quanh gradient và `DragGesture`. Nó là mục duy nhất phân
giải rõ, ~26%.

**3. Ghi chú 250Hz trong repo không mô tả thứ đo được.**
`Features/Prototypes/PlayerMorphUIKitView.swift` ghi "khoảng bốn lượt dựng lại cây
view mỗi khung hình, ba bị vứt", và brief dựng khả năng 2 lên trên nó. Bốn lần ghi
trong một khung đo ra bằng đúng một lần, ở cả bốn biến thể. Ghi chú ấy là cơ sở nêu
ra cho một cuộc port 1855 dòng sang UIKit.

**4. Brief giả định phần rảnh giữa hai mẫu là trung tính.** Không phải, và đây là
chỗ suýt hỏng cả việc: thiết kế đầu tiên của bộ đo giữ run loop ra ngoài để không ai
commit sau lưng phép đo — một lý lẽ nghe rất hợp lý — và cho ra một bảng số hoàn toàn
là nhiễu, trong đó một `Color` "đắt hơn" sáu lớp gradient. Chỉ có đối chứng bắt được.
Đây là lần thứ năm ở khu vực này mà một giả thuyết nghe hợp lý mà chưa đo hoá ra sai;
lần này nó chết trước khi thành một bản vá.

### Một điều brief không hỏi nhưng đo được

Thẻ tới `progress = 1` ở ~367ms, mà chi phí một lượt cập nhật vẫn ~4,0ms/khung tới
517ms và chỉ hạ xuống ~3,0ms sau đó — chứ không về 0,33ms như `Color`. Có thứ vẫn
đang được tính lại sau khi cú morph đã kết thúc trên màn hình. Với cảnh báo ở giới
hạn (2): đây là chi phí biên của một lượt cập nhật bị ép, không phải chi phí lúc
rảnh — nên nó là một câu hỏi để đo tiếp, không phải một kết luận.
