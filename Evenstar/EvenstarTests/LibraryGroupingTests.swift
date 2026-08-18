import XCTest
@testable import Evenstar

final class LibraryGroupingTests: XCTestCase {

    private func track(_ title: String,
                       artist: String = "A",
                       album: String = "Al",
                       disc: Int? = nil,
                       number: Int? = nil,
                       artwork: String? = nil) -> Track {
        Track(title: title,
              artistName: artist,
              albumTitle: album,
              trackNumber: number,
              discNumber: disc,
              durationSeconds: 1,
              relativePath: "\(title).mp3",
              artworkRelativePath: artwork,
              format: "mp3")
    }

    func testAlbumsSeparateSameTitleByDifferentArtists() {
        let tracks = [
            track("x", artist: "Alpha", album: "Greatest Hits"),
            track("y", artist: "Beta", album: "Greatest Hits")
        ]
        let albums = LibraryGrouping.albums(from: tracks)
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(Set(albums.map(\.artist)), ["Alpha", "Beta"])
    }

    func testSameTitledAlbumsOrderDeterministicallyByArtist() {
        // Title alone is not a unique key (`AlbumKey` is title *and* artist),
        // and the array comes from `Dictionary.map`, whose order is
        // arbitrary, then `sorted(by:)`, which is not guaranteed stable — so
        // without an artist tie-break two same-titled albums could swap
        // order between launches.
        let tracks = [
            track("y", artist: "Zeta", album: "Greatest Hits"),
            track("x", artist: "Alpha", album: "Greatest Hits")
        ]
        let albums = LibraryGrouping.albums(from: tracks)
        XCTAssertEqual(albums.map(\.artist), ["Alpha", "Zeta"])
    }

    func testAlbumIdCannotCollideAcrossSeparatorShapedNames() {
        // AlbumKey.id is "\(title)\u{0}\(artist)" — title first. Data must match
        // that field order: album "X" + artist "Y-Z" vs album "X-Y" + artist "Z"
        // both collapse to "X-Y-Z" under a printable "-" separator, but stay
        // distinct ("X\0Y-Z" vs "X-Y\0Z") under the real NUL separator.
        let tracks = [
            track("a", artist: "Y-Z", album: "X"),
            track("b", artist: "Z", album: "X-Y")
        ]
        let ids = Set(LibraryGrouping.albums(from: tracks).map(\.id))
        XCTAssertEqual(ids.count, 2)
    }

    func testAlbumTracksOrderByDiscThenNumberThenTitle() {
        let tracks = [
            track("z", disc: 1, number: 2),
            track("a", disc: 2, number: 1),
            track("m", disc: 1, number: 1)
        ]
        let ordered = LibraryGrouping.sortedAlbumTracks(tracks).map(\.title)
        XCTAssertEqual(ordered, ["m", "z", "a"])
    }

    func testUnnumberedTracksSortAfterNumberedOnes() {
        let tracks = [
            track("aaa", number: nil),
            track("zzz", number: 1)
        ]
        let ordered = LibraryGrouping.sortedAlbumTracks(tracks).map(\.title)
        XCTAssertEqual(ordered, ["zzz", "aaa"])
    }

    func testUnnumberedDiscsSortAfterNumberedOnes() {
        // Same nil-sorts-last rule, but for discNumber specifically — a
        // low trackNumber must not let a nil-disc track jump ahead of a
        // properly disc-numbered one.
        let tracks = [
            track("aaa", disc: nil, number: 1),
            track("zzz", disc: 1, number: 9)
        ]
        let ordered = LibraryGrouping.sortedAlbumTracks(tracks).map(\.title)
        XCTAssertEqual(ordered, ["zzz", "aaa"])
    }

    func testArtistsGroupByNameAndGatherEveryTrack() throws {
        let tracks = [
            track("a", artist: "Alpha"),
            track("b", artist: "Beta"),
            track("c", artist: "Alpha")
        ]
        let artists = LibraryGrouping.artists(from: tracks)
        XCTAssertEqual(artists.count, 2)
        // The rows come back from the lookup, not from the group — an
        // `ArtistGroup` carries none. Asked through the lookup because that is
        // the path the artist screen actually takes to get them.
        let alpha = try XCTUnwrap(artists.first(where: { $0.name == "Alpha" }))
        XCTAssertEqual(LibraryGrouping.tracks(byArtist: alpha, from: tracks).map(\.title), ["a", "c"])
    }

    func testGroupingSortsByLocalizedStandardOrder() {
        // Plain string comparison orders "Track 10" before "Track 9" (because
        // "1" < "9"); localizedStandardCompare compares the embedded numbers
        // numerically and puts "Track 9" first. The two disagree here, so this
        // is the pair that can actually catch a regression to plain `<`.
        let tracks = [track("x", album: "Track 10"), track("y", album: "Track 9")]
        XCTAssertEqual(LibraryGrouping.albums(from: tracks).map(\.title), ["Track 9", "Track 10"])
    }

    // MARK: - Resolving a group back to rows
    //
    // `AlbumGroup`/`ArtistGroup` carry no `Track`, so these two lookups are the
    // only route from a group to its rows. What they have to preserve is what
    // the groups used to hand over directly: exactly the right tracks, in
    // exactly the order the detail screens list and play them in.

    func testAlbumLookupTakesOnlyThatAlbumInRunningOrder() throws {
        let tracks = [
            track("late", album: "Al", number: 2),
            track("elsewhere", album: "Other", number: 1),
            track("early", album: "Al", number: 1)
        ]
        let album = try XCTUnwrap(LibraryGrouping.albums(from: tracks).first { $0.title == "Al" })
        XCTAssertEqual(LibraryGrouping.tracks(inAlbum: album, from: tracks).map(\.title),
                       ["early", "late"])
    }

