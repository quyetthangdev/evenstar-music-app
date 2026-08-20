# Đồng bộ qua CloudKit — thiết kế

**Ngày:** 2026-08-20
**Nhánh:** `cloudkit-sync`, cắt từ `main`
**Trạng thái:** đã duyệt 5/5 mục trong brainstorming

## Mục tiêu

Thư viện, playlist và trạng thái phát đi theo Apple Account của người dùng, giữa
các máy của **chính họ**. Không tài khoản riêng, không server riêng, không đồng
bộ file nhạc.

Nói rõ cái **không** làm, vì đó là thứ giữ cho thiết kế nhỏ:

- **Không đồng bộ file âm thanh.** File nhạc ở lại máy đã nhập nó. Máy khác thấy
  hàng dữ liệu nhưng không phát được, và được đánh dấu rõ.
- **Không có tài khoản của Evenstar.** Không đăng ký, không mật khẩu, không email.
  Apple Account đã đăng nhập trên máy là toàn bộ danh tính.
- **Không chia sẻ giữa nhiều người.** CloudKit private database, một người dùng.
- **Không có công tắc bật/tắt đồng bộ.** Lý do ở mục 4.

## Vì sao CloudKit chứ không phải Supabase

Cả hai đều làm được việc. CloudKit thắng ở đúng bài toán này:

- **Không có tầng xác thực để viết.** Supabase cần đăng nhập, phiên, làm mới
  token, xử lý hết hạn, màn hình đăng nhập, luồng quên mật khẩu. CloudKit không
  cần một dòng nào — hệ điều hành đã biết người dùng là ai.
- **SwiftData nói chuyện thẳng với nó.** `ModelConfiguration(cloudKitDatabase:)`
  là toàn bộ tích hợp. Supabase đòi một tầng ánh xạ giữa `@Model` và bảng Postgres,
  và tầng ấy là nơi lỗi đồng bộ sinh ra.
- **Không chi phí vận hành.** Không hoá đơn, không hạn mức, không gia hạn.
- **Ngoại tuyến là mặc định.** Ghi khi mất mạng rồi đồng bộ sau là hành vi có sẵn.

Cái giá phải trả, nói thẳng: **khoá vào Apple.** Không có bản Android, không có
bản web, không xuất dữ liệu ra ngoài hệ sinh thái. Với một app nhạc cục bộ trên
iOS thì đó không phải mất mát.

---

## Mục 1 — Mô hình dữ liệu

### Ràng buộc CloudKit áp lên `@Model`

CloudKit không chấp nhận ba thứ, và mã hiện tại vi phạm hai:

1. **Không `@Attribute(.unique)`.** Có **6 chỗ** phải bỏ.
2. **Mọi thuộc tính phải optional hoặc có giá trị mặc định.** Đúng **33 thuộc
   tính** phải nhận mặc định — đếm bằng máy, không ước lượng (bảng dưới).
3. **Quan hệ phải optional.** Repo **không có `@Relationship` nào**, nên không có
   việc phải làm ở đây.

### Sáu chỗ `unique` phải bỏ

| Model | Thuộc tính |
|---|---|
| `Track` | `id` |
| `JamendoTrack` | `id`, `jamendoID` |
| `DriveFolder` | `folderID` |
| `DriveTrack` | `id`, `fileID` |

### 33 thuộc tính phải nhận giá trị mặc định

| Model | Số | Thuộc tính |
|---|---|---|
| `Track` | 9 | `id`, `title`, `artistName`, `albumTitle`, `durationSeconds`, `relativePath`, `format`, `dateAdded`, `playCount` |
| `JamendoTrack` | 9 | `id`, `jamendoID`, `title`, `artistName`, `albumTitle`, `durationSeconds`, `audioURLString`, `dateAdded`, `playCount` |
| `DriveTrack` | 9 | `id`, `fileID`, `folderID`, `fileName`, `title`, `durationSeconds`, `metadataResolved`, `dateAdded`, `playCount` |
| `DriveFolder` | 3 | `folderID`, `displayName`, `linkedAt` |
| `PlaybackState` | 3 | `positionSeconds`, `queueTrackIDs`, `queueIndex` |

