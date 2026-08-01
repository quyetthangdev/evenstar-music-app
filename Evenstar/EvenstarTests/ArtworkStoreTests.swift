import XCTest
import UIKit
import SwiftUI
@testable import Evenstar

final class ArtworkStoreTests: XCTestCase {

    /// Writes a solid-colour JPEG of the given pixel size into Documents/Artwork
    /// and returns its Documents-relative path. ArtworkStore resolves paths
    /// through FileLocation, so the fixture has to live where it would in real use.
    private func makeArtwork(side: CGFloat, color: UIColor) throws -> String {
        let folder = FileLocation.artworkFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "test-\(UUID().uuidString).jpg"
        let url = folder.appendingPathComponent(name)

        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        try data.write(to: url)
        return "Artwork/\(name)"
    }

    private func remove(_ relativePath: String) {
        try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: relativePath))
    }

    func testDownsamplesToRequestedSize() async throws {
        let path = try makeArtwork(side: 600, color: .red)
        defer { remove(path) }

        let loaded = await ArtworkStore.image(for: path, maxPixel: 44)
        let image = try XCTUnwrap(loaded)

        XCTAssertLessThanOrEqual(image.size.width, 44)
        XCTAssertLessThanOrEqual(image.size.height, 44)
    }

    func testSecondLoadReturnsTheCachedInstance() async throws {
        let path = try makeArtwork(side: 200, color: .green)
        defer { remove(path) }

        let loadedFirst = await ArtworkStore.image(for: path, maxPixel: 44)
        let loadedSecond = await ArtworkStore.image(for: path, maxPixel: 44)
        let first = try XCTUnwrap(loadedFirst)
        let second = try XCTUnwrap(loadedSecond)

        XCTAssertTrue(first === second, "Expected the cached instance, not a fresh decode")
    }

    func testMissingFileReturnsNil() async {
        let image = await ArtworkStore.image(
            for: "Artwork/does-not-exist-\(UUID().uuidString).jpg",
            maxPixel: 44
        )

        XCTAssertNil(image)
    }

    func testUndecodableDataReturnsNil() async throws {
        let folder = FileLocation.artworkFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "not-an-image-\(UUID().uuidString).jpg"
        try Data("this is not a jpeg".utf8).write(to: folder.appendingPathComponent(name))
        let path = "Artwork/\(name)"
        defer { remove(path) }

        let image = await ArtworkStore.image(for: path, maxPixel: 44)

        XCTAssertNil(image)
    }

    func testDominantColorOfASolidImageIsThatColor() async throws {
        let path = try makeArtwork(side: 120, color: UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        defer { remove(path) }

        let loadedColor = await ArtworkStore.dominantColor(for: path)
        let color = try XCTUnwrap(loadedColor)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.9, accuracy: 0.15)
        XCTAssertEqual(g, 0.1, accuracy: 0.15)
        XCTAssertEqual(b, 0.1, accuracy: 0.15)
    }
}
