import Foundation

/// Judges one track's licence against the user's one licence setting.
///
/// **A pure function on purpose.** It is the only part of this integration
/// where being wrong is a legal problem rather than a visual one, so it is
/// testable without a network, and it is tested.
///
/// This used to build a `ccnc=false` query parameter for Jamendo's search API.
/// It cannot: measured live (see `task-9-brief.md`), `ccnc` only ever narrows
/// the catalogue to NC-only or leaves it unfiltered — there is no
/// server-side way to ask for "no NC". So the filter has to run client-side,
/// against each decoded track, which is what `JamendoClient` now does with
/// `permits(licenceURL:commercialOnly:)`.
enum JamendoLicencePolicy {
    /// Read by `@AppStorage` in `SettingsView` and by the client. One name,
    /// stated once.
    static let storageKey = "jamendoCommercialOnly"

    /// The default, and it is the restrictive one. The app intends to charge
    /// money, CC-NC forbids commercial use, and whether "playing music inside a
    /// paid app" counts is genuinely unsettled. Pulling music out of a released
    /// app is the outcome this avoids.
    static let defaultCommercialOnly = true

    /// Whether a track may be offered given the current setting.
    ///
    /// Off, everything passes and the licence is never examined — asking for
    /// NC-only would be a third behaviour nobody chose.
    ///
    /// On, a licence must be a Creative Commons URL whose clause list does not
    /// contain `nc` (`by`, `by-sa`, `by-nd` pass; `by-nc*` variants do not). A
    /// track whose licence is `nil`, malformed, or not from
    /// `creativecommons.org` at all — the Free Art License turns up in the
    /// catalogue too — is rejected rather than assumed safe: an unreadable
    /// licence is a licence whose terms are unknown, and the whole point of
    /// the restrictive default is to not ship music on unknown terms.
    static func permits(licenceURL: URL?, commercialOnly: Bool) -> Bool {
        guard commercialOnly else { return true }
        guard let licenceURL, let clauses = commercialClauses(in: licenceURL) else { return false }
        return !clauses.contains("nc")
    }

    /// The dash-separated clause list from a Creative Commons licence URL —
    /// `["by", "nc", "sa"]` from `.../licenses/by-nc-sa/2.0/`. `nil` for any
    /// URL that is not shaped like one, which is deliberately the same outcome
    /// as an NC clause: unrecognised terms do not pass when the setting is on.
    private static func commercialClauses(in url: URL) -> [String]? {
        guard url.host()?.hasSuffix("creativecommons.org") == true else { return nil }
        let components = url.pathComponents
        guard let licencesIndex = components.firstIndex(of: "licenses") else { return nil }
        let clauseIndex = components.index(after: licencesIndex)
        guard clauseIndex < components.count else { return nil }
        return components[clauseIndex].split(separator: "-").map(String.init)
    }
}
