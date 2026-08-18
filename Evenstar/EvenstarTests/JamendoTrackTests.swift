import XCTest
@testable import Evenstar

@MainActor
final class JamendoTrackTests: XCTestCase {

    private func catalogueTrack(album: String = "Dawn") -> JamendoCatalogueTrack {
        JamendoCatalogueTrack(
            id: "1886179", title: "Sunrise", artistName: "Alpha", albumTitle: album,
            durationSeconds: 184,
            audioURL: URL(string: "https://prod.jamendo.com/1886179.mp3")!,
            coverURL: URL(string: "https://usercontent.jamendo.com/1.jpg"),
            licenceURL: URL(string: "http://creativecommons.org/licenses/by/3.0/"),
            shareURL: URL(string: "https://www.jamendo.com/track/1886179")
        )
    }

    func testItCarriesTheCatalogueFieldsAcross() {
        let track = JamendoTrack(from: catalogueTrack(), artworkRelativePath: "Artwork/x.jpg")

        XCTAssertEqual(track.jamendoID, "1886179")
        XCTAssertEqual(track.title, "Sunrise")
        XCTAssertEqual(track.artistName, "Alpha")
        XCTAssertEqual(track.durationSeconds, 184)
        XCTAssertEqual(track.artworkRelativePath, "Artwork/x.jpg")
    }

    /// The whole reason this conforms to `Playable`: `PlaybackService` must be
    /// able to hold it in the same queue as a local file without knowing which
    /// is which.
    func testPlaybackURLIsTheStreamURL() {
        let track = JamendoTrack(from: catalogueTrack(), artworkRelativePath: nil)

        XCTAssertEqual(track.playbackURL().absoluteString, "https://prod.jamendo.com/1886179.mp3")
    }

    /// Saved without a cover — the download failed, or the catalogue had none.
    /// The track still plays; only the artwork is absent.
    func testATrackWithNoCoverHasNoArtworkPath() {
        let track = JamendoTrack(from: catalogueTrack(), artworkRelativePath: nil)

        XCTAssertNil(track.artworkRelativePath)
    }

    /// The same placeholder an untagged local file gets, so
    /// `PlayerSubtitle`'s collapse rule applies to all three sources
    /// identically. A second spelling of "unknown album" would silently stop
    /// that collapse on one source only.
    func testAMissingAlbumUsesTheSharedPlaceholder() {
        let track = JamendoTrack(from: catalogueTrack(album: MetadataPlaceholder.album),
                                 artworkRelativePath: nil)

        XCTAssertEqual(track.albumTitle, MetadataPlaceholder.album)
    }
}
