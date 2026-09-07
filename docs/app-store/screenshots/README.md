# Ảnh chụp App Store — sau lượt từ chối 5.2.1

## Apple từ chối vì cái gì

Ngày 2026-09-07, bản 1.0 (4) bị từ chối theo **Guideline 5.2.1 — Intellectual
Property**:

> The app includes protected album cover artworks in app icons, screenshots or
> previews without the necessary authorization.

**Không phải app bị từ chối, mà là ảnh chụp màn hình.** Bản binary không có
vấn đề gì; Apple không nói gì về nó. Tấm ảnh có lỗi là tấm chụp tab Jamendo
trong màn Bài hát, hiện ba bài kèm ảnh bìa lấy từ máy chủ Jamendo — ảnh chân
dung nghệ sĩ của Chaz Robinson, Pokki DJ và Melanie Ungar.

Nhạc Jamendo mang giấy phép Creative Commons, nhưng **ảnh bìa thì không nhất
thiết**, và Apple không đứng ra phân xử chuyện ấy giúp bạn. Trong tài liệu
tiếp thị thì gánh nặng chứng minh thuộc về bạn.

## Quy tắc từ giờ

**Không màn hình nào của Jamendo được xuất hiện trong ảnh chụp hay video xem
trước.** `JamendoResultRow` gọi `RemoteArtworkThumbnail(url: track.coverURL)`,
nên mọi hàng kết quả Jamendo đều kéo ảnh của bên thứ ba về. Không có cách nào
chụp màn ấy mà sạch bản quyền.

Điều này chỉ áp dụng cho **ảnh tiếp thị**. Trong app lúc chạy thật thì hiển
thị ảnh bìa Jamendo hoàn toàn bình thường, đó là dữ liệu API của họ trả về
cho người dùng.

## Bộ nhạc mẫu

`tao-nhac-mau.py` dựng tám tệp mp3 với ảnh bìa **do chính script sinh ra**,
dùng cùng công thức xoắn ốc Vogel của biểu tượng app. Nghĩa là mọi pixel bìa
trong ảnh chụp đều là của bạn.

```bash
cd <thư mục làm việc>
cp <repo>/docs/app-store/icon/phyllotaxis.py .
python3 tao-nhac-mau.py
```

Bốn album, mỗi album hai bài, mỗi album một bộ màu riêng. Âm thanh là im
lặng — ảnh chụp không phát ra tiếng. Thời lượng đặt từ 2:58 tới 4:23 để
thanh tiến trình và cột thời lượng trông thật.

## Cách chụp

1. Chạy máy ảo iPhone 17 Pro Max, đó là máy Apple dùng để duyệt.
2. Kéo tám tệp mp3 từ Finder thả vào cửa sổ Simulator. Chúng rơi vào ứng dụng
   Tệp.
3. Mở Evenstar, bấm nút cộng ở tab Bài hát, chọn cả tám.
4. Chụp sáu màn, **không màn nào là Jamendo**:
   - Player mở toàn màn hình với một bài có bìa đẹp
   - Danh sách Bài hát kèm mini player ở dưới
   - Album dạng lưới
   - Nghệ sĩ
   - Hàng đợi đang mở
   - Thư mục Drive, hoặc Tìm kiếm

## Sau khi có ảnh mới

Tải ảnh mới lên, xoá hết ảnh cũ, rồi **trả lời tin nhắn của Apple ngay trong
App Store Connect**. Nói rõ bạn đã gỡ toàn bộ ảnh bìa của bên thứ ba khỏi ảnh
chụp, và ảnh mới chỉ dùng bìa do bạn tạo. Không trả lời thì lượt duyệt đứng
im chờ bạn.
