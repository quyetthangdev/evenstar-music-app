import Foundation
import SwiftData

/// One audio file inside a linked `DriveFolder`.
///
/// Deliberately not a variant of `Track`. Sharing that model would be cheaper
/// in the playback layer but would force every existing `@Query` to grow a
/// filter, and missing one would leak Drive rows into the local library. Two
/// models make the compiler enforce the split instead of a reviewer.
///
/// **Reconciling a scan against existing rows must fetch by `fileID` and
/// mutate in place — never construct a fresh `DriveTrack(fileID:...)` and
/// insert it for a `fileID` that may already exist.** SwiftData's
/// `@Attribute(.unique)` on `fileID` does keep the row count at one either
/// way, but on a collision it is `id` — not the caller — that decides which
/// object's `id` the surviving row keeps, and it is not necessarily the
/// original. Re-inserting a known `fileID` on every rescan therefore mints a
/// new `id` for that row on every rescan. `PlaybackState` persists queue
/// membership as bare `UUID`s (`currentTrackID`, `queueTrackIDs`) with no
/// relationship back to this table, so nothing re-links them when a row's
/// `id` changes underneath it — a restored queue silently loses any track
/// whose `id` moved. See `testInsertingTheSameFileIDTwiceKeepsOneRow` for the
/// reproduction.
@Model
final class DriveTrack {
    /// What `PlaybackState` persists to identify a queued track. Distinct
    /// from `fileID`, which is Google's.
    ///
    /// *Not* stable across a `fileID` collision — see the type-level doc
    /// comment. Only stable if every reconcile fetches the existing row by
    /// `fileID` and mutates it, rather than reconstructing and inserting.
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
