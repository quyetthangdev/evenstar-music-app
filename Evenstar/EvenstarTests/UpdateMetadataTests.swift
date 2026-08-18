import XCTest
@testable import Evenstar

/// `LibraryService.updateMetadata` — editing a track's tags.
///
/// The interesting part is not the assignment. It is `metadataRevision`: an
/// in-place property edit is invisible to a `@Query`, because the array it
/// publishes holds the same objects in the same order afterwards. Without a
/// separate signal, the Album and Nghệ sĩ tabs cache a grouping that never
/// rebuilds and go on showing the album a track used to be in — with a clean
/// build, a green suite, and nothing on screen saying why.
@MainActor
final class UpdateMetadataTests: XCTestCase {

    private func makeStack() throws -> (LibraryService, Track) {
        let library = try InMemoryLibrary.make()
        let track = Track(
            title: "Tên cũ",
            artistName: "Nghệ sĩ cũ",
            albumTitle: "Album cũ",
            durationSeconds: 100,
            relativePath: "Music/\(UUID().uuidString).m4a",
            format: "m4a"
        )
        try library.insert(track)
        return (library, track)
    }

    // MARK: - The values

    func testAllThreeFieldsAreWritten() throws {
        let (library, track) = try makeStack()

        try library.updateMetadata(
            title: "Tên mới", artistName: "Nghệ sĩ mới", albumTitle: "Album mới", for: track
        )

        XCTAssertEqual(track.title, "Tên mới")
        XCTAssertEqual(track.artistName, "Nghệ sĩ mới")
        XCTAssertEqual(track.albumTitle, "Album mới")
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        let (library, track) = try makeStack()

        try library.updateMetadata(
            title: "  Tên mới  ", artistName: "\tNghệ sĩ\n", albumTitle: "  Album ", for: track
        )

        XCTAssertEqual(track.title, "Tên mới")
        XCTAssertEqual(track.artistName, "Nghệ sĩ")
        XCTAssertEqual(track.albumTitle, "Album")
    }

    /// Blank must become the placeholder, not an empty string. Two ways to say
    /// "unknown" would split the Nghệ sĩ tab into an "Unknown Artist" bucket and
    /// an unnamed one sitting beside it.
    func testABlankArtistBecomesThePlaceholder() throws {
        let (library, track) = try makeStack()

        try library.updateMetadata(title: "Tên", artistName: "", albumTitle: "", for: track)

        XCTAssertEqual(track.artistName, MetadataPlaceholder.artist)
        XCTAssertEqual(track.albumTitle, MetadataPlaceholder.album)
    }

    func testWhitespaceOnlyCountsAsBlank() throws {
        let (library, track) = try makeStack()

        try library.updateMetadata(title: "Tên", artistName: "   ", albumTitle: "\n", for: track)

        XCTAssertEqual(track.artistName, MetadataPlaceholder.artist)
        XCTAssertEqual(track.albumTitle, MetadataPlaceholder.album)
    }

    /// A blank title has no sensible placeholder — the row would be an empty
    /// line in every list, and it is the thing the user picks the track by.
    func testABlankTitleThrowsAndChangesNothing() throws {
        let (library, track) = try makeStack()

        XCTAssertThrowsError(
            try library.updateMetadata(
                title: "  ", artistName: "Nghệ sĩ mới", albumTitle: "Album mới", for: track
            )
        )
        XCTAssertEqual(track.title, "Tên cũ")
        XCTAssertEqual(track.artistName, "Nghệ sĩ cũ", "a rejected edit must not half-apply")
        XCTAssertEqual(track.albumTitle, "Album cũ")
    }

    // MARK: - The revision

    func testTheRevisionStartsAtZero() throws {
        let (library, _) = try makeStack()
        XCTAssertEqual(library.metadataRevision, 0)
    }

    /// The whole reason this property exists.
    func testASuccessfulEditBumpsTheRevision() throws {
        let (library, track) = try makeStack()
        let before = library.metadataRevision

        try library.updateMetadata(
            title: "Tên mới", artistName: "A", albumTitle: "B", for: track
        )

        XCTAssertEqual(library.metadataRevision, before + 1)
    }

    func testEachEditBumpsItAgain() throws {
        let (library, track) = try makeStack()

        for index in 1...3 {
            try library.updateMetadata(
                title: "Tên \(index)", artistName: "A", albumTitle: "B", for: track
            )
            XCTAssertEqual(library.metadataRevision, index)
        }
    }

    /// A rejected edit must not announce a change that did not happen — the
    /// screens would regroup for nothing.
    func testARejectedEditDoesNotBumpTheRevision() throws {
        let (library, track) = try makeStack()
        let before = library.metadataRevision

        XCTAssertThrowsError(
            try library.updateMetadata(title: "", artistName: "A", albumTitle: "B", for: track)
        )

        XCTAssertEqual(library.metadataRevision, before)
    }

    /// Inserting and deleting are reported by `@Query` on their own, so they
    /// deliberately do not touch this counter.
    func testInsertingAndDeletingDoNotBumpTheRevision() throws {
        let (library, track) = try makeStack()
        let before = library.metadataRevision

        let other = Track(
            title: "Bài khác", artistName: "X", albumTitle: "Y",
            durationSeconds: 50, relativePath: "Music/\(UUID().uuidString).m4a", format: "m4a"
        )
        try library.insert(other)
        try library.delete(other)
        _ = track

        XCTAssertEqual(library.metadataRevision, before)
    }

    // MARK: - Regrouping actually sees it

    /// The end-to-end property: after an edit, regrouping from the same fetched
    /// array yields the new album. This is what the two screens do when the
    /// revision fires.
    func testRegroupingAfterAnEditYieldsTheNewAlbum() throws {
        let (library, track) = try makeStack()

        try library.updateMetadata(
            title: "Tên", artistName: "Nghệ sĩ", albumTitle: "Album mới", for: track
        )
        let albums = LibraryGrouping.albums(from: try library.fetchAllTracks())

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.title, "Album mới")
    }
}
