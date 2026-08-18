# K1 — Thu hẹp phạm vi dựng lại của bốn `@State` ảnh bìa: **cổng chặn trượt, đã vứt bản sửa**

**Trạng thái: `DONE_WITH_CONCERNS`. Không commit. `PlayerCard.swift` nguyên
trạng, cây làm việc sạch, `git status --short` rỗng, `git diff HEAD` rỗng, HEAD
vẫn là `5043d08`.**

Bản sửa **làm đúng cái nó hứa về mặt cấu trúc** — đếm được, không phải suy ra:
khung 0 của cú mở lạnh đi từ **3 lượt `PlayerCard.body` xuống 2**. Nhưng lượt
`body` ấy **không đo được bằng đồng hồ**. Khung 0 của cú mở lạnh đo ra
**+6,8% / −6,1% / −1,9%** qua ba lần chạy xen kẽ 20 lần mount, trong khi đối
chứng null trên đúng cùng máy cùng buổi ra **−4,1% / −0,3% / +1,2%**. Vế thứ nhất
của cổng chặn đòi **−15%**. Không lần nào tới gần.

Trên đường **ấm** nó còn hơi đắt thêm — **+6,5% / +7,0% / +2,4%**, dấu ổn định
qua cả ba lần chạy và 60 lần mount.

Đã làm theo brief: vứt bản sửa, báo số, không chỉnh cổng chặn.

---

## 0. Tóm tắt trước, vì kết luận đi ngược brief

| câu hỏi | câu trả lời đo được |
|---|---|
| Bản sửa có thật sự bỏ được một lượt `body` của cả thẻ ở khung 0 không? | **Có.** 3 → 2 lượt, đếm bằng bộ đếm trong chính `body`. |
| Bỏ lượt ấy có làm khung 0 rẻ đi 15% không? | **Không.** +6,8 / −6,1 / −1,9%, sàn nhiễu ±4pp. |
| Vậy **một** lượt `body` của cả thẻ đáng bao nhiêu ở khung 0? | Đối chứng dương (thêm một lượt, 3 → 4): **+20,7 / +12,1 / −26,3%**. Tức nó nằm **ngay trên sàn nhiễu, không ổn định** — trung vị +12%. |
| Có gai mới không? | **Không.** Đỉnh luôn ở khung 0 ở cả hai cấu hình; tỉ lệ đỉnh 1,07 / 0,94 / 0,98. Đỉnh phần morph (khung 1+) 0,98 / 1,01 / 0,90. |
| Đường ấm? | **Đắt thêm**, đều đặn: +6,5 / +7,0 / +2,4%, thắng theo cặp 8/20, 7/20, 4/20. |

**Điều đáng ghi nhất, và nó không nằm trong bất kỳ giả thuyết nào của brief:** cú
ghi `@State` ở khung 0 **không tốn một lượt `body` như brief mô tả — nó tốn hai
lượt thừa gộp thành một**, và cả cụm ấy cộng lại vẫn không nổi lên trên sàn
nhiễu. Chi tiết ở mục 4.

---

## 1. Sàn nhiễu, đo bằng đối chứng null, **trước** khi tin bất cứ con số nào

Đối chứng null: **cùng một cấu hình đo hai lần dưới hai cái tên** (`before` và
`after` đều bật cùng đường mã), chấm trên **khung 0 của cú mở lạnh**, trung vị
các lần mount, đúng khuôn xen kẽ của `h1`/`j1` (vòng ngoài là lần lặp, vòng trong
là cấu hình, đảo thứ tự ở các lần lặp lẻ).

Đo **hai lần**, với hai cỡ mẫu, và khác biệt giữa chúng là bài học lớn nhất của
đợt này:

| cỡ mẫu | lần 1 | lần 2 | lần 3 | sàn nhiễu |
|---|---|---|---|---|
| **9 lần mount** mỗi cấu hình | +5,0% | −3,0% | +7,1% | **±7 điểm phần trăm** |
| **20 lần mount** mỗi cấu hình | −4,1% | −0,3% | +1,2% | **±4 điểm phần trăm** |

Cả hai đều tốt hơn ±16pp mà `j1` đo được, và lý do đúng như `j1` dự đoán: đây chỉ
có **hai** cấu hình nên chúng được đo gần nhau về thời gian.

Thêm một thống kê thứ hai, không tham số, vì trung vị của 9–20 mẫu vẫn trôi:
**tỉ lệ thắng theo cặp** — trong bao nhiêu lần lặp thì `after` rẻ hơn `before`
của *chính lần lặp ấy*. Đối chứng null: **12/20, 12/20, 11/20**. Đúng 50% như
phải thế.

### Một cảnh báo về **tổng 60 khung**: đại lượng ấy ở đây vô dụng

Cùng đối chứng null, chấm trên tổng 60 khung thay vì khung 0, cỡ 9 lần mount:
**+30,0% / −14,8% / +49,4%.** Sàn nhiễu ±50pp.

`h1` đo được ±5pp trên tổng 40 khung, nên con số này cần một lời giải thích chứ
không phải một cái nhún vai. Nó nằm ở `idle(until:)`: cửa sổ 60 khung = 1000ms
phủ 470ms *sau khi* cú morph 520ms đã xong, và ở phần đuôi ấy chi phí mỗi khung
rơi xuống 0,2–1,0ms. Khi máy bận, `RunLoop.main.run(until:)` trả về muộn hơn hạn,
lượt cập nhật tiếp theo không nhích, và `commit` đo một cú no-op — **rẻ hơn**.
Đó chính là cơ chế đã giết bản đầu tiên của bộ đo `h1` (`spin(until:)`), quay lại
ở dạng nhẹ hơn, và nó bơm phương sai vào bất kỳ tổng nào kéo dài quá cú morph.

**Hệ quả: mọi kết luận dưới đây chấm trên khung 0 và trên đường cong theo khung,
không bao giờ trên tổng.** Cột tổng vẫn được in ra trong log để đối chiếu, nhưng
không có kết luận nào đứng trên nó.

---

## 2. Thiết kế, và những gì đã bác bỏ

### Cái đã dựng

Một view con lồng trong `PlayerCard`, `ArtworkSlot`, **giữ cả bốn `@State`** —
`artwork`, `artworkOwner`, `cachedCover`, `cachedCoverOwner` — cùng với
`displayedArtwork`, `refreshCachedCover`, `loadArtwork`, và cả hai mốc ghi:
`.task(id: identity)` và `.onChange(of: identity, initial: true)`. Thân của nó
đúng bằng cái `ZStack` ba lớp (mảng màu / ảnh / nốt nhạc) mà `artworkView` đang
dựng — tức đúng phần duy nhất đọc bốn giá trị ấy. Toàn bộ chuỗi modifier phía
trên (lớp frost, cú tan, `clipShape`, bóng đổ, `position`, `QueuePanel`) ở
nguyên chỗ cũ trong `PlayerCard`.

