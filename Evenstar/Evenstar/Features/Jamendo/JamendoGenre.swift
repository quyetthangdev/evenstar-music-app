import Foundation

/// A genre chip: the tag Jamendo indexes, and the name a person reads.
///
/// **These are two different strings and cannot be one.** The tag goes on the
/// wire verbatim — `hiphop`, one word, lower case, because that is what
/// Jamendo's index contains. The label is what belongs on a control in an app
/// whose source language is Vietnamese, and for a third of these that is not
/// the tag with its first letter capitalised.
///
/// The chips used to render `tag.capitalized` directly, which produced
/// "Electronic" and "Classical" in a Vietnamese interface and "Hiphop" in
/// both — a spelling that is wrong in either language.
///
/// An enum rather than a dictionary keyed by string: a dictionary lets a chip
/// exist for a tag with no label, and the failure is a blank capsule nobody
/// notices until it ships. Here the compiler will not let the two drift.
enum JamendoGenre: String {
    case rock
    case pop
    case electronic
    case jazz
    case classical
    case hiphop

    /// What the API is sent. Never shown to anyone.
    var tag: String { rawValue }

    /// Which chips the discovery screen offers, in the order it offers them.
    ///
    /// An explicit list rather than `CaseIterable`, for the reason
    /// `RepeatMode` gives for the same choice: the order is a decision about
    /// what the screen looks like, and deriving it from the declaration order
    /// would let someone reorder the cases for readability and silently
    /// reorder the UI. Jamendo's tag vocabulary runs to thousands of words; a
    /// row of six familiar ones is a starting point, and a tag list nobody can
    /// read is not.
    static let offered: [JamendoGenre] = [
        .rock, .pop, .electronic, .jazz, .classical, .hiphop
    ]

    var label: String {
        switch self {
        // Loanwords Vietnamese already uses unchanged. Deliberately not routed
        // through the string catalogue: a key whose two translations are the
        // same word is a row that can only ever be got wrong, never right.
        case .rock: "Rock"
        case .pop: "Pop"
        case .jazz: "Jazz"
        // Two words in both languages. The tag stays one word because that is
        // what Jamendo indexes — this is exactly the split the type exists for.
        case .hiphop: "Hip hop"
        case .electronic:
            String(localized: "Điện tử",
                   bundle: AppLanguage.resolvedBundle,
                   locale: AppLanguage.resolvedLocale)
        case .classical:
            String(localized: "Cổ điển",
                   bundle: AppLanguage.resolvedBundle,
                   locale: AppLanguage.resolvedLocale)
        }
    }
}
