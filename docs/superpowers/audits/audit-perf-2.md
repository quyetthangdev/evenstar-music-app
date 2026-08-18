# Evenstar — điều tra hiệu năng, vòng hai

Phạm vi: toàn bộ `Evenstar/Evenstar/` (17.422 dòng). Không chỉ thẻ player như vòng một — lần này gồm cả năm màn hình thư viện, Drive, Jamendo, tìm kiếm, tài khoản, và lớp dịch vụ.

Cơ sở: **năm phiên Instruments `Animation Hitches` trên iPhone 12 bản Release**, cộng với đọc mã. Mỗi con số dưới đây có xuất xứ; chỗ nào là suy đoán thì nói rõ là suy đoán.

---

## Bối cảnh: vòng một đã kết luận sai chỗ nào

`audit-perf.md` kết luận thủ phạm chính là `.shadow()` trên thẻ đang đổi kích thước, dựa vào Color Offscreen-Rendered Yellow cho thấy cả màn hình vàng, và Instruments quy 50% hitch cho "Expensive GPU".

**Số đo mới bác kết luận ấy.** Sửa **một** cú ghi SwiftData đồng bộ trên main thread — không đụng tới một `.shadow()` hay `Material` nào — cho kết quả:

| | trước | sau |
|---|---|---|
| commit (app dựng khung) | 959 ms | 303 ms |
| render | 652 ms | 352 ms |
| **GPU** | **1072 ms** | **371 ms** |

GPU giảm 65% mà không ai chạm vào GPU. Nghĩa là GPU không tự quá tải — **nó đang chạy theo main thread**. Mỗi khung bị main thread giữ lại là một khung compositor phải làm bù, và Instruments quy phần bù ấy cho `backboardd`, đúng chữ ký mà vòng một đọc thành "Expensive GPU".

Bài học phương pháp: *offscreen pass tốn tiền* và *offscreen pass là nút cổ chai* là hai mệnh đề khác nhau. Vòng một chứng minh mệnh đề thứ nhất rồi kết luận mệnh đề thứ hai.

---

## Số đo hiện tại

Chuẩn hoá theo **số giây thật sự có vẽ** (bảng `displayed-surfaces-per-second`), không chia đều cho thời lượng ghi:

| phiên | giây vẽ | hitch | ms/giây | lần chặn main thread | dài nhất |
|---|---|---|---|---|---|
| gốc | 28 | 3294 ms | **117.6** | 23 | 441, 323, 116 |
| sau khi chặn ghi mảng UUID | 18 | 1547 ms | **85.9** | 7 | 324, 118, 111 |
| sau khi sửa crash cử chỉ | 28 | 2058 ms | **73.5** | 17 | 122, 82, 58 |

Ngưỡng của Apple: dưới 5 ms/giây là tốt, 5–10 thấy được, trên 10 là tệ. **Hiện tại vẫn gấp bảy lần ngưỡng tệ.**

Đã hết: những cú chặn thảm hoạ (441ms → 122ms). Đó mới là thứ đọc ra như "đứng hình". Còn lại là vấp đều.

---

## Bảng vấn đề, xếp theo cấp độ

Cấp theo chi phí × tần suất, không theo công sức sửa. "Đo được" nghĩa là có trong trace; "đọc mã" nghĩa là suy ra từ cấu trúc, chưa đo riêng.

