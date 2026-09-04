# Khai báo App Store Connect — Evenstar 1.0

Chép thẳng từ đây vào từng ô. Mọi câu chữ dưới đây đã đối chiếu với mã nguồn,
không có tính năng nào được nói quá.

**Sự thật nền:** bundle `com.evenstar.app`, phiên bản 1.0 build 1, iPhone only,
iOS 18.6 trở lên, tiếng Việt và tiếng Anh, không có tài khoản, không có quảng
cáo, không có mua trong ứng dụng.

---

## 0. Hai thứ đang thiếu và **chặn** nộp bài

Apple bắt buộc cả hai, và không có cái nào tồn tại trong repo:

1. **Privacy Policy URL.** Bắt buộc với mọi app, kể cả app không thu thập gì.
   Mẫu ở mục 7 dưới đây, chỉ cần đưa lên một trang web bất kỳ.
2. **Ảnh chụp màn hình 6.9 inch.** Tối thiểu một tấm, tối đa mười. Chụp trên
   iPhone 17 Pro Max hoặc máy ảo cùng kích thước. iPhone-only nên không cần
   ảnh iPad.

Support URL cũng bắt buộc. Một trang GitHub Pages hay một issue tracker công
khai là đủ.

---

## 1. TestFlight — việc trước mắt

### Beta App Description

Tiếng Việt:

> Evenstar phát nhạc của chính bạn: file nhạc bạn nhập từ ứng dụng Tệp, thư
> mục Google Drive bạn dán liên kết vào, và nhạc Creative Commons từ Jamendo.
>
> Bản thử này cần bạn để mắt tới: nhập nhạc từ Tệp, phát nền và điều khiển ở
> màn hình khoá, xoay ngang, và đồng bộ thư viện giữa hai máy cùng Apple
> Account.

Tiếng Anh:

> Evenstar plays your own music: files you import from the Files app, Google
> Drive folders you paste a link to, and Creative Commons tracks from Jamendo.
>
> Things worth watching in this build: importing from Files, background
> playback and lock-screen controls, landscape, and library sync between two
> devices on the same Apple Account.

### What to Test

> Nhập vài file mp3 từ ứng dụng Tệp. Phát một bài rồi khoá máy — điều khiển ở
> màn khoá phải hiện đúng tên bài và ảnh bìa. Xoay ngang khi player đang mở.
> Nếu bạn có hai máy cùng Apple Account, kiểm xem thư viện có hiện ở cả hai.

### Export compliance

Chọn **không** dùng mã hoá ngoài diện miễn trừ. `ITSAppUsesNonExemptEncryption`
đã nằm sẵn trong Info.plist với giá trị `false`, nên App Store Connect sẽ tự
điền và không hỏi lại ở mỗi build.

### Beta App Review (chỉ khi mở external testing)

Dán y hệt mục 6 bên dưới. Người duyệt TestFlight external và người duyệt App
Store gặp cùng một vấn đề: **thư viện trống trơn khi mở lần đầu**.

---

## 2. App Information

| Ô | Giá trị |
|---|---|
| Name | `Evenstar` |
| Subtitle (30 ký tự) | `Nhạc của bạn, gọn gàng` |
| Subtitle (EN) | `Your music, kept simple` |
| Primary Category | Music |
| Secondary Category | để trống |
| Content Rights | Chọn "chứa nội dung bên thứ ba" và xem mục 6 |
| Age Rating | 4+ — xem mục 5 |

Ngôn ngữ chính đặt theo `developmentRegion` trong dự án, hiện là **English**.
Muốn tiếng Việt là chính thì đổi trong Xcode trước khi nộp, xem tài liệu
`truoc-khi-nop`.

---

## 3. Nội dung bán hàng

### Promotional Text (170 ký tự, sửa được không cần duyệt lại)

VI: `Nhập nhạc từ Tệp, dán liên kết thư mục Drive, hoặc tìm nhạc Creative Commons trên Jamendo. Không tài khoản, không quảng cáo.`

