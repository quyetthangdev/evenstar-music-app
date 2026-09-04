# Sẵn sàng nộp App Store — spec

**Ngày:** 2026-09-03
**Bối cảnh:** rà toàn bộ codebase trước lượt nộp đầu tiên lên App Store Connect.
Bản Release cho `generic/platform=iOS` build sạch, không một cảnh báo, nên phần
còn lại đều là cấu hình phân phối chứ không phải lỗi biên dịch.

---

## Phần phải sửa trong mã

### S1 — Thiếu privacy manifest

Không có tệp `.xcprivacy` nào trong dự án. App đọc và ghi `UserDefaults` qua
`@AppStorage` ở `AppTheme`, `AppLanguage`, `JamendoLicencePolicy` và `RootView`.
`UserDefaults` nằm trong danh sách API bắt buộc khai lý do của Apple, nên một
bản upload thiếu manifest sẽ nhận thư ITMS-91053.

Không có gói SPM nào trong dự án, nên không phải lo manifest của bên thứ ba.

**Yêu cầu:** một `PrivacyInfo.xcprivacy` được đóng vào bundle của app, khai
`NSPrivacyAccessedAPICategoryUserDefaults` với lý do `CA92.1`, không theo dõi,
không thu thập dữ liệu, không domain theo dõi.

**Rủi ro riêng của dự án này:** dự án dùng Xcode 16 synced folders. Tệp đặt
trong `Evenstar/Evenstar/` được thêm vào target tự động, nhưng điều đó phải
được **kiểm chứng bằng test đọc `Bundle.main`**, không phải bằng niềm tin.

### S2 — Thiếu khai báo mã hoá xuất khẩu

`Evenstar/Info.plist` hiện chỉ có đúng một khoá, `UIBackgroundModes`. Thiếu
`ITSAppUsesNonExemptEncryption` nghĩa là mỗi build lên App Store Connect đều
treo lại chờ trả lời thủ công câu hỏi tuân thủ xuất khẩu.

App không dùng mã hoá riêng nào ngoài HTTPS của hệ thống, nên giá trị đúng là
`false`.

**Yêu cầu:** khoá có mặt trong Info.plist và có mặt trong bundle đã dựng.

### S3 — Sập ngay khi mở app nếu CloudKit không mở được

`EvenstarApp.init()` gọi `fatalError` khi `EvenstarStores.makeContainer()` ném
lỗi. Container ấy khai `cloudKitDatabase: .private(...)`. Nghĩa là mọi lý do
khiến kho không mở được đều thành một cú sập ở màn hình đầu tiên:

- container iCloud chưa được gán cho App ID;
- một lượt migrate SwiftData thất bại trên máy người dùng đã có dữ liệu cũ;
- kho trên đĩa hỏng hoặc không mở được vì bất cứ lý do nào khác.

Máy của reviewer rơi vào nhóm đầu là chuyện thường. Đây là đường dẫn tới từ
chối 2.1 chắc chắn nhất trong toàn bộ codebase.

**Một điều bản thảo đầu của spec này nói sai, sửa lại cho đúng:** lược đồ
CloudKit chưa đẩy sang Production **không** làm kho hỏng, nên bộ tầng dưới đây
không hề cứu được nó. `NSPersistentCloudKitContainer` nạp kho bình thường khi
lược đồ vắng mặt ở Production; chỗ hỏng nằm ở lượt mirror sau đó, bất đồng bộ.
Người dùng ở lại tầng `synced` với đồng bộ chết lặng, và không tầng nào được
kích hoạt. Đó là lý do M1 dưới đây là một việc bắt buộc làm bằng tay chứ không
phải một chuyện mã có thể lo — hai thứ ấy không thay thế cho nhau.

**Yêu cầu:** mở kho theo tầng, hạ dần thay vì sập.

1. `synced` — CloudKit bật, hai kho trên đĩa. Bình thường.
2. `localOnly` — hai kho trên đĩa, CloudKit tắt. Đồng bộ mất, dữ liệu còn.
3. `inMemory` — không kho nào trên đĩa mở được. App vẫn chạy được.

Chỉ khi cả ba tầng đều hỏng mới được coi là không cứu nổi.

### S4 — Người dùng không được báo khi tụt xuống tầng bộ nhớ

Hệ quả của S3. Nếu app mở ở tầng `inMemory`, thư viện hiện ra **trống rỗng**
dù trên đĩa vẫn còn nguyên. Người dùng thấy thế sẽ nhập lại toàn bộ nhạc, và
lần chạy sau khi kho đĩa mở lại được thì họ có một thư viện nhân đôi.

