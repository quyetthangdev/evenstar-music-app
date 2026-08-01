# Evenstar Phase 2a — Hướng dẫn QA trên iPhone thật

**Ngày:** 2026-08-01
**Nhánh:** `phase-2a` (23 commit, 47 test xanh, clean build không warning)
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

---

## Nhóm 2 — Lỗi đã biết còn tồn đọng, cần bạn xác nhận mức độ

### 2.1 Nháy icon khi tự chuyển bài  ⚠️ đã biết còn lỗi
Mở màn hình Now Playing, để một bài chạy **hết tự nhiên** (đừng bấm next), nhìn kỹ nút play/pause đúng lúc chuyển bài.

**Câu hỏi cụ thể:** icon có nháy sang trạng thái "paused" trong một khoảnh khắc rồi trở lại không?

- Nếu **có** → đúng là lỗi P1 đã ghi nhận. Nhạc vẫn chạy tiếp bình thường, chỉ là nháy hình. Cho tôi biết nó có khó chịu không.
- Nếu **không** → tốt, cửa sổ lỗi hẹp hơn dự đoán.

> Nguyên nhân: guard chống race dùng `currentTime < duration - 0.5`, nhưng `AVAudioPlayer.currentTime` trả về **0** sau khi bài kết thúc chứ không phải `duration`, nên guard không chặn được gì. Sửa một dòng nếu bạn thấy phiền.

### 2.2 Import file iCloud chưa tải về  ✅ đã sửa, cần xác nhận
Chọn 4–5 file từ iCloud Drive **chưa tải xuống máy**.

- **Đã sửa:** sheet giờ cuộn được và kéo lên cao được, nên danh sách lý do không còn bị cắt. Việc của bạn là xác nhận: kéo sheet lên và cuộn thử, có đọc được hết mọi lý do không?

### 2.3 Cuộc gọi đến giữa lúc nghe nhạc  ⚠️ nghi ngờ cao
Nhờ ai gọi vào máy khi đang phát nhạc. Sau khi cúp:

1. Mini player hiện icon gì? (đúng: icon **play**, tức đang dừng — không phải icon pause)
2. Màn hình khoá còn báo đang phát không?
3. Bấm play — **nhạc có thật sự kêu lại không?**

> Câu 1 và 2 đã được sửa ở F4. **Câu 3 nhiều khả năng vẫn hỏng** — `activateSessionIfNeeded()` chỉ chạy đúng một lần và không kích hoạt lại audio session sau khi hệ thống ngắt. Đây là lỗi có từ trước, thuộc phạm vi Phase 2d, nhưng bản sửa F4 khiến bạn gặp nó thường xuyên hơn. Nếu bấm play mà im lặng — đó chính là nó.

Làm lại thí nghiệm tương tự với **rút tai nghe** đang cắm.

### 2.4 Kéo thanh scrubber có làm đóng sheet không?  ⚠️ chưa kiểm chứng được
Mở Now Playing, kéo thanh scrubber để tua bài — kéo vài lần, cả chậm lẫn nhanh.

**Câu hỏi cụ thể:** có lần nào sheet bị đóng lại thay vì tua không?

Now Playing giờ là `.sheet`, nên kéo dọc ở vùng trống sẽ đóng nó. Kéo ngang để tua thì đúng, nhưng nếu ngón tay lệch dọc lúc bắt đầu, hệ thống có thể hiểu nhầm. Apple Music cũng có đặc tính này.

- Nếu **không bao giờ** xảy ra → không cần làm gì
- Nếu **thỉnh thoảng** xảy ra → cho tôi biết tần suất, có cách giới hạn cử chỉ của slider

---

## Nhóm 3 — Kiểm tra quy mô (quan trọng cho lời hứa "1k–5k bài")

Ba vấn đề hiệu năng đã được **cố ý hoãn sang Phase 2b**. Chúng vô hình với 5 file. Mục đích ở đây là đo xem chúng tệ tới mức nào để xếp ưu tiên cho 2b.

### 3.1 Import lô lớn
Import 40–60 file cùng lúc, trong đó có file FLAC/WAV lớn. Bấm giờ.

- Thanh tiến trình chạy mượt hay **đứng rồi nhảy**?
- Tổng thời gian bao lâu?

> Nguyên nhân đã biết: file được copy **đồng bộ trên main thread**, và mỗi file lại quét toàn bộ bảng Track để chống trùng.

### 3.2 Cuộn danh sách lớn
Import 300+ bài (có ảnh bìa), rồi vuốt cuộn thật mạnh. Mở Xcode → Debug gauge xem bộ nhớ.

- Có giật khung hình không?
- Bộ nhớ nhảy lên bao nhiêu?

> Nguyên nhân đã biết: `ArtworkThumbnail` đọc file và **giải mã ảnh ở độ phân giải gốc** mỗi lần render row, không cache. Ảnh bìa album thường 1000×1000 đến 3000×3000 — giải mã một ảnh 3000×3000 tốn ~36 MB chỉ để vẽ một ô 44×44. Spec có yêu cầu dùng `NSCache` nhưng chưa làm.

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
- [ ] Chạm mini player → Now Playing mở lên dạng sheet, kéo xuống đóng được; kéo scrubber, play/pause, next đều chạy
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