EN: `Import from Files, paste a Drive folder link, or browse Creative Commons tracks on Jamendo. No account, no ads.`

### Description

Tiếng Việt:

```
Evenstar là trình phát nhạc cho nhạc của chính bạn.

NHẠC TỪ ĐÂU
• Nhập file từ ứng dụng Tệp — mp3, m4a và các định dạng iOS đọc được.
• Dán liên kết một thư mục Google Drive công khai và nghe trực tiếp từ đó.
• Tìm nhạc Creative Commons trên Jamendo, lưu bài bạn thích vào thư viện.

NGHE
• Phát nền, điều khiển ở màn hình khoá và Trung tâm điều khiển.
• Hàng đợi xem được và sửa được, phát ngẫu nhiên, lặp một bài hoặc cả hàng.
• Hẹn giờ ngủ.
• Tự động phát tiếp khi hết hàng đợi.

THƯ VIỆN
• Sắp theo bài hát, album hoặc nghệ sĩ.
• Tìm kiếm theo tên bài, nghệ sĩ hay album.
• Sửa tên bài, tên nghệ sĩ, tên album và ảnh bìa cho từng bài.
• Thư viện đi theo Apple Account của bạn, nên máy nào cũng thấy cùng một danh
  sách. Bản thân file nhạc vẫn nằm ở máy bạn đã nhập.

GỌN
• Không tài khoản, không đăng ký, không quảng cáo.
• Không theo dõi, không thu thập dữ liệu.
• Tiếng Việt và tiếng Anh, đổi được ngay trong app.
• Giao diện sáng, tối, hoặc theo hệ thống.

Về giấy phép Jamendo: nhiều bài mang giấy phép cấm dùng cho mục đích thương
mại. Evenstar mặc định ẩn chúng đi; bạn bật hiện lại trong Cài đặt và tự chịu
trách nhiệm về cách dùng.
```

Tiếng Anh:

```
Evenstar is a music player for music you already have.

WHERE THE MUSIC COMES FROM
• Import files from the Files app — mp3, m4a, and the formats iOS can read.
• Paste a link to a public Google Drive folder and play straight from it.
• Browse Creative Commons tracks on Jamendo and save the ones you like.

LISTENING
• Background playback, with lock screen and Control Center controls.
• A queue you can see and rearrange, shuffle, repeat one or repeat all.
• Sleep timer.
• Autoplay when the queue runs out.

YOUR LIBRARY
• Browse by song, album, or artist.
• Search by title, artist, or album.
• Edit the title, artist, album, and cover art of any track.
• Your library follows your Apple Account, so every device shows the same
  list. The audio files themselves stay on the device you imported them to.

KEPT SIMPLE
• No account, no sign-up, no ads.
• No tracking, no data collection.
• English and Vietnamese, switchable inside the app.
• Light, dark, or follow the system.

A note on Jamendo licences: many tracks carry a non-commercial licence.
Evenstar hides those by default; you can show them in Settings and take
responsibility for how you use them.
```

### Keywords (100 ký tự, phân cách bằng dấu phẩy, không khoảng trắng thừa)

VI: `nhạc,trình phát,offline,mp3,drive,jamendo,creative commons,thư viện,hẹn giờ ngủ`

EN: `music,player,offline,mp3,drive,jamendo,creative commons,library,sleep timer,local`

Đừng lặp lại tên app hay tên category trong keywords — Apple đã đánh chỉ mục
chúng rồi, lặp lại chỉ phí ký tự.

---

## 4. App Privacy — từng mục một

Vào App Store Connect → app của bạn → **App Privacy** ở cột trái, dưới nhóm
General.

### Bước 1 — Privacy Policy URL

Ô này nằm ngay đầu mục App Privacy, **không** nằm ở phần nội dung bán hàng.
Bắt buộc. Xem mẫu ở mục 7.

### Bước 2 — Data Collection

Bấm **Get Started**. Apple hỏi đúng một câu:

> Do you or your third-party partners collect data from this app?

Chọn **No, we do not collect data from this app**.

