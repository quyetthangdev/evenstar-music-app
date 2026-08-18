import Foundation

/// The Google API key used to read public Drive folders.
///
/// **This is empty in the repository on purpose, and the app reports a specific
/// error rather than failing obscurely when it is.** Fill it in locally and do
/// not commit the change.
///
/// Hiding a key inside an app binary is theatre — anyone can extract it. The
/// real boundary is in Google Cloud Console: restrict the key to the **Drive
/// API only** and to this app's **bundle ID**. Do that before shipping; a key
/// without those restrictions is a key anyone can spend your quota with.
enum DriveAPIKey {
    static let value = ""

    static var isConfigured: Bool { !value.isEmpty }
}
