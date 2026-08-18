# J1 — Khung 0 tốn 15ms vì cái gì

**Trạng thái: xong. Không có bản sửa nào.** `PlayerCard.swift` nguyên trạng
(`git checkout` đã hoàn nguyên; `grep` ba định danh tạm ra 0). Chỉ một file test
được đổi: `Evenstar/EvenstarTests/PlayerCardCommitCostTests.swift`.

Bộ đo `h1` được dùng lại nguyên vẹn — `CommitProbe`, `CardRig`, `Drive`,
`LayeredMorph` không sửa một dòng logic nào. Phần thêm vào là hai thứ: một tham
số `alreadyPlaying` cho `CardRig.make`, và một closure `Drive.morphWithoutAnimation`.

---

## Tóm tắt trước, vì kết luận đi ngược brief

| câu hỏi | câu trả lời đo được |
|---|---|
| Khung 0 đắt vì diff cây hay vì dựng animation? | **Diff/dựng cây.** Bỏ *toàn bộ* animation đổi khung 0 đi −18,8% / +4,3% / +5,1% / −14,3% qua bốn lần chạy — vắt qua số 0. |
| Nhưng chính xác hơn thế | **Hơn một nửa khung 0 thậm chí không phải cú morph.** Cú mở "ấm" (thẻ đã gắn sẵn bài, chỉ chạy `expand()`) tốn **−54,2 / −53,7 / −54,8 / −54,8%** so với cú mở "lạnh". |
| Thành phần nào đắt nhất ở khung 0 | `NowPlayingContent` (~−38%), rồi `MiniPlayerChrome` (~−25%). Tám thứ tắt hết cùng lúc: **−85%**. |
| Khung 0 có đắt như nhau ở mọi cú mở không | **Không.** Lần mount đầu của cả tiến trình: 50,3ms và 194,6ms ở hai lần chạy, so với 10–17ms mọi lần sau. |

---

## 1. Phần 1 — diff hay dựng animation

### Phép tách, đúng như brief mô tả

Một công tắc runtime tạm trong `PlayerCard` thay `withAnimation(curve)` ở nhánh
thường của `morph(to:curve:)` bằng `withTransaction(Transaction(animation: nil))`.
Một công tắc thứ hai đưa `.animation(BottomBarStyle.settle, value:)` ở ngoài
cùng `body` về `nil` — vì cú chạm đổi **hai** thứ cùng lúc và cái thứ hai cũng là
một animation. Tách làm hai để trả lời riêng được.

Cây view sau cú đổi **giống hệt nhau ở cả hai cấu hình**: `settled` nhảy thẳng
tới 1 trong cả hai đường, nên `body` đánh giá ở `progress = 1` ở cả hai. Khác
biệt duy nhất là SwiftUI có được yêu cầu dựng một đối tượng animation cho mỗi
thuộc tính vừa đổi hay không.

### Công tắc có thật sự tắt animation không — kiểm bằng pixel

Không tin vào một `Bool`. Đọc mép trên của thẻ từ pixel, cùng cách
`testWhereTheCardIsAtEachSample` đã làm:

```
[switch-check] rest=698pt
  frame 2: noAnimation top=0pt,   animated top=nil pt
  frame 8: noAnimation top=0pt,   animated top=392pt
```

Tắt animation → thẻ đã ở đích (`top = 0`) ngay khung 2. Bật → khung 8 thẻ mới ở
392pt, còn hơn nửa đường. (`nil` ở khung 2 của đường có animation không phải lỗi:
`body` hoà mờ cả thẻ vào bằng `BottomBarStyle.settle`, và bảng travel của `h1` ghi
đúng cùng khoảng trắng ấy ở năm khung đầu.) Công tắc nối vào thật.

### Bốn lần chạy, xen kẽ trong một tiến trình