| # | Cấp | Chỗ | Vấn đề | Bằng chứng |
|---|---|---|---|---|
| 1 | **Nghiêm trọng** | `AccountView.swift:31,32` | Gom nhóm + sắp xếp **toàn thư viện hai lần trong `body`** chỉ để lấy hai con số | Đọc mã |
| 2 | **Nghiêm trọng** | 5 file | **Năm `@Query` cùng quét toàn bộ bảng `Track`**, sống song song | Đọc mã |
| 3 | **Cao** | `PlaybackService.swift:1140` | Timer 0.5s ghi `position`, và `NowPlayingContent` đọc nó trong `body` | Đo được + đọc mã |
| 4 | **Cao** | `PlayerCard.swift:743` | `displayedArtwork` tra `NSCache` **mỗi lần `body` chạy**, tức mỗi khung khi kéo | Đọc mã |
| 5 | **Cao** | `PlayerCard.swift` (2.332 dòng) | Một `View` với 47 thành viên; mọi thay đổi đều dựng lại cả thân | Đo được |
| 6 | **Trung bình** | `ArtworkThumbnail.swift:27` | Tra cache **đồng bộ trong `init`**, chạy cho mọi hàng ở mọi lượt dựng | Đọc mã |
| 7 | **Trung bình** | `SearchView.swift:39` | Lọc toàn thư viện trong `body`, mỗi ký tự gõ | Đọc mã |
| 8 | **Trung bình** | `FloatingTabBar.swift:448,561,805` | Ba `.regularMaterial` **luôn nằm trên màn hình** | Đo được (vòng một) |
| 9 | **Trung bình** | `RootView.swift:290` | Lớp làm nóng vẽ `NowPlayingContent` suốt 500ms đầu | Đọc mã |
| 10 | **Thấp** | 3 file | `UIScreen.main.scale` — API đã bỏ, và là lượt chạm main-actor | Đọc mã |
| 11 | **Thấp** | `PlaybackService.swift:219` | `persistInterval = 5` giây nhưng vẫn ghi cả bản ghi mỗi lần | Đo được |
| 12 | **Thấp** | `ReorderableStack.swift:453,454` | Hai `.shadow` chồng nhau trên hàng đang nhấc | Đọc mã |

---

## Chi tiết

### 1. `AccountView` gom nhóm cả thư viện trong `body` — cấp Nghiêm trọng

```swift
row("Bài hát",  value: "\(tracks.count)")
row("Album",    value: "\(LibraryGrouping.albums(from: tracks).count)")
row("Nghệ sĩ",  value: "\(LibraryGrouping.artists(from: tracks).count)")
```

`LibraryGrouping.albums(from:)` là `Dictionary(grouping:)` trên toàn bộ mảng, rồi `.map` dựng `AlbumGroup`, rồi `.sorted` với so sánh `localizedStandard`, và bên trong còn `sortedAlbumTracks` sắp xếp từng nhóm. `artists(from:)` làm điều tương tự. Cả hai chạy **trong thân view**, tức mỗi lần `AccountView` dựng lại — mà nó dựng lại mỗi khi `@Query` đổi, tức mỗi lần nhập/xoá/sửa một bài.

Với thư viện 1.000 bài: hai lượt gom nhóm cộng bốn lượt sắp xếp chuỗi có bản địa hoá, để hiển thị hai số nguyên.

`AlbumsView.swift:52,60` và `ArtistsView.swift:32,38` làm **đúng** — gom nhóm trong `.task`/`onChange`, cất vào `@State`. `AccountView` là chỗ duy nhất làm trong `body`. Không phải mẫu hình sai, mà là một chỗ sót.

**Sửa:** dời vào `.task(id: tracks.count)` sẵn có ở dòng 74, cất hai số vào `@State`.

### 2. Năm `@Query` cùng quét bảng `Track` — cấp Nghiêm trọng

```
Features/Library/SongsView.swift:10
Features/Library/AlbumsView.swift:9
Features/Library/ArtistsView.swift:9
Features/Search/SearchView.swift:6
Features/Account/AccountView.swift:14
```

Cả năm cùng một truy vấn: mọi `Track`, sắp theo `title` với `localizedStandard`.

`TabView` của SwiftUI dựng lười, nhưng **giữ lại sau khi đã dựng**. Chạm hết các tab một lượt là năm truy vấn sống song song. Từ đó, mỗi lần chèn/xoá/sửa một `Track` sẽ:

1. Chạy lại năm lượt fetch qua SQLite
2. Sắp xếp năm lần với so sánh có bản địa hoá (đắt hơn so sánh byte nhiều lần)
3. Vô hiệu hoá năm cây view, mỗi cây dựng lại

