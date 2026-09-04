# Biểu tượng app — hoa văn xoắn ốc Vogel

Hoa văn không phải ảnh bitmap được kéo giãn: nó được **sinh bằng công thức**
trong `phyllotaxis.py`. Chấm thứ n nằm ở góc `n × 137.5077°` (góc vàng) với
bán kính tỉ lệ `√n`. Các nhánh xoắn mà mắt nhìn thấy không hề được vẽ ra —
chúng nổi lên từ chính góc ấy.

Nghĩa là muốn đổi số chấm, cỡ chấm, màu nền hay lỗ giữa thì sửa tham số rồi
chạy lại, không cần vẽ tay và không bao giờ mất nét.

```bash
python3 -c "from phyllotaxis import render; render(1024).save('AppIcon.png')"
```

## Bản đang dùng

`Assets.xcassets/AppIcon.appiconset/AppIcon.png` — 150 chấm, nền trắng,
1024×1024, không kênh alpha. Trung thành với bản gốc, `margin = 0.20`.

## Chỉnh to nhỏ

`margin` là phần lề mỗi bên, nên đường kính hoa văn bằng `(1 - 2*margin)` lần
cạnh khung. Xem `so-sanh-le.png` cho bốn mức đã dựng.

Cỡ chấm tỉ lệ với **bán kính hoa văn**, không với cạnh khung. Đó là chủ ý:
nếu tính theo khung thì thu nhỏ `margin` chỉ kéo các chấm lại gần nhau mà
không nhỏ đi, và hoa văn dày lên trông như một vết mực. Tính theo bán kính
thì cả hình thu đều, giữ nguyên tỉ lệ.

**Điểm yếu đã đo, không phải phỏng đoán:** xem `so-sanh-co-that.png`. Ở cỡ
58 pixel, tức mục Cài đặt, 150 chấm nhỏ hơn 1 pixel mỗi chấm và cả hình tan
thành một vệt xám. Trên màn hình chính cạnh các app khác, nó đọc thành một
vòng tròn mờ chứ không ra hoa văn.

## Hai biến thể đã dựng sẵn

- `bien-the-B-60cham.png` — cùng hoa văn, 60 chấm to hơn, vẫn nền trắng.
  Giữ được hình ở mọi cỡ.
- `bien-the-C-nen-toi.png` — 60 chấm sáng trên nền xanh đêm. Rõ nhất ở cỡ
  nhỏ, và không bị chìm khi màn hình chính dùng hình nền sáng.

Đổi sang biến thể nào thì chép đè lên `AppIcon.png` trong asset catalog.

## Màn khởi động

`Info.plist` khai `UILaunchScreen` với `UIImageName = LaunchLogo` và
`UIColorName = LaunchBackground`. Logo là bản nền trong suốt trong
`LaunchLogo.imageset`, ngồi trên colorset nên mép không bao giờ lệch màu.

Lưu ý: build setting `INFOPLIST_KEY_UILaunchScreen_Generation` vẫn bật, nên
Xcode chèn thêm một `UILaunchScreen` rỗng lồng bên trong dict này. Vô hại —
đã chạy thật trên máy ảo và màn khởi động hiện đúng. Muốn dọn cho sạch thì
tắt cờ ấy trong Xcode, ở Build Settings của target.

Apple khuyên màn khởi động nên giống màn hình đầu của app chứ không phải một
màn thương hiệu. Đặt logo ở đây là đi ngược khuyến nghị ấy, nhưng không phải
lý do bị từ chối và rất nhiều app vẫn làm.
