# Evenstar Phase 2a — Hướng dẫn QA trên iPhone thật

**Ngày:** 2026-08-01
**Nhánh:** `phase-2a` (30 commit, 47 test xanh, clean build không warning)
**Mục đích:** Bổ sung cho checklist trong Task 11 của plan. Danh sách này **xếp theo xác suất lộ lỗi**, dựa trên những gì các vòng review đã tìm thấy — không phải theo thứ tự tính năng.

---

## Điều quan trọng nhất cần biết trước khi bắt đầu

**Chưa có file nhạc nào từng được import vào app này.** Toàn bộ giao diện có dữ liệu thật — danh sách bài, mini player, màn hình Now Playing, thanh scrubber, vuốt xoá, tự chuyển bài — chưa từng render một lần nào. Tất cả mới chỉ được kiểm bằng đọc code và unit test với audio player giả lập. Simulator chỉ từng hiển thị màn hình trống.

Bạn là người chạy thật đầu tiên. Vì vậy hãy ghi lại **mọi** thứ trông lạ, kể cả khi nó không nằm trong danh sách này.

---

## Chuẩn bị

Chọn file nhạc **có chủ đích**, đừng dùng `test1.mp3`, `test2.mp3`:

- Ít nhất 3 bài có dấu tiếng Việt trong tên — ưu tiên bắt đầu bằng **Đ, Ư, Ơ, À, Ê**
- Vài bài bắt đầu bằng chữ **thường** và vài bài bắt đầu bằng chữ **HOA**
- Ít nhất 1 file **lớn** (FLAC hoặc WAV trên 50 MB)
- 1 file `.txt` đổi đuôi thành `.mp3` (để test file hỏng)
- 1 file `.txt` để nguyên (để test định dạng không hỗ trợ)
- Nếu được: vài file trên **iCloud Drive chưa tải về máy**

---

## Nhóm 1 — Gần như chắc chắn lộ lỗi

### 1.1 Thứ tự sắp xếp tiếng Việt
Import các bài có dấu, rồi nhìn thứ tự danh sách.

- **Đúng:** các bài có dấu nằm xen kẽ đúng vị trí alphabet, chữ hoa/thường không tách thành hai nhóm
- **Sai:** mọi bài có dấu bị dồn xuống cuối; hoặc tất cả bài chữ HOA đứng trước tất cả bài chữ thường

> Đây là lỗi đã được sửa ở đợt cuối (F1). Kiểm tra để xác nhận bản sửa có tác dụng thật trên thiết bị.

### 1.2 Xoá bài đang tạm dừng
Phát một bài → bấm **pause** → vuốt sang trái đúng dòng đó → Delete.

- **Đúng:** vẫn im lặng, bài kế tiếp được nạp nhưng **không tự phát**
- **Sai:** loa đột nhiên kêu

> Đã sửa ở F2. Đây là lỗi nhanh tái hiện nhất nếu bản sửa hỏng.

### 1.3 Lý do import thất bại
Import cùng lúc: 1 file `.txt` + 1 file `.mp3` giả (thực ra là text).

- **Đúng:** sheet hiện số lượng **và** lý do — ví dụ "Unsupported format: .txt" và "Could not extract audio metadata"
- **Sai:** chỉ hiện "2 failed" trống không

> Đã sửa ở F3. Checklist gốc yêu cầu rõ có lý do.

### 1.4 Import file iCloud chưa tải về  ✅ đã sửa, cần xác nhận
Chọn 4–5 file từ iCloud Drive **chưa tải xuống máy**.

- **Đã sửa:** sheet giờ cuộn được và kéo lên `.large` được, nên chữ không còn bị cắt.

  Cần xác nhận: kéo sheet lên cao, cuộn thử — mỗi dòng hiện ra có đọc trọn vẹn không, có dòng nào bị cắt ngang không, và nút "Done" có chạm tới được không?

  Lưu ý để bạn khỏi báo nhầm lỗi: danh sách **cố ý** chỉ hiện tối đa 4 lý do rồi gộp phần còn lại thành "+N more". Chọn 5 file thì thấy "+1 more" là **đúng thiết kế**, không phải bị cắt.

---

## Nhóm 2 — Lỗi đã biết còn tồn đọng, cần bạn xác nhận mức độ

