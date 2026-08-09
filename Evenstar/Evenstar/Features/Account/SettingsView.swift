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
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
