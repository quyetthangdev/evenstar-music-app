import XCTest
import UIKit
@testable import Evenstar

/// `LibraryService.setArtwork` and the downsampling step in front of it.
///
/// The rule these exist to hold is the fresh-filename one. Overwriting the old
/// path would look correct everywhere except on screen: `ArtworkStore` caches
/// decoded images under `path@pixelSize`, so the same path keeps serving the
/// previous picture and the user sees their choice do nothing. Nothing about
/// that failure is visible in a build, in a crash log, or in any other test.
@MainActor
final class SetArtworkTests: XCTestCase {

    private var written: [String] = []

    /// `async` purely to inherit the class's isolation — nothing here awaits.
    /// The synchronous `tearDown()` is nonisolated and an override cannot add
    /// isolation its overridden declaration does not have, so `@MainActor`
    /// reaches every test method in this class and stops at that one, leaving
    /// `written` unreachable from it. The `async` override the compiler does
    /// let a `@MainActor` class isolate. Same change, same reason, as the four
    /// in `ReduceMotionTests`.
    override func tearDown() async throws {
        for path in written {
            try? FileManager.default.removeItem(
                at: FileLocation.absoluteURL(forRelative: path)
            )
        }
        written = []
        try await super.tearDown()
    }

    private func makeStack() throws -> (LibraryService, Track) {
        let library = try InMemoryLibrary.make()
        let track = Track(
            title: "Bài thử",
            artistName: "Nghệ sĩ",
            albumTitle: "Album",
            durationSeconds: 100,
            relativePath: "Music/\(UUID().uuidString).m4a",
            format: "m4a"
        )
        try library.insert(track)
        return (library, track)
    }

    private func jpeg(side: CGFloat, color: UIColor) throws -> Data {
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 1))
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: FileLocation.absoluteURL(forRelative: relativePath).path
        )
    }

    // MARK: - The fresh-filename rule

    func testSecondPickWritesADifferentPath() throws {
        let (library, track) = try makeStack()

        let first = try library.setArtwork(try jpeg(side: 40, color: .red), for: track)
        written.append(first)
        let second = try library.setArtwork(try jpeg(side: 40, color: .blue), for: track)
        written.append(second)

        XCTAssertNotEqual(
            first, second,
            "Reusing the path leaves ArtworkStore's cache serving the old image"
        )
        XCTAssertEqual(track.artworkRelativePath, second)
    }

    func testSecondPickRemovesTheFileTheFirstWrote() throws {
        let (library, track) = try makeStack()

        let first = try library.setArtwork(try jpeg(side: 40, color: .red), for: track)
        written.append(first)
        XCTAssertTrue(exists(first), "precondition: the first write landed")

        let second = try library.setArtwork(try jpeg(side: 40, color: .blue), for: track)
        written.append(second)

        XCTAssertFalse(exists(first), "the replaced cover must not be left on disk")
        XCTAssertTrue(exists(second))
    }

    func testFirstPickOnATrackWithNoArtworkSucceeds() throws {
        let (library, track) = try makeStack()
        XCTAssertNil(track.artworkRelativePath, "precondition: no cover yet")

        let path = try library.setArtwork(try jpeg(side: 40, color: .green), for: track)
        written.append(path)

        XCTAssertEqual(track.artworkRelativePath, path)
        XCTAssertTrue(exists(path))
        XCTAssertTrue(path.hasPrefix("Artwork/"), "must land where delete(_:) looks for it")
    }

    /// Album and Nghệ sĩ copy the cover path into `AlbumGroup`/`ArtistGroup`
    /// when they group, so a copied string cannot notice the row behind it
    /// changing. `metadataRevision` is the only thing that tells those two
    /// screens to regroup, and without this bump a newly picked cover stays
    /// invisible on both grids until something unrelated changes the library.
    func testPickingACoverAsksTheGroupedScreensToRegroup() throws {
        let (library, track) = try makeStack()
        let before = library.metadataRevision

        let path = try library.setArtwork(try jpeg(side: 40, color: .red), for: track)
        written.append(path)

        XCTAssertGreaterThan(library.metadataRevision, before)
    }

    /// The write has to survive being read back through the same path the UI
    /// uses, not merely exist on disk.
    func testTheWrittenFileIsReadableByArtworkStore() async throws {
        let (library, track) = try makeStack()
        let path = try library.setArtwork(try jpeg(side: 200, color: .orange), for: track)
        written.append(path)

        let image = await ArtworkStore.image(for: path, maxPixel: 100)

        XCTAssertNotNil(image)
    }

    // MARK: - Downsampling

    func testJpegForStorageShrinksAnOversizedPhoto() async throws {
        let huge = try jpeg(side: 3000, color: .purple)

        let storedOrNil = await ArtworkStore.jpegForStorage(from: huge, maxPixel: 400)
        let stored = try XCTUnwrap(storedOrNil)
        let decoded = try XCTUnwrap(UIImage(data: stored))

        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 400)
        XCTAssertLessThan(
            stored.count, huge.count,
            "a downsampled copy that is not smaller has saved the user nothing"
        )
    }

    func testJpegForStorageLeavesASmallPhotoWithinBounds() async throws {
        let small = try jpeg(side: 120, color: .cyan)

        let storedOrNil = await ArtworkStore.jpegForStorage(from: small, maxPixel: 1400)
        let stored = try XCTUnwrap(storedOrNil)
        let decoded = try XCTUnwrap(UIImage(data: stored))

        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 1400)
    }

    func testJpegForStorageReturnsNilForDataThatIsNotAnImage() async {
        let garbage = Data("this is not a picture".utf8)

        let stored = await ArtworkStore.jpegForStorage(from: garbage)

        XCTAssertNil(stored)
    }
}
