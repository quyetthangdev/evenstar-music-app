import Foundation

/// What `PlaybackService` needs of anything it can play.
///
/// Exists so one queue can hold local files and Drive files without the service
/// knowing which is which. Everything the service already does — repeat, the
/// lock screen, session restore, play counting, the skip-forward-on-failure
/// loop — then works for both sources without being written twice.
///
/// `AnyObject` because the service mutates `playCount` and `lastPlayedAt` in
/// place on rows that SwiftData is tracking.
protocol Playable: AnyObject {
    /// Stable across launches. `PlaybackState` persists these.
    var id: UUID { get }
    var title: String { get }
    var artistName: String { get }
    var albumTitle: String { get }
    var durationSeconds: Double { get }
    /// Documents-relative. `nil` for anything with no local artwork, which is
    /// every Drive track — artwork is out of scope for this đợt.
    var artworkRelativePath: String? { get }
    var playCount: Int { get set }
    var lastPlayedAt: Date? { get set }

    /// Where the bytes are. A file URL for local tracks, an https URL for Drive.
    func playbackURL() -> URL
}

extension Track: Playable {
    func playbackURL() -> URL {
        FileLocation.absoluteURL(forRelative: relativePath)
    }
}

extension DriveTrack: Playable {
    /// `artistName` and `albumTitle` are optional on the row because they are
    /// genuinely unknown until the track has been played once; the protocol
    /// wants a string, so unknown becomes the same placeholder the local
    /// library uses for untagged files.
    var artistName: String { artistNameOrNil ?? "Nghệ sĩ không rõ" }
    var albumTitle: String { albumTitleOrNil ?? "Album không rõ" }
    var artworkRelativePath: String? { nil }

    func playbackURL() -> URL {
        DriveClient.mediaURL(fileID: fileID)
    }
}
