import Foundation

/// What the app shows in place of an artist or album tag it does not have.
///
/// One pair of constants rather than a literal at each site, because the sites
/// are not independent: `ImportService` writes these onto an untagged local
/// file, `DriveTrack` reports them for a Drive file whose tags have not been
/// read yet, and `NowPlayingContent` *compares against* the album one to decide
/// whether to collapse its subtitle to the artist alone. That comparison is
/// what makes drift expensive — a second spelling of "unknown album" does not
/// look wrong in a list, it silently stops the collapse and the expanded player
/// starts showing "unknown artist · unknown album" for one source and just
/// "unknown artist" for the other.
///
/// Deliberately plain `String`s, not `LocalizedStringKey`. The localization đợt
/// converts these to String Catalog entries; the point of hoisting them now is
/// that it will have one pair to translate rather than four literals to hunt
/// down.
enum MetadataPlaceholder {
    static let artist = "Unknown Artist"
    static let album = "Unknown Album"
}
