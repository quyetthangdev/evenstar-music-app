# Onboarding cho Evenstar — thiết kế

**Ngày:** 2026-08-19
**Trạng thái:** đã thống nhất qua brainstorming, chưa có plan thi công.

---

## 1. Vấn đề

App đã có `EmptyLibraryView` — một `ContentUnavailableView` với nút "Thêm nhạc".
Nó lo được việc "chưa có nhạc thì làm gì". Nó **không** lo được hai việc:

1. **Ấn tượng đầu.** Lần chạy đầu tiên đưa người dùng thẳng vào một danh sách
   rỗng. Không có chỗ nào nói app này là gì.
2. **Hai thứ không tự phát hiện được:**
   - **Vuốt player xuống để đóng.** Có thanh grabber ở đỉnh nhưng không nói rõ
     là kéo được, và **không có nút đóng nào khác**. Ai không biết thì bị kẹt
     trong player.
   - **Thanh tab tự thu lại khi cuộn.** Không có dấu hiệu nào báo trước, và lần
     đầu nó xảy ra thì dễ bị đọc là lỗi.

Hai thứ khác đã cân nhắc và **loại**: giới thiệu ba nguồn nhạc (On device /
Drive / Jamendo), và dẫn người dùng tới bài hát đầu tiên. Chúng không nằm trong
phạm vi đợt này.

## 2. Mâu thuẫn định hình cả thiết kế

**Các cử chỉ cần dạy chỉ tồn tại khi đã có nhạc.** Ở lần chạy đầu thư viện rỗng,
nên dạy chúng ngay lúc ấy là dạy thứ người dùng không thể thử — cách nhanh nhất
để onboarding bị bấm bỏ qua.

Nên onboarding **không phải một thời điểm mà là hai**:

| thời điểm | vai trò |
|---|---|
| lần chạy đầu, thư viện rỗng | màn giới thiệu — ấn tượng đầu, và chọn ngôn ngữ |
| lần đầu thứ đó dùng được | gợi ý tại chỗ, trên UI thật |

## 3. Kiến trúc

`RootView` **vẫn được gắn ngay từ đầu**; màn giới thiệu phủ lên trên.

```swift
// EvenstarApp.body
WindowGroup {
    ZStack {
        RootView()
            .accessibilityHidden(!introFinished)
        if !introFinished {
            OnboardingIntroView(onFinish: { introFinished = true })
        }
    }
    .environment(...)   // giữ nguyên bảy environment hiện có
}
```

**Vì sao phủ lên chứ không thay thế.** `RootView` làm hai việc ở 500ms đầu:
lớp làm nóng trả trước hoá đơn vẽ-lần-đầu của chrome player, và `LibraryStore`
được seed đồng bộ trong `EvenstarApp.init` để khung đầu không nháy màn hình rỗng.
Thay `RootView` bằng màn giới thiệu sẽ dời cả hai sang *sau* lúc người dùng bấm
"Bắt đầu" — tức rơi đúng vào lúc họ bắt đầu dùng app. Phủ lên thì `RootView` làm
nóng trong lúc người dùng đang đọc.

**`RootView.body` không đọc cờ onboarding nào.** Cú đọc `@AppStorage` nằm ở
`EvenstarApp`, và nó đổi đúng một lần trong đời. Đây là ràng buộc chịu lực, không
phải sở thích: một cú đọc trong `RootView.body` dựng lại `TabView` cùng cả năm
tab, và đó là thứ `PlayerExpansion` cùng `FloatOverPlayer` đã phải tránh bằng
cách đọc giá trị bên trong thân modifier của chính chúng.

**File mới**, `Features/Onboarding/`:

- `OnboardingIntroView.swift`
- `OnboardingHint.swift` — nhãn dùng chung
- `PlayerCloseHint.swift`
- `TabBarMinimiseHint.swift`
- `OnboardingFlags.swift` — khoá lưu trữ và hai hàm thuần

Không sửa `PlayerCard.swift`.

## 4. Màn giới thiệu

```
┌────────────────────┐
│      Evenstar      │
│                    │
│  Nhạc của bạn,     │
│  trên máy của bạn. │
│                    │
│  ○ Theo hệ thống   │
│  ● Tiếng Việt      │
│  ○ English         │
│                    │
│    [ Bắt đầu ]     │
└────────────────────┘
```

