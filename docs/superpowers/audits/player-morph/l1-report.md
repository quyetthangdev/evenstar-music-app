# L1 — Thủ phạm là offscreen rasterization, và bốn vòng trước không thể thấy nó

**Trạng thái: đã sửa một phần, có commit.** Thay đổi mã: đúng một chỗ trong
`PlayerCard.card(size:insets:)` — hình dùng để cắt thẻ. Kèm bảy test mới.

Không dùng bộ đo `h1`. Dụng cụ của đợt này là **Color Offscreen-Rendered
Yellow**, Release, iPhone 12, và **tay người dùng**. Tổng thời gian: một buổi
chiều, bảy lượt build trên máy thật.

---

## 0. Vì sao bốn vòng trước đo đúng mà tìm không ra

Bộ đo của `h1` bấm giờ đúng ba dòng:

```swift
view.setNeedsLayout(); view.layoutIfNeeded(); CATransaction.flush()
```

`CATransaction.flush()` **giao** transaction cho render server rồi trả về. Nó
không đợi rasterize, không đợi GPU. Nên bộ đo ấy đo **một cột trên ba**.

Bảng A1 của chính dự án, đo trên thiết bị, cho thấy cột ấy nhỏ thế nào ở đúng
loại lỗi này:

| Bản | hitch | commit | render | GPU |
|---|---|---|---|---|
| Material + bóng | 87,6 | 12,1 | 33,3 | 41,8 |
| Material, không bóng | **0,0** | 0,0 | 0,0 | 0,0 |

**86% chi phí nằm ngoài cột duy nhất mà `h1`–`k1` nhìn được.** Sáu bản sửa
trước không sai về SwiftUI; chúng nhắm vào cột không có tiền. Đó là lời giải
cho câu "chi phí trải đều khắp cây, không đọng ở đâu gỡ được" của README cũ:
nó trải đều vì thứ đang đọng nằm ở tầng khác.

Mục 5 của `h1` đã tự ghi rằng phép thử bằng tay trên Release *"có giá trị hơn
mọi thứ đo được trước nó"*. Đợt này chỉ làm đúng điều ấy, trước.

---

## 1. Bảy lượt chụp, mỗi lượt một biến

| # | đổi gì | màn danh sách | player không bìa | player có bìa |
|---|---|---|---|---|
| 0 | *(mã gốc)* | vàng hết | vàng hết | vàng hết |
| 1 | gỡ `.floatingBarShadow()` của thẻ | vàng hết | vàng hết | vàng hết |
| 2 | gỡ `.clipShape` của thẻ | **sạch** | gần sạch | vàng hết |
| 3 | gỡ thêm 4 lớp trên bìa | sạch | **sạch** | **sạch** |
| 4 | clip thẻ = `RoundedRectangle` **đều** | **sạch** | — | — |
| 5 | clip thẻ = `Rectangle()` | sạch | — | — |

Đọc ra ba thứ:

**A. `.clipShape(UnevenRoundedRectangle(...))` của thẻ làm cả màn hình bị
rasterize ngoài màn hình — ở mọi màn hình của app, kể cả khi player đóng**, vì
thẻ luôn nằm trong cây. Bốn bán kính khác nhau không ánh xạ xuống
`layer.cornerRadius` được (CA chỉ có **một** bán kính; `maskedCorners` chọn góc
nào nhận nó, không cho mỗi góc một số), nên SwiftUI phải dựng mask layer.
Lượt 4 chứng minh một bán kính **đều** thì hết.

**B. Bốn lớp trên `artworkView`** — `.overlay(.ultraThinMaterial + mask)`,
`.mask(dissolveStops)`, `.shadow`, `.clipShape` — gây offscreen **cỡ cả màn
hình, chỉ khi có bìa**, vì `hasArtwork` bật chế độ full-bleed. Đây chính là
biến phân biệt người dùng báo từ đầu: *có bìa thì khựng, không bìa thì mượt*.
**Chưa sửa.**

**C. Phần vàng còn lại là Material** — `.thinMaterial` của viên thuốc, ba
`.regularMaterial` của thanh tab. Lượt 5 chứng minh nó không phải cú bo góc.

---

## 2. Giới hạn của dụng cụ, và nó cắn ở đâu

**Vàng chỉ nói *có offscreen*, không nói *đắt bao nhiêu*.** Bằng chứng nằm
ngay trong bảng A1: "Material, không bóng" đo ra **0,0 ms/giây** — miễn phí —
mà nó **vẫn vàng**.

Hệ quả cụ thể trong đợt này: ở lượt 1 tôi kết luận *"bóng không phải thủ phạm"*
vì màu vàng không đổi. Kết luận ấy **không có cơ sở** — công cụ không phân biệt
được đúng cái khác biệt ấy. Thẻ vẫn có `.thinMaterial` ở nền **và**
`.floatingBarShadow()` chồng lên, tức đúng cặp đã đo được 87,6 ms/giây ở thanh
tab. Số phận của cái bóng ấy vẫn là câu hỏi mở, đúng như doc của
`BottomBarStyle.floatingShadow` đã ghi.

Muốn xếp hạng bên trong nhóm đã tìm ra thì phải chạy **E2** (trace
`Animation Hitches`, ba cột riêng) hoặc thử tay từng lớp. Không phải chụp thêm ảnh.

---

## 3. Bản sửa

Một chỗ: hình cắt thẻ, `UnevenRoundedRectangle` → `RoundedRectangle` bán kính
đều, qua một `CardClip` `ViewModifier`.