Vòng ngoài là lần lặp, vòng trong là cấu hình, thứ tự đảo ở các lần lặp lẻ —
đúng khuôn `h1` đã dựng sau khi cách "sửa → chạy → hoàn nguyên" bị vứt. 20–21 lần
mount mỗi cấu hình.

Δ tính trên **khung 0**, trung vị các lần mount.

| cấu hình | lần 1 | lần 2 | lần 3 | lần 4 | trung vị |
|---|---|---|---|---|---|
| **đối chứng null** (cùng cấu hình, đo hai lần) | +1,9% | +2,8% | +0,0% | +1,8% | **+1,9%** |
| bỏ animation của cú **morph** | — | +6,4% | −3,3% | −1,9% | −1,9% |
| bỏ animation **hoà mờ thẻ** | — | +7,2% | −0,9% | +2,5% | +0,8% |
| **bỏ cả hai** | −18,8% | +4,3% | +5,1% | −14,3% | **−5,0%** |
| **cú mở ấm** (chỉ có cú morph) | −54,2% | −53,7% | −54,8% | −54,8% | **−54,5%** |

Sàn nhiễu của bảng này, đo bằng đối chứng null qua bốn lần chạy: **±3 điểm phần
trăm**.

### Đọc bảng

**Bỏ toàn bộ việc dựng animation không làm khung 0 rẻ đi.** Bốn lần chạy cho
−18,8 / +4,3 / +5,1 / −14,3 — vắt qua 0, không lần nào lặp lại dấu của lần trước
một cách đáng tin, và cách sàn nhiễu ±3pp xa tới mức *không* thể gọi là "chưa
phân giải được vì quá nhỏ": nó là một đại lượng có phương sai lớn quanh 0.

Và có một chỗ phép đo tự làm khó mình theo chiều **có lợi cho** giả thuyết
animation: ở cấu hình `nil`, khung 0 layout tấm thẻ ở hình học **đích** (390×874,
`NowPlayingContent` trải hết cỡ), còn ở cấu hình có animation, khung 0 layout ở
hình học **xuất phát** (viên thuốc 348×54) vì giá trị đang vẽ mới là thứ layout
đọc. Tức cấu hình `nil` làm *nhiều* việc layout hơn, và vẫn không đắt hơn một
cách ổn định. Trên đường morph thuần (cú mở ấm) điều ấy hiện ra rõ: bỏ animation
làm khung 0 **đắt thêm** +16,1 / +17,4 / +25,3 / −10,5%.

### Kiểm lại bằng cách thứ hai: bộ đo có nhìn thấy việc dựng animation không?

Một câu trả lời "không có tác dụng" chỉ có nghĩa nếu bộ đo *nhìn thấy được* tác
dụng ấy khi nó thật sự có mặt. Nên: một view tổng hợp gồm `N` hình chữ nhật, mỗi
cái năm thuộc tính động (rộng, cao, độ mờ, xoay, offset), cây đã gắn sẵn và đã
làm nóng, đổi bằng một lần ghi — một lần trong `withAnimation`, một lần trong
transaction `nil`. Cùng bộ đo, cùng `CommitProbe.sweep`.

```
[anim-rate]  200 thuộc tính động:  nil 1.943ms -> animated  3.774ms   (+1.83ms, 9.2µs/thuộc tính)
[anim-rate]  800 thuộc tính động:  nil 5.806ms -> animated 12.415ms   (+6.61ms, 8.3µs/thuộc tính)
[anim-rate] 3200 thuộc tính động:  nil 17.533ms -> animated 38.923ms  (+21.39ms, 6.7µs/thuộc tính)
```

Bộ đo nhìn thấy rất rõ, và tác dụng gần như tuyến tính theo số thuộc tính, ở mức
**6,7–9,2µs mỗi thuộc tính động**.