Một trang. Bộ chọn ngôn ngữ dùng **đúng** `AppLanguage` đang có — ba nhánh, mỗi
nhánh tự gọi tên mình theo chú thích của chính kiểu ấy ("someone who has the app
in a language they cannot read still has to find their own in the list"), và ghi
vào `AppLanguage.storageKey`. Không tạo cơ chế lưu thứ hai. Đổi ngôn ngữ đổi luôn
chữ trên màn giới thiệu ngay tại chỗ, vì hạ tầng ấy đã chạy.

Nút "Bắt đầu" dùng `.prominentAction`, style đã có.

**Ba chi tiết chịu lực:**

- Nền đục và ăn chạm, nên `RootView` phía sau không nhận cú chạm nào. Cộng
  `accessibilityHidden` để VoiceOver không đọc xuyên qua.
- Cú tan khi bấm "Bắt đầu" chạy trên một hằng số trong `BottomBarStyle`, có nhánh
  phẳng khi bật Giảm chuyển động — đúng khuôn mười hằng số kia. Không gõ số vào
  thân view.
- **Không có nút "Bỏ qua".** Một trang, một nút; thêm đường thoát thứ hai là thêm
  một trạng thái để sai.

## 5. Hai gợi ý

### Gợi ý B không dạy cử chỉ

Cuộn danh sách là phản xạ tự nhiên; người dùng vẫn cuộn dù không ai bảo. Thứ
không tự hiểu được là **kết quả** — thanh tab tự thu lại. Nên gợi ý B là một lời
**giải thích sau khi việc đã xảy ra**, không phải hướng dẫn trước. Điều đó quyết
định thời điểm của nó.

### Bảng

| | gợi ý A — đóng player | gợi ý B — thanh tab thu lại |
|---|---|---|
| hiện khi | player mở hết lần đầu | `isMinimised` thành `true` lần đầu |
| ở đâu | ngay dưới grabber, đỉnh thẻ | trên thanh tab đã thu, trỏ vào nút mở lại |
| chữ | ↓ "Vuốt xuống để đóng" | "Thanh tab thu lại khi bạn cuộn. Bấm để mở lại." |
| tắt khi | bắt đầu kéo, **hoặc** sau 6 giây | bấm mở lại, **hoặc** sau 6 giây |

Mỗi gợi ý hiện **một lần trong đời app**. Làm đúng việc là cách tắt tự nhiên
nhất — không có nút "Đã hiểu".

### Chỗ gắn

```swift
// RootView ZStack, sau PlayerCard
PlayerCloseHint(expansion: expansion).zIndex(2)
TabBarMinimiseHint(isMinimised: isMinimisedActive).zIndex(2)
```

`PlayerCloseHint` đọc `expansion.progress` **bên trong thân của chính nó**, y như
`FloatOverPlayer` — nên một cú kéo tay ghi giá trị ấy mỗi khung không dựng lại
`TabView`. `RootView.body` chỉ dựng ra hai view.

Gợi ý A **không nằm trong `PlayerCard`**: nó định vị theo safe area đỉnh màn
hình, và player mở hết thì tràn màn hình nên "dưới grabber" là một khoảng cố định
từ đỉnh. Đó là 3.000 dòng không phải mở ra.

Một `OnboardingHint` dùng chung — nhãn, hướng mũi, closure "đã xong" — cộng hai
chỗ gọi mỏng. Hai gợi ý thì chưa cần hạ tầng gì hơn.

### Bốn chi tiết chịu lực

- **Không chắn chạm.** `allowsHitTesting(false)` trên cả hai. Người dùng vẫn dùng
  được app trong lúc gợi ý còn đó — đó là lý do chọn nhãn nổi thay vì lớp tối.
- **Không hiện trong lúc màn giới thiệu còn đó, và không đếm 6 giây ở đó.** Cả
  hai đọc thêm cờ `introFinished`.
- **Giảm chuyển động:** hiện bằng opacity, mũi đứng im. Chế độ thường mũi nhấp
  nhẹ theo một hằng số trong `BottomBarStyle` có nhánh phẳng.
- **Đồng hồ 6 giây huỷ được** — `.task` gắn theo điều kiện hiện, nên khi người
  dùng làm đúng thì nó bị huỷ chứ không nổ muộn.

## 6. Lưu trạng thái và hai hàm thuần

Ba cờ trong `UserDefaults`, khoá giữ trong `enum OnboardingFlags` theo khuôn
`AppLanguage.storageKey` / `AppTheme.storageKey`:

```
onboardingIntroFinished
onboardingPlayerCloseHintSeen
onboardingTabBarHintSeen
```

**Ghi cờ ngay lúc gợi ý hiện ra, không phải lúc tắt.** Ai vuốt ngay lập tức thì
coi như chưa đọc — nhưng đúng ca ấy họ *đã làm được cử chỉ*, nên không còn gì để
dạy. Đổi lại: không phải lo cú ghi bị mất khi app bị kill giữa lúc gợi ý còn hiện.

```swift
static func showsPlayerCloseHint(
    introFinished: Bool, alreadySeen: Bool, presentedProgress: Double
) -> Bool

static func showsTabBarHint(
    introFinished: Bool, alreadySeen: Bool, isMinimised: Bool
) -> Bool
```

Ba đầu vào mỗi hàm, không đọc gì từ môi trường — cùng khuôn `morphNeedsFade` và
`source(hasArtwork:loaded:)`, hai hàm mà repo đã trả giá để học rằng chúng phải
thuần mới kiểm được.

**`presentedProgress` là chịu lực.** `expansion.progress` đọc trong `body` đã là
1 ngay khung đầu của một `withAnimation`, nên gác gợi ý vào nó sẽ làm nhãn hiện
khi tấm thẻ còn bé — chưa bung xong đã bảo "vuốt xuống để đóng". Nên
`PlayerCloseHint` là một view **`Animatable`** đọc giá trị đang được *vẽ*, đúng
khuôn `CardSurface` và `PresentedFloat`. Ngưỡng là một hằng số có tên.

**Một dòng chỉ có trong bản Debug**, trong Settings: *"Đặt lại onboarding"* —
xoá ba cờ. Không có nó thì mỗi lần xem lại onboarding phải xoá app và nhập lại
nhạc. Bọc `#if DEBUG` theo tiền lệ Đợt C1, nên nó không có mặt trong bản phát
hành. **Không** có dòng "Xem lại giới thiệu" trong bản phát hành.

## 7. Test

**1. Bảng quyết định của hai hàm thuần** — `OnboardingFlagsTests`.
Chưa xong giới thiệu → không hiện; đã xem → không hiện; đúng điều kiện → hiện;
với gợi ý A thêm hai mốc `presentedProgress` hai bên ngưỡng. Kiểm đột biến từng
rào: bỏ `introFinished` → đỏ, bỏ `alreadySeen` → đỏ, hạ ngưỡng → đỏ.

**2. Hằng số chuyển động mới** — thêm vào `ReduceMotionTests`.
`testEverySpringConstantFlattens` khẳng định **từng hằng số có tên**; nó không tự
quét cả file. Thêm hằng số mới mà không thêm vào test thì test vẫn xanh và nhánh
Giảm chuyển động của hằng số ấy không có ai canh. Nếu là lò xo thì thêm cả vào
bảng `springs` của `SpringSettlingEvidenceTests`, vốn tự dẫn thời lượng phẳng từ
`t(98%)`.

**3. Chuỗi chữ có thật trong cả hai ngôn ngữ.**
Theo tiền lệ `AppLanguageTests`: kiểm chuỗi onboarding **giải ra khác nhau** ở
locale `vi` và `en`, tức String Catalog đã được điền thật chứ không để trống rồi
rơi về tiếng Anh cho cả hai. Không có test này thì bản tiếng Anh có thể ra tiếng
Việt và không ai biết — cái bẫy `developmentRegion` mà kế hoạch bản địa hoá đã
ghi lại.

**Không** viết test host-view hay pixel. `CommitProbe`/`LivePixels` tồn tại vì cú
morph có tính chất đo được và có tiền sử sai; một nhãn hiện rồi tắt thì không.
Thứ đáng ghim là quyết định, và nó ở nhóm 1.

## 8. Ngoài phạm vi

- Giới thiệu ba nguồn nhạc (On device / Drive / Jamendo).
- Dẫn người dùng tới bài hát đầu tiên.
- Gợi ý cho kéo thả sắp xếp hàng đợi, và cho việc bấm viên thuốc để mở player.
- Xem lại giới thiệu trong bản phát hành.
