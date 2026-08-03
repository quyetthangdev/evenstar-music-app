import XCTest
@testable import Evenstar

final class LibraryGroupingTests: XCTestCase {

    private func track(_ title: String,
                       artist: String = "A",
                       album: String = "Al",
                       disc: Int? = nil,
                       number: Int? = nil) -> Track {
        Track(title: title,
              artistName: artist,
              albumTitle: album,
              trackNumber: number,
              discNumber: disc,
              durationSeconds: 1,
              relativePath: "\(title).mp3",
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

    func testAlbumIdCannotCollideAcrossSeparatorShapedNames() {
        // "X" + "Y-Z" vs "X-Y" + "Z" must not produce the same id.
        let tracks = [
            track("a", artist: "X", album: "Y-Z"),
            track("b", artist: "X-Y", album: "Z")
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

    func testArtistsGroupByNameAndGatherEveryTrack() {
        let tracks = [
            track("a", artist: "Alpha"),
            track("b", artist: "Beta"),
            track("c", artist: "Alpha")
        ]
        let artists = LibraryGrouping.artists(from: tracks)
        XCTAssertEqual(artists.count, 2)
        XCTAssertEqual(artists.first(where: { $0.name == "Alpha" })?.tracks.count, 2)
    }

    func testGroupingSortsByLocalizedStandardOrder() {
        let tracks = [track("x", album: "b"), track("y", album: "A")]
        XCTAssertEqual(LibraryGrouping.albums(from: tracks).map(\.title), ["A", "b"])
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
