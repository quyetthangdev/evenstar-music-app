import SwiftUI

/// The app's settings, on their own screen.
///
/// Split out of `AccountView`, which had grown into three unrelated things in
/// one list: what the library adds up to, where its music comes from, and how
/// the app behaves. Only the last is a setting, and settings are the part that
/// grows — every preference added from here on has a home rather than another
/// section wedged between the storage figure and the version number.
///
/// **No "Thông báo" row.** The app sends no notifications — it does not link
/// `UserNotifications` and never asks for permission — so a row for them would
/// be a control that leads to a switch governing nothing. It belongs here the
/// day something actually notifies, and not before.
struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    /// Same key `JamendoDiscoveryView` reads with its own `@AppStorage`, and
    /// the same default — `JamendoLicencePolicy.defaultCommercialOnly`, not a
    /// literal `true` restated here. Two names for the one preference would
    /// desync the instant either side changed, and a mismatched default would
    /// mean a fresh install disagreeing with itself about what it is set to
    /// before the user has touched the toggle at all.
    @AppStorage(JamendoLicencePolicy.storageKey) private var commercialOnly =
        JamendoLicencePolicy.defaultCommercialOnly

    // `#if DEBUG`, không loại khỏi target: dự án dùng Xcode 16 synced
    // folders, nên loại một file khỏi target đòi sửa `.pbxproj` — việc bị
    // cấm với agent. Bọc thay vì xoá để mục "Bản thử" biến mất khỏi Release
    // mà bốn bản thử vẫn mở được ở Debug.
    #if DEBUG
    @State private var showingMorphDemo = false
    @State private var showingUIKitDemo = false
    @State private var showingZoomDemo = false
    @State private var showingReorderDemo = false
    #endif

    var body: some View {
        List {
            Section {
                // `.navigationLink`, not `.segmented`.
                //
                // The segmented control this replaced broke two of the
                // guidelines' own bullets for that control: "keep segment size
                // consistent" and "keep icon and title widths consistent" —
                // "Theo hệ thống" is three times the width of "Tối", so the
                // three segments could never be balanced. It also had to hide
                // its label to fit, and a settings row without a label is not a
                // settings row.
                //
                // A navigation-link picker is the idiom Settings itself uses for
                // a choice of more than two: the row states the setting and its
                // current value, and the options live on a pushed screen with a
                // checkmark. It also stops caring how long the option names are,
                // which is what makes it survive translation.
                Picker("Giao diện", selection: $theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Hiển thị")
            }

            Section {
                // A real picker now, not a button that hands the job to iOS.
                //
                // The first version of this row opened Settings, on the belief
                // that an in-app switcher needs a relaunch. That is true of
                // `AppleLanguages`, and false of SwiftUI: a `LocalizedStringKey`
                // resolves against the environment's locale, so setting
                // `\.locale` at the root retranslates every `Text` on the spot.
                // Checked on screen before this was written — a phone in
                // Vietnamese, the environment forced to English, and the
                // navigation title came out "Songs".
                Picker("Ngôn ngữ", selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            } footer: {
                // Said plainly rather than left to be discovered. The bits that
                // stay in the phone's language are the system's own screens —
                // the photo picker, the file importer, the volume control — and
                // no app can translate those for itself.
                Text("Màn hình do hệ thống cung cấp — chọn ảnh, chọn tệp, điều khiển âm lượng — vẫn theo ngôn ngữ của máy.")
            }

            Section {
                // Names what the switch *does to the screen*, not what the
                // licence permits. "Chỉ nhạc dùng được cho mục đích thương
                // mại" described a property of a licence, from a lawyer's
                // side of the table, and left the reader to work out why they
                // should care — the first person to read it said plainly that
                // they could not tell. A setting nobody understands is a
                // setting nobody can make an informed choice about, which
                // defeats the reason this one is exposed at all.
                Toggle("Ẩn nhạc hạn chế thương mại", isOn: $commercialOnly)
            } header: {
                Text("Jamendo")
            } footer: {
                // States the consequence rather than hiding it, the same
                // reason the Drive link screen states its privacy warning at
                // the moment of linking rather than after the fact: turning
                // this off is a real legal decision (see
                // `JamendoLicencePolicy`'s doc comment on why the default is
                // the restrictive one), and it belongs on the control itself,
                // not behind a tap into "more info".
                Text("Nhiều bài trên Jamendo mang giấy phép NC: nghe cá nhân thì thoải mái, nhưng cấm dùng trong sản phẩm có thu tiền. Bật để giấu chúng khỏi màn Khám phá. Tắt thì có nhiều nhạc hơn để chọn, và bạn tự chịu trách nhiệm về giấy phép.")
            }

            // `#if DEBUG`, không loại khỏi target: dự án dùng Xcode 16
            // synced folders, nên loại một file khỏi target đòi sửa
            // `.pbxproj` — việc bị cấm với agent. Cả `Section` nằm trong
            // khối này, kể cả header, vì một mục "Bản thử" rỗng còn tệ hơn
            // một mục có nội dung.
            #if DEBUG
            Section {
                // `verbatim` khắp mục này, khác với mọi mục khác trong màn
                // hình: đây là bản thử sẽ bị xoá, và `Text("…")` là
                // `LocalizedStringKey` nên ba chuỗi này sẽ được trích thẳng
                // vào `Localizable.xcstrings` rồi nằm lại đó thành khoá chết
                // sau khi bản thử đi. Hôm nay chúng hiện y hệt nhau vì nguồn
                // của catalogue vốn là tiếng Việt.
                Button { showingMorphDemo = true } label: {
                    Text(verbatim: "Chuyển cảnh player — SwiftUI")
                }
                Button { showingUIKitDemo = true } label: {
                    Text(verbatim: "Chuyển cảnh player — UIKit")
                }
                Button { showingZoomDemo = true } label: {
                    Text(verbatim: "Chuyển cảnh player — hệ thống (.zoom)")
                }
                Button { showingReorderDemo = true } label: {
                    Text(verbatim: "Kéo thả playlist — tự dựng cử chỉ")
                }
            } header: {
                Text(verbatim: "Bản thử")
            } footer: {
                // Nói thẳng đây là bản thử, vì nó *trông* như một player thật
                // và không phải player của app này: dữ liệu giả, không phát
                // được gì. Một màn hình lạ không có lời giải thích là một lỗi
                // đối với người dùng, kể cả khi nó nằm sâu trong Cài đặt.
                Text(verbatim: "Hai player rời, dữ liệu giả, cùng hình dáng nhưng khác động cơ chuyển động: một bằng SwiftUI, một bằng UIViewPropertyAnimator. Không ảnh hưởng gì tới nhạc đang phát.")
            }
            #endif
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        // `#if DEBUG`, không loại khỏi target: dự án dùng Xcode 16 synced
        // folders, nên loại một file khỏi target đòi sửa `.pbxproj` — việc
        // bị cấm với agent. Các chú thích bên dưới giải thích mã sắp không
        // tồn tại ở Release, nên phải nằm trong cùng khối này.
        #if DEBUG
        // `fullScreenCover`, không phải `NavigationLink`: bản thử tự dựng cả
        // thanh tab và mini player của riêng nó, nên nó cần cả màn hình. Đẩy
        // nó vào navigation stack thì hai thanh tab chồng lên nhau.
        .fullScreenCover(isPresented: $showingMorphDemo) {
            PlayerMorphDemoView { showingMorphDemo = false }
        }
        // Bản UIKit, để so cạnh nhau: cùng số đo, cùng hình dáng, khác động cơ.
        // Xem `PlayerMorphUIKitView` để biết nó trả lời câu hỏi gì.
        .fullScreenCover(isPresented: $showingUIKitDemo) {
            PlayerMorphUIKitView { showingUIKitDemo = false }
                .ignoresSafeArea()
        }
        // Bản thứ ba: không một dòng animation nào tự viết. Xem
        // `PlayerZoomDemoView` — chạm để mở, vuốt để đóng, hệ thống lo hết.
        .fullScreenCover(isPresented: $showingZoomDemo) {
            PlayerZoomDemoView { showingZoomDemo = false }
        }
        // Kéo thả tự dựng: `List` không cho chạm vào hàng đang nhấc, nên nền
        // lúc nhấn giữ và cú đáp đàn hồi lúc thả chỉ có được khi tự sở hữu cử
        // chỉ. Xem `PlaylistReorderDemo`.
        .fullScreenCover(isPresented: $showingReorderDemo) {
            PlaylistReorderDemo { showingReorderDemo = false }
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