Đây là mẫu hình `@Query` phổ biến nhất bị dùng sai trong SwiftData. Nó không hiện ra trong trace của phiên này vì phiên đo không nhập nhạc — nhưng nhập 40 bài là 40 vòng như trên, và đó đúng là lúc app phải mượt nhất.

**Sửa:** một `@Query` duy nhất ở `RootView`, đưa xuống qua environment; hoặc `@Query` với `FetchDescriptor` hẹp cho từng màn (Album chỉ cần `albumTitle` + `artistName`, không cần cả bản ghi).

### 3. Timer 0.5 giây kéo cả `NowPlayingContent` dựng lại — cấp Cao

`PlaybackService.swift:1140` chạy `Timer(timeInterval: 0.5, repeats: true)` ghi `position`. `NowPlayingContent.swift:318` đọc `playback.position` trong `scrubber`, nằm trong `body`.

Với `@Observable`, đọc `position` trong `body` nghĩa là **cả `NowPlayingContent` dựng lại hai lần mỗi giây** khi đang phát — kể cả khi player đóng, vì view vẫn nằm trong cây ở opacity 0. Thân ấy gồm khối tiêu đề, thanh tua, ba nút transport, thanh âm lượng và hàng nút hàng đợi.

Vòng một đã ghi nhận (mục 218) và chưa sửa.

**Sửa:** bọc phần đọc `position` vào một view con nhỏ, để chỉ nó dựng lại. Cùng thủ thuật `Slot` trong `ReorderableStack` đang dùng, và ghi chú ở đó đã giải thích nguyên lý.

### 4. `displayedArtwork` tra cache mỗi khung — cấp Cao

`PlayerCard.swift:743` là **computed property**, không phải `@State`:

```swift
private var displayedArtwork: UIImage? {
    Self.preferredCover(
        hasArtwork: hasArtwork,
        loadedForThisTrack: ...,
        cachedForThisPath: ArtworkStore.anyCachedImage(for: ...)
    )
}
```

`anyCachedImage` tra `NSCache`, mà `NSCache` **có khoá bên trong**. Nó được gọi từ `artworkView`, chạy lại mỗi khung suốt cú kéo. Sáu mươi lần một giây, một lượt lấy khoá cộng dựng chuỗi khoá cache, trên main thread, giữa một animation.

Không đắt bằng một lượt giải mã ảnh, nhưng nó là loại chi phí không nên có ở đó: kết quả không đổi giữa các khung của cùng một cú kéo.

**Sửa:** phân giải một lần khi bài đổi, cất vào `@State`.

### 5. `PlayerCard` là một `View` 2.332 dòng với 47 thành viên — cấp Cao

Đây là chỗ khó sửa nhất và cũng là nơi tốn nhất trong trace.

`@State` trong file này gồm: `settled`, `dragDelta`, `isDragging`, `queueFactor`, `queueContentReveal`, `queueContentSlide`, `queueTitleHidden`, `queueIsReordering`, `showingQueue`, `artwork`, `tint`, `artworkOwner`. Mỗi lần **bất kỳ** cái nào đổi, `body` chạy lại — và `body` dựng cả thẻ, tấm bìa, chrome thu nhỏ, nội dung mở rộng, grabber, cùng mọi thứ bên trong.

Trong lúc kéo có ít nhất ba trong số đó đổi mỗi khung.

Trace cho thấy chi phí ấy: `AG::Subgraph::update`, `AG::Graph::propagate_dirty`, `Attribute.init` là nhóm ký hiệu dày nhất trên main thread sau khi đã loại phần environment.

**Sửa:** tách theo trục thay đổi. Tấm bìa chỉ cần `progress`/`queueFactor`; chrome thu nhỏ chỉ cần `progress`; nội dung mở rộng chỉ cần `progress` và ba con số hàng đợi. Ba view con nhận đúng thứ chúng cần thì mỗi khung chỉ dựng lại phần thật sự đổi. Đây là việc lớn, và nên làm sau khi mục 1–4 đã dọn xong để đo được nó đáng bao nhiêu.