    func testAlbumLookupSeparatesSameTitledAlbumsByArtist() throws {
        // The counterpart to `testAlbumsSeparateSameTitleByDifferentArtists`:
        // splitting the groups is worth nothing if resolving one of them back
        // to rows collects both artists' tracks again.
        let tracks = [
            track("x", artist: "Alpha", album: "Greatest Hits"),
            track("y", artist: "Beta", album: "Greatest Hits")
        ]
        let alpha = try XCTUnwrap(LibraryGrouping.albums(from: tracks).first { $0.artist == "Alpha" })
        XCTAssertEqual(LibraryGrouping.tracks(inAlbum: alpha, from: tracks).map(\.title), ["x"])
    }

    func testArtistLookupOrdersAlbumByAlbumNotAlphabetically() throws {
        // "Zed" sorts after "Anthology", and within each album running order
        // beats title order — so a flat alphabetical sort would give
        // ["a", "b", "y", "z"] and every one of the four is in the wrong place.
        let tracks = [
            track("z", artist: "Solo", album: "Anthology", number: 1),
            track("y", artist: "Solo", album: "Anthology", number: 2),
            track("b", artist: "Solo", album: "Zed", number: 1),
            track("a", artist: "Solo", album: "Zed", number: 2)
        ]
        let artist = try XCTUnwrap(LibraryGrouping.artists(from: tracks).first)
        XCTAssertEqual(LibraryGrouping.tracks(byArtist: artist, from: tracks).map(\.title),
                       ["z", "y", "b", "a"])
    }

    func testLookupsIgnoreRowsThatAreNoLongerInTheLibrary() throws {
        // The property the whole change rests on: a group is resolved against
        // the array it is handed, not against the one it was built from. That
        // is what lets `LibraryStore` drop a row before it is deleted and have
        // every screen agree, one pass before the regroup catches up.
        let kept = track("kept")
        let removed = track("removed")
        let album = try XCTUnwrap(LibraryGrouping.albums(from: [kept, removed]).first)
        let artist = try XCTUnwrap(LibraryGrouping.artists(from: [kept, removed]).first)

        XCTAssertEqual(LibraryGrouping.tracks(inAlbum: album, from: [kept]).map(\.title), ["kept"])
        XCTAssertEqual(LibraryGrouping.tracks(byArtist: artist, from: [kept]).map(\.title), ["kept"])
    }

    // MARK: - The cover, copied out

    func testAlbumCoverComesFromTheFirstTrackInRunningOrder() throws {
        // Not the first track in the input array, and not the first one that
        // happens to have a cover: the album screen's thumbnail used to read
        // `tracks.first?.artworkRelativePath` off the running-order list, and
        // moving that string into the group must not quietly change which
        // track it comes from.
        let tracks = [
            track("second", number: 2, artwork: "Artwork/second.jpg"),
            track("first", number: 1, artwork: "Artwork/first.jpg")
        ]
        let album = try XCTUnwrap(LibraryGrouping.albums(from: tracks).first)
        XCTAssertEqual(album.artworkRelativePath, "Artwork/first.jpg")
    }

    func testAlbumCoverIsNilWhenTheFirstTrackHasNone() throws {
        // Deliberate, and preserved rather than improved: `tracks.first?` was
        // always nil-if-the-first-one-is-nil, even with a later track that has
        // a cover. Changing it here would be a silent behaviour change riding
        // along with a crash fix.
        let tracks = [
            track("first", number: 1, artwork: nil),
            track("second", number: 2, artwork: "Artwork/second.jpg")
        ]
        let album = try XCTUnwrap(LibraryGrouping.albums(from: tracks).first)
        XCTAssertNil(album.artworkRelativePath)
    }

    func testArtistCoverComesFromTheFirstTrackByTitle() throws {
        // By title, not by running order — the artist grid never grouped its
        // own tracks into albums to pick a cover, and still must not.
        let tracks = [
            track("zzz", artist: "Solo", album: "Al", number: 1, artwork: "Artwork/zzz.jpg"),
            track("aaa", artist: "Solo", album: "Other", number: 9, artwork: "Artwork/aaa.jpg")
        ]
        let artist = try XCTUnwrap(LibraryGrouping.artists(from: tracks).first)
        XCTAssertEqual(artist.artworkRelativePath, "Artwork/aaa.jpg")
    }

    func testSearchMatchesTitleArtistAndAlbum() {
        let tracks = [
            track("Sunrise", artist: "Nobody", album: "None"),
            track("Nothing", artist: "Sunset", album: "None"),
            track("Nothing", artist: "Nobody", album: "Sunbeam")
        ]
        XCTAssertEqual(LibraryGrouping.search("sun", in: tracks).count, 3)
    }

    func testSearchIgnoresVietnameseDiacriticsInBothDirections() {
        let stored = [track("Biển nhớ"), track("Bien xanh")]
        XCTAssertEqual(LibraryGrouping.search("bien", in: stored).count, 2)
        XCTAssertEqual(LibraryGrouping.search("Biển", in: stored).count, 2)
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(LibraryGrouping.search("SUNRISE", in: [track("sunrise")]).count, 1)
    }

    func testEmptyOrWhitespaceQueryReturnsNothing() {
        let tracks = [track("a"), track("b")]
        XCTAssertTrue(LibraryGrouping.search("", in: tracks).isEmpty)
        XCTAssertTrue(LibraryGrouping.search("   ", in: tracks).isEmpty)
    }

    func testEmptyLibraryGroupsToEmpty() {
        XCTAssertTrue(LibraryGrouping.albums(from: []).isEmpty)
        XCTAssertTrue(LibraryGrouping.artists(from: []).isEmpty)
    }
}