**Yêu cầu:** một cảnh báo khi và chỉ khi tầng là `inMemory`, nói rõ ba điều:
dữ liệu chưa mất, đừng nhập lại, hãy khởi động lại app. Tầng `localOnly`
không cảnh báo — mất đồng bộ không phải mất dữ liệu, và một hộp thoại ở mỗi
lần mở app khi người dùng chỉ chưa đăng nhập iCloud là quấy rầy vô cớ.

### S5 — Hai khoá dịch chết trong String Catalog

`Localizable.xcstrings` phủ đủ cả `en` lẫn `vi` cho toàn bộ khoá, nhưng còn
hai khoá ở trạng thái `stale`, tức không còn chỗ nào trong mã dùng tới:

- `Chế độ`
- `Ngôn ngữ được đổi trong Cài đặt của iOS. Nếu không thấy mục đó, thêm một
  ngôn ngữ nữa vào Cài đặt chung → Ngôn ngữ & Vùng.`

Không phải lỗi phát hành, nhưng dọn trước khi nộp thì bản dịch gửi đi không
mang theo rác.

---

## Phần không sửa được trong mã — phải làm bằng tay

Ba thứ dưới đây tác nhân **không được** đụng vào, vì chúng nằm trong
`project.pbxproj` hoặc ngoài repo, và một lượt sửa hỏng ở đó khoá mất dự án.

### M1 — Đẩy lược đồ CloudKit sang Production

Bắt buộc, và là nửa còn lại của S3. Bản sửa S3 khiến app không sập nữa; nó
không làm đồng bộ chạy được. Nếu lược đồ chỉ tồn tại ở Development thì mọi
người dùng App Store mở app đều rơi xuống tầng `localOnly`.

### M2 — `aps-environment` sau khi export

`Evenstar/Evenstar.entitlements` ghi `development`. Nền `remote-notification`
là chính đáng vì đồng bộ SwiftData qua CloudKit cần push im lặng. Xcode được
cho là tự thay giá trị này thành `production` khi export bản App Store, nhưng
"được cho là" không phải bằng chứng — phải mở entitlements trong `.ipa` ra xem.

### M3 — Giới hạn khoá Google Drive API

`DriveAPIKey.value` có giá trị thật. Điểm tốt: tệp đang được `skip-worktree`
và khoá **không** nằm trong lịch sử git. Điểm còn lại: khoá vẫn đi theo binary
và ai cũng moi ra được. Ranh giới thật nằm ở Google Cloud Console — giới hạn
theo bundle ID `com.evenstar.app` và chỉ cho Drive API.

### M4 — Ngôn ngữ chính lệch nhau

`developmentRegion` trong pbxproj là `en`, `sourceLanguage` trong
`Localizable.xcstrings` là `vi`. Cả hai ngôn ngữ đều phủ đủ khoá nên app không
hỏng, nhưng App Store Connect sẽ lấy `en` làm ngôn ngữ chính của app.

### M5 — Ghi chú cho reviewer

App phát nhạc từ Google Drive của người dùng và từ Jamendo. Mở app lần đầu
trên máy sạch thì thư viện **trống**. Reviewer không có nhạc để thử, và một
màn hình trống là lý do từ chối 2.1 quen thuộc. Phải gửi kèm một thư mục Drive
công khai có sẵn vài bài, và một câu giải thích nguồn nội dung.

---

## Hai phát hiện đã rút lại

Ghi lại để không ai đi kiểm tra lại chúng.

**Loại tệp tải về khỏi sao lưu iCloud — rút.** Ban đầu tôi cho rằng nhạc tải
về nằm trong `Documents` mà không loại khỏi backup. Đọc kỹ thì `RoutingAudio
Player` định tuyến theo `url.isFileURL`: nhạc Drive và Jamendo được **phát
trực tuyến qua https**, không tải xuống. `Documents/Music` vì thế chỉ chứa
tệp người dùng tự nhập từ ứng dụng Tệp — dữ liệu không tái tạo được, và
đúng ra phải được sao lưu. `Documents/Artwork` lẫn cả ảnh bìa tải từ Jamendo
lẫn ảnh bìa người dùng tự chọn từ Ảnh; loại cả thư mục khỏi backup sẽ làm mất
nhóm sau khi khôi phục máy. Giữ nguyên là đúng.

**Khoá app về portrait — rút.** Ban đầu tôi cho rằng khai báo landscape là
thừa. `PlayerCard` có hàng chục ghi chú đo đạc riêng cho landscape, và
`run.sh` nói thẳng rằng safe-area khi xoay ngang là thứ chỉ máy thật trả lời
được. Landscape là chủ ý, không phải sót. Việc cần làm là **thử trên máy
thật**, không phải khoá lại.
