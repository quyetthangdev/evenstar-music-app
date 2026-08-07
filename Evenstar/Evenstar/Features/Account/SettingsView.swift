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
