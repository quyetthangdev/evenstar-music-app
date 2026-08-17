import XCTest
@testable import Evenstar

@MainActor
final class ImportServiceTests: XCTestCase {

    private var tempDir: URL!

    /// `setUp() async throws` rather than `setUpWithError()`, and `async` only
    /// to inherit the class's isolation — nothing here awaits. The synchronous
    /// hooks are nonisolated and an override cannot add isolation its
    /// overridden declaration does not have, which leaves `tempDir` unreachable
    /// from them. The `async` pair a `@MainActor` class can isolate. Same
    /// change, same reason, as in `ReduceMotionTests` and `SetArtworkTests`.
    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeSourceFile(name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("fake audio bytes".utf8).write(to: url)
        return url
    }

    func testImportSkipsUnsupportedFormats() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "notes.txt")

        let summary = await importer.importFiles(at: [url])

        XCTAssertEqual(summary.imported.count, 0)
        XCTAssertEqual(summary.failures.count, 1)
        if case .unsupportedFormat = summary.failures.first?.error {
            // OK
        } else {
            XCTFail("Expected unsupportedFormat")
        }
        XCTAssertTrue(reader.readURLs.isEmpty, "Reader should not be called for unsupported file")
    }

    func testImportInsertsTrackWithFallbackMetadata() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "Bohemian Rhapsody.mp3")

        let summary = await importer.importFiles(at: [url])

        XCTAssertEqual(summary.imported.count, 1)
        XCTAssertEqual(summary.failures.count, 0)
        let inserted = try XCTUnwrap(summary.imported.first)
        let destURL = FileLocation.absoluteURL(forRelative: inserted.relativePath)
        defer {
            try? FileManager.default.removeItem(at: destURL)
        }
        XCTAssertEqual(inserted.title, "Bohemian Rhapsody")    // filename fallback
        XCTAssertEqual(inserted.artistName, "Unknown Artist")
        XCTAssertEqual(inserted.albumTitle, "Unknown Album")
        XCTAssertEqual(inserted.format, "mp3")
        // Verify file was copied into sandbox
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
    }

    func testImportUsesEmbeddedTitleWhenPresent() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "track.mp3")
        reader.outcomesByURL[url] = .success(
            ExtractedMetadata(
                title: "Real Title", artist: "Real Artist", album: "Real Album",
                trackNumber: nil, discNumber: nil,
                durationSeconds: 200,
                sampleRate: 44100, bitDepth: 16,
                artworkData: nil
            )
        )

        let summary = await importer.importFiles(at: [url])

        let inserted = try XCTUnwrap(summary.imported.first)
        let destURL = FileLocation.absoluteURL(forRelative: inserted.relativePath)
        defer {
            try? FileManager.default.removeItem(at: destURL)
        }
        XCTAssertEqual(inserted.title, "Real Title")
        XCTAssertEqual(inserted.artistName, "Real Artist")
        XCTAssertEqual(inserted.albumTitle, "Real Album")
    }

    func testImportDedupesByLowercaseTupleAndRoundedDuration() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        // Create separate subdirectories so case-insensitive filesystems don't collide
        let dir1 = tempDir.appendingPathComponent("a")
        let dir2 = tempDir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        let url1 = dir1.appendingPathComponent("Bohemian Rhapsody.mp3")
        let url2 = dir2.appendingPathComponent("BOHEMIAN RHAPSODY.mp3")
        try Data("fake audio bytes".utf8).write(to: url1)
        try Data("fake audio bytes".utf8).write(to: url2)
        reader.defaultOutcome = .success(
            ExtractedMetadata(
                title: nil, artist: nil, album: nil,
                trackNumber: nil, discNumber: nil,
                durationSeconds: 354.27,
                sampleRate: nil, bitDepth: nil,
                artworkData: nil
            )
        )

        let summary = await importer.importFiles(at: [url1, url2])

        XCTAssertEqual(summary.imported.count, 1)
        XCTAssertEqual(summary.duplicates.count, 1)
        // Cleanup
        for t in summary.imported {
            try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: t.relativePath))
        }
    }

    func testImportWritesArtworkWhenPresent() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "with-art.mp3")
        let artworkBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]) // JPEG SOI + APP0 prefix
        reader.outcomesByURL[url] = .success(
            ExtractedMetadata(
                title: "T", artist: "A", album: "B",
                trackNumber: nil, discNumber: nil,
                durationSeconds: 100,
                sampleRate: nil, bitDepth: nil,
                artworkData: artworkBytes
            )
        )

        let summary = await importer.importFiles(at: [url])

        let inserted = try XCTUnwrap(summary.imported.first)
        let audioURL = FileLocation.absoluteURL(forRelative: inserted.relativePath)
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }
        let artworkPath = try XCTUnwrap(inserted.artworkRelativePath)
        let artworkURL = FileLocation.absoluteURL(forRelative: artworkPath)
        defer {
            try? FileManager.default.removeItem(at: artworkURL)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: artworkURL.path))
    }

    func testImportRecordsMetadataExtractionFailure() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "broken.mp3")
        reader.outcomesByURL[url] = .throwing(AudioMetadataError.unreadable)

        let summary = await importer.importFiles(at: [url])

        XCTAssertEqual(summary.imported.count, 0)
        XCTAssertEqual(summary.failures.count, 1)
        if case .metadataExtractionFailed = summary.failures.first?.error { } else {
            XCTFail("Expected metadataExtractionFailed")
        }
    }

    /// `FileManager.copyItem(at:to:)` reports out-of-space as
    /// `NSCocoaErrorDomain` / `NSFileWriteOutOfSpaceError`, not
    /// `NSPOSIXErrorDomain` / `ENOSPC` directly. This subclass reproduces
    /// that real-world shape so the test exercises the actual classification
    /// path rather than an easier-to-match stand-in.
    private final class DiskFullFileManager: FileManager {
        private(set) var copyAttempts: [URL] = []

        override func copyItem(at srcURL: URL, to dstURL: URL) throws {
            copyAttempts.append(srcURL)
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        }
    }

    func testDiskFullIsClassifiedAndStopsTheBatch() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let fileManager = DiskFullFileManager()
        let importer = ImportService(library: library, metadataReader: reader, fileManager: fileManager)
        let url1 = try makeSourceFile(name: "one.mp3")
        let url2 = try makeSourceFile(name: "two.mp3")
        let url3 = try makeSourceFile(name: "three.mp3")

        let summary = await importer.importFiles(at: [url1, url2, url3])

        XCTAssertEqual(summary.imported.count, 0)
        XCTAssertEqual(summary.failures.count, 1)
        if case .diskFull = summary.failures.first?.error {
            // OK
        } else {
            XCTFail("Expected diskFull, got \(String(describing: summary.failures.first?.error))")
        }
        // Batch-stop: only the failing file was ever attempted. url2/url3
        // must never have reached copyItem or even metadata extraction.
        XCTAssertEqual(fileManager.copyAttempts, [url1])
        XCTAssertEqual(reader.readURLs, [url1])
    }

    func testProgressUpdatesAsFilesAreProcessed() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let urls = try (0..<3).map { try makeSourceFile(name: "t\($0).mp3") }
        // Different durations so dedupe doesn't collapse them
        for (i, url) in urls.enumerated() {
            reader.outcomesByURL[url] = .success(
                ExtractedMetadata(
                    title: "t\(i)", artist: "a", album: "b",
                    trackNumber: nil, discNumber: nil,
                    durationSeconds: Double(60 + i * 10),
                    sampleRate: nil, bitDepth: nil,
                    artworkData: nil
                )
            )
        }

        let summary = await importer.importFiles(at: urls)

        XCTAssertEqual(summary.imported.count, 3)
        XCTAssertEqual(importer.progress.completed, 3)
        XCTAssertEqual(importer.progress.total, 3)
        XCTAssertFalse(importer.isImporting)
        // Cleanup
        for t in summary.imported {
            try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: t.relativePath))
        }
    }
}
