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
/// - **The test for `privacy: .public` is never the value's *type* — it is
///   whether that value's *text* can contain something belonging to the
///   user.** Two things pass that test today, for two different reasons, and
///   neither reason generalises to "errors are public" on its own:
///   - `error.localizedDescription`, for the error types this app currently
///     logs (`URLError`, `CocoaError`, `AVFoundation`'s error domains, and
///     similar). These describe the failure, not the user. This does *not*
///     hold for every `Error` that could ever exist — a hand-rolled error
///     whose `localizedDescription` embeds a file path or a URL would fail
///     the test and must stay redacted.
///   - The `DecodingError` at `JamendoClient`'s response decode, logged with
///     `String(describing: error)` rather than `.localizedDescription`. This
///     passes for a narrower reason: the types being decoded there
///     (`Payload`, `Row`) use compiler-synthesized `Decodable`, so the error
///     is entirely `JSONDecoder`-generated and its description is only a
///     coding path and a type name — never a decoded value. That reasoning
///     depends on those types staying synthesized; a hand-written
///     `init(from:)` added to either one later could make the description
///     carry real field content, and the site would need to stay redacted
///     from that point on. One corner case is not fully ruled out even as
///     things stand: a `.dataCorrupted` case from malformed low-level bytes
///     (bad UTF-8, say) rather than a type/key mismatch — its
///     `debugDescription` comes from `JSONDecoder` internals this project
///     cannot inspect, so it is not provably free of raw content. Flagged
///     here rather than only in a report, so anyone touching that site again
///     can weigh it.
///   Before marking anything else public, apply the test itself, not either
///   bullet as a rule of thumb: can this value's text ever hold something the
///   user typed, named, or pointed at? If yes, or if unsure, it stays
///   redacted.
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