Bản đã đo nằm ở `k1-PlayerCard-scoped-attempt.swift.discarded` cùng thư mục này.

### Bốn chỗ brief bảo phải cẩn thận, và cách đã giữ

1. **Thời điểm `.onChange`.** Giữ nguyên, và **đo được** chứ không suy ra: xem
   mục 8, test pixel `testTheFallbackCoverIsOnScreenOnTheFrameTheTrackChanges`.
   `body` của view con chạy *bên trong* lượt cập nhật đã dựng ra nó, nên
   `onChange` gắn ở đó vẫn nằm trong đúng lượt ấy. Bộ đếm ở mục 4 xác nhận từ
   phía khác: cấu hình mới vẫn tiêu đúng **ba** lượt cập nhật ở khung 0, chỉ khác
   ở chỗ hai trong ba lượt ấy giờ là lượt của ô bìa.
2. **Chốt chủ sở hữu.** Cả hai vế vẫn so với `identity`, và `identity` là giá trị
   `PlayerCard.artworkIdentity` tính ra ở đúng lượt `body` dựng ra view con.
   `preferredCover(hasArtwork:loadedForThisTrack:cachedForThisPath:)` không đổi
   một ký tự. Hai chỗ trong `loadArtwork` cần định danh **sống** sau `await`
   (`artworkOwner = artworkIdentity` và `refreshCachedCover(..., owner:)`) được
   giữ sống bằng một computed `liveIdentity` đọc từ `playback` — chỉ gọi từ
   `loadArtwork`, không bao giờ từ `body`, vì đọc `@Observable` trong `body` sẽ
   tự phá mục đích của cả việc tách.
3. **Cỡ giải mã khớp cỡ vẽ.** Ở đây nó khớp **chặt hơn trước**: `decodeSide` là
   đúng con số `card(size:insets:)` đã tính ở dòng `let artworkSide = ...` và
   truyền cho `artworkView` để vẽ. Bản cũ để `loadArtwork` dựng lại `fullSize` từ
   `safeAreaSize`/`insets` rồi gọi lại `artworkSide(fullSize:topInset:)` — hai
   con số phải bằng nhau bằng niềm tin; sau khi tách chỉ còn một con số.
4. **`@Environment(\.displayScale)` rỗng trong `init`.** Ràng buộc ấy **không**
   quay lại, và lý do là lý do cũ, ghi ở chú thích của chính thuộc tính ấy: giá
   trị chỉ được đọc từ `.task` trở đi. `ArtworkThumbnail` phải dựng `maxPixel`
   trong `init` vì nó cần con số ở đó; `ArtworkSlot` thì không.

### Đã cân nhắc và bác bỏ

- **Chỉ dời cặp `.onChange` (`cachedCover`/`cachedCoverOwner`), để `.task` ở
  lại.** Hợp lý trên giấy — chỉ cặp ấy ghi *đồng bộ trong khung 0*, còn `.task`
  tiếp đất ở khung sau. Bỏ, vì nó để lại `displayedArtwork` đọc hai `@State` ở
  hai chủ khác nhau, tức chốt chủ sở hữu bị chẻ làm đôi qua một ranh giới view —
  đúng loại thứ mà chú thích của `cachedCoverOwner` ghi lại là đã hỏng một lần.
  Sau khi có số ở mục 4 thì lựa chọn này cũng vô nghĩa: nó nhắm vào một lượt
  `body` mà lượt ấy đo ra gần bằng không.
- **Đưa cả `tint` xuống view con.** Không được: nền, ô placeholder và dải màu
  trội đều đọc nó. Nó được ghi ngược lên qua một closure, và lần ghi ấy vẫn dựng
  lại cả thẻ — đúng như trước. Nó rơi *sau* cú giải mã bất đồng bộ nên không nằm
  ở khung 0.
- **`Animatable` để đọc giá trị đang vẽ.** Brief cấm; repo đã revert đúng cách ấy
  ở `b14ad5d`. Không đụng.
- **Hoãn dựng gì đó.** Đó là `i1`, và `i1` đã trả lời: cái gai phải trả ở đâu đó.

### Bộ đo

Một công tắc runtime tạm `PlayerCard.abScopedArtwork` gác đúng hai chỗ: nhánh
`if` trong `artworkView` chọn giữa view con và cái `ZStack` cũ y nguyên tại chỗ,
và hai `guard !Self.abScopedArtwork else { return }` ở thân `.task`/`.onChange`
cũ. **Bản thân hai modifier ấy vẫn gắn nguyên trong cả hai cấu hình** — chỉ *việc
làm* khác nhau, không phải hình dạng cây. Nếu điều đó có lệch thì nó lệch theo
chiều làm bản sửa trông **kém hơn** sự thật, tức là bảo thủ.

File test tạm `EvenstarTests/TempScopedArtworkAB.swift`, A/B **xen kẽ trong một
tiến trình**, `-parallel-testing-enabled NO` (bẫy mà `i1` đã ghi lại: xcodebuild
chạy trên một clone simulator và container của clone bị xoá cùng file log).

---

## 3. Vì sao 9 lần mount là không đủ, và tại sao chuyện đó suýt thành một bản vá

Ba lần chạy đầu tiên, **9 lần mount** mỗi cấu hình, khung 0 của cú mở lạnh:

```
[ab-cold] FRAME 0: before 15.542ms, after  8.878ms, delta -42.9%
[ab-cold] FRAME 0: before 16.431ms, after 13.609ms, delta -17.2%
[ab-cold] FRAME 0: before 15.886ms, after 15.138ms, delta -4.7%
```

Đọc vội thì đây là "hai trong ba lần vượt cổng chặn". Đó là một cái bẫy, và nó là
**đúng cái bẫy mà brief nói tới khi kể chuyện một agent vá một lỗi không tồn tại
và chỉ bị bắt vì nó coi một con số bất thường là dữ liệu chứ không phải nhiễu.**
Ba con số ấy trải 38 điểm phần trăm, trong khi đối chứng null của cùng cỡ mẫu chỉ
trải 10. Một đại lượng có phương sai gấp bốn lần sàn nhiễu của chính nó thì
không phải một hiệu ứng — nó là một ước lượng chưa hội tụ.

Nên: nâng lên **20 lần mount**, thêm log **từng lần mount** và thêm thống kê
thắng-theo-cặp, rồi đo lại đối chứng null với **cùng** cỡ mẫu, xen kẽ null / A-B
/ null / A-B / null / A-B để máy trôi thì trôi cho cả hai.

