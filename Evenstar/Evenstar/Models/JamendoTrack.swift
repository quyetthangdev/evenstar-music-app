import Foundation
import SwiftData

/// A Jamendo track the user saved.
///
/// Stores what the catalogue returned **at save time**. Rendering a row never
/// re-queries: a library that needs the network to draw itself is not a library.
///
/// `@Attribute(.unique)` on `jamendoID` and not on the title: two different
/// recordings can share a title, and the same recording must not be saved twice.
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