**Vì sao đúng vẻ ngoài.** Thu gọn thì bốn góc vốn đã bằng nhau (32 = nửa chiều
cao viên thuốc). Mở hết thì hai góc dưới nằm ở mép màn hình, mà thiết bị tự bo
nhiều hơn (iPhone 12 ~47pt, 14 Pro ~55pt), nên góc bo 38 của thẻ nằm trọn trong
phần đã bị cắt. Khác thật chỉ ở giữa chừng: đáy thẻ bo 32→38 thay vì vuông dần
về 0 — người dùng nhìn và không thấy sai.

**Vì sao phải rẽ nhánh theo máy.** Lý lẽ trên đứng được nhờ màn hình bo góc.
iPhone SE 2/3 và iPad có nút Home có màn hình **góc vuông**; ở đó nhánh đều sẽ
hở hai lỗ tròn ở đáy player mở hết. Phân biệt bằng **safe-area inset dưới**:
đúng một lớp máy có màn bo góc, và đó là lớp có thanh Home ảo, tức lớp có inset
dưới khác 0. Không dùng API private `_displayCornerRadius`.

**Biên an toàn 1pt, đã ghim.** Máy có màn bo góc hẹp nhất còn chạy iOS 18 là
iPhone XS / 11 Pro ở ~39pt, so với `expandedCornerRadius` = 38.
`testTheExpandedCornerStaysInsideTheNarrowestRoundedDisplay` đỏ nếu ai nâng con
số ấy lên 40 — kiểm bằng đột biến, đã chạy.

**Kết quả.** Người dùng xác nhận mượt hơn, thử tay trên Release, hai lượt độc
lập. Màn danh sách sạch hoàn toàn. Suite 547 test, 0 fail.

Nhân tiện, bộ đo commit-phase của `h1` cũng thấy: thẻ thật đi từ **124,90ms**
(`h1` ghi) xuống 57–104ms qua ba lần chạy. Dựng mask layer có một phần chi phí
nằm ở main thread — nên `h1` *chạm* được vào nó, chỉ là phần chạm được quá nhỏ
để nổi lên trên sàn nhiễu ±5pp.

---

## 4. Ba thứ tìm ra kèm, chưa sửa, đã xác nhận **có trên mã gốc**

1. **Nhóm B — bốn lớp trên bìa.** Phần còn lại của cú khựng, và là phần gác
   theo `hasArtwork`. Đây là việc tiếp theo.

2. **Bìa không lớn dần theo thẻ** (*"như kiểu ảnh có sẵn"*). Cơ chế đã tìm ra:
   `if source == .image` trong `artworkView` là một `if` **cấu trúc**, và
   `loadArtwork` ghi `artwork` bằng một cú ghi `@State` trần. Khi cú giải mã
   tiếp đất giữa cú morph, `Image` bị **chèn** vào cây mà không nối vào
   animation đang bay. Lưới an toàn là `cachedCover`/`anyCachedImage` — doc của
   nó đã gọi đúng tên triệu chứng này: *"it is the cover failing to grow with
   the card"* — và nó chỉ bắt được khi bài ấy từng được giải mã ở *một cỡ nào
   đó* trong tiến trình.

3. **Blur trễ khi thu nhỏ.** Vùng thanh tab giữ blur suốt cú thu nhỏ rồi mới
   đổi một phát sau khi xong. Chưa tìm ra cơ chế. Đã kiểm: **có trên mã gốc**,
   không phải do bản sửa này.

## 5. Một lãng phí thuần, độc lập với mọi thứ trên

`PlayerCard.loadArtwork` giải mã bìa ở `artworkSide × displayScale` (≈**1026**px
trên iPhone 12); `PlaybackService.lockScreenArtworkPixels` = **1024**px.
`ArtworkStore.cacheKey` là `"\(path)@\(Int(maxPixel))"`, nên hai khoá khác nhau
⇒ **hai lượt giải mã đầy đủ cùng một JPEG**, hai bitmap ~4MB, cách nhau đúng 2
pixel, chạy song song mỗi lần đổi bài. Cộng lượt thứ ba 48px cho
`dominantColor`.

Bộ đo của `h1`–`k1` không bao giờ thấy được chuyện này: `warmUp()` **cố ý** để
cú giải mã đầu tiên rơi ra ngoài phép đo, và `ArtworkStore` cache theo tiến
trình với một file 600×600 dùng chung cho mọi lần mount — nên trong ~200 lần
mount của cả bốn vòng, cú giải mã xảy ra đúng **một** lần, ở mount 0, tức đúng
con số 50–195ms mà cả bốn báo cáo gạt sang một bên là *"hoá đơn của `RootView`"*.

---

## 6. Nếu ai đó quay lại chỗ này

1. **Chụp Yellow trước khi viết bộ đo.** Hai phút, và nó tìm ra thứ bốn vòng đo
   công phu không thấy. Nhưng đọc mục 2 trước: nó chỉ định vị, không xếp hạng.
2. **Một biến mỗi lượt build.** Bảy lượt ở trên, mỗi lượt đổi đúng một thứ. Đó
   là lý do bảng ở mục 1 đọc được.
3. **Nhóm B là việc tiếp theo,** và `i1` §10 đã nói đúng cách tiêu tiền ở đó:
   làm các lớp ấy rẻ đi, không phải chọn xem trả tiền lúc nào.