Hiệu ứng biến mất.

Độ tản trong một cấu hình giải thích vì sao — lần chạy 2, khung 0 theo từng lần
mount:

```
[ab-cold] frame0 mount 00  before 39.131ms  after  4.617ms
[ab-cold] frame0 mount 01  before  4.651ms  after  4.341ms
[ab-cold] frame0 mount 02  before 13.183ms  after 14.230ms
[ab-cold] frame0 mount 03  before  4.236ms  after 13.344ms
[ab-cold] frame0 mount 04  before 13.363ms  after 12.372ms
[ab-cold] frame0 mount 05  before 13.517ms  after 13.608ms
[ab-cold] frame0 mount 06  before  4.240ms  after 12.545ms
[ab-cold] frame0 mount 07  before 10.091ms  after 12.316ms
[ab-cold] frame0 mount 08  before 15.328ms  after 12.021ms
[ab-cold] frame0 mount 09  before  8.158ms  after 12.445ms
[ab-cold] frame0 mount 10  before 12.480ms  after 11.927ms
[ab-cold] frame0 mount 11  before 15.052ms  after 13.397ms
[ab-cold] frame0 mount 12  before 13.371ms  after 10.421ms
[ab-cold] frame0 mount 13  before 17.116ms  after 13.763ms
[ab-cold] frame0 mount 14  before 13.672ms  after 13.372ms
[ab-cold] frame0 mount 15  before  4.727ms  after 15.908ms
[ab-cold] frame0 mount 16  before  9.667ms  after 12.537ms
[ab-cold] frame0 mount 17  before 12.792ms  after 13.241ms
[ab-cold] frame0 mount 18  before 14.049ms  after  4.923ms
[ab-cold] frame0 mount 19  before 16.204ms  after 16.234ms
```

4,2ms tới 39ms **trong cùng một cấu hình**. Trung vị của 9 mẫu rút từ một phân bố
như thế có sai số vài chục phần trăm — không phải vì máy nhiễu mà vì mẫu ít.
(Con số 39,1ms ở lần mount 0 là hoá đơn một-lần của cả tiến trình mà `j1` mục 3
đã đo và đặt tên; nó luôn rơi vào cấu hình đứng đầu danh sách.)

---

## 4. Bộ đo có mù không? Đếm lượt `body`, không đoán

Một kết quả "không có tác dụng" chỉ có nghĩa nếu bộ đo *nhìn thấy được* tác dụng
ấy khi nó có mặt — nguyên tắc của `h1` và của `j1`. Nên trước khi kết luận, đếm.

Một bộ đếm tạm ở đầu `PlayerCard.body` và một ở đầu `ArtworkSlot.body`; đặt lại
về 0 **sau** `warmUp()`, rồi `tapToOpen()` và đúng **một** lượt cập nhật đồng bộ
(chính là khung mà cổng chặn chấm), rồi đếm lại sau khi run loop đã chạy xong cú
morph:

```
[wiring] before        : frame 0 card 3 slot 0  |  after settle card 4 slot 0
[wiring] before + extra: frame 0 card 4 slot 0  |  after settle card 5 slot 0
[wiring] after (scoped): frame 0 card 2 slot 3  |  after settle card 3 slot 4
```

Ba điều đọc ra, và cả ba đều quan trọng:

**1. Bản sửa làm đúng cái nó hứa.** Khung 0 đi từ **3 lượt `PlayerCard.body`
xuống 2**. Một phần ba số lượt dựng lại cả thẻ ở khung đắt nhất, biến mất. Đây
không phải suy luận về nội bộ SwiftUI, đây là một bộ đếm.

**2. Brief mô tả thiếu một lượt, và nó nói ngược lại chính brief.** Brief viết
`PlayerCard` bị bắt dựng lại **"hai lượt thừa"** ở mỗi lần đổi bài, một từ
`.onChange` và một từ `.task`. Đo ra: ở khung 0 có **ba** lượt tổng cộng, và
`.task` **không** đóng góp lượt nào trong đó — thân nó là một `Task` trên main
actor, chỉ tiếp đất sau khi lượt cập nhật ấy xong, nên nó là lượt thứ tư ở cột
"after settle". Ba lượt của khung 0 là: lượt do `currentTrack` đổi, lượt do
`onChange(of: explicitSelections)` gọi `expand()`, và lượt do
`onChange(of: artworkIdentity)` gọi `refreshCachedCover`. Bản sửa bỏ đúng lượt
cuối.

**3. Đối chứng dương đầu tiên của tôi là một đối chứng hỏng, và nó tự khai ra.**
Bản đầu của công tắc `abExtraBodyPass` ghi thêm một `@State` **ngay trong cùng
`onChange`** với `refreshCachedCover`. Bộ đếm: `frame 0 card 3` — **y hệt
`before`**. SwiftUI gộp mọi lần ghi trong một lượt thành một cú làm-mất-hiệu-lực,
nên "thêm một lần ghi" thêm đúng **không** lượt dựng lại. Đó là phát hiện §3 của
`h1` ("bốn lần ghi trong một khung tốn đúng bằng một lần") tới từ một hướng khác
và trên một cơ chế khác — và nếu tôi tin con số thời gian mà không đếm, tôi đã
báo cáo một "đối chứng dương cho ra 0" và dùng nó để nói rằng bộ đo mù.

Đối chứng dương thật phải là một cú ghi **dây chuyền** — ghi để đáp lại lượt
trước, nên không gộp được:
`.onChange(of: abPassCounter) { abPassCounter2 += 1 }`. Bộ đếm khi ấy ra
`frame 0 card 4`, tức nó thật sự thêm một lượt.

---

## 5. Đối chứng dương: **một** lượt `body` của cả thẻ đáng bao nhiêu ở khung 0?

`before` (3 lượt) so với `before + extra` (4 lượt), cùng bộ đo, 20 lần mount, ba
lần chạy:

```
[ab-extra] FRAME 0: before 11.857ms, extra 14.314ms, delta +20.7%
[ab-extra] FRAME 0 paired: extra cheaper in 4/20 repetitions
[ab-extra] FRAME 0: before 12.210ms, extra 13.692ms, delta +12.1%
[ab-extra] FRAME 0 paired: extra cheaper in 7/20 repetitions
[ab-extra] FRAME 0: before 13.186ms, extra  9.715ms, delta -26.3%
[ab-extra] FRAME 0 paired: extra cheaper in 10/20 repetitions
```

