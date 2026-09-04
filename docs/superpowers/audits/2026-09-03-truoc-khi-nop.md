# Trước khi bấm nộp — việc phải làm bằng tay

Năm việc dưới đây không có test nào bắt được, và không tác nhân nào được làm
thay. Tick từng dòng trước khi tải build lên.

## 1. Đẩy lược đồ CloudKit sang Production

Đây là **nửa còn lại** của bản sửa "không sập khi CloudKit hỏng", và là nửa mà
mã không làm thay được.

Đừng hiểu nhầm bộ tầng trong `EvenstarStores.load` là lưới an toàn cho việc
này. Lược đồ chưa đẩy sang Production **không** làm kho hỏng:
`NSPersistentCloudKitContainer` nạp kho bình thường rồi mới thất bại ở lượt
mirror, bất đồng bộ. Nghĩa là người dùng ở lại tầng `synced`, không tầng nào
được kích hoạt, không hộp thoại nào hiện lên, và đồng bộ chết lặng cho tới khi
có người để ý. Quên bước này thì không có gì báo cho bạn biết.

- Mở CloudKit Console, container `iCloud.com.evenstar.app`.
- Development → Deploy Schema to Production.
- Kiểm rằng bốn kiểu bản ghi `CD_Track`, `CD_DriveTrack`, `CD_JamendoTrack`,
  `CD_DriveFolder` đều có mặt ở Production.

Lược đồ CloudKit **chỉ thêm được, không sửa ngược**. Đẩy nhầm là khoá vĩnh
viễn hình dạng dữ liệu, nên đọc lại lược đồ trước khi bấm.

### Rủi ro đã biết, chưa đo: kho mở ở tầng `localOnly`

Tầng `localOnly` mở **đúng tệp `default.store`** mà tầng `synced` dùng, chỉ tắt
mirror. Mở một kho đã từng mirror mà không mirror thì Core Data chịu được, các
bảng phụ của CloudKit nằm im. Câu chưa có ai trả lời là **xuất ngược**: những
hàng ghi trong phiên tắt mirror chỉ được đẩy lên ở lần chạy sau nhờ persistent
history. SwiftData bật history tracking mặc định trên iOS 18, nên nhiều khả
năng chuyện này tự lo được — nhưng không có gì trong đợt này chứng minh điều
ấy, và kiểu hỏng của nó thì im lặng: hai máy lệch nhau vĩnh viễn, không lỗi ở
đâu cả. Nếu có báo cáo đồng bộ thiếu bài, hãy nhìn vào đây trước.

## 2. Kiểm `aps-environment` trong bản đã export

`Evenstar/Evenstar.entitlements` ghi `development`. Nền `remote-notification`
là chính đáng — đồng bộ SwiftData qua CloudKit cần push im lặng. Xcode được
cho là tự thay giá trị này thành `production` khi export bản App Store, nhưng
"được cho là" không phải bằng chứng:

    unzip -p Evenstar.ipa 'Payload/Evenstar.app/embedded.mobileprovision' \
      | security cms -D | plutil -p - | grep -A2 aps-environment

Phải thấy `production`. Thấy `development` thì đừng nộp.

## 3. Giới hạn khoá Google Drive API

`DriveAPIKey.value` có giá trị thật và nó đi theo binary — ai cũng moi ra
được. Tệp đang được `skip-worktree` và khoá không nằm trong lịch sử git, nên
repo thì sạch; ranh giới thật nằm ở phía Google.

Trong Google Cloud Console, với khoá này:

- Application restrictions → iOS apps → thêm bundle ID `com.evenstar.app`.
- API restrictions → Restrict key → chỉ chọn Google Drive API.

Khoá không giới hạn là khoá bất kỳ ai cũng tiêu hết quota giúp bạn.

## 4. Ngôn ngữ chính của app

`developmentRegion` trong pbxproj là `en`, còn `sourceLanguage` trong
`Localizable.xcstrings` là `vi`. Cả hai ngôn ngữ đều phủ kín 155 khoá nên app
không hỏng, nhưng App Store Connect sẽ lấy **English** làm ngôn ngữ chính.

Muốn tiếng Việt là ngôn ngữ chính thì đổi `developmentRegion` thành `vi` trong
Xcode, ở Project → Info → Localizations. Sửa bằng tay trong Xcode, không sửa
pbxproj bằng trình soạn thảo.

## 5. Ghi chú cho người duyệt

App phát nhạc từ Google Drive của chính người dùng và từ Jamendo. Mở app lần
đầu trên một máy sạch thì thư viện **trống rỗng** — người duyệt không có nhạc
nào để thử, và một màn hình trống là lý do từ chối 2.1 quen thuộc.

Trong ô App Review Information, dán:

- một liên kết thư mục Google Drive công khai có sẵn vài tệp mp3, kèm câu
  "dán liên kết này vào Tài khoản → Thư mục Drive";
- một câu về nguồn nội dung: nhạc đến từ tệp người dùng tự nhập, từ Drive của
  chính họ, và từ Jamendo theo giấy phép Creative Commons — app không lưu trữ
  hay phân phối nhạc của bên thứ ba nào.

Nhắc thêm cho người duyệt rằng nhạc nền và màn hình khoá đều hoạt động, và
rằng app hỗ trợ xoay ngang.

---

## Phụ lục — cái bẫy DerivedData

Không liên quan tới App Store, nhưng đã ăn mất một lượt build trong đợt này.

Xcode đang đặt `IDECustomDerivedDataLocation` là `/Volumes/Storage/DerivedData/`.
Khi ổ ngoài ấy không được gắn, mọi lệnh `xcodebuild` hỏng với

    Couldn't create workspace arena folder ... You don't have permission

— một thông báo không hề nhắc tới chuyện ổ đĩa biến mất. Cắm lại ổ, hoặc ghi
đè trên dòng lệnh bằng `-derivedDataPath <thư mục nào đó>`.
