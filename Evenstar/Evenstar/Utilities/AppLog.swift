import OSLog

/// Unified-logging entry points, in place of `print`.
///
/// `print` only reaches stdout — visible in Xcode's console while a cable is
/// attached, and nowhere else. It never reaches unified logging, so it is
/// absent from Console.app on a user's machine and absent from a
/// sysdiagnose. A failure that only ever `print`s is, in practice, a failure
/// nobody but a developer holding the device can ever see. `Logger` fixes
/// that: everything logged through it is collected by the system and stays
/// reachable after the fact.
///
/// ## Privacy — read before adding a new call site
///
/// `Logger` redacts every interpolated value to `<private>` by default, and
/// that default is correct for this app: unified logs can leave the device
/// (sysdiagnose, Console.app over a network), so anything identifying a
/// person must not be in them.
///
/// - **Track and artist names, file paths, URLs — anything that names what a
///   user has or does: leave the default (redacted) privacy.** Do not add
///   `privacy: .public` to make a value easier to read while debugging.
/// - **`error.localizedDescription` is the one exception: mark it
///   `privacy: .public`.** It describes the failure, not the user, and is
///   exactly what a diagnosis needs to be legible in Console.app.
/// - If it is unclear which side a value falls on, leave it redacted.
///   Redacting something that turns out to be harmless only costs a
///   Console.app click; publishing something that turns out to be personal
///   cannot be taken back once it has left a device.
enum AppLog {
    /// The running app's own bundle id, not a literal — a hardcoded
    /// subsystem string would silently stop matching the day the bundle id
    /// changes, and logs would vanish from the filter people are using to
    /// find them without anything failing loudly.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Evenstar"

    /// The on-device library: reading, deleting, and the queue that follows
    /// from either.
    static let library = Logger(subsystem: subsystem, category: "library")

    /// Jamendo: the catalogue client and the saved-track screens built on it.
    static let jamendo = Logger(subsystem: subsystem, category: "jamendo")

    /// Audio session and transport.
    static let playback = Logger(subsystem: subsystem, category: "playback")
}