Chọn xong là hết. App Store Connect không hỏi thêm mục nào nữa, và trang App
Privacy công khai của app sẽ hiện dòng **Data Not Collected**.

### Vì sao "No" là câu trả lời đúng, không phải câu trả lời tiện

Apple định nghĩa "collect" hẹp hơn người ta tưởng: **truyền dữ liệu ra khỏi
máy VÀ giữ nó lâu hơn mức cần để phục vụ yêu cầu ngay lúc đó**. Ba trường hợp
sau, theo đúng định nghĩa ấy, không phải thu thập:

1. Dữ liệu không rời khỏi máy.
2. Dữ liệu nằm trong iCloud riêng của người dùng qua CloudKit private
   database — bạn không có cách nào đọc được.
3. Dữ liệu gửi cho một dịch vụ chỉ để phục vụ đúng yêu cầu đó, không lưu lại,
   và bạn không truy cập được.

Evenstar rơi trọn vào cả ba.

### Đối chiếu từng nhóm dữ liệu Apple liệt kê

Nếu bạn muốn tự kiểm, hoặc nếu Apple hỏi lại, đây là mười bốn nhóm trong bảng
của họ và lý do từng nhóm là "không":

| Nhóm | Có? | Vì sao |
|---|---|---|
| Contact Info | Không | Không tài khoản, không form, không xin email |
| Health & Fitness | Không | Không đụng tới |
| Financial Info | Không | Miễn phí, không mua trong ứng dụng |
| Location | Không | Không xin quyền vị trí, không dùng CoreLocation |
| Sensitive Info | Không | Không đụng tới |
| Contacts | Không | Không đọc danh bạ |
| User Content | Không | Nhạc, ảnh bìa và thông tin bài bạn sửa đều ở lại máy; phần đồng bộ đi vào iCloud riêng của người dùng |
| Browsing History | Không | Không có trình duyệt |
| Search History | **Đọc kỹ** | Xem ghi chú dưới bảng |
| Identifiers | Không | Không có User ID, không đọc IDFA hay device ID |
| Purchases | Không | Không có gì để mua |
| Usage Data | Không | Không có SDK phân tích nào; dự án không có một gói phụ thuộc nào |
| Diagnostics | Không | App chỉ ghi log cục bộ bằng OSLog. Báo cáo sự cố của chính Apple là do người dùng bật chia sẻ với Apple, không phải app thu thập |
| Other Data | Không | — |

**Ghi chú về Search History.** Từ khoá bạn gõ để tìm nhạc được gửi tới
`api.jamendo.com`, và ID thư mục bạn dán được gửi tới `googleapis.com`. Đây là
chỗ duy nhất trong app có dữ liệu người dùng rời khỏi máy ngoài iCloud.

Vẫn là "không thu thập", vì ba lẽ:

- Hai lượt gọi ấy không kèm bất kỳ định danh nào của người dùng — không tài
  khoản, không device ID, không cookie. Chỉ có từ khoá và khoá API tĩnh của
  nhà phát triển.
- App không lưu lại từ khoá ở đâu cả, và bạn không có máy chủ để lưu.
- Jamendo và Google ở đây là **nhà cung cấp API công khai**, không phải
  "third-party partner" theo nghĩa Apple dùng — tức không phải một SDK nhúng
  trong app nhận dữ liệu thay bạn.

Nếu sau này bạn gắn một định danh ổn định vào lượt gọi Jamendo, câu trả lời
này hết đúng và phải khai lại.

### Bước 3 — Publish

Bấm **Publish** ở góc trên bên phải. Câu trả lời chỉ có hiệu lực sau khi bấm
nút này. Đây là chỗ hay bị quên, và hậu quả là bị chặn ở lượt nộp.

### Phải khớp với tệp trong bundle

`PrivacyInfo.xcprivacy` đã nằm trong bản build bạn đẩy lên TestFlight, và nó
khai ba điều:

- `NSPrivacyTracking` = false
- `NSPrivacyCollectedDataTypes` = rỗng
- một API bắt buộc khai lý do: `UserDefaults`, mã `CA92.1`