### 2.1 Nháy icon khi tự chuyển bài  ⚠️ đã biết còn lỗi
Mở màn hình Now Playing, để một bài chạy **hết tự nhiên** (đừng bấm next), nhìn kỹ nút play/pause đúng lúc chuyển bài.

**Câu hỏi cụ thể:** icon có nháy sang trạng thái "paused" trong một khoảnh khắc rồi trở lại không?

- Nếu **có** → đúng là lỗi P1 đã ghi nhận. Nhạc vẫn chạy tiếp bình thường, chỉ là nháy hình. Cho tôi biết nó có khó chịu không.
- Nếu **không** → tốt, cửa sổ lỗi hẹp hơn dự đoán.

> Nguyên nhân: guard chống race dùng `currentTime < duration - 0.5`, nhưng `AVAudioPlayer.currentTime` trả về **0** sau khi bài kết thúc chứ không phải `duration`, nên guard không chặn được gì. Sửa một dòng nếu bạn thấy phiền.

### 2.3 Cuộc gọi đến giữa lúc nghe nhạc  ⚠️ nghi ngờ cao
Nhờ ai gọi vào máy khi đang phát nhạc. Sau khi cúp:

1. Mini player hiện icon gì? (đúng: icon **play**, tức đang dừng — không phải icon pause)
2. Màn hình khoá còn báo đang phát không?
3. Bấm play — **nhạc có thật sự kêu lại không?**

> Câu 1 và 2 đã được sửa ở F4. **Câu 3 nhiều khả năng vẫn hỏng** — `activateSessionIfNeeded()` chỉ chạy đúng một lần và không kích hoạt lại audio session sau khi hệ thống ngắt. Đây là lỗi có từ trước, thuộc phạm vi Phase 2d, nhưng bản sửa F4 khiến bạn gặp nó thường xuyên hơn. Nếu bấm play mà im lặng — đó chính là nó.

Làm lại thí nghiệm tương tự với **rút tai nghe** đang cắm.

### 2.4 Kéo thanh scrubber có làm card co lại không?  ⚠️ chưa kiểm chứng được
Chạm mini player để mở rộng thành Now Playing, rồi kéo thanh scrubber để tua bài — kéo vài lần, cả chậm lẫn nhanh.

**Câu hỏi cụ thể:** có lần nào card bị co lại (collapse) thay vì tua không?

Now Playing không còn là `.sheet` — nó chính là card đó ở đầu kia của phép biến hình, và cử chỉ kéo-để-đóng giờ là một `DragGesture` viết tay gắn trên toàn bộ card, không phải cử chỉ hệ thống của sheet nữa. Thanh scrubber là một view con nằm bên trong card, nên SwiftUI về nguyên tắc phải ưu tiên gesture của nó khi ngón tay chạm đúng track của slider — nhưng đó là điều cần xác nhận thật trên máy, không phải điều mặc định đúng. Thử kéo ngang trên track để tua, kéo dọc gần đó để card co lại, và vài lần bắt đầu chạm hơi lệch để xem gesture nào "thắng".

- Nếu slider luôn tua đúng, card không bao giờ co lại khi ngón tay đang ở trên track → không cần làm gì
- Nếu card thỉnh thoảng co lại khi đang kéo slider → cho tôi biết tần suất, có cách giới hạn vùng kích hoạt gesture của card

---

## Nhóm 3 — Kiểm tra quy mô (quan trọng cho lời hứa "1k–5k bài")

Ba vấn đề hiệu năng đã được **cố ý hoãn sang Phase 2b**. Chúng vô hình với 5 file. Mục đích ở đây là đo xem chúng tệ tới mức nào để xếp ưu tiên cho 2b.

### 3.1 Import lô lớn
Import 40–60 file cùng lúc, trong đó có file FLAC/WAV lớn. Bấm giờ.

- Thanh tiến trình chạy mượt hay **đứng rồi nhảy**?
- Tổng thời gian bao lâu?

> Nguyên nhân đã biết: file được copy **đồng bộ trên main thread**, và mỗi file lại quét toàn bộ bảng Track để chống trùng.