Trung vị **+12,1%**. Hai lần chạy đầu là hiệu ứng thật và mạnh theo thống kê cặp
(4/20 và 7/20 — dưới ngưỡng 50% xa; với 20 phép thử độc lập thì 4/20 có xác suất
ngẫu nhiên cỡ 6·10⁻⁴). Lần chạy thứ ba là 10/20, tức không có gì.

**Đây là trần của cả ý tưởng K1, đo trực tiếp.** Nếu *thêm* một lượt đáng khoảng
+12% và không đáng tin ở một trong ba lần chạy, thì *bỏ* một lượt không thể đáng
−15% một cách ổn định. Và bản sửa còn không được hưởng trọn con số ấy: nó không
**bỏ** lượt thứ ba, nó **đổi** nó lấy một lượt `body` của ô bìa cộng phần layout
của một vùng bằng cả tấm thẻ (ảnh tràn màn hình 390×874).

Điều này khớp với hai kết luận đã có, đo bằng hai bộ đo khác:

- `h1` §3: *"Cú chạm — nơi `body` chạy đúng một lần — đã ngốn 75% chi phí của một
  khung kéo. Nghĩa là thứ đắt vẫn đắt trong khi `body` đứng yên."*
- `j1` §2: *"chi phí đi theo **lượng cây**, không đi theo số animation"* — tắt tám
  khối view làm khung 0 rơi −84,6%.

Ba bộ đo, ba cơ chế, cùng một câu: **chạy `body` không phải chỗ tốn tiền; dựng và
so cái cây mà `body` sinh ra mới là.** Thu hẹp *ai bị làm mất hiệu lực* không thu
hẹp *cây phải dựng lại* khi cái cây ấy vẫn là tấm ảnh cỡ màn hình.

---

## 6. Ba lần chạy xen kẽ, verbatim

Ba lần gọi `xcodebuild` độc lập, 20 lần mount mỗi cấu hình, 60 khung,
`-parallel-testing-enabled NO`, đảo thứ tự cấu hình ở các lần lặp lẻ. Xen kẽ với
ba lần chạy đối chứng null trên cùng máy cùng buổi.

### Khung 0 — vế thứ nhất của cổng chặn

```
[null-cold] FRAME 0: before 11.368ms, after 10.907ms, delta -4.1%
[null-cold] FRAME 0 paired: after cheaper in 12/20 repetitions
[ab-cold]   FRAME 0: before  9.354ms, after  9.989ms, delta +6.8%
[ab-cold]   FRAME 0 paired: after cheaper in 13/20 repetitions

[null-cold] FRAME 0: before 14.314ms, after 14.271ms, delta -0.3%
[null-cold] FRAME 0 paired: after cheaper in 12/20 repetitions
[ab-cold]   FRAME 0: before 13.363ms, after 12.545ms, delta -6.1%
[ab-cold]   FRAME 0 paired: after cheaper in 10/20 repetitions

[null-cold] FRAME 0: before 13.863ms, after 14.032ms, delta +1.2%
[null-cold] FRAME 0 paired: after cheaper in 11/20 repetitions
[ab-cold]   FRAME 0: before 14.885ms, after 14.597ms, delta -1.9%
[ab-cold]   FRAME 0 paired: after cheaper in 13/20 repetitions
```

A/B: **+6,8% / −6,1% / −1,9%**, trung vị −1,9%, thắng theo cặp 13/10/13 trên 20.
Đối chứng null: **−4,1% / −0,3% / +1,2%**, thắng theo cặp 12/12/11 trên 20.

**Hai bộ số không phân biệt được với nhau.** Không phải "nhỏ" — là *chưa phân
giải được*, theo đúng nghĩa `h1` đặt cho chữ ấy.

### Đỉnh — vế thứ hai của cổng chặn

```
[ab-cold] PEAK before  9.354ms at frame 0; after  9.989ms at frame 0; ratio 1.07x
[ab-cold] MORPH PEAK (frames 1+) before 2.060ms at frame 2; after 2.022ms at frame 2; ratio 0.98x
[ab-cold] WORST single frame (1+) across all mounts, before: 4.730ms / after: 4.550ms

[ab-cold] PEAK before 13.363ms at frame 0; after 12.545ms at frame 0; ratio 0.94x
[ab-cold] MORPH PEAK (frames 1+) before 3.062ms at frame 8; after 3.100ms at frame 17; ratio 1.01x
[ab-cold] WORST single frame (1+) across all mounts, before: 4.801ms / after: 5.114ms

[ab-cold] PEAK before 14.885ms at frame 0; after 14.597ms at frame 0; ratio 0.98x
[ab-cold] MORPH PEAK (frames 1+) before 3.627ms at frame 25; after 3.277ms at frame 18; ratio 0.90x
[ab-cold] WORST single frame (1+) across all mounts, before: 4.828ms / after: 4.846ms
```

`MORPH PEAK` và `WORST single frame` được in ra **đích danh vì `i1`**: `i1` chỉ
"không tạo đỉnh mới" nhờ mượn khung 0 — vốn đắt vì chuyện khác — làm mốc so sánh,
và ở lần chạy thứ ba cái cớ ấy hết. Ở đây cả hai thước đo bỏ hẳn khung 0 ra và
vẫn sạch: đỉnh phần morph lệch dưới 10%, và khung tệ nhất trên **mọi** lần mount
nằm trong 4,5–5,1ms ở cả hai cấu hình, cả ba lần chạy. Không có gì giống cái gai
10–18ms của `i1`.

---

## 7. Đường cong theo từng khung, trước và sau

### Lần chạy 3, verbatim, 60 khung, trung vị 20 lần mount