Đặt cạnh tấm thẻ: một khung 0 nặng ~16ms **làm bằng việc dựng animation** sẽ đòi
cỡ **2.300 thuộc tính động**. Phép đo trực tiếp ở trên chặn cả hoá đơn animation
của tấm thẻ xuống dưới sàn nhiễu (~±0,5ms), tức dưới cỡ **70 thuộc tính**. Hai
cách đo độc lập, cùng một câu trả lời.

### Và một cách thứ ba, mạnh hơn cả hai

Bảng xếp hạng ở mục 2 trả lời cùng câu hỏi từ phía đối diện: **tắt tám khối view
đi làm khung 0 rơi từ ~16,5ms xuống ~2,5ms (−85%).** Chi phí đi theo *lượng cây*,
không đi theo *số animation* — số animation không đổi ở phần lớn các cấu hình ấy.

### Trả lời

> **Khung 0 đắt vì SwiftUI dựng và so cây view, không vì nó dựng đối tượng
> animation.** Cách sửa mà kết quả này chỉ tới là làm cây nhỏ đi, không phải giảm
> số thuộc tính động.

### Nhưng brief hỏi thiếu một vế, và vế ấy lớn hơn cả câu hỏi

Brief giả định khung 0 = "khung `withAnimation` chạy". Phép đo nói khác:

| | khung 0 |
|---|---|
| cú mở **lạnh** (bài vừa tới + `expand()`) — đúng cái `h1`/`i1` đo | ~16,2ms |
| cú mở **ấm** (thẻ đã gắn sẵn bài, chỉ `expand()`) | ~7,3ms |
| tỉ lệ | **0,455 — bốn lần chạy: 0,458 / 0,463 / 0,452 / 0,452** |

Phép tách: `CardRig.make(alreadyPlaying: true)` gọi `playback.play(...)` **trước
khi** gắn view. Lúc gắn, `currentTrack` đã khác `nil` và `settled` vẫn là 0, nên
thẻ hiện ra là viên thuốc thu gọn *có bài*, và `warmUp()` nuốt trọn phần chi phí
"bài vừa tới". Cú `tapToOpen()` của sweep sau đó chỉ đẩy `explicitSelections` lên
lần thứ hai: `currentTrack?.id` không đổi nên không có `collapse()`, không có cú
hoà mờ `settle`, `artworkIdentity` không đổi nên không chạy lại `.task` cũng như
`refreshCachedCover`. Còn lại đúng cú morph.

**Hơn một nửa của khung 0 không phải cú morph.** Nó là lần đầu tiên cây view có
bài được dựng: mọi nhánh gác sau `hasArtwork`, `MiniPlayerChrome` và
`NowPlayingContent` lần đầu dựng chữ của bài, `.opacity` của cả thẻ rời khỏi 0,
`.task(id:)` khởi động, `onChange(of: artworkIdentity, initial:)` ghi thêm một
lượt `@State` nữa trong cùng khung.

Đây là đại lượng ổn định nhất trong cả báo cáo — bốn lần chạy nằm trong nửa điểm
phần trăm của nhau, trong khi mọi thứ khác ở đây trôi vài chục.

---

## 2. Phần 2 — xếp hạng lại, chỉ nhìn khung 0

### Cách đo

Cùng công tắc `PlayerCard.costOff: Set<String>` như `h1`, cùng kiểu A/B xen kẽ
trong một tiến trình. 20–21 lần mount mỗi cấu hình, 12–15 cấu hình mỗi lần chạy,
bốn lần chạy độc lập. Điểm chấm là **khung 0**, trung vị các lần mount.

Một thay đổi so với `h1`, và nó đến từ một con số làm giật mình: lần chạy đầu
tiên cho các lần mount trong cùng một cấu hình rải từ 4ms tới 41ms. Đó là hình
dạng của "đôi khi cú cập nhật rơi vào mẫu 1 thay vì mẫu 0". Nên mỗi lần mount ghi
lại cả **tám khung đầu**, và bảng dưới cũng ghi `frames0–2`. Đọc lại từng vector:
cú cập nhật **luôn** rơi vào khung 0 — mọi lần mount đều có dạng
`14.4  0.6  2.5  1.8  1.6 …`. Độ tản là độ tản thật của khung 0, không phải cú
trượt mẫu. Cột `frames0–2` giữ lại trong bảng vì nó là cùng kết luận đo theo một
cách khác.