Mọi thuộc tính optional (`trackNumber`, `lastPlayedAt`, `artworkRelativePath`, …)
đã hợp lệ, không phải đụng. Bốn thuộc tính của `PlaybackState` đã mang mặc định
sẵn (`repeatModeRaw`, `isShuffled`, `unshuffledQueueTrackIDs`, `isAutoplay`) —
và doc comment của chúng đã ghi đúng lý do đó là điều bắt buộc, nên mẫu để noi
theo nằm sẵn trong repo.

### Bỏ `unique` **rẻ hơn** vẻ ngoài, và đây là bằng chứng

Nghe như tháo mất hàng rào chống trùng. Thực tế repo **đã tự chống trùng bằng
tay** rồi, và tài liệu của chính nó nói vì sao:

`JamendoLibraryService.inFlightSaves` gom mỗi `jamendoID` về một `Task` duy nhất,
nên hai lệnh `save()` đồng thời cho cùng một id không bao giờ thành hai lệnh
insert. Doc comment của `JamendoTrack` ghi rõ lý do: dựa vào `unique` **là lỗi
họ đã sửa**, vì khi va chạm thì SwiftData upsert và `id` của hàng sống sót *không
nhất thiết* là `id` gốc — trong khi `PlaybackState` giữ thành viên hàng đợi bằng
`UUID` trần không có quan hệ ngược, nên một hàng đổi `id` làm hàng đợi mất bài
trong im lặng.

`DriveTrack` mang đúng cảnh báo ấy: mọi lượt quét lại **phải fetch theo `fileID`
rồi sửa tại chỗ**, không được dựng `DriveTrack` mới và insert.

Nghĩa là: `unique` ở đây chưa bao giờ là hàng rào thật. Bỏ nó không mất gì đang
được dùng.

### Nhưng CloudKit **có** sinh một ca trùng mới

Ca mà `inFlightSaves` không với tới: **hai máy cùng lưu một bài khi ngoại tuyến**.
Không có `Task` chung, không có khoá chung. Cả hai lên mây, và ta có hai hàng
cùng khoá tự nhiên.

### Quy tắc gộp trùng

Diễn đạt thành **hàm thuần**, không chạm SwiftData, để test được:

Vào: hai hàng cùng khoá tự nhiên. Ra: quyết định gộp.

1. **Giữ hàng có `dateAdded` sớm hơn.** Đó là hàng "gốc"; hàng kia là bản sao
   sinh sau.
2. **Cộng `playCount`.** Mỗi máy đếm lượt nghe riêng; tổng mới là số thật.
3. **`lastPlayedAt` lấy cái muộn hơn** (nil thua mọi ngày).
4. **Xoá hàng còn lại.**
5. **Nếu `PlaybackState` trỏ tới hàng bị xoá** (`currentTrackID` hoặc phần tử
   trong `queueTrackIDs` / `unshuffledQueueTrackIDs`), **trỏ lại sang hàng giữ**.

Bước 5 là bước dễ quên nhất và là bước đúng cái lỗi mà hai doc comment trên đã
ghi lại: hàng đợi giữ `UUID` trần, không ai nối lại hộ.

**Khoá tự nhiên, và hai bảng bị loại:**

| Model | Khoá tự nhiên | Gộp? |
|---|---|---|
| `DriveTrack` | `fileID` | **Có** |
| `JamendoTrack` | `jamendoID` | **Có** |
| `Track` | *không có* | **Không** |
| `DriveFolder` | `folderID` | **Không** |

Hai chỗ loại trừ ấy được tìm ra khi viết plan, bằng cách đọc mã thay vì suy đoán,
và mỗi chỗ có lý do riêng.

**`Track` không có khoá tự nhiên.** `ImportService` dựng
`relativePath = "Music/\(id.uuidString).\(ext)"` — đường dẫn chứa `id` của chính
hàng ấy, nên hai máy nhập cùng một file sinh hai đường dẫn khác nhau. Đó là khoá
riêng của máy, không phải khoá tự nhiên.