### 3.2 Cuộn danh sách lớn  ✅ đã sửa, cần xác nhận
Import 300+ bài (có ảnh bìa), rồi vuốt cuộn thật mạnh. Mở Xcode → Debug gauge xem bộ nhớ.

- Có giật khung hình không?
- Bộ nhớ nhảy lên bao nhiêu?

**Đã sửa:** `ArtworkStore` giờ giải mã ảnh đúng ở kích thước cần vẽ (downsample qua ImageIO) thay vì độ phân giải gốc, và cache kết quả bằng `NSCache` (~50 MB). Cuộn lại qua các dòng đã từng hiện ra trước đó phải mượt, vì ảnh đã nằm sẵn trong cache.

Lưu ý liên quan bản sửa F1 đợt cuối: lần giải mã **đầu tiên** của mỗi dòng — tức lần đầu nó xuất hiện trên màn hình — vẫn là một lần decode ảnh thật, giờ được đảm bảo chạy ngoài main thread bằng `@concurrent`. Cái cần theo dõi khi cuộn mạnh lần đầu qua danh sách chưa từng thấy là độ mượt của *những dòng mới xuất hiện lần đầu*; cuộn lùi lại qua các dòng đã thấy rồi thì phải mượt hoàn toàn vì đó là cache hit.

### 3.3 Thời gian khởi động với thư viện lớn
Sau 3.2: phát một bài → kill app từ App Switcher → mở lại → bấm giờ tới lúc mini player hiện ra.

> Nguyên nhân đã biết: khôi phục chạy **một truy vấn DB cho mỗi bài** trong queue, mà queue là toàn bộ thư viện.

---

## Nhóm 4 — Checklist gốc của plan

Chạy nốt các mục còn lại trong Task 11 của plan:

- [ ] Lần mở đầu tiên hiện màn hình trống với nút Import
- [ ] Import 5 file → "Imported 5"
- [ ] Import lại đúng 5 file đó → "5 duplicates skipped"
- [ ] Chạm bài hát → mini player hiện, nhạc phát
- [ ] Chạm mini player → card mở rộng thành Now Playing toàn màn hình; kéo xuống co lại về mini player; kéo scrubber, play/pause, next đều chạy
- [ ] Bài cuối kết thúc → mini player biến mất, màn hình khoá sạch
- [ ] Khoá máy khi đang phát → màn hình khoá hiện tên/ca sĩ/album/ảnh bìa + điều khiển được
- [ ] Bấm nút tai nghe (AirPods/EarPods) → play/pause chạy
- [ ] Kill app khi **đang phát** → mở lại → đúng bài, đang dừng, đúng vị trí (sai lệch dưới ~5 giây là **đúng thiết kế**, không phải lỗi)
- [ ] Xoá bài đang phát → mở lại app → queue co lại đúng, không mất các bài còn tốt

---

## Một cái bẫy dedupe đáng thử

Import **bản live và bản studio của cùng một bài** có cùng độ dài (làm tròn tới giây).

Quy tắc chống trùng là `(tên viết thường, ca sĩ viết thường, độ dài làm tròn)` — nên nó sẽ **âm thầm bỏ qua** bản thứ hai dù bạn thực sự muốn có cả hai. Đây là thiết kế theo spec, không phải lỗi, nhưng bạn nên biết trước khi nó ăn mất bài của bạn.

---

## Sau khi QA xong

Báo cho tôi những gì bạn gặp. Tuỳ kết quả:

- **Sạch hoặc chỉ lỗi nhỏ** → tag `phase2a-complete`, merge vào `main`, mở Phase 2b
- **Có lỗi thật** → tôi chạy systematic-debugging trên từng cái, sửa, rồi mới tag

---

## Nhóm 5 — Hai control mới trên Now Playing  *(thêm 2026-08-02)*

Phần này **quan trọng hơn mọi nhóm khác**, vì thanh âm lượng là thành phần duy nhất trong cả app **không có cách nào kiểm chứng tự động**. `MPVolumeView` không vẽ gì trên simulator — ảnh chụp không cho biết nó có tồn tại không, chứ đừng nói có chạy không. Bạn là tầng kiểm tra duy nhất của nó.

Làm theo đúng thứ tự này. Mục 5.1 mà hỏng thì mọi quan sát khác về âm lượng đều vô nghĩa.