Apple đối chiếu tệp này với câu trả lời trên web. Trả lời "No" là khớp. Nếu
bạn đổi ý và khai có thu thập, phải sửa cả tệp trong mã rồi build lại.

### Không có câu hỏi về Tracking

Câu hỏi "do you use this data to track?" chỉ hiện ra cho từng nhóm dữ liệu bạn
đã khai là có thu thập. Trả lời "No" ở bước 2 thì Apple không hỏi tới, và
`NSPrivacyTracking` = false trong bundle đã nói giúp bạn.

## 5. Age Rating — 4+

Trả lời **None** cho toàn bộ câu hỏi. App không có bạo lực, không có nội dung
người lớn, không có cờ bạc, không có mua bán.

Hai câu dễ trả lời nhầm:

- **User Generated Content: No.** Người dùng chỉ nhập file cho riêng mình, không
  có gì đăng lên hay chia sẻ giữa người dùng với nhau.
- **Unrestricted Web Access: No.** App không có trình duyệt. Liên kết duy nhất
  mở ra ngoài là trang giấy phép của bài Jamendo đang phát.

---

## 6. App Review Information — phần quan trọng nhất

**Vì sao mục này quyết định đậu hay trượt:** mở app lần đầu trên máy sạch thì
thư viện **trống trơn**. Người duyệt không có nhạc nào để thử, và một màn hình
trống là lý do từ chối 2.1 quen thuộc. Không có tài khoản demo nào cứu được
chuyện này — thứ họ cần là nhạc.

### Notes (dán nguyên văn)

```
Evenstar plays music the user already owns. It ships with no content, so a
fresh install shows an empty library. Three ways to get music in, all
reachable without an account:

1. FASTEST — Jamendo (no setup):
   Open the app, tap the search icon, then "Khám phá Jamendo" / "Explore
   Jamendo". Pick any track and press play. These are Creative Commons
   licensed tracks streamed from Jamendo's public API.

2. Google Drive folder we prepared for review:
   Go to the Account tab, then "Thư mục Drive" / "Drive folders", tap "Thêm
   thư mục" / "Add folder", and paste this link:

   <<< DÁN LIÊN KẾT THƯ MỤC DRIVE CÔNG KHAI VÀO ĐÂY >>>

   The folder contains a few royalty-free mp3 files. Tracks stream directly
   from Drive; nothing is downloaded.

3. Files app import:
   Drag any mp3 into the device, then use the + button on the Songs tab.

CONTENT RIGHTS
The app hosts and distributes no music of its own. Audio comes from (a) files
the user imported themselves, (b) a Google Drive folder the user owns or was
given a public link to, and (c) Jamendo's public catalogue of Creative Commons
licensed music, streamed via their documented API. Tracks with non-commercial
licences are hidden by default and the user must opt in to see them.

OTHER THINGS TO KNOW
- Background audio and lock screen controls are supported; play a track and
  lock the device to see them.
- The app supports landscape on iPhone.
- The library (titles, artists, album names, cover art) syncs across the
  user's own devices via CloudKit private database. Audio files stay local.
- No account, no sign-up, no ads, no in-app purchases, no analytics.
```

### Sign-In Required

Chọn **No**. App không có màn hình đăng nhập nào.

### Contact Information

Điền tên, số điện thoại và email bạn thật sự đọc được. Apple gọi thẳng vào đây
khi có gì cần hỏi.

---

## 7. Privacy Policy — mẫu để đưa lên web

Bắt buộc phải có URL. Nội dung dưới đây đúng với app hiện tại; đưa lên GitHub
Pages, Notion công khai, hay bất cứ trang nào có địa chỉ ổn định.

