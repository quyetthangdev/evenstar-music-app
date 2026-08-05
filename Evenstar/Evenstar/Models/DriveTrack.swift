import Foundation
import SwiftData

/// One audio file inside a linked `DriveFolder`.
///
/// Deliberately not a variant of `Track`. Sharing that model would be cheaper
/// in the playback layer but would force every existing `@Query` to grow a
/// filter, and missing one would leak Drive rows into the local library. Two
/// models make the compiler enforce the split instead of a reviewer.
@Model
final class DriveTrack {
    /// Stable across app launches, and what `PlaybackState` persists.
    /// Distinct from `fileID`, which is Google's.
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var fileID: String
    var folderID: String
    var fileName: String
    var title: String
    /// Stored optional, because "not read yet" is real and distinct from
    /// "read, and the file has no artist tag". `Playable` exposes non-optional
    /// `artistName`/`albumTitle` computed from these — see `Playable.swift`.
    var artistNameOrNil: String?
    var albumTitleOrNil: String?
    /// 0 until `metadataResolved`. Not optional: `Playable` needs a number, and
    /// two ways to say "unknown" in one row is one too many.
    var durationSeconds: Double
    /// False until the track has been played once and its real tags read over
    /// the network. Scanning deliberately does not read tags — see the spec.
    var metadataResolved: Bool
    var dateAdded: Date
    var playCount: Int
    var lastPlayedAt: Date?

    init(id: UUID = UUID(),
         fileID: String,
         folderID: String,
         fileName: String,
         title: String? = nil,
         artistName: String? = nil,
         albumTitle: String? = nil,
         durationSeconds: Double = 0,
         metadataResolved: Bool = false,
         dateAdded: Date = .now,
         playCount: Int = 0,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.fileID = fileID
        self.folderID = folderID
        self.fileName = fileName
        self.title = title ?? Self.titleFromFileName(fileName)
        self.artistNameOrNil = artistName
        self.albumTitleOrNil = albumTitle
        self.durationSeconds = durationSeconds
        self.metadataResolved = metadataResolved
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }

    /// `(NSString as NSString).deletingPathExtension` rather than splitting on
    /// ".", so a title containing a dot keeps it.
    static func titleFromFileName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}