### Sàn nhiễu, đo bằng hai đối chứng null

- **`baseline` đo lại lần thứ hai dưới một cái tên khác** — cùng một cấu hình,
  không đổi một dòng nào.
- **`QueuePanel` tắt đi** — đối chứng null của `h1`, code chết trong kịch bản này
  (`showingQueue == false` và `queueFactor == 0` suốt cú mở).

| | lần 1 | lần 2 | lần 3 | lần 4 |
|---|---|---|---|---|
| baseline đo lại | −9,3% | −4,6% | −7,8% | −15,8% |
| QueuePanel (code chết) | −6,9% | +0,4% | −10,7% | −3,2% |

Tám phép đo, biên độ −15,8 tới +0,4. **Sàn nhiễu: ±16 điểm phần trăm.** Lớn hơn
hẳn ±5pp của `h1`, và lý do rõ ràng: `h1` chấm trên tổng 40 khung, đây chấm trên
**một** khung. Trung bình hoá bốn mươi mẫu ăn mất phần lớn phương sai; một mẫu thì
không.

Bảy trong tám phép đo ấy âm, tức có một thiên lệch hệ thống nhỏ làm cấu hình
**đầu tiên** trong danh sách (luôn là `baseline`) đọc ra cao. Đã thử chữa bằng
cách đổi số lần lặp từ 21 sang 20 để mọi cấu hình có đúng số lượt ở đầu và ở cuối
— **không chữa được** (lần chạy 4 là lần tệ nhất). Nên nó được ghi là một giới
hạn ở mục 4, không phải một thứ đã sửa xong.

### Bảng — cú mở lạnh, khung 0

| # | thành phần tắt đi | lần 1 | lần 2 | lần 3 | lần 4 | trung vị | kết luận |
|---|---|---|---|---|---|---|---|
| 1 | **`NowPlayingContent`** | −38,7% | −36,9% | −47,9% | −21,3% | **−37,8%** | **phân giải rõ, cả bốn lần vượt sàn** |
| 2 | **`MiniPlayerChrome`** | −41,3% | −24,4% | −25,1% | −24,7% | **−24,9%** | **phân giải rõ, cả bốn lần vượt sàn** |
| 3 | ảnh bìa (bitmap) | −18,2% | +2,5% | −27,2% | −4,4% | −11,3% | chưa phân giải (đổi dấu) |
| 4 | dải `LinearGradient` tối dần | −11,2% | −8,9% | −3,4% | −17,8% | −10,1% | chưa phân giải |
| 5 | `dissolveStops` | −13,4% | +3,7% | −7,0% | −10,3% | −8,7% | chưa phân giải (đổi dấu) |
| 6 | dải `tintStops` | −13,6% | −2,7% | −33,7% | +1,6% | −8,2% | chưa phân giải (đổi dấu) |
| 7 | bóng đổ tấm bìa | −16,8% | −4,1% | −2,6% | +1,0% | −3,4% | chưa phân giải (đổi dấu) |
| 8 | lớp `.ultraThinMaterial` có mask | −7,3% | +0,7% | −25,1% | +3,0% | −3,2% | chưa phân giải (đổi dấu) |
| — | *`QueuePanel` (đối chứng null)* | *−6,9%* | *+0,4%* | *−10,7%* | *−3,2%* | *−5,1%* | *0 — không nằm trong cây* |
| — | *`baseline` đo lại (đối chứng null)* | *−9,3%* | *−4,6%* | *−7,8%* | *−15,8%* | *−8,6%* | *0 — cùng một cấu hình* |
| — | **tắt cả tám thứ trên cùng lúc** | **−88,0%** | **−83,1%** | **−80,0%** | **−86,1%** | **−84,6%** | **phân giải rõ** |

