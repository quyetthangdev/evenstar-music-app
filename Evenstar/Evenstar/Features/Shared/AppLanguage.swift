import Foundation

/// Which language the app draws itself in, whatever the phone is set to.
///
/// Same shape as `AppTheme`, and for the same reason: "Theo hệ thống" is not a
/// third language, it is the absence of an override, and only an optional can
/// say that.
///
/// **iOS already offers a per-app language in Settings, and this deliberately
/// duplicates it.** The system's version is correct but hard to find — it lives
/// three screens into Settings and only appears once the phone itself has more
/// than one preferred language. Choosing here reaches the same result from the
/// place people look for it.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }

    /// Each language names itself, the way every language picker on iOS does —
    /// someone who has the app in a language they cannot read still has to find
    /// their own in the list.
    var label: String {
        switch self {
        case .system: String(localized: "Theo hệ thống", bundle: Self.resolvedBundle, locale: Self.resolvedLocale)
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        }
    }

    /// `nil` for `.system`: no override, defer to the phone.
    var locale: Locale? {
        switch self {
        case .system: nil
        case .vietnamese: Locale(identifier: "vi")
        case .english: Locale(identifier: "en")
        }
    }

    static let storageKey = "appLanguage"

    /// The locale to localise with, readable from anywhere — including from
    /// outside any view.
    ///
    /// **This is why it reads `UserDefaults` rather than caching in a
    /// variable.** `.environment(\.locale,)` covers `Text` and nothing else:
    /// `String(localized:)` resolves against the *process's* languages and
    /// ignores the environment entirely, and this app routes both its enum
    /// labels and every one of its error messages through it. Those are called
    /// from places that have no environment to read — an `errorDescription` is
    /// built wherever the failure happened.
    ///
    /// A stored static would need to be kept in step with the setting and would
    /// be a mutable global besides. `UserDefaults` is already the store, is
    /// thread-safe, and cannot go stale.
    ///
    /// **`resolvedBundle` above is the half that actually chooses the language,
    /// and `resolvedLocale` is not.** `String(localized:locale:)`'s `locale`
    /// only formats the values interpolated into the string — Apple's own
    /// documentation says so, and this was written the other way round first:
    /// the navigation title translated and the tab labels did not, because a
    /// locale cannot pick a strings table. The table comes from the bundle, so
    /// every call site passes both.
    static var resolvedBundle: Bundle {
        guard let language = stored, let code = language.locale?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    private static var stored: AppLanguage? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return AppLanguage(rawValue: raw)
    }

    static var resolvedLocale: Locale {
        guard let locale = stored?.locale else { return .autoupdatingCurrent }
        return locale
    }
}
