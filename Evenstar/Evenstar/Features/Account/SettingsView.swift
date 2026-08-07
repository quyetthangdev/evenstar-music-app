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
    @Environment(\.openURL) private var openURL

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
                Button {
                    // The one URL iOS accepts for "open my own settings page".
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    HStack {
                        Text("Ngôn ngữ")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Self.currentLanguageName)
                            .foregroundStyle(.secondary)
                        // The system's own mark for "this leaves the app", the
                        // way Settings shows it. Not a chevron: a chevron
                        // promises a screen inside this app, and this is not
                        // one.
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                // `.plain`, or the whole row is painted in the accent colour.
                //
                // `.primary` and `.secondary` are *hierarchical* styles: they
                // resolve against whatever foreground style is in force, and
                // inside a default `Button` label that is the tint. So the label
                // came out accent-coloured and the value came out accent at 60%,
                // reading as a link rather than as a settings row — the same
                // trap the repeat button's tint hit from the other direction.
                //
                // Settings' own rows that open elsewhere look like ordinary
                // rows. Being tappable is said by the mark on the right, not by
                // colouring the words.
                .buttonStyle(.plain)
            } footer: {
                Text("Ngôn ngữ được đổi trong Cài đặt của iOS. Nếu không thấy mục đó, thêm một ngôn ngữ nữa vào Cài đặt chung → Ngôn ngữ & Vùng.")
            }
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The language the app is currently running in, named in that language.
    ///
    /// Read from the bundle rather than from `Locale.current`: what matters is
    /// which localisation the app actually resolved to, which is not always the
    /// phone's first choice — a phone set to a language the app does not have
    /// falls back, and the row must say what is on screen rather than what was
    /// asked for.
    private static var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