```
[ab-cold] frame 00  t=   0.0ms  before 14.885ms  after 14.597ms
[ab-cold] frame 01  t=  16.7ms  before 0.454ms  after 0.511ms
[ab-cold] frame 02  t=  33.3ms  before 1.896ms  after 1.807ms
[ab-cold] frame 03  t=  50.0ms  before 2.521ms  after 2.025ms
[ab-cold] frame 04  t=  66.7ms  before 2.642ms  after 2.659ms
[ab-cold] frame 05  t=  83.3ms  before 3.165ms  after 2.942ms
[ab-cold] frame 06  t= 100.0ms  before 2.989ms  after 3.118ms
[ab-cold] frame 07  t= 116.7ms  before 2.213ms  after 2.379ms
[ab-cold] frame 08  t= 133.3ms  before 3.174ms  after 3.042ms
[ab-cold] frame 09  t= 150.0ms  before 3.272ms  after 3.079ms
[ab-cold] frame 10  t= 166.7ms  before 3.103ms  after 3.102ms
[ab-cold] frame 11  t= 183.3ms  before 3.250ms  after 3.012ms
[ab-cold] frame 12  t= 200.0ms  before 3.281ms  after 3.170ms
[ab-cold] frame 13  t= 216.7ms  before 3.088ms  after 2.957ms
[ab-cold] frame 14  t= 233.3ms  before 3.259ms  after 3.162ms
[ab-cold] frame 15  t= 250.0ms  before 3.493ms  after 3.210ms
[ab-cold] frame 16  t= 266.7ms  before 3.238ms  after 3.114ms
[ab-cold] frame 17  t= 283.3ms  before 3.137ms  after 3.177ms
[ab-cold] frame 18  t= 300.0ms  before 3.117ms  after 3.277ms
[ab-cold] frame 19  t= 316.7ms  before 2.981ms  after 3.089ms
[ab-cold] frame 20  t= 333.3ms  before 3.234ms  after 2.770ms
[ab-cold] frame 21  t= 350.0ms  before 3.434ms  after 3.106ms
[ab-cold] frame 22  t= 366.7ms  before 3.462ms  after 3.141ms
[ab-cold] frame 23  t= 383.3ms  before 3.453ms  after 2.894ms
[ab-cold] frame 24  t= 400.0ms  before 3.373ms  after 2.674ms
[ab-cold] frame 25  t= 416.7ms  before 3.627ms  after 2.824ms
[ab-cold] frame 26  t= 433.3ms  before 3.426ms  after 2.693ms
[ab-cold] frame 27  t= 450.0ms  before 3.444ms  after 3.019ms
[ab-cold] frame 28  t= 466.7ms  before 3.190ms  after 2.848ms
[ab-cold] frame 29  t= 483.3ms  before 3.067ms  after 2.704ms
[ab-cold] frame 30  t= 500.0ms  before 3.443ms  after 2.859ms
[ab-cold] frame 31  t= 516.7ms  before 2.993ms  after 2.396ms
[ab-cold] frame 32  t= 533.3ms  before 2.246ms  after 2.106ms
[ab-cold] frame 33  t= 550.0ms  before 2.491ms  after 2.336ms
[ab-cold] frame 34  t= 566.7ms  before 2.699ms  after 2.076ms
[ab-cold] frame 35  t= 583.3ms  before 2.565ms  after 2.199ms
[ab-cold] frame 36  t= 600.0ms  before 2.608ms  after 2.100ms
[ab-cold] frame 37  t= 616.7ms  before 2.571ms  after 2.419ms
[ab-cold] frame 38  t= 633.3ms  before 2.167ms  after 2.237ms
[ab-cold] frame 39  t= 650.0ms  before 2.715ms  after 2.633ms
[ab-cold] frame 40  t= 666.7ms  before 2.627ms  after 2.254ms
[ab-cold] frame 41  t= 683.3ms  before 2.545ms  after 2.322ms
[ab-cold] frame 42  t= 700.0ms  before 2.324ms  after 2.050ms
[ab-cold] frame 43  t= 716.7ms  before 2.191ms  after 2.175ms
[ab-cold] frame 44  t= 733.3ms  before 2.131ms  after 1.951ms
[ab-cold] frame 45  t= 750.0ms  before 2.649ms  after 2.233ms
[ab-cold] frame 46  t= 766.7ms  before 2.418ms  after 2.105ms
[ab-cold] frame 47  t= 783.3ms  before 2.489ms  after 2.159ms
[ab-cold] frame 48  t= 800.0ms  before 2.393ms  after 2.026ms
[ab-cold] frame 49  t= 816.7ms  before 2.515ms  after 2.067ms
[ab-cold] frame 50  t= 833.3ms  before 2.295ms  after 1.862ms
[ab-cold] frame 51  t= 850.0ms  before 2.406ms  after 2.175ms
[ab-cold] frame 52  t= 866.7ms  before 1.538ms  after 1.201ms
[ab-cold] frame 53  t= 883.3ms  before 1.277ms  after 1.143ms
[ab-cold] frame 54  t= 900.0ms  before 1.305ms  after 1.139ms
[ab-cold] frame 55  t= 916.7ms  before 1.272ms  after 0.912ms
[ab-cold] frame 56  t= 933.3ms  before 0.912ms  after 0.792ms
[ab-cold] frame 57  t= 950.0ms  before 0.937ms  after 0.585ms
[ab-cold] frame 58  t= 966.7ms  before 0.931ms  after 0.803ms
[ab-cold] frame 59  t= 983.3ms  before 1.065ms  after 0.896ms
```

Lần chạy 1, cùng cửa sổ, khung 0–39 (phần đuôi cùng hình dạng):

```
[ab-cold] frame 00  t=   0.0ms  before 9.354ms  after 9.989ms
[ab-cold] frame 01  t=  16.7ms  before 1.312ms  after 1.382ms
[ab-cold] frame 02  t=  33.3ms  before 2.060ms  after 2.022ms
[ab-cold] frame 03  t=  50.0ms  before 1.728ms  after 1.748ms
[ab-cold] frame 04  t=  66.7ms  before 1.832ms  after 1.780ms
[ab-cold] frame 05  t=  83.3ms  before 1.872ms  after 1.932ms
[ab-cold] frame 06  t= 100.0ms  before 1.906ms  after 1.932ms
[ab-cold] frame 07  t= 116.7ms  before 1.840ms  after 1.781ms
[ab-cold] frame 08  t= 133.3ms  before 1.821ms  after 1.883ms
[ab-cold] frame 09  t= 150.0ms  before 1.814ms  after 1.940ms
[ab-cold] frame 10  t= 166.7ms  before 1.752ms  after 1.793ms
[ab-cold] frame 11  t= 183.3ms  before 1.961ms  after 1.816ms
[ab-cold] frame 12  t= 200.0ms  before 1.922ms  after 1.910ms
[ab-cold] frame 13  t= 216.7ms  before 1.713ms  after 1.756ms
[ab-cold] frame 14  t= 233.3ms  before 1.711ms  after 1.777ms
[ab-cold] frame 15  t= 250.0ms  before 1.835ms  after 1.883ms
[ab-cold] frame 16  t= 266.7ms  before 1.756ms  after 1.879ms
[ab-cold] frame 17  t= 283.3ms  before 1.625ms  after 1.941ms
[ab-cold] frame 18  t= 300.0ms  before 1.954ms  after 1.817ms
[ab-cold] frame 19  t= 316.7ms  before 1.692ms  after 1.694ms
[ab-cold] frame 20  t= 333.3ms  before 1.798ms  after 1.892ms
[ab-cold] frame 21  t= 350.0ms  before 1.879ms  after 1.959ms
[ab-cold] frame 22  t= 366.7ms  before 1.776ms  after 1.837ms
[ab-cold] frame 23  t= 383.3ms  before 1.690ms  after 1.957ms
[ab-cold] frame 24  t= 400.0ms  before 1.845ms  after 1.976ms
[ab-cold] frame 25  t= 416.7ms  before 1.664ms  after 1.721ms
[ab-cold] frame 26  t= 433.3ms  before 1.866ms  after 1.921ms
[ab-cold] frame 27  t= 450.0ms  before 1.741ms  after 1.891ms
[ab-cold] frame 28  t= 466.7ms  before 1.711ms  after 1.706ms
[ab-cold] frame 29  t= 483.3ms  before 1.657ms  after 1.689ms
[ab-cold] frame 30  t= 500.0ms  before 2.055ms  after 1.981ms
[ab-cold] frame 31  t= 516.7ms  before 1.606ms  after 1.216ms
[ab-cold] frame 32  t= 533.3ms  before 1.507ms  after 1.436ms
[ab-cold] frame 33  t= 550.0ms  before 1.465ms  after 1.360ms
[ab-cold] frame 34  t= 566.7ms  before 1.411ms  after 1.415ms
[ab-cold] frame 35  t= 583.3ms  before 1.397ms  after 1.339ms
[ab-cold] frame 36  t= 600.0ms  before 1.377ms  after 1.402ms
[ab-cold] frame 37  t= 616.7ms  before 1.222ms  after 1.340ms
[ab-cold] frame 38  t= 633.3ms  before 1.411ms  after 1.379ms
[ab-cold] frame 39  t= 650.0ms  before 1.516ms  after 1.790ms
```

