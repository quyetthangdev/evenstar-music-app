import Foundation

/// The one line under the title, in both the expanded player and the collapsed
/// one.
///
/// **Two things share that line, and which of them wins is a decision worth
/// testing.** Ordinarily it carries metadata — the artist, or "artist · album"
/// when the album is known. When playback is stopped by a failure it carries the
/// failure instead, because a dead play button with no explanation is the state
/// this type exists to prevent: `PlaybackService.handleFailure` clears
/// `hasLoaded` so play is inert rather than dishonest, and until now
/// `DriveSongsList` was the only screen in the app that said why. A user who
/// taps a Drive track, expands the player and then walks into a tunnel is not
/// looking at the Drive list.
///
/// **It replaces the metadata line rather than being added below it, and that is
/// a layout constraint, not a preference.** `PlayerCard.artworkSide` reserves a
/// fixed 440pt for everything `NowPlayingContent` stacks under the artwork,
/// against a stack that already measures ~380 — see the long note on that
/// constant. A sixth element plus its 24pt `VStack` gap does not fit, and the
/// symptom would be the volume slider sliding off the bottom of a 4.7" screen,
/// which is the exact regression that constant has been corrected for twice.
/// Substituting one line for another costs nothing, and while playback is
/// stopped by a failure the artist and album are the less useful of the two.
///
/// Lifted out of `NowPlayingContent` — where it was a private computed property
/// with no test — so both surfaces read one rule and so the rule can be pinned.
/// With the spec's second metadata stage deferred to its own đợt (no Drive track
/// ever has its ID3 tags read), the placeholder branch below is the permanent
/// state of every Drive track rather than an edge case, which is precisely why
/// it needs a test.
enum PlayerSubtitle: Equatable {
    /// The ordinary line: artist, or "artist · album".
    case metadata(String)
    /// Playback is stopped and this is why. Drawn in red.
    case failure(String)

    /// What the subtitle line should say.
    ///
    /// - Parameter error: `PlaybackService.stalledPlaybackError`, **not**
    ///   `lastPlaybackError`. The narrower one is deliberate: a track skipped
    ///   past because Drive no longer serves it leaves `lastPlaybackError` set
    ///   while the *next* track plays, and captioning a track that is playing
    ///   fine with the previous one's failure would be a new lie in place of the
    ///   old silence. The Drive list's banner reads the wider one.
    static func line(track: (any Playable)?, error: Error?) -> PlayerSubtitle {
        if let error {
            return .failure(error.localizedDescription)
        }
        guard let track else { return .metadata("") }
        return .metadata(metadataText(artist: track.artistName, album: track.albumTitle))
    }

    /// The collapsed player's variant: the artist alone, never "artist · album".
    ///
    /// Its line is a `.caption2` inside a 54pt pill beside three controls, so it
    /// has never had room for the album and this must not quietly give it one.
    /// The failure substitution is identical, which is the part that has to be
    /// shared — a failure surfaced on one of the two screens and not the other
    /// is how the original defect looked, one layer up.
    static func collapsedLine(track: (any Playable)?, error: Error?) -> PlayerSubtitle {
        if let error {
            return .failure(error.localizedDescription)
        }
        return .metadata(track?.artistName ?? "")
    }

    /// Collapses to the artist alone when the album is the placeholder.
    ///
    /// The comparison is against `MetadataPlaceholder.album` rather than a
    /// literal, and `DriveTrack.albumTitle` reports that same constant, so a
    /// Drive track and an untagged local file read identically here. See
    /// `MetadataPlaceholder`.
    static func metadataText(artist: String, album: String) -> String {
        album == MetadataPlaceholder.album ? artist : "\(artist) · \(album)"
    }

    /// The string to draw, whichever case this is.
    var text: String {
        switch self {
        case .metadata(let value), .failure(let value): value
        }
    }

    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