```
CHÍNH SÁCH QUYỀN RIÊNG TƯ — EVENSTAR
Cập nhật: 2026-09-04

Evenstar không thu thập, không lưu trữ và không chia sẻ dữ liệu cá nhân của
bạn. Chúng tôi không có máy chủ, không có tài khoản người dùng, và không dùng
bất kỳ công cụ phân tích hay quảng cáo nào.

DỮ LIỆU Ở ĐÂU
File nhạc và ảnh bìa bạn nhập nằm trong vùng lưu trữ riêng của app trên máy
bạn. Thông tin thư viện — tên bài, tên nghệ sĩ, tên album, ảnh bìa — được đồng
bộ qua iCloud của chính bạn (CloudKit private database) để các máy dùng chung
Apple Account thấy cùng một thư viện. Chúng tôi không truy cập được vùng dữ
liệu ấy.

KHI APP GỌI RA NGOÀI
- Jamendo (api.jamendo.com): app gửi từ khoá bạn nhập để tìm nhạc, và tải về
  luồng phát cùng ảnh bìa của bài bạn chọn. Không kèm định danh nào của bạn.
- Google Drive (googleapis.com): app gửi ID thư mục bạn tự dán vào, để đọc
  danh sách file và phát trực tiếp. Không kèm định danh nào của bạn.

Chúng tôi không nhận được, không nhìn thấy và không lưu lại bất cứ thứ gì từ
hai lượt gọi ấy. Việc hai dịch vụ trên xử lý yêu cầu của bạn thế nào thuộc
chính sách riêng của họ.

QUYỀN CỦA HỆ THỐNG
App xin quyền truy cập Ảnh chỉ khi bạn chủ động chọn một ảnh làm bìa bài hát,
và chỉ đọc đúng ảnh bạn chọn.

TRẺ EM
App không thu thập dữ liệu từ bất kỳ ai, kể cả trẻ em.

LIÊN HỆ
<<< EMAIL CỦA BẠN >>>
```

Bản tiếng Anh nên có, vì ngôn ngữ chính của app đang là English. Dịch thẳng
bản trên là đủ.

---

## 8. Ảnh chụp màn hình — gợi ý sáu tấm

Chụp ở 6.9 inch. Thứ tự này kể một câu chuyện thay vì liệt kê tính năng:

1. **Player mở toàn màn hình** với một bài có ảnh bìa đẹp. Đây là tấm bán hàng.
2. **Danh sách bài hát** với mini player ở dưới, cho thấy thư viện thật.
3. **Album** dạng lưới, cho thấy app có sức chứa.
4. **Hàng đợi** đang mở, cho thấy điều khiển được.
5. **Khám phá Jamendo**, cho thấy có nhạc miễn phí ngay cả khi chưa nhập gì.
6. **Thư mục Drive**, cho thấy nguồn nhạc thứ ba.

Đừng chụp màn hình trống. Nhập nhạc thật vào trước khi chụp.

---

## 9. Thứ tự làm

1. Đưa privacy policy lên web, lấy URL.
2. Chuẩn bị thư mục Drive công khai có vài file mp3, lấy liên kết, dán vào
   mục 6.
3. Chụp sáu tấm ảnh màn hình.
4. Điền App Information, Pricing (Free), và phần nội dung ở mục 3.
5. Trả lời App Privacy và Age Rating.
6. Dán App Review Information.
7. Chọn build đã lên TestFlight, rồi Submit for Review.

Trước bước 7, đọc lại `docs/superpowers/audits/2026-09-03-truoc-khi-nop.md` —
đặc biệt việc đẩy lược đồ CloudKit sang Production, vì mã không cứu được ca ấy.

---

## 10. Trang hỗ trợ — phần FAQ nên bổ sung

Bản đầu của trang hỗ trợ có đủ email và thời gian phản hồi, đạt yêu cầu Support
URL của Apple. Nhưng phần FAQ đang trả lời những câu chung chung, không phải
những câu **app này** thực sự sinh ra. Bốn câu dưới đây bám vào hành vi có
thật trong mã.

### Thư viện trống khi mở lần đầu

