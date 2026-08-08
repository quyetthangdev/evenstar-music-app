import XCTest
@testable import Evenstar

@MainActor
final class JamendoLibraryServiceTests: XCTestCase {

    /// Real cover files land under Documents/Artwork during these tests —
    /// `downloadCover` writes through `FileLocation`, not a stub filesystem.
    /// Tracked here and removed in `tearDown` so a run does not leave rubbish
    /// behind for the next one.
    private var written: [String] = []

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        for path in written {
            try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: path))
        }
        written = []
        super.tearDown()
    }

    private func makeService() throws -> (JamendoLibraryService, LibraryService) {
        let library = try InMemoryLibrary.make()
        return (JamendoLibraryService(library: library, session: StubURLProtocol.session()), library)
    }

    private func catalogueTrack(id: String = "1", cover: String? = "https://x/1.jpg") -> JamendoCatalogueTrack {
        JamendoCatalogueTrack(
            id: id, title: "Sunrise", artistName: "Alpha", albumTitle: "Dawn",
            durationSeconds: 184,
            audioURL: URL(string: "https://prod.jamendo.com/\(id).mp3")!,
            coverURL: cover.flatMap(URL.init(string:)),
            licenceURL: URL(string: "http://creativecommons.org/licenses/by/3.0/"),
            shareURL: URL(string: "https://www.jamendo.com/track/\(id)")
        )
    }

    /// A 1x1 JPEG, so the cover download has something real to write.
    private var jpeg: Data {
        Data(base64Encoded: """
        /9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a\
        HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAA\
        AAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==
        """.replacingOccurrences(of: "\\\n", with: ""))!
    }

    func testSavingInsertsARow() async throws {
        let (service, _) = try makeService()
        StubURLProtocol.responses = [.init(status: 200, body: jpeg)]

        let saved = try await service.save(catalogueTrack())
        if let path = saved.artworkRelativePath { written.append(path) }

        XCTAssertEqual(saved.jamendoID, "1")
        XCTAssertTrue(try service.isSaved(jamendoID: "1"))
    }

    /// **Dedupe is by Jamendo's id.** Saving the same track twice must leave one
    /// row, not two rows the user then has to delete individually.
    func testSavingTheSameTrackTwiceLeavesOneRow() async throws {
        let (service, _) = try makeService()
        StubURLProtocol.responses = [
            .init(status: 200, body: jpeg),
            .init(status: 200, body: jpeg)
        ]

        let first = try await service.save(catalogueTrack(id: "7"))
        if let path = first.artworkRelativePath { written.append(path) }
        let second = try await service.save(catalogueTrack(id: "7"))
        if let path = second.artworkRelativePath, path != first.artworkRelativePath { written.append(path) }

        XCTAssertEqual(try service.savedCount(), 1)
    }

    /// The cover is downloaded so a saved track is a first-class citizen —
    /// full-bleed artwork in the player, a thumbnail in every list — without
    /// widening `Playable` with a remote-artwork case.
    func testSavingDownloadsTheCover() async throws {
        let (service, _) = try makeService()
        StubURLProtocol.responses = [.init(status: 200, body: jpeg)]

        let saved = try await service.save(catalogueTrack())
        if let path = saved.artworkRelativePath { written.append(path) }

        let path = try XCTUnwrap(saved.artworkRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: FileLocation.absoluteURL(forRelative: path).path))
    }

    /// **A failed cover download must not fail the save.** The user asked for
    /// the music; losing the picture is not a reason to refuse them the track.
    func testAFailedCoverDownloadStillSavesTheTrack() async throws {
        let (service, _) = try makeService()
        StubURLProtocol.responses = [.init(status: 500, body: Data())]

        let saved = try await service.save(catalogueTrack())

        XCTAssertEqual(saved.jamendoID, "1")
        XCTAssertNil(saved.artworkRelativePath)
    }

    func testATrackWithNoCoverURLSavesWithoutOne() async throws {
        let (service, _) = try makeService()

        let saved = try await service.save(catalogueTrack(cover: nil))

        XCTAssertNil(saved.artworkRelativePath)
    }

    func testUnsavingRemovesTheRow() async throws {
        let (service, _) = try makeService()
        StubURLProtocol.responses = [.init(status: 200, body: jpeg)]
        let saved = try await service.save(catalogueTrack())
        if let path = saved.artworkRelativePath { written.append(path) }

        try service.unsave(saved)

        XCTAssertFalse(try service.isSaved(jamendoID: "1"))
    }
}