### Bảng — cú mở ấm (chỉ cú morph), khung 0

Ba lần chạy, so với `WARM baseline` của chính lần chạy ấy:

| thành phần tắt đi | lần 2 | lần 3 | lần 4 | trung vị |
|---|---|---|---|---|
| **`NowPlayingContent`** | −47,0% | −31,0% | −46,8% | **−46,8%** |
| `MiniPlayerChrome` | −9,4% | −10,8% | −20,0% | −10,8% |

### Đọc bảng

**Thứ hạng khác `h1`, đúng như brief đoán, và khác theo một cách không ai đoán.**
`h1` xếp `MiniPlayerChrome` thứ tư và ghi "chưa phân giải" (−2,6 / −6,9 / −3,5%
trên tổng 40 khung). Ở khung 0 nó là **hạng nhì, −25%, phân giải rõ ở cả bốn lần
chạy**. Nó gần như miễn phí khi *chạy* và đắt khi *dựng* — chính xác cái phân biệt
brief nêu ra khi nói hai bảng trả lời hai câu hỏi khác nhau.

**Hai bảng đọc chung mới ra chuyện.** `MiniPlayerChrome` đắt ở cú mở lạnh (−25%)
và lẫn trong nhiễu ở cú mở ấm (−11%). `NowPlayingContent` đắt ở **cả hai** (−38%
lạnh, −47% ấm). Tức: chi phí của `MiniPlayerChrome` là chi phí *lần đầu dựng chữ
của bài*; chi phí của `NowPlayingContent` là chi phí *có mặt trong cây và phải so
lại*, và nó tồn tại kể cả khi không có gì mới để dựng. Đây khớp với thứ `i1` đo
độc lập bằng một cơ chế khác (hoãn dựng: −27,3 / −21,8 / −26,6%).

**Sáu mục còn lại đều không phân giải được, và bốn trong sáu đổi dấu giữa các lần
chạy.** Với sàn nhiễu ±16pp thì "trung vị −11%" không phải một con số nhỏ, nó là
một con số *chưa đo được*. Không được đọc bảng này như một thứ tự từ 3 tới 8.

**Nhưng tổng thì phân giải rất rõ: tắt tám thứ ấy đi làm khung 0 rơi −84,6%,**
từ ~16,5ms xuống ~2,5ms. Chi phí là có thật và nằm trong tám khối view ấy; nó chỉ
không tập trung vào một chỗ nào ngoài hai cái đầu. Đây cũng là dòng mạnh nhất
trong cả báo cáo ủng hộ câu trả lời của phần 1: chi phí đi theo lượng cây.

---

## 3. Phần 3 — khung 0 có đắt như nhau ở mọi cú mở không

**Không. Lần mount đầu của tiến trình là một hoá đơn khác hẳn, và nó xuất hiện
đúng một lần.**

Chín lần mount liên tiếp, cùng một rig, cùng một cú mở:

```
[first-mount] mount 0: frame 0  50.321ms
[first-mount] mount 1: frame 0   5.319ms
[first-mount] mount 2: frame 0  11.608ms
[first-mount] mount 3: frame 0  17.049ms
[first-mount] mount 4: frame 0   9.113ms
[first-mount] mount 5: frame 0   7.330ms
[first-mount] mount 6: frame 0  18.591ms
[first-mount] mount 7: frame 0  15.025ms
[first-mount] mount 8: frame 0  17.556ms
[first-mount] mount 0 50.321ms so với trung vị phần còn lại 15.025ms; tỉ lệ 3.35
```

Một lần chạy khác của bộ đo tách (cấu hình đứng đầu danh sách, nên lần mount đầu
của nó là lần mount đầu của cả tiến trình):

