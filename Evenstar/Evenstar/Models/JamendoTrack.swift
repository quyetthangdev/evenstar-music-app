import Foundation
import SwiftData

/// A Jamendo track the user saved.
///
/// Stores what the catalogue returned **at save time**. Rendering a row never
/// re-queries: a library that needs the network to draw itself is not a library.
///
/// `@Attribute(.unique)` on `jamendoID` and not on the title: two different
/// recordings can share a title, and the same recording must not be saved twice.
///
/// **A `jamendoID` collision — two `JamendoTrack(jamendoID:...)` inserts for
/// the same id — does not raise an error.** SwiftData's `@Attribute(.unique)`
/// upserts: the two rows collapse to one, but on a collision it is `id`, not
/// the caller, that decides which object's `id` the surviving row keeps, and
/// it is not necessarily either original. `PlaybackState` persists queue
/// membership as bare `UUID`s (`currentTrackID`, `queueTrackIDs`) with no
/// relationship back to this table, so nothing re-links them when a row's
/// `id` changes underneath it — a restored queue silently loses any track
/// whose `id` moved. This is exactly what an unguarded double-`save()` could
/// produce; see `JamendoLibraryService.inFlightSaves` for why a second
/// concurrent `save()` for the same id is coalesced onto the first rather
/// than allowed to insert its own row. Same shape as `DriveTrack`'s
/// type-level doc comment, for the same reason.
@Model
final class JamendoTrack {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var jamendoID: String
    var title: String
    var artistName: String
    var albumTitle: String
    var durationSeconds: Double
    var audioURLString: String
    /// The licence this track is offered under. Shown to the user — CC-BY
    /// obliges visible credit — and `nil` only when the catalogue omitted it.
    var licenceURLString: String?
    /// The track's page on Jamendo, for the attribution link.
    var shareURLString: String?
    /// Documents-relative, downloaded when the track was saved. See
    /// `JamendoLibraryService.save`.
    var artworkRelativePath: String?
    var dateAdded: Date
    var playCount: Int
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        jamendoID: String,
        title: String,
        artistName: String,
        albumTitle: String,
        durationSeconds: Double,
        audioURLString: String,
        licenceURLString: String? = nil,
        shareURLString: String? = nil,
        artworkRelativePath: String? = nil,
        dateAdded: Date = Date(),
        playCount: Int = 0,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.jamendoID = jamendoID
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.durationSeconds = durationSeconds
        self.audioURLString = audioURLString
        self.licenceURLString = licenceURLString
        self.shareURLString = shareURLString
        self.artworkRelativePath = artworkRelativePath
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }

    convenience init(from track: JamendoCatalogueTrack, artworkRelativePath: String?) {
        self.init(
            jamendoID: track.id,
            title: track.title,
            artistName: track.artistName,
            albumTitle: track.albumTitle,
            durationSeconds: track.durationSeconds,
            audioURLString: track.audioURL.absoluteString,
            licenceURLString: track.licenceURL?.absoluteString,
            shareURLString: track.shareURL?.absoluteString,
            artworkRelativePath: artworkRelativePath
        )
    }
}
