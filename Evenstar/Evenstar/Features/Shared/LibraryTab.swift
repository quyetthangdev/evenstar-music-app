import SwiftUI

/// Năm điểm đến của app. Search là một tab thường của hệ thống
/// (`Tab(role: .search)`), không còn là nút tròn riêng như thời thanh tab tự vẽ.
enum LibraryTab: String, Identifiable {
    case songs, albums, artists, account, search
    var id: String { rawValue }

    /// **`String(localized:)`, not a bare literal.** A `String` handed to
    /// `Text` is displayed verbatim — only a string *literal* becomes a
    /// `LocalizedStringKey` and goes through the catalogue. So an enum that
    /// returns plain literals renders untranslated no matter how complete the
    /// catalogue is, and it does not even appear in it to be noticed as
    /// missing: the tab bar and the source chips stayed Vietnamese in an
    /// English build, with everything else around them translated.
    ///
    /// Localising here rather than at the call site keeps it a `String`, which
    /// one caller needs — the accessibility label interpolates it into a
    /// sentence, and `LocalizedStringKey` cannot be interpolated into one.
    var label: String {
        switch self {
        case .songs:   String(localized: "Bài hát", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .albums:  String(localized: "Album", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .artists: String(localized: "Nghệ sĩ", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .account: String(localized: "Tài khoản", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .search:  String(localized: "Tìm kiếm", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        }
    }

    var symbol: String {
        switch self {
        case .songs:   "music.note.list"
        case .albums:  "square.stack"
        case .artists: "music.mic"
        case .account: "person.crop.circle"
        case .search:  "magnifyingglass"
        }
    }
}