```
[split]   cold + animation mount 0: 194.583  2.050  0.754  0.643  0.792  10.248  7.058  4.142
[split]   cold + animation mount 1:  10.046  1.707  1.806  1.710  1.539   1.772  1.774  1.623
[split]   cold + animation mount 2:  14.377  0.640  2.534  1.785  1.637   1.556  1.813  1.602
```

**194,6ms ở lần mount đầu, 10–14ms ở mọi lần sau.** Và cấu hình đứng thứ hai
trong cùng lần chạy — tức lần mount thứ hai của tiến trình — đã về 21,1ms.

Đây chính là những con số `i1` ghi lại mà không giải thích được: *"khung tệ nhất
trên mọi lần mount: 68,8 / 55,9 / 85,1ms"*. Chúng là lần mount đầu, một lần mỗi
tiến trình. `i1` đã suy đúng ở mục 6 của nó (chữ ký giống con số 56ms mà `RootView`
ghi lại) nhưng chưa đo trực tiếp được; ở đây đo được.

**Hệ quả:** con số 15ms mà cả `h1`, `i1` và brief này xoay quanh là chi phí của
một cú mở **bình thường**, không phải cú mở đầu tiên. Lớp làm nóng ở `RootView`
đang phủ một hoá đơn *khác*, lớn hơn 3–13 lần, và nó phủ hay không phủ hết là một
câu hỏi tách bạch với mọi thứ trong bảng xếp hạng. Không đo được ở đây vì bộ đo
này không gắn `RootView`.

---

## 4. Giới hạn — chỗ nào simulator có thể nói dối

1. **Sàn nhiễu của bảng xếp hạng là ±16pp và đó là một hạn chế nghiêm trọng.**
   `h1` chấm trên tổng 40 khung và có ±5pp; chấm trên **một** khung thì mất hết
   phần trung bình hoá. Hệ quả cụ thể: sáu trong tám mục ở bảng mục 2 **không** đo
   được, và tăng số lần lặp không cứu — độ tản là độ tản *mount-to-mount* (4ms tới
   41ms trong cùng một cấu hình), không phải nhiễu máy, nên nó chỉ co theo căn bậc
   hai của số lần lặp trong khi chi phí chạy tăng tuyến tính. 20 lần mount × 15 cấu
   hình đã là 156 giây một lần chạy.

   Bộ đo cho **bảng tách** (mục 1) thì ngược lại: đối chứng null của nó nằm trong
   +0,0…+2,8% qua bốn lần chạy, tức ±3pp. Khác biệt là số cấu hình — 5–7 thay vì
   12–15 — nên mọi cấu hình được đo gần nhau hơn về thời gian. Bài học cho lần sau:
   **bảng xếp hạng khung 0 phải chạy ít cấu hình một lần**, không phải nhiều lần lặp.

2. **Có một thiên lệch vị trí chưa giải thích được.** Bảy trên tám phép đo đối
   chứng null ra **âm**, tức cấu hình đầu danh sách (`baseline`) đọc ra cao hơn bản
   sao của chính nó. Đã thử chữa bằng số lần lặp chẵn (để mọi cấu hình có đúng số
   lượt ở đầu và cuối) và không chữa được. Ảnh hưởng thực tế: mọi con số trong bảng
   mục 2 có thể đang **âm hơn sự thật vài điểm phần trăm**. Hai mục phân giải rõ
   (−38%, −25%) không bị lật bởi một sai số cỡ ấy; sáu mục còn lại thì có thể — và
   chúng vốn đã được ghi là chưa phân giải.

3. **Cấu hình `nil` layout ở hình học đích, cấu hình có animation layout ở hình
   học xuất phát.** Đây là một sai lệch có thật trong phép tách của phần 1, và nó
   được nêu ra chứ không giấu đi. Nó nghiêng **về phía** giả thuyết animation (bên
   `nil` làm nhiều việc layout hơn mà vẫn không đắt hơn), nên kết luận "không phải
   animation" là kết luận *bảo thủ*. Trên đường morph ấm, sai lệch ấy đo được:
   +16…+25%.

