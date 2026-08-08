import Foundation

/// The Jamendo client id, from `devportal.jamendo.com`.
///
/// **Empty in the repository on purpose**, and the app reports
/// `JamendoError.missingClientID` rather than failing obscurely when it is.
/// Fill it in locally and do not commit the change:
///
///     git update-index --skip-worktree Evenstar/Evenstar/Services/JamendoAPIKey.swift
///
/// Hiding a credential in an app binary is theatre — anyone can extract it. The
/// real boundary is the quota and restrictions on Jamendo's side.
enum JamendoAPIKey {
    static let value = ""

    static var isConfigured: Bool { !value.isEmpty }
}
