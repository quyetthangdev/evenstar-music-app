import Foundation

struct AlbumGroup: Identifiable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]
}

struct ArtistGroup: Identifiable {
    let id: String
    let name: String
    let tracks: [Track]
}

/// Album and artist screens are groupings over the same `Track` rows the songs
/// list already queries — there is no album or artist entity in the schema.
/// Kept as pure functions over `[Track]` so they can be tested without a view
/// or a `ModelContainer`.
enum LibraryGrouping {

    /// Albums key on title *and* artist: "Greatest Hits" by two artists is two
    /// albums, not one with both artists' tracks mixed in.
    ///
    /// Consequence worth knowing: a compilation with per-track artists splits
    /// into one album per artist. `Track` has no `albumArtist` field, so this
    /// cannot be fixed here without a schema change. See the design spec.
    static func albums(from tracks: [Track]) -> [AlbumGroup] {
        let grouped = Dictionary(grouping: tracks) {
            AlbumKey(title: $0.albumTitle, artist: $0.artistName)
        }
        return grouped
            .map { key, value in
                AlbumGroup(id: key.id,
                           title: key.title,
                           artist: key.artist,
                           tracks: sortedAlbumTracks(value))
            }
            .sorted { ordered($0.title, $1.title) }
    }

    static func artists(from tracks: [Track]) -> [ArtistGroup] {
        Dictionary(grouping: tracks, by: \.artistName)
            .map { name, value in
                ArtistGroup(id: name,
                            name: name,
                            tracks: value.sorted { ordered($0.title, $1.title) })
            }
            .sorted { ordered($0.name, $1.name) }
    }

    /// Running order, not alphabetical: an album listed A–Z is wrong in a way
    /// users see immediately.
    ///
    /// A missing number sorts *after* every numbered track rather than being
    /// read as 0, so one untagged file cannot jump ahead of a correctly
    /// tagged album.
    static func sortedAlbumTracks(_ tracks: [Track]) -> [Track] {
        tracks.sorted { lhs, rhs in
            let ld = lhs.discNumber ?? Int.max
            let rd = rhs.discNumber ?? Int.max
            if ld != rd { return ld < rd }
            let lt = lhs.trackNumber ?? Int.max
            let rt = rhs.trackNumber ?? Int.max
            if lt != rt { return lt < rt }
            return ordered(lhs.title, rhs.title)
        }
    }

    /// Matches title, artist or album.
    ///
    /// `localizedStandardContains` is required rather than convenient: it is
    /// both case- and diacritic-insensitive, so "bien" finds "Biển" and "Biển"
    /// finds "Bien". `lowercased().contains` fails both directions on
    /// Vietnamese and must not be substituted here.
    static func search(_ query: String, in tracks: [Track]) -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return tracks.filter {
            $0.title.localizedStandardContains(trimmed)
                || $0.artistName.localizedStandardContains(trimmed)
                || $0.albumTitle.localizedStandardContains(trimmed)
        }
    }

    private static func ordered(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    /// The NUL separator is what stops artist "X" + album "Y-Z" colliding with
    /// artist "X-Y" + album "Z"; a printable separator cannot guarantee that,
    /// because it can occur inside a real title.
    private struct AlbumKey: Hashable {
        let title: String
        let artist: String
        var id: String { "\(title)\u{0}\(artist)" }
    }
}