### 5.1 Kéo được thanh âm lượng không?  ⚠️ nghi ngờ cao nhất
Mở Now Playing, đặt ngón lên thanh âm lượng (dưới hàng nút), kéo ngang.

- **Đúng:** âm lượng đổi theo ngón tay suốt quãng kéo
- **Sai kiểu A — không nhúc nhích:** vùng bắt của thumb quá nhỏ. Đã sửa từ 1×1 lên 30×30 nhưng chưa ai xác nhận được
- **Sai kiểu B — chạy khoảng 1cm rồi đứng:** đây là dự đoán P1. `DragGesture` của thẻ là `UIGestureRecognizer`, `UISlider` là `UIControl` dùng `touchesBegan/Moved` — khi cử chỉ của thẻ nhận diện, UIKit gửi `touchesCancelled` cho slider. Thẻ sẽ **không** thu về (kéo ngang nên `progress` gần như không đổi), nên nó trông như slider hỏng chứ không như xung đột cử chỉ

Phân biệt A với B rất quan trọng — hai nguyên nhân khác hẳn nhau.

### 5.2 Hai thanh có cùng màu không?
So thanh tiến trình và thanh âm lượng, **cả chế độ sáng lẫn tối**.

Nhìn riêng **phần chưa chạy tới** (bên phải). Nếu phần đó ở thanh âm lượng nhạt hơn rõ so với thanh tiến trình → vòng lặp tô màu không tìm thấy `UISlider`. Phần đã chạy (bên trái) có thể vẫn đúng nhờ `tintColor`, nên đừng chỉ nhìn nó.

### 5.3 Hai thanh có cùng chiều rộng không?
Cùng mép trái, cùng mép phải. Lệch nghĩa là `sizeThatFits` không ăn.

Cũng để ý **độ dày**: thanh tiến trình 7pt, track của `UISlider` khoảng 4pt. Chúng **sẽ** khác nhau. Bạn quyết xem có chướng không — có cách sửa bằng API chính thức, tôi đã ghi lại.

### 5.4 Kéo thanh tiến trình có làm thẻ thu về không?
Bắt đầu trên thanh, kéo ngang, cố tình lệch lên xuống. **Thẻ không được thu về.**

Đây là rủi ro đã treo từ khi player chuyển sang sheet rồi sang thẻ tự dựng. Giờ mới có dịp kiểm.

### 5.5 Chạm một cái vào thanh tiến trình
Nó sẽ **tua tới đúng chỗ đó**, không cần kéo. Không có undo.

Vùng nhạy là dải 342×28pt. Apple Music thật ra **bắt buộc phải kéo**, không tua khi chạm — comment trong code nói ngược lại và tôi ghi nhận đó là sai. Bạn thấy chạm-để-tua tiện hay dễ bấm nhầm?

### 5.6 Xem hoạt ảnh phình
Chạm và giữ trên thanh tiến trình. Ba thứ phải xảy ra **như một chuyển động**: vạch cao từ 7 lên 12pt, hai nhãn thời gian đậm lên, và phần tô chạy tới điểm chạm (không nhảy cóc).

### 5.7 iPhone SE + tên bài hai dòng  ⚠️ đã tính toán, chưa nhìn
Nếu mượn được máy 4.7", phát một bài có **tên dài xuống hai dòng**, mở Now Playing.

Thanh âm lượng có bị cắt mất ở đáy thẻ không? Khoản dự trù đã nâng 300 → 380 để chặn việc này, nhưng con số đó tính bằng tay chứ chưa ai nhìn thấy.

### 5.8 VoiceOver
Bật VoiceOver, mở Now Playing, vuốt tới thanh tiến trình. Nó phải đọc **"Playback position"** kèm thời gian, và vuốt lên/xuống phải tua được ±15 giây.

`Slider` cũ có sẵn khả năng này; thanh tự dựng thì không, nên đã phải thêm lại bằng tay.

### 5.9 Khoảng trống dưới thanh âm lượng
Trên iPhone 12 sẽ còn khoảng **113pt trống** dưới thanh âm lượng — màn hình trông nặng phần trên. Nguyên nhân: `.offset(y:)` cố định không phân bổ được không gian. Apple Music đặt âm lượng gần đáy. Cho tôi biết có chướng mắt không.