4. **Con số tuyệt đối sai, và sai theo cách đã biết.** ~16ms cho khung 0 ở đây,
   trên Mac, Debug, simulator, không display link. Trace trên iPhone 12 Release ghi
   trung vị 16,06ms cho **mọi** khung của pha commit. Hai con số trùng nhau là trùng
   hợp; chỉ **thứ tự** và **tỉ lệ** được nêu ra.

5. **Bộ đo ép một lượt layout ở mỗi mẫu** — giới hạn của `h1`, còn nguyên hiệu
   lực. Nó báo chi phí biên của một lượt cập nhật, không phải chi phí lúc rảnh.

6. **Chỉ đo chiều mở** — giới hạn của `h1`, còn nguyên. Không có cách nào đóng thẻ
   từ test mà không đổi luôn thứ đang vẽ.

7. **"Tắt bóng đổ" không tháo modifier, nó đưa `radius` và `opacity` về 0.** Tháo
   hẳn `.shadow` đòi một `if` bọc quanh, tức đổi định danh cấu trúc của view — thứ
   sẽ tự nó làm hỏng phép đo. Mục ấy vốn không phân giải được nên không đổi kết
   luận, nhưng nó không phải cùng một loại công tắc như bảy mục kia.

8. **`ArtworkStore` cache theo tiến trình** — giới hạn của `h1`, còn nguyên. Trên
   máy thật, đổi bài là giải mã lại, nên phần "bài vừa tới" của khung 0 ở mục 1 rất
   có thể **lớn hơn** trên thiết bị, không nhỏ hơn.

---

## 5. Những chỗ mâu thuẫn với brief

**1. Khung 0 không phải "khung `withAnimation` chạy" theo nghĩa brief dùng.**
Brief viết: *"Đó là khung `withAnimation` chạy: SwiftUI đánh giá `body`, so cây
mới với cây cũ, và dựng một đối tượng animation cho mọi thuộc tính vừa đổi."* Hai
vế đầu đúng. Vế thứ ba đo ra **không đáng kể**. Và cả ba vế cộng lại vẫn chỉ giải
thích được **46%** của khung 0 — phần còn lại là cây view của một thẻ *có bài*
được dựng lần đầu, một chuyện xảy ra ở cùng khung nhưng vì lý do khác.

**2. Phép tách brief đề ra cho một kết quả nằm ngoài hai nhánh brief chuẩn bị
sẵn.** Brief viết: "rẻ hơn nhiều ⇒ dựng animation; đắt gần bằng ⇒ diff cây". Đo ra
**vế thứ ba**: cấu hình `nil` khi thì rẻ hơn 19%, khi thì đắt hơn 5%, trung vị
−5% với sàn nhiễu ±3pp. Không phải "đắt gần bằng" theo nghĩa hai con số sát nhau,
mà là hai con số có phương sai lớn quanh nhau. Kết luận vẫn rơi vào nhánh "diff
cây", nhưng nó rơi vào đó nhờ **ba** phép đo đồng thuận, không nhờ một.

**3. `MiniPlayerChrome` là hạng nhì và không có trong lý lẽ nào của brief.** Brief
liệt nó ra như một ứng viên, không dành cho nó một dòng lập luận nào. Ở khung 0 nó
là −25%, phân giải rõ ở cả bốn lần chạy, trong khi `h1` đo nó ra −2,6/−6,9/−3,5%
trên tổng và xếp "chưa phân giải". Nó là ví dụ sạch nhất cho luận điểm của chính
brief rằng hai bảng trả lời hai câu hỏi khác nhau.