Đổi sang khoá tên+nghệ sĩ+thời lượng (kiểu `findExistingTrack` đang dùng) còn
**tệ hơn hẳn**: gộp xong, hàng sống sót giữ **một** `relativePath`, và máy không
phải chủ đường dẫn đó vẫn còn file thật trên đĩa nhưng không còn hàng nào trỏ
tới. Mất quyền phát một bài mình đang có, đổi lấy một danh sách gọn hơn.

Nên hai hàng `Track` cùng tên trên hai máy **không phải trùng lặp**. Chúng là hai
file thật ở hai chỗ thật, và mỗi máy chỉ phát được cái của mình. Cái giá, nói
thẳng: người dùng **thấy bài ấy hai dòng**. Gộp hai dòng ở tầng hiển thị là một
tính năng riêng, không thuộc đợt này.

**`DriveFolder` không có tiêu chí cắt hoà tất định.** Nó không có `id`, không có
bộ đếm — không trường nào phân biệt được hai hàng cùng `folderID`. Mà quy tắc gộp
**bắt buộc** phải tất định: lượt gộp chạy độc lập trên mỗi máy, nên nếu máy A giữ
hàng X và máy B giữ hàng Y, mỗi máy xoá hàng kia và cả hai lệnh xoá cùng đồng bộ
lên — **mất sạch cả hai**. Một hàng thừa là chuyện thẩm mỹ; mất cả hai là mất dữ
liệu.

**Cắt hoà khi `dateAdded` bằng nhau: cắt bằng `id`.** Cùng lý do trên, và đây là
ca có thật — hai máy lưu cùng một bài trong cùng một giây. Cắt bằng thứ tự đầu vào
là cách chắc chắn làm mất bài.

**Khi nào chạy:** một lượt lúc khởi động. Hàng trùng đến trong phiên này được dọn
ở **lần mở app sau**. Đánh đổi có chủ ý: bám theo `NSPersistentStoreRemoteChange`
dọn sớm hơn nhưng thêm một luồng sự kiện bắn liên tục vào một thao tác có xoá
hàng.

---

## Mục 2 — Bài không có trên máy này

### Vì sao "có mặt" **không** được đồng bộ

Sự có mặt của file là **thuộc tính của máy**, không phải của bài. Lưu nó thành
một thuộc tính của `@Model` là sai ngay từ định nghĩa: máy A ghi `true`, máy B
đồng bộ về và đọc `true` cho một file nó không có.

Nên nó được **tính tại chỗ**, không lưu.

### Cách tính

Một lượt `contentsOfDirectory` trên `FileLocation.musicFolderURL()` lúc khởi
động, đổ vào một `Set<String>` các đường dẫn tương đối, giữ trong `LibraryStore`.
Một syscall cho cả thư viện, không phải một `fileExists` cho mỗi hàng.

Chỉ áp cho **`Track`**. `DriveTrack` và `JamendoTrack` là URL mạng — chúng không
có khái niệm "có trên máy này".

### Bốn hành vi

**(1) Hiển thị.** Hàng vắng mặt hiện mờ, kèm chữ "không có trên máy này". Vẫn
thấy được — người dùng cần biết mình *có* bài ấy, chỉ là không ở đây.

**(2) Chạm không phát và không xếp hàng.** Chạm một hàng vắng mặt không làm gì
ngoài việc nói lý do.

**(3) Tự chuyển bài bỏ qua bài vắng mặt — ĐÃ CÓ SẴN.**

Đây là hiệu chỉnh so với bản trình bày ban đầu. `PlaybackService.loadCurrentAndPlay()`
đã có vòng bỏ-qua-bài-không-mở-được: `AVAudioPlayer(contentsOf:)` ném lỗi với file
vắng mặt, vòng lặp tăng `attempts`, đi tiếp, và có chặn trên `queue.count` nên
kết thúc ở `stopPlayback()` chứ không quay vòng vô hạn.

**Không phải việc phải làm. Là việc phải ghim bằng test**, vì nó là hành vi mà
thiết kế này dựa vào, và một lần sửa vô ý ở đó sẽ làm nhạc dừng trong im lặng.

