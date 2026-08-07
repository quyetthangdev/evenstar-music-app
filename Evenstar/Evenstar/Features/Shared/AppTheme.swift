import SwiftUI

/// Which appearance the app draws itself in, whatever the phone is set to.
///
/// Three cases and not two. "Sáng" and "Tối" are the override; **"Theo hệ
/// thống" is not a third colour, it is the absence of an override** — and that
/// distinction is the whole reason this is an enum rather than a `Bool`. A
/// two-state switch cannot say "I have no opinion", so an app built on one
/// either picks a side for the user at first launch or has to carry a separate
/// "has the user chosen yet" flag beside it. Modelling the absence directly
/// removes both problems, and it is also what `preferredColorScheme` already
/// expects: it takes an *optional* scheme and treats `nil` as "defer".
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// See `LibraryTab.label` for why this is `String(localized:)` and not a
    /// bare literal.
    var label: String {
        switch self {
        case .system: String(localized: "Theo hệ thống")
        case .light: String(localized: "Sáng")
        case .dark: String(localized: "Tối")
        }
    }

    /// What to hand `preferredColorScheme`. `nil` means "no preference", which
    /// is how the system default is expressed — not a missing value to be
    /// defaulted away somewhere else.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The `UserDefaults` key, named once.
    ///
    /// Two `@AppStorage` properties read this — `RootView` to apply it and
    /// `AccountView` to edit it — and a key spelled out twice is a key that
    /// eventually differs in one. The symptom would be silent: the setting
    /// would appear to save and the app would never change.
    static let storageKey = "appTheme"
}
