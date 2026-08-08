import Foundation

/// Turns the user's one licence setting into query parameters.
///
/// **A pure function on purpose.** It is the only part of this integration
/// where being wrong is a legal problem rather than a visual one, so it is
/// testable without a network, and it is tested.
///
/// `ccnc=false` excludes non-commercial licences. Off, the parameter is
/// *absent* rather than `true`: asking Jamendo for NC-only would be a third
/// behaviour nobody chose.
enum JamendoLicencePolicy {
    /// Read by `@AppStorage` in `SettingsView` and by the client. One name,
    /// stated once.
    static let storageKey = "jamendoCommercialOnly"

    /// The default, and it is the restrictive one. The app intends to charge
    /// money, CC-NC forbids commercial use, and whether "playing music inside a
    /// paid app" counts is genuinely unsettled. Pulling music out of a released
    /// app is the outcome this avoids.
    static let defaultCommercialOnly = true

    static func queryItems(commercialOnly: Bool) -> [URLQueryItem] {
        guard commercialOnly else { return [] }
        return [URLQueryItem(name: "ccnc", value: "false")]
    }
}