**(4) Xoá bài vắng mặt phải cảnh báo.**

Đây là chỗ nguy hiểm thật. Trên máy B, xoá một bài vắng mặt trông như "dọn một
hàng rác". Thực tế nó **xoá bài khỏi mọi máy**, kể cả máy đang giữ file thật.

Cảnh báo: *"Bài này không có trên máy này. Xoá sẽ gỡ nó khỏi mọi máy."*

**Câu chữ có chủ ý.** Bản nháp đầu viết *"có trên một máy khác"* — app **không biết
được** điều đó. Một bài vắng mặt có thể chỉ là file bị xoá từ ngoài app trên một
máy dùng đơn lẻ, và lúc ấy câu kia là nói dối người dùng đúng lúc họ đang quyết
định xoá. Câu đã chọn đúng trong cả hai trường hợp.

Quy tắc là hàm thuần: trạng thái vào, có/không cảnh báo ra.

---

## Mục 3 — Bật CloudKit

### Phần trong mã — một chỗ

`EvenstarApp.init` hiện dựng container không cấu hình. Đổi sang một
`ModelConfiguration` khai báo container CloudKit.

### Phần phải làm trong Xcode — **agent không được đụng**

Repo **chưa có file `.entitlements` nào**. Tạo nó và thêm capability sẽ sửa
`.pbxproj`, mà ràng buộc của dự án cấm agent sửa `.pbxproj`/`.xcscheme`.

Các bước người dùng tự làm:

1. Target **Evenstar** → **Signing & Capabilities** → **+ Capability** → **iCloud**
2. Tick **CloudKit**
3. Thêm container: `iCloud.com.evenstar.app`
4. **+ Capability** → **Background Modes** → tick **Remote notifications**

**Bước 4 là bước dễ sót và hậu quả im lặng:** thiếu nó thì đồng bộ chỉ chạy khi
app đang mở, và trông y hệt như đồng bộ hỏng.

### Bẫy Development / Production

CloudKit có hai môi trường tách biệt. Schema tự sinh ở **Development** từ lần
chạy đầu. Bản **Release** nói chuyện với **Production**, và schema ở đó **không
tự có**.

Triệu chứng: bản Debug đồng bộ tốt, phát hành xong bản Release không đồng bộ gì
cả, **không một thông báo lỗi nào**.

Phải vào CloudKit Console bấm **Deploy Schema to Production** trước mỗi lần phát
hành có đổi model. Đây là mục bàn giao thường trực, không phải việc một lần.

### Kiểm bằng tay

- Simulator/máy phải đăng nhập iCloud, nếu không container không dựng được.
- Kiểm đồng bộ thật **cần hai máy** cùng Apple Account. Một máy không chứng minh
  được gì.

---

## Mục 4 — Dữ liệu đang có, và hai máy đều đã có dữ liệu

### Migration

Bỏ `unique` và thêm giá trị mặc định đều thuộc loại **migration nhẹ** — SwiftData
tự xử, không cần `VersionedSchema`.

Nhưng **không được tin, phải kiểm**, vì `EvenstarApp.init` có
`fatalError("Failed to create ModelContainer")`: migration hỏng nghĩa là **app
crash ngay khi mở**, không có đường phục hồi nào ngoài xoá app.

**Bước bắt buộc, làm trước mọi việc khác:** cài bản hiện tại, tạo dữ liệu thật,
rồi cài đè bản mới lên. **Không** kiểm trên máy sạch — máy sạch luôn qua.

### Lần bật đầu tiên

Dữ liệu cục bộ đẩy lên iCloud. Một chiều, không có gì để hoà giải.

### Hai máy đều đã có dữ liệu từ trước

Cả hai cùng đẩy. Kết quả là **hợp** của hai thư viện, kèm trùng lặp theo khoá tự
nhiên — đúng thứ quy tắc gộp trùng ở mục 1 xử lý.

Đây là ca **duy nhất** mà lượt gộp trùng chạy ở quy mô lớn, nên nó phải chạy được
với hàng trăm hàng, không chỉ với hai.