### 6. `ArtworkThumbnail.init` tra cache đồng bộ — cấp Trung bình

`ArtworkThumbnail.swift:27` gọi `ArtworkStore.cachedImage(for:maxPixel:)` **trong `init`**.

Ghi chú tại chỗ giải thích vì sao: `.task` chạy sau lượt dựng đầu, nên hàng nào cuộn vào cũng nháy xám một khung. Lý do đúng, và cái giá cũng thật: `init` của một `View` chạy **mỗi lần view cha dựng lại**, không phải mỗi lần view xuất hiện. Cuộn danh sách 1.000 bài thì mỗi ô hiện ra chạy một lượt tra `NSCache` có khoá, cộng một lượt dựng chuỗi khoá.

Trace hiện ký hiệu `ListCollectionViewCellBase.hostingView(_:willUpdate:)` trong 8 mẫu của các lần chặn — đó là ô `List` đang cập nhật, và đây là thứ chạy bên trong.

**Sửa:** giữ nguyên hành vi, nhưng nhớ kết quả theo `(path, maxPixel)` trong một `Dictionary` thường thay vì `NSCache` cho đường đi đồng bộ — bỏ được phần khoá. Hoặc chấp nhận: nó đúng, chỉ là không rẻ như ghi chú ngụ ý.

### 7. `SearchView` lọc toàn thư viện trong `body` — cấp Trung bình

`SearchView.swift:39`: `let results = LibraryGrouping.search(query, in: tracks)` nằm trong `body`. Mỗi ký tự gõ là một lượt quét toàn bộ mảng với gấp nếp dấu và chữ hoa thường.

Với vài nghìn bài thì vẫn dưới ngưỡng thấy được, nhưng nó nằm trên đường đi của bàn phím — nơi trễ đọc ra ngay lập tức.

**Sửa:** `.task(id: query)` với một quãng chờ 150ms, cất kết quả vào `@State`.

### 8. Ba `Material` luôn trên màn hình — cấp Trung bình

`FloatingTabBar.swift:448,561,805` — ba `.regularMaterial`, mỗi cái là một lượt làm mờ trực tiếp tính lại mỗi khung, kể cả khi không có gì chuyển động.

Vòng một đã ghi nhận. Số đo mới cho thấy chúng **không** phải nút cổ chai — nhưng chúng là chi phí nền, và chi phí nền là thứ cộng vào mọi thứ khác. Ba lượt blur trên một máy 60Hz để vẽ ba viên thuốc luôn hiện.

**Chưa nên sửa.** Đo riêng trước: ghi 15 giây chỉ cuộn danh sách, một lần với thanh tab như hiện tại, một lần thay `Material` bằng màu đặc. Chênh lệch nói thẳng nó đáng bao nhiêu.

### 9. Lớp làm nóng vẽ cả chrome player suốt 500ms đầu — cấp Trung bình

`RootView.swift:290` dựng một `NowPlayingContent` thật ở opacity 0.02, dưới `TabView`, trong 500ms sau khi mở app, để trả trước chi phí rasterize glyph.

Ý tưởng đúng và có đo (ghi chú nói 56ms cho khung đầu của cú bung đầu tiên). Nhưng nó đánh đổi lấy 500ms đầu tiên của app — đúng lúc `@Query` đang fetch, SwiftData đang mở store, và người dùng đang nhìn màn hình đầu. Chi phí bị dời chứ không bị bỏ, và nó dời vào chỗ đông đúc nhất.

**Đề xuất:** dời sang sau lượt vẽ đầu tiên hoàn tất, thay vì chạy song song với nó.

### 10–12. Ba mục nhỏ

