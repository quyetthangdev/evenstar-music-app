# Cú bung player giật ở khung đầu — bốn vòng đo, rồi một cú chụp ảnh

> **ĐÃ CŨ MỘT PHẦN. Đọc [`l1-report.md`](l1-report.md) trước.** Thủ phạm là
> **offscreen rasterization**, và bốn vòng đo dưới đây không thể thấy nó: bộ đo
> của chúng dừng ở `CATransaction.flush()`, tức chỉ đo pha commit, còn bảng A1
> của chính dự án cho thấy 86% chi phí của lỗi cùng loại nằm ở render và GPU.
> Hai phút chụp Color Offscreen-Rendered Yellow trên Release tìm ra chỗ mà bốn
> vòng này không tìm ra.
>
> **E2 đã chạy ngày 2026-08-19** và nó đóng lại câu hỏi cuối của khu vực này:
> GPU chỉ chiếm **7,3%** hitch, nên bốn lớp offscreen trên `artworkView`
> ("nhóm B") **không đáng tách**. Chi phí nằm ở main thread khi SwiftUI dựng và
> so cây view — đúng thứ `h1`/`j1`/`k1` kết luận từ phía bộ đo commit-phase.
> Hitch đi từ 73,5 xuống **22,9 ms/giây**. Xem
> [`2026-08-19-e2-trace.md`](../2026-08-19-e2-trace.md).
>
> Phần dưới **vẫn đúng và vẫn đáng đọc** — sáu giả thuyết bị bác bỏ ở đây đều
> bị bác bỏ đúng, và phương pháp A/B đan xen của `h1` vẫn là khuôn tốt nhất
> repo này có. Chỉ có câu "chưa sửa được" là không còn đúng.

## Triệu chứng

Mở player bài **có ảnh bìa** thì cú bung khựng nhẹ; bài **không** có bìa thì
mượt. Người dùng phát hiện bằng tay trên bản Release, máy nguội — phép thử ấy có
giá trị hơn mọi thứ đo được trước nó, vì nó khoanh được vùng.

## Bốn thứ đã bị bác bỏ, kèm bằng chứng

| Giả thuyết | Bác bỏ bằng |
|---|---|
| Bóng đổ / lớp `Material` của thẻ (giống lỗi thanh tab đã đo 87,6 ms/giây) | Xếp hạng thành phần: cả hai không tách được khỏi nhiễu |
| Hai lớp hiệu ứng ảnh bìa (`.ultraThinMaterial` có mask, `dissolveStops`) | `h1`, `j1` — không phân giải; bản sửa nhắm vào chúng bị **revert** ở `b14ad5d` vì làm cả hai đường tệ hơn |
| Cú kéo tay ghi `@State` ở ~250Hz ⇒ 4 lượt dựng mỗi khung, 3 bị vứt | `h1` — SwiftUI **gộp** chúng: 4 lượt ghi mỗi khung tốn đúng bằng 1 (189,9 so với 189,6ms). Dòng chú thích nêu con số 250Hz trong `PlayerMorphUIKitView.swift` **không mô tả đúng thực tế**, và nó là căn cứ được nêu cho một cuộc port 1.855 dòng sang UIKit |
| Dựng đối tượng animation | `j1` — bỏ **toàn bộ** animation đổi khung 0 đi −18,8/+4,3/+5,1/−14,3%, vắt qua số 0 |

## Đã đo được gì

- **Cú morph rẻ.** 1–4ms mỗi khung. Chỉ **khung 0** đắt: ~16ms, vượt ngân sách
  16,67ms. Đó là cú rơi khung người dùng thấy.
- **Khung 0 đắt vì dựng và so cây view**, không vì animation.
- **54% khung 0 không phải cú morph.** Mở khi bài vừa được chọn ~16,2ms; mở khi
  thẻ đã sẵn bài ~7,3ms. Tỉ lệ 0,455, bốn lần chạy trong nửa điểm phần trăm.
- **Xếp hạng khung 0:** `NowPlayingContent` −38%, `MiniPlayerChrome` −25%, sáu
  thứ còn lại không phân giải. Tắt cả tám: −85% (16,5 → 2,5ms).
- **Một lượt dựng lại toàn thẻ chỉ đáng ~12%** (`k1`, positive control).
- **Lần mount đầu của tiến trình là hoá đơn riêng:** 50–195ms, một lần. Đó là
  câu hỏi của lớp làm nóng ở `RootView`, không phải của `PlayerCard`.
- Thiết bị (Instruments, iPhone 12, Release): pha commit trung vị **16,06ms**,
  **42%** số khung vượt ngân sách.

## Hai bản sửa đã dựng, đo, và vứt

| | Làm gì | Vì sao vứt |
|---|---|---|
| `i1` | Hoãn dựng `NowPlayingContent` khi thẻ đang morph | Tổng giảm 27% nhưng dồn thành một gai 15–18ms ở khung cuối, **cao hơn cả đỉnh cũ**. Chi phí bị *dời*, không mất |
| `k1` | Đưa bốn `@State` ảnh bìa xuống view con để thu hẹp phạm vi dựng lại | Đúng về cấu trúc — khung 0 đi từ 3 xuống 2 lượt dựng toàn thẻ — nhưng hiệu ứng không tách được khỏi null control. Một lượt chỉ đáng ~12%; **chưa bao giờ có 15% để lấy** |

Cả hai bị cổng chặn bắt **trước khi tới tay người dùng**. Bốn bản sửa trước đó
thì không, và một trong số ấy làm app tệ hơn hẳn.

## Bộ đo

`Evenstar/EvenstarTests/PlayerCardCommitCostTests.swift` (commit `5043d08`) —
host `PlayerCard` trong `UIWindow` thật, đo chi phí một lượt cập nhật ở từng
khung. **Có đối chứng**, và thiết kế đầu tiên của nó đã **trượt** đối chứng ấy
(một hình chữ nhật "chậm hơn" chồng sáu lớp, do vòng chờ bận làm animation đứng
im). Đừng tin một bộ đo chưa có đối chứng.

**Sàn nhiễu:** ±16 điểm phần trăm khi chấm trên *một* khung với nhiều cấu hình;
±3pp khi ít cấu hình. Chấm trên tổng 40 khung thì ±5pp.

## Nếu ai đó quay lại chỗ này

1. **Chi phí trải đều khắp cây, không đọng ở đâu gỡ được.** Không có mỏ nào chưa
   đào. Đường duy nhất còn lại là làm cây nhỏ đi về cấu trúc — nhiều ngày, và
   **bộ đo hiện tại không đủ nhạy để lái**: thứ cần đo có độ lớn ~12%, sàn nhiễu
   ±16%. Muốn đi đường ấy thì phải làm bộ đo nhạy hơn **trước**.
2. **Khung 0 chia hai, và hai nửa cần hai câu hỏi khác nhau.** Gộp chúng lại sẽ
   ra 15ms và không nói được gì — đó là chỗ `h1` và `i1` mắc kẹt.
3. **Con số 55–195ms không thuộc câu chuyện này.** Nó là lần mount đầu của tiến
   trình, một lần, và thuộc `RootView`.
4. **Đo trước, đừng suy luận.** Sáu lần thử ở đây, cả sáu bắt đầu từ một giả
   thuyết nghe hợp lý mà chưa đo. Hai lần cuối có cổng chặn nên không ai phải
   trả giá.