Log đầy đủ của cả sáu lần chạy (ba null, ba A/B), cả cột warm và cột đối chứng
dương, ở `k1-logs/` cùng thư mục này.

### Đọc hai đường cong

**Hình dạng giống hệt nhau ở mọi khung.** Không có khung nào mà `after` bật lên
so với hàng xóm của nó — không có gì giống khung 32 của `i1`. Ở lần chạy 3 đường
`after` nằm dưới đường `before` một cách đều đặn khoảng 0,3–0,7ms từ khung 20 trở
đi (và đó là **cả** phần đuôi sau khi thẻ đã đứng yên, tức nó *có thể* là một
khoản tiết kiệm nhỏ thật ở trạng thái nghỉ); ở lần chạy 1 hai đường chồng lên
nhau; ở lần chạy 2 `after` nằm hơi **trên**. Ba lần chạy, ba dấu — đúng chữ ký
của một đại lượng chưa phân giải được, không phải của một hiệu ứng.

Và một điểm mốc để đọc: khung 0 là **9,4–14,9ms** trong khi khung đắt thứ nhì là
**2,1–3,6ms**. Khung 0 vẫn gấp 4–7 lần mọi khung khác, ở **cả hai** cấu hình. Đó
là nhận xét §3 của `i1` còn nguyên hiệu lực sau đợt này.

---

## 8. Cú mở ấm, tách riêng

Cùng bộ đo, `alreadyPlaying: true` (dựng lại phép tách của `j1`: bài được chọn
**trước khi** gắn view, nên `warmUp()` nuốt trọn phần "bài vừa tới" và
`tapToOpen()` chỉ còn cú morph). 20 lần mount, ba lần chạy:

```
[ab-warm] FRAME 0: before 7.018ms, after 7.475ms, delta +6.5%
[ab-warm] FRAME 0 paired: after cheaper in 8/20 repetitions
[ab-warm] PEAK before 7.018ms at frame 0; after 7.475ms at frame 0; ratio 1.07x

[ab-warm] FRAME 0: before 6.298ms, after 6.740ms, delta +7.0%
[ab-warm] FRAME 0 paired: after cheaper in 7/20 repetitions
[ab-warm] PEAK before 6.298ms at frame 0; after 6.740ms at frame 0; ratio 1.07x

[ab-warm] FRAME 0: before 4.571ms, after 4.679ms, delta +2.4%
[ab-warm] FRAME 0 paired: after cheaper in 4/20 repetitions
[ab-warm] PEAK before 4.571ms at frame 0; after 4.679ms at frame 0; ratio 1.02x
```

**Đắt thêm, và dấu ổn định qua cả ba lần chạy.** +6,5 / +7,0 / +2,4%, thắng theo
cặp 8/20, 7/20, 4/20 — cả ba đều dưới 50%, tức `after` thua nhiều hơn thắng ở cả
ba lần chạy và cả 60 lần lặp. Độ lớn nằm quanh sàn nhiễu nhưng dấu thì không
ngẫu nhiên.

Giải thích, và nó không cần một giả thuyết mới: trên đường ấm `artworkIdentity`
**không đổi**, nên không có lượt `body` nào để bỏ đi — bản sửa chỉ còn thêm vào
một tầng view identity và một thân view phải chạy mỗi khi thẻ chạy. Đúng như phép
tách lạnh/ấm của `j1` dự đoán: cái này sửa nửa "bài vừa tới", và nửa còn lại chỉ
phải trả tiền.

Phép tách lạnh/ấm của `j1` cũng tái lập được ở đây, như một đối chứng phụ: khung
0 lạnh 13,4–14,9ms so với ấm 4,6–7,0ms, tức cú mở ấm rẻ hơn 50–66%. `j1` đo được
−54,5%. Cùng khoảng, bộ đo dựng lại từ đầu.

---

## 9. Áp cổng chặn

Cổng chặn có hai vế, nối bằng **và**:

> 1. Khung 0 của cú mở **lạnh** giảm ít nhất **15%**, qua ít nhất ba lần chạy xen
>    kẽ trong cùng tiến trình.
> 2. **Không có gai mới** ở bất kỳ khung nào.

- **Vế 1: TRƯỢT.** +6,8% / −6,1% / −1,9%. Không lần chạy nào tới −15%; không lần
  chạy nào ra khỏi sàn nhiễu ±4pp đo được của chính bộ đo này; thắng theo cặp
  13/10/13 trên 20 so với 12/12/11 của đối chứng null.
- **Vế 2: ĐẠT.** Đỉnh vẫn ở khung 0 ở cả hai cấu hình (tỉ lệ 1,07 / 0,94 / 0,98);
  đỉnh phần morph, bỏ khung 0 ra, 0,98 / 1,01 / 0,90; khung tệ nhất trên mọi lần
  mount 4,5–5,1ms ở cả hai cấu hình.

**Nối bằng "và" ⇒ trượt.** Và nó trượt ở vế mà không có cách đọc nào cứu được:
không phải "giảm 12% thay vì 15%", mà là *không đo được một cái giảm nào*.

