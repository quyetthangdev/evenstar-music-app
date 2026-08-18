import XCTest
@testable import Evenstar

/// The one line under the title, in both players.
///
/// It had no test at all while it was a private computed property inside
/// `NowPlayingContent`, and the placeholder branch it was written for is no
/// longer an edge case: the spec's second metadata stage — reading a played
/// track's real ID3 tags over the network — is deferred to its own đợt, so
/// *every* Drive track reports `MetadataPlaceholder.artist` and
/// `MetadataPlaceholder.album` permanently. This is the state the line is in
/// most of the time on the Drive side, which makes it the state most worth
/// pinning.
@MainActor
final class PlayerSubtitleTests: XCTestCase {

    private func driveTrack(artist: String? = nil, album: String? = nil) -> DriveTrack {
        DriveTrack(
            fileID: "file-\(UUID().uuidString)",
            folderID: "F1",
            fileName: "Bien nho.mp3",
            artistName: artist,
            albumTitle: album
        )
    }

    // MARK: - The metadata line

    func testAFullyTaggedTrackShowsArtistAndAlbum() {
        let track = InMemoryLibrary.makeTrack(artistName: "Alpha", albumTitle: "Night Songs")

        XCTAssertEqual(
            PlayerSubtitle.line(track: track, error: nil),
            .metadata("Alpha · Night Songs")
        )
    }

    /// The collapse exists so an untagged file does not read
    /// "Unknown Artist · Unknown Album", which is twice as much nothing.
    func testAPlaceholderAlbumCollapsesToTheArtistAlone() {
        let track = InMemoryLibrary.makeTrack(
            artistName: "Alpha", albumTitle: MetadataPlaceholder.album
        )

        XCTAssertEqual(PlayerSubtitle.line(track: track, error: nil), .metadata("Alpha"))
    }

    /// The permanent state of every Drive track while the second metadata stage
    /// is deferred: `DriveTrack` reports the *same* placeholder constants an
    /// untagged local file does, precisely so this collapse applies to both. A
    /// second spelling of "unknown album" would not look wrong in a list — it
    /// would silently stop the collapse here, and only on one source.
    func testADriveTrackWithNoTagsCollapsesTheSameWayALocalOneDoes() {
        XCTAssertEqual(
            PlayerSubtitle.line(track: driveTrack(), error: nil),
            .metadata(MetadataPlaceholder.artist)
        )
    }

    func testADriveTrackWithAKnownAlbumShowsBoth() {
        let track = driveTrack(artist: "Alpha", album: "Night Songs")

        XCTAssertEqual(
            PlayerSubtitle.line(track: track, error: nil),
            .metadata("Alpha · Night Songs")
        )
    }

    func testNothingPlayingIsAnEmptyLineRatherThanAPlaceholder() {
        XCTAssertEqual(PlayerSubtitle.line(track: nil, error: nil), .metadata(""))
    }

    // MARK: - The failure line

    /// `handleFailure` makes play inert rather than dishonest, which without a
    /// message is a dead button. Before this, `DriveSongsList` was the only
    /// screen in the app that consumed `lastPlaybackError` — and a user who taps
    /// a Drive track, expands the player and walks into a tunnel is not looking
    /// at the Drive list.
    func testAStalledFailureReplacesTheMetadataLine() {
        let track = InMemoryLibrary.makeTrack(artistName: "Alpha", albumTitle: "Night Songs")

        let line = PlayerSubtitle.line(track: track, error: DriveError.offline)

        XCTAssertEqual(line, .failure(String(localized: "Không có kết nối mạng.")))
        XCTAssertTrue(line.isFailure)
    }

    /// Vietnamese, not a raw `URLError`'s English system text. The classifier is
    /// what guarantees it, and this is the assertion that would notice a raw
    /// error being handed to `lastPlaybackError` again.
    func testTheFailureLineIsTheVietnameseMessage() {
        let line = PlayerSubtitle.line(
            track: InMemoryLibrary.makeTrack(), error: DriveError.fileUnavailable
        )

        XCTAssertEqual(
            line.text,
            String(localized: "Không phát được bài này. Tệp có thể đã bị xoá khỏi Drive hoặc thư mục không còn được chia sẻ.")
        )
    }

    /// A failure with nothing loaded still says why, rather than falling back to
    /// an empty line — this is the state after a queue has stopped outright.
    func testAFailureOutranksHavingNoTrack() {
        XCTAssertEqual(
            PlayerSubtitle.line(track: nil, error: DriveError.missingAPIKey),
            .failure(String(localized: "Chưa cấu hình API key cho Google Drive."))
        )
    }

    // MARK: - The collapsed player's variant

    /// The pill is a `.caption2` line inside 54pt beside three controls. It has
    /// never had room for the album and sharing the rule must not quietly give
    /// it one.
    func testTheCollapsedLineShowsTheArtistAloneEvenWhenTheAlbumIsKnown() {
        let track = InMemoryLibrary.makeTrack(artistName: "Alpha", albumTitle: "Night Songs")

        XCTAssertEqual(
            PlayerSubtitle.collapsedLine(track: track, error: nil),
            .metadata("Alpha")
        )
    }

    /// The half that *is* shared. A failure surfaced on one of the two screens
    /// and not the other is the original defect, one layer up.
    func testTheCollapsedLineTakesTheSameFailureSubstitution() {
        let track = InMemoryLibrary.makeTrack(artistName: "Alpha", albumTitle: "Night Songs")

        XCTAssertEqual(
            PlayerSubtitle.collapsedLine(track: track, error: DriveError.offline),
            .failure(String(localized: "Không có kết nối mạng."))
        )
    }
}