### Điều người dùng sẽ **nhìn thấy** — ghi ra để không tưởng là lỗi

iPhone có 50 bài file, iPad có 20 bài khác. Sau đồng bộ **cả hai máy đều thấy 70
hàng** — iPhone phát được 50, iPad phát được 20, phần còn lại mờ đi.

Đó là thiết kế chạy đúng.

### Hai quyết định đã chốt

**Không có công tắc bật/tắt đồng bộ.** SwiftData dựng container ở `init`, nên đổi
lúc chạy không làm được sạch — nó đòi khởi động lại app. Một công tắc phải bảo
người dùng "tắt app rồi mở lại" là một công tắc tệ hơn không có.

**Bật CloudKit là cửa một chiều trên thực tế.** Tắt sau này thì dữ liệu cục bộ
còn nguyên và ngừng đồng bộ, nhưng bản sao trong iCloud vẫn nằm đó cho tới khi
người dùng tự xoá.

---

## Mục 5 — Test

### Bốn thứ test tự động ghim được

Cả bốn đều là **hàm thuần**, không chạm SwiftData, không chạm CloudKit:

1. **Quy tắc gộp trùng** — hai hàng vào, một quyết định ra. Gồm cả bước 5 (trỏ
   lại `PlaybackState`), là bước dễ quên nhất.
2. **Bỏ qua bài vắng mặt khi tự chuyển bài** — ghim hành vi *đã có*. Ca khó:
   **tất cả** bài còn lại đều vắng → phải dừng hẳn, không lặp vô hạn.
3. **Cảnh báo khi xoá bài vắng mặt** — trạng thái vào, có/không cảnh báo ra.
4. **Tính tập bài có mặt** — chạm đĩa, nhưng chỉ một thư mục tạm.

### Hai thứ **không** test tự động được

**Migration.** Chỉ kiểm được bằng cài đè lên bản có dữ liệu. Hỏng ở đây là crash
lúc mở app.

**Đồng bộ.** Cần hai máy thật cùng Apple Account.

### Một điều bị **cấm** trong plan

**Không viết test nào cố chứng minh CloudKit đồng bộ.** Chúng sẽ phải mock, và
một test mock ở đây **tệ hơn không có test**: nó xanh, nó trông như có lưới, và
nó không bắt được lỗi thật nào.

Repo này đã dính đúng cái bẫy ấy một lần —
`testTheCardIsOpaqueWhileItTravels` ghim chính giả định sai của người viết và
đứng xanh suốt **bốn** lần sửa hỏng.

### 567 test hiện có

Không đụng tới. `EvenstarTests/InMemoryLibrary.swift` dựng
`ModelConfiguration(isStoredInMemoryOnly: true)` riêng, nên container CloudKit
của app không đi vào đường ấy.

---

## Thứ tự thi công

1. **Chuẩn bị**: cài bản hiện tại và tạo dữ liệu thật, để sẵn một bản cài có dữ
   liệu. Không kiểm được một migration chưa viết — cái làm được trước là bản cài
   để lát nữa cài đè lên.
2. Bỏ 6 `unique`, thêm 33 giá trị mặc định. **Rồi kiểm migration ngay**, bằng
   cách cài đè lên bản ở bước 1. Hỏng ở đây là app crash lúc mở, nên không đi
   tiếp khi chưa qua.
3. Quy tắc gộp trùng + test.
4. Tính tập bài có mặt trong `LibraryStore` + test.
5. UI mờ + chạm không phát.
6. Cảnh báo khi xoá + test.
7. Ghim hành vi bỏ qua bài vắng mặt bằng test.
8. **Bàn giao Xcode** — người dùng bật capability.
9. `ModelConfiguration(cloudKitDatabase:)` trong `EvenstarApp.init`.
10. Kiểm hai máy.

Bước 8 chặn bước 9, và bước 9 chặn bước 10. Các bước 2–7 không phụ thuộc CloudKit
được bật, nên làm và test được trước khi chạm Xcode.

## Việc bàn giao thường trực

- **Deploy Schema to Production** trước mỗi lần phát hành có đổi model.