**4. `dissolveStops` và `tintStops` lại tiếp tục không phân giải được.** Brief của
`h1` đặt hai cái tên ấy lên đầu; `h1` đo ra chúng lẫn trong nhiễu; ở đây, trên
đúng cái khung mà "dựng object mỗi khung" đáng ra phải lộ ra nhất, chúng vẫn lẫn
trong nhiễu và vẫn đổi dấu giữa các lần chạy (−13,6 / −2,7 / −33,7 / +1,6). Hai
đợt đo, hai bộ đo, cùng một câu trả lời: không đứng riêng ra được.

**5. Sàn nhiễu ±5pp mà brief thừa hưởng từ `h1` không áp dụng cho bảng này.** Nó
là ±16pp. Bất cứ ai đọc bảng mục 2 với ngưỡng 5pp sẽ thấy sáu "phát hiện" không có
thật.

### Một điều brief không hỏi nhưng đo được

Ở cấu hình bỏ hết animation, các khung 4–7 rơi từ ~9–11ms xuống **~2,7–3,0ms**,
đều đặn qua bốn lần chạy. Tức phần đuôi của cú morph — thứ `h1` ghi lại là "vẫn
~3–4ms/khung sau khi thẻ đã tới đích" — **thật sự là animation đang chạy**, khác
hẳn khung 0. Hai khu vực, hai nguyên nhân, và một bản sửa nhắm vào cái này sẽ
không chạm được cái kia.

---

## 6. Cây làm việc và bộ test

`PlayerCard.swift` hoàn nguyên bằng `git checkout`; `git status` sạch trừ file
test. Công tắc tạm (`costOff`, `noMorphAnimation`, `noSettleAnimation`) và hai lớp
test dùng chúng (`TempFrameZeroSplitTests`, `TempFrameZeroRankingTests`) đã bị
xoá — `grep` ba định danh trong `PlayerCard.swift` ra 0.

Phần **giữ lại** trong `PlayerCardCommitCostTests.swift` là phần không cần công
tắc nào, tức là ba phép đo có thể chạy lại bất cứ lúc nào:

- `testWhatAColdOpenPaysAtFrameZeroThatAWarmOpenDoesNot` — phép tách lạnh/ấm, con
  số ổn định nhất của cả đợt.
- `testFrameZeroOfTheFirstMountAgainstEveryMountAfterIt` — câu trả lời phần 3.
- `testTheCostOfConstructingAnimationsPerAnimatedAttribute` — đối chứng dương cho
  phần 1, kèm assertion rằng bộ đo *nhìn thấy được* việc dựng animation. Nếu
  assertion ấy đỏ ở tương lai thì mọi kết luận của phần 1 mất hiệu lực, và nó là
  chỗ nói ra điều đó.

Cùng với đó: `CardRig.make(alreadyPlaying:)` và `Drive.morphWithoutAnimation`, hai
thứ nhỏ mà phép tách lạnh/ấm và đối chứng dương cần.

---

## 7. Nếu có đợt sau

Không đề xuất bản sửa nào — brief cấm, và năm lần trước ở khu vực này đã chứng
minh vì sao. Chỉ ghi lại ba chỗ số đo chỉ tới, để đợt sau không phải đoán lại:

1. **Khung 0 chia hai, và hai nửa cần hai câu hỏi khác nhau.** ~54% là "bài vừa
   tới": cây của một thẻ có bài dựng lần đầu. ~46% là cú morph. Bất kỳ phép đo nào
   sau này gộp hai thứ ấy vào một con số sẽ lại ra 15ms và lại không nói được gì.
2. **Sàn nhiễu của một-khung là ±16pp.** Muốn xếp hạng bên trong nhóm sáu mục chưa
   phân giải thì phải đổi bộ đo, không phải chạy lâu hơn — và bằng chứng là bộ đo
   tách, cùng máy cùng ngày, đạt ±3pp chỉ nhờ có ít cấu hình hơn.
3. **Con số 55–85ms không thuộc về cùng câu chuyện.** Nó là lần mount đầu của tiến
   trình, một lần, và nó là câu hỏi của `RootView` chứ không phải của `PlayerCard`.