- **`UIScreen.main.scale`** ở `ArtworkThumbnail.swift:73`, `JamendoResultRow.swift:209`, `PlayerCard.swift:2319`. API này đã bị bỏ từ iOS 16 và là lượt chạm main-actor. Thay bằng `\.displayScale` trong environment — vừa đúng cho màn ngoài, vừa không phải một lượt gọi động.
- **`persistInterval = 5` giây** nhưng mỗi lượt ghi vẫn gán mọi thuộc tính. Sau khi đã chặn hai mảng UUID thì phần còn lại rẻ, nhưng `try? library.save()` vẫn xả cả `ModelContext` — gồm mọi thay đổi đang treo của `Track`.
- **Hai `.shadow` chồng nhau** ở `ReorderableStack.swift:453,454` trên hàng đang nhấc. Đúng về mặt hình (bóng môi trường + bóng tiếp xúc), nhưng là hai lượt vẽ bóng trên một view đang di chuyển mỗi khung. Một hàng thôi, nên nhỏ.

---

## Đã sửa trong phiên này

Ghi lại để không ai sửa lại lần nữa.

**Ghi SwiftData đồng bộ trên main thread — 441ms.** `persistImmediately()` gán vô điều kiện hai mảng UUID; SwiftData đánh dấu bẩn khi *gán*, không phải khi giá trị đổi, nên mọi cú ghi — kể cả cú ghi 5 giây một lần chỉ để cập nhật vị trí phát — mã hoá lại toàn bộ hàng đợi thành blob rồi viết xuống SQLite. Chặn bằng phép so trước khi gán. Đo được: 117.6 → 85.9 ms/giây, và stack `NSSQLCore` biến mất khỏi các lần chặn.

**Crash trong AttributeGraph.** `ReorderLongPress` gọi `context.converter.localLocation` từ trong callback của recogniser UIKit. Phép đọc ấy bắt AttributeGraph tính lại chuỗi thuộc tính hình học đi qua `OffsetPosition` và `AnimatableFrameAttribute` — đúng những thuộc tính đang được animate. Hỏi graph ngoài lượt cập nhật view thì nó `abort()`. Thay bằng `recognizer.location(in: nil)` cộng một mốc đo trong lượt cập nhật.

**Ba lượt đẩy `\.colorScheme` gộp còn hai**, và chỗ còn lại nằm ngoài phần thân chạy theo từng khung. Nhóm ký hiệu `_UIHostingView.updateEnvironment` / `UITraitCollection.resolvedEnvironment` / `_traitCollectionDidChangeInternal` là dày nhất trong các lần chặn còn lại. **Chưa đo lại sau khi sửa** — đây là giả thuyết đã hành động, chưa phải kết luận.

---

## Thứ tự đề xuất

1. **Mục 1** — sửa trong mười phút, bỏ được hai lượt gom nhóm toàn thư viện mỗi lần `AccountView` dựng lại.
2. **Mục 2** — một `@Query`, đưa xuống qua environment. Đây là mục có tỉ lệ lợi/công cao nhất trong bảng.
3. **Mục 3, 4** — hai lượt tách view nhỏ, mẫu hình đã có sẵn trong `ReorderableStack`.
4. **Đo lại.** Bốn mục trên cộng lại đủ để nói con số 73.5 có tụt hay không. Nếu tụt dưới 20 thì mục 5 không cần làm.
5. **Mục 5** — chỉ khi số đo còn đòi.

---

## Cách đo, cho lần sau

```
xcrun xctrace record --template 'Animation Hitches' \
  --device <UDID> --attach Evenstar --time-limit 45s --output out.trace
```

Ba điều bắt buộc, mỗi điều đã hỏng một lần trong phiên này:

- **Chuẩn hoá theo `displayed-surfaces-per-second`.** Một phiên cho ra 11.1 ms/giây trông như đã đạt, trong khi app chỉ vẽ 6 trên 45 giây. Chia theo số giây thật sự có vẽ thì con số là 83.
- **Kiểm CPU của tiến trình `xctrace` nếu nó lâu.** Một phiên treo 21 phút ở 0% CPU với file trace đứng im — không phải đang lưu, mà là đã chết. Đừng `pkill` giữa phiên ghi: nó để lại phiên chưa đóng ở phía máy và làm treo lần sau.
- **Đo từng thao tác một.** Gộp năm thao tác vào một trace thì mọi giả thuyết đều khớp dữ liệu.