Cộng thêm một khoản đắt lên nhỏ nhưng ổn định ở đường ấm (mục 8), tức là ở nửa
kia của cú mở người dùng gặp mỗi lần bấm vào viên thuốc mà không đổi bài.

**Không chỉnh cổng chặn. Không đi tìm thiết kế thứ hai để lách qua. Đã vứt bản
sửa.**

### Vì sao không thử một thiết kế thứ hai

Brief cho phép, với điều kiện đo nó và nói ra. Đã cân nhắc và **không thử**, vì
mục 5 đã đóng cửa bằng số chứ không bằng lý lẽ: đối chứng dương nói **một** lượt
`PlayerCard.body` ở khung 0 đáng khoảng +12% và không ổn định. Mọi biến thể của
"thu hẹp phạm vi dựng lại" đều là một cách khác để mua đúng món hàng ấy. Không có
biến thể nào mua được nhiều hơn một lượt: bộ đếm nói khung 0 chỉ có **ba** lượt,
một trong ba là cú dựng đầu tiên (không bỏ được) và một là `expand()` (không
thuộc đợt này).

Muốn đi xa hơn thì phải nhắm vào thứ mà `j1` §2 đo ra là −84,6%: **lượng cây phải
dựng ở khung 0**, tức `NowPlayingContent` (−38%) và `MiniPlayerChrome` (−25%). Đó
là một đợt khác, và `i1` §10 đã ghi lại rằng đường đi hứa hẹn là *làm chúng rẻ
đi*, không phải chọn xem trả tiền lúc nào.

---

## 10. Kiểm tra đột biến

Một test mới đã được viết và đã chạy: `PlayerCardArtworkSlotTests.`
`testTheFallbackCoverIsOnScreenOnTheFrameTheTrackChanges`. Nó **không** được
commit (không có commit nào), nhưng nó được giữ lại nguyên văn ở
`k1-PlayerCardArtworkSlotTests.swift.keep` cùng thư mục này, vì nó xanh trên mã
**hiện tại** ở `5043d08` và ghim đúng tính chất mà brief bắt phải giữ.

Nó đo bằng pixel: hai bài, hai bìa một-màu (đỏ và xanh lá), cả hai đã có trong
cache `ArtworkStore` như một hàng danh sách vừa cuộn qua sẽ để lại. Mở bài đỏ, để
mọi thứ lắng, rồi `play(green)` và **không cho run loop chạy một lần nào** trước
khi đọc pixel — nên không một `Task` nào có thể đã tiếp đất, và thứ vẽ ra chỉ có
thể tới từ đường đồng bộ.

Hai đột biến, cả hai chạy trên mã sản phẩm ở `5043d08`:

**Đột biến 1 — dời `refreshCachedCover` từ `.onChange` vào thân `.task`.**
Chính là cách hỏng mà brief gọi tên ("dời chỗ mà làm nó chạy muộn hơn là mất
chính thứ nó tồn tại để làm"). **ĐỎ**, cả hai assertion:

```
XCTAssertLessThan failed: ("97") is not less than ("11") —
  the card is still drawing the previous track's cover on the frame the track changed: (r: 97, g: 11, b: 11)
XCTAssertGreaterThan failed: ("11") is not greater than ("137") —
  the cached fallback cover was not on screen on the frame the track changed: (r: 97, g: 11, b: 11)
```

**Đột biến 2 — bỏ chốt `cachedCoverOwner == artworkIdentity` ở
`displayedArtwork`** (trả thẳng `cachedCover`). **SỐNG SÓT. Test vẫn xanh.**

Và đó là dữ liệu, không phải nhiễu — nên nó được báo cáo chứ không giấu đi. Lý do
nó sống sót đọc ra được từ chính mã: ở khung mà test chấm, `.onChange` **đã** chạy
rồi, nên `cachedCover` đã là ảnh của bài xanh và `cachedCoverOwner` đã là bài
xanh. Chốt chủ sở hữu chỉ có việc để làm trong cửa sổ **trước khi** `onChange`
chạy — tức trong đúng lượt `body` đầu tiên của bài mới, một trạng thái không quan
sát được từ ngoài vì `onChange` chạy trong cùng lượt cập nhật ấy và cây layer chỉ
được đọc sau khi lượt ấy xong.

**Hệ quả phải nói thẳng: assertion thứ nhất của test ấy (`onSwitch.r < onSwitch.g`)
không ghim được chốt chủ sở hữu như tên nó gợi ý.** Nó ghim đúng một thứ —
assertion thứ hai — là *bìa dự phòng có mặt ở khung ấy*. Nếu test này từng được
commit, câu chú thích ở đầu nó phải nói đúng chừng ấy, và assertion thứ nhất nên
đổi thành một khẳng định về mảng `placeholderTile` chứ không phải về "bìa bài
trước". Chốt chủ sở hữu vẫn cần một cách kiểm khác — nhiều khả năng là một test
thuần trên một hàm nhận cả bốn giá trị, chứ không phải một test pixel.

Bộ đo A/B cũng được kiểm đúng cái nó cần: xem mục 4. Nó **đã** bắt được một đối
chứng dương hỏng (một công tắc không nối vào đâu cả), bằng bộ đếm chứ không bằng
đồng hồ.

---

## 11. Toàn bộ suite, trên cây đã hoàn nguyên

```
xcodebuild -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

```
Executed 540 tests, with 6 tests skipped and 0 failures (0 unexpected) in 130.861 (131.019) seconds
** TEST SUCCEEDED **
```

540 test, 534 pass, 0 fail, 6 skip — **đúng bằng con số `h1` và `i1` ghi lại**,
tức cây đã về đúng chỗ cũ. `TabSelectionWashTravelTests` xanh; nó cũng xanh ở lần
chạy song song trước đó. Không phải xử lý ngoại lệ nào.

```
$ git status --short
$ git diff --stat HEAD
$ git log --oneline -1
5043d08 test: bộ đo chi phí commit của PlayerCard, có đối chứng
$ grep -c "abScopedArtwork\|abExtraBodyPass\|abBodyRuns\|abSlotRuns\|abPassCounter\|ArtworkSlot\|bodyContent" \
    Evenstar/Evenstar/Features/Player/PlayerCard.swift
0
```

---

## 12. Những chỗ mâu thuẫn với brief

**1. Brief đếm sai số lượt, và sai theo chiều làm ý tưởng trông hay hơn.** Brief
viết `PlayerCard` bị bắt dựng lại "**hai lượt thừa**" mỗi lần đổi bài, một từ
`.onChange` và một từ `.task`. Đo bằng bộ đếm: khung 0 có **ba** lượt tổng cộng
và `.task` **không** đóng góp lượt nào trong đó (nó tiếp đất sau, ở lượt thứ tư).
Nên thứ bản sửa có thể lấy được ở khung 0 là **một** lượt trên ba, không phải hai
lượt thừa.

**2. "Ghi vào `@State` bắt toàn bộ thân view 2.900 dòng chạy lại và so lại" —
đúng, và không quan trọng.** Nó chạy lại thật; bộ đếm chứng minh. Nhưng đối chứng
dương đo trực tiếp cái giá của một lượt như thế ở khung 0: trung vị +12%, không
ổn định qua ba lần chạy. Đó là lần thứ ba trong bốn đợt mà "SwiftUI dựng lại cây
nên nó phải đắt" hoá ra không đứng riêng ra được (`h1` §3 với `dissolveStops`,
`j1` §1 với việc dựng animation, và giờ là đây).

**3. Con số "54% của khung 0 không phải cú morph" đúng và tái lập được, nhưng nó
không chỉ tới bản sửa này.** Phép tách lạnh/ấm ở đây ra 50–66%, khớp `j1`. Nhưng
nửa "bài vừa tới" ấy hoá ra gần như hoàn toàn là **cây view của một thẻ có bài
được dựng lần đầu**, không phải hai lượt ghi `@State`. Brief đọc số của `j1` đúng
và quy trách nhiệm cho cái phần nhỏ nhất của nó.

**4. Sàn nhiễu của brief thừa hưởng từ `j1` (±16pp) là bi quan cho hình dạng
này**, đúng như brief đoán: hai cấu hình cho ±4pp ở 20 lần mount. Nhưng cùng lúc
brief **thiếu** một cảnh báo mà đợt này phải tự tìm ra: sàn nhiễu của *tổng* trên
cửa sổ 60 khung là ±50pp, tệ hơn hẳn ±5pp của `h1` trên 40 khung, vì phần đuôi
sau cú morph gần như rỗng và một cú `idle` trễ hạn đo ra rẻ hơn.

---

## 13. Những thứ để ý mà không sửa

1. **SwiftUI gộp mọi lần ghi trong một lượt, kể cả ghi vào hai `@State` khác
   nhau.** Đo được ở mục 4 bằng bộ đếm: thêm một lệnh `abPassCounter += 1` vào
   cùng `onChange` với `refreshCachedCover` thêm đúng **không** lượt dựng lại.
   `h1` §3 kết luận điều này bằng đồng hồ trên đường kéo; đây là cùng kết luận,
   đo bằng bộ đếm, trên đường đổi bài. **Hệ quả thực tế cho bất kỳ đợt sau nào:
   gộp thêm việc vào một `onChange` đã có là miễn phí về số lượt; tách nó ra
   thành một `onChange` phản ứng dây chuyền thì không.**

2. **Khung 0 vẫn là khung đắt nhất và vẫn chưa ai giải thích được nó.** 9,4–14,9ms
   so với 2,1–3,6ms của khung đắt thứ nhì, ở cả hai cấu hình, cả ba lần chạy.
   Đúng nhận xét §3 của `i1`, không suy suyển sau ba đợt.

3. **Cỡ giải mã đang được tính hai lần từ hai đường và phải bằng nhau bằng niềm
   tin.** `card(size:insets:)` tính `artworkSide` từ `fullSize` để vẽ;
   `loadArtwork` dựng lại `fullSize` từ `safeAreaSize`/`insets` rồi gọi lại
   `artworkSide(fullSize:topInset:)` để giải mã. Chú thích ở cả hai chỗ cảnh báo
   hai bên phải đồng ý. Bản sửa đã vứt xoá được sự trùng lặp ấy như một tác dụng
   phụ (truyền `decodeSide` vào), và **đó là điều duy nhất của bản sửa còn đáng
   giá sau khi số đo nói không**. Nó là một dọn dẹp một dòng, có thể làm riêng,
   không cần cổng chặn nào — nhưng không làm ở đợt này vì brief nói không sửa
   `PlayerCard.swift` khi cổng chặn trượt.

4. **Đường ấm chưa từng được ai đo trước `j1`, và nó là đường người dùng gặp
   nhiều hơn.** Mở lại player khi đang phát dở một bài (không đổi bài) là cú mở
   ấm. Nó rẻ hơn 50–66% so với cú mở lạnh. Mọi bản sửa nhắm vào cú mở lạnh cần
   được đo trên cả hai, vì như đợt này cho thấy, nó có thể lấy ở một bên và trả ở
   bên kia.

5. **Bẫy `-parallel-testing-enabled NO` mà `i1` §9.5 ghi lại vẫn còn nguyên** và
   vẫn chưa có một dòng nào trong doc của `CommitProbe.log` nói ra. Đợt này lại
   phải tự biết. Vẫn không sửa được vì file ấy nằm ngoài phạm vi cho phép.

---

## 14. Nếu có đợt sau

Không đề xuất bản sửa nào cho khu vực bốn `@State` này. Ba điều để đợt sau khỏi
đo lại:

1. **Thu hẹp phạm vi dựng lại của `PlayerCard` đã hết đất.** Khung 0 chỉ có ba
   lượt `body`; một là cú dựng đầu, một là `expand()`, một là ảnh bìa. Lượt cuối
   đã được đo trực tiếp và đáng khoảng +12% ở khung 0, không ổn định. `Slot` và
   `PlaybackScrubber` là hai tiền lệ đúng cho kỹ thuật này, nhưng chúng thu hẹp
   những cú ghi xảy ra **mỗi khung**; cái này xảy ra **một lần mỗi lần đổi bài**,
   và đó là khác biệt quyết định.
2. **Trần của mọi thứ ở đây là "lượng cây phải dựng ở khung 0".** `j1` §2 đo:
   `NowPlayingContent` −38%, `MiniPlayerChrome` −25%, tám khối cùng lúc −84,6%.
   Đó là chỗ có tiền, và `i1` §10 đã nói cách tiêu: làm chúng rẻ đi, không phải
   hoãn dựng.
3. **Đo bằng ít nhất 20 lần mount, chấm trên khung 0, kèm thống kê thắng theo
   cặp, và luôn kèm một đối chứng null cùng cỡ mẫu trong cùng buổi.** 9 lần mount
   cho ra −42,9% cho một thay đổi mà 20 lần mount cho ra −1,9%. Đó là số liệu
   suýt trở thành bản vá thứ bảy.

Đây là lần thứ sáu ở khu vực này mà một giả thuyết nghe rất hợp lý hoá ra sai.
Khác biệt lần này, như `i1`: nó chết trước khi tới tay người dùng, và chết bằng
số — hai lần, vì lần đo đầu tiên suýt nói ngược lại.
