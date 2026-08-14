import Foundation

/// One album, as everything outside `LibraryGrouping` is allowed to know it:
/// four strings and **no `Track` rows at all**.
///
/// The absence is the whole point of the type. This used to hold `[Track]`, and
/// `AlbumsView` keeps its grouping in `@State` refreshed by `onChange` — whose
/// action runs *after* the update pass that triggered it. Between
/// `LibraryService.delete`'s `context.delete` + `save()` and that action, the
/// cached array still held the deleted row, and `AlbumCell` read
/// `tracks.first?.artworkRelativePath` straight off it: a message to a dead
/// SwiftData row, which raises `NSObjectInaccessibleException`, an Objective-C
/// exception Swift cannot catch. Deleting the track that was playing reached
/// that window reliably, because `PlaybackService.handleTrackDeleted` clears
/// `currentTrack`, which `RootView`'s body reads, so a full rebuild of all five
/// tabs was already scheduled before the row died.
///
/// `LibraryStore.remove(_:)` closes that window for `store.tracks`, and cannot
/// close it here: this cache is the screen's own, and is refreshed later. So
/// the fix is to leave the screen nothing that can die. A `String` copied out
/// of a row before the delete stays readable forever; the row it came from
/// does not.
///
/// The rows themselves are still reachable, but only through
/// `tracks(inAlbum:from:)`, which resolves them against a `[Track]` handed in
/// by the caller — in the app that is always `LibraryStore.tracks`, which is
/// dead-row-free by construction. See `LibraryStore.remove(_:)`.
struct AlbumGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    /// The cover the grid draws: the artwork of this album's first track in
    /// running order, copied at grouping time.
    ///
    /// `nil` when *that* track has no cover, even if a later one does —
    /// unchanged from when the cell reached through `tracks.first` for it.
    ///
    /// Copied rather than read live, which costs one thing worth naming:
    /// changing a cover now has to announce itself, because the value here
    /// cannot notice. `LibraryService.setArtwork` bumps `metadataRevision` for
    /// exactly that reason, and both screens already regroup on it.
    let artworkRelativePath: String?
}

/// One artist. Same shape and the same reason as `AlbumGroup` — see it.
struct ArtistGroup: Identifiable, Hashable {
    let id: String
    let name: String
    /// The artwork of this artist's first track by title, copied at grouping
    /// time. See `AlbumGroup.artworkRelativePath`.
    let artworkRelativePath: String?
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
        albumsByKey(tracks).map { key, ordered in
            AlbumGroup(id: key.id,
                       title: key.title,
                       artist: key.artist,
                       artworkRelativePath: ordered.first?.artworkRelativePath)
        }
    }

    static func artists(from tracks: [Track]) -> [ArtistGroup] {
        Dictionary(grouping: tracks, by: \.artistName)
            .map { name, value in
                let byTitle = value.sorted { ordered($0.title, $1.title) }
                return ArtistGroup(id: name,
                                   name: name,
                                   artworkRelativePath: byTitle.first?.artworkRelativePath)
            }
            .sorted { ordered($0.name, $1.name) }
    }

    /// The rows behind one album, in running order — what `AlbumDetailView`
    /// lists and plays.
    ///
    /// Takes the library to resolve against rather than carrying the rows
    /// inside `AlbumGroup`, so a screen holding a group holds nothing that a
    /// delete can invalidate. Callers pass `LibraryStore.tracks`, which never
    /// contains a deleted row during an update pass.
    ///
    /// Matching goes through `AlbumKey` rather than comparing the two strings
    /// by hand: this has to select exactly the tracks `albums(from:)` put in
    /// the group, and reusing the key type is what stops the two drifting.
    static func tracks(inAlbum album: AlbumGroup, from tracks: [Track]) -> [Track] {
        let key = AlbumKey(title: album.title, artist: album.artist)
        return sortedAlbumTracks(tracks.filter { key == AlbumKey(title: $0.albumTitle, artist: $0.artistName) })
    }

    /// The rows behind one artist, album by album: album order from the same
    /// rule `albums(from:)` uses, running order within each album from
    /// `sortedAlbumTracks`. Never alphabetical across the whole artist.
    ///
    /// See `tracks(inAlbum:from:)` for why the library is a parameter.
    static func tracks(byArtist artist: ArtistGroup, from tracks: [Track]) -> [Track] {
        albumsByKey(tracks.filter { $0.artistName == artist.name }).flatMap(\.tracks)
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

    /// The one place tracks are split into albums and put in order. Both
    /// `albums(from:)` and `tracks(byArtist:from:)` are built on it, so the
    /// album order the grid shows and the album order the artist screen plays
    /// in cannot disagree.
    private static func albumsByKey(_ tracks: [Track]) -> [(key: AlbumKey, tracks: [Track])] {
        Dictionary(grouping: tracks) {
            AlbumKey(title: $0.albumTitle, artist: $0.artistName)
        }
        .map { (key: $0.key, tracks: sortedAlbumTracks($0.value)) }
        .sorted { lhs, rhs in
            // Tie-break on artist, matching `AlbumKey`: two albums can
            // share a title (a compilation splits into one album per
            // track artist — see the note above), and `sorted` is not
            // guaranteed stable, so title alone leaves their order to
            // vary between launches.
            if ordered(lhs.key.title, rhs.key.title) { return true }
            if ordered(rhs.key.title, lhs.key.title) { return false }
            return ordered(lhs.key.artist, rhs.key.artist)
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

// MARK: - Navigation identity
//
// `NavigationLink(value:)` and `navigationDestination(for:)` require `Hashable`,
// and both groups get it by synthesis: every stored property is a `String` or
// `String?`.
//
// It used to be written by hand, keyed on `id` alone, because both groups held
// `[Track]` and `Track` is a SwiftData `@Model` class conforming to neither
// `Hashable` nor `Equatable` — there was nothing to synthesise from. Dropping
// the rows removed that obstacle and two caveats with it: a hand-written `==`
// that quietly ignored fields, and the note that two groups built from
// different library snapshots compared equal despite holding different tracks.
//
// The synthesised `==` is what keeps a changed cover visible: `AlbumCell` takes
// an `AlbumGroup` by value, and SwiftUI skips redrawing a view whose input
// compares equal. An `id`-only `==` would have declared an album with a brand
// new `artworkRelativePath` unchanged, and the new cover would not have
// appeared until something else forced the cell to rebuild.