> **Tôi vừa cài xong, sao không có bài nào?**
> Evenstar không đi kèm nhạc. Có ba cách đưa nhạc vào: nhập file từ ứng dụng
> Tệp bằng nút cộng ở tab Bài hát; dán liên kết một thư mục Google Drive công
> khai ở Tài khoản → Thư mục Drive; hoặc vào Tìm kiếm → Khám phá Jamendo để
> nghe nhạc Creative Commons miễn phí, không cần chuẩn bị gì.
>
> **I just installed it, why is my library empty?**
> Evenstar ships with no music. Three ways to add some: import files from the
> Files app with the + button on the Songs tab; paste a public Google Drive
> folder link under Account → Drive folders; or open Search → Explore Jamendo
> for free Creative Commons tracks, which needs no setup.

### Bài hiện ra nhưng không phát được

Đây là câu sẽ được hỏi nhiều nhất, và nó bắt nguồn từ một quyết định thiết kế
có chủ ý: **thông tin thư viện đồng bộ qua iCloud, file nhạc thì không.**

> **Máy thứ hai của tôi hiện đủ bài nhưng bấm vào không phát, có chữ "Không có
> trên máy này".**
> Đúng như thiết kế. Tên bài, nghệ sĩ, album và ảnh bìa đi theo Apple Account
> của bạn nên máy nào cũng thấy cùng một danh sách. File nhạc thì nằm ở máy
> bạn đã nhập, không được tải qua iCloud, vì chúng thường rất nặng. Muốn nghe
> trên máy kia thì nhập lại file vào máy ấy.
>
> Lưu ý: **xoá một bài đang ở trạng thái này sẽ gỡ nó khỏi mọi máy**, kể cả máy
> đang giữ file. App có nhắc điều đó trước khi xoá.
>
> **My second device lists every song but nothing plays, it says "not on this
> device".**
> That is by design. Titles, artists, albums and cover art follow your Apple
> Account, so every device shows the same list. The audio files stay on the
> device you imported them to — they are not copied through iCloud, because
> they are large. To play them elsewhere, import the files on that device too.
>
> Note: deleting a track in this state removes it from **every** device,
> including the one that still holds the file. The app warns you first.

### Liên kết Drive không nhận

> **Tôi dán liên kết Drive mà app báo không hợp lệ.**
> Evenstar chỉ nhận liên kết **thư mục**, không nhận liên kết tới một file
> đơn lẻ. Liên kết đúng có dạng `drive.google.com/drive/folders/...`. Nếu bạn
> đang cầm một liên kết dạng `/file/d/...` thì đó là link của một file, hãy mở
> thư mục chứa nó rồi chia sẻ thư mục.
>
> Thư mục cũng phải để chế độ ai có liên kết đều xem được. Thư mục riêng tư sẽ
> không đọc được vì app không đăng nhập vào tài khoản Google của bạn.
>
> **My Drive link is rejected.**
> Evenstar accepts **folder** links only, not links to a single file. A valid
> link looks like `drive.google.com/drive/folders/...`. If yours looks like
> `/file/d/...` that is a file link — open the folder that contains it and
> share the folder instead.
>
> The folder must also be shared as "anyone with the link can view". Private
> folders cannot be read, because the app never signs in to your Google
> account.

### Nhạc Jamendo bị thiếu bài

> **Tôi tìm trên Jamendo mà ít kết quả hơn trên web của họ.**
> Mặc định Evenstar ẩn những bài mang giấy phép cấm dùng cho mục đích thương
> mại. Vào Tài khoản → Cài đặt và tắt "Ẩn nhạc hạn chế thương mại" để thấy đủ.
> Khi tắt, bạn tự chịu trách nhiệm về cách dùng những bài đó.
>
> **Jamendo search shows fewer results than their website.**
> By default Evenstar hides tracks with a non-commercial licence. Turn off
> "Hide non-commercial tracks" under Account → Settings to see them all. With
> it off, how you use those tracks is your responsibility.

### Sửa nhỏ

Dòng thời gian phản hồi đang viết "24–48 business hours", trộn hai đơn vị. Nên
là "within 1–2 business days" hoặc "within 24–48 hours".
