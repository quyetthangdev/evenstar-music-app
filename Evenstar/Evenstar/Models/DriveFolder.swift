import Foundation
import SwiftData

/// A Google Drive folder the user has linked.
///
/// Only folders shared as *anyone with the link* work — the app reads them with
/// a plain API key and never signs in. See the design spec for why signing in
/// is not an option here.
@Model
final class DriveFolder {
    @Attribute(.unique) var folderID: String
    var displayName: String
    var linkedAt: Date
    /// `nil` until the first successful scan, which is what distinguishes
    /// "never scanned" from "scanned and empty".
    var lastScannedAt: Date?

    init(folderID: String,
         displayName: String,
         linkedAt: Date = .now,
         lastScannedAt: Date? = nil) {
        self.folderID = folderID
        self.displayName = displayName
        self.linkedAt = linkedAt
        self.lastScannedAt = lastScannedAt
    }
}
