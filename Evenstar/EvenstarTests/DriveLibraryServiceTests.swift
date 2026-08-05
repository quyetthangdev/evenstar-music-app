import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class DriveLibraryServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func page(_ files: [(String, String)]) -> Data {
        let items = files.map { #"{"id":"\#($0.0)","name":"\#($0.1)","mimeType":"audio/mpeg"}"# }
        return Data(#"{"files":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    private func makeService() throws -> (DriveLibraryService, LibraryService) {
        let library = try InMemoryLibrary.make()
        let service = DriveLibraryService(
            library: library,
            client: DriveClient(apiKey: "test-key", session: StubURLProtocol.session())
        )
        return (service, library)
    }

    func testScanInsertsOneTrackPerAudioFile() async throws {
        let (service, library) = try makeService()
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")

        let count = try await service.scan(folder)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 2)
        XCTAssertNotNil(folder.lastScannedAt)
    }

    /// Rescanning must not duplicate. This is the behaviour a user exercises
    /// every time they pull to refresh.
    func testRescanningIsIdempotent() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]

        _ = try await service.scan(folder)

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }

    func testANewFileOnDriveAppearsOnTheNextScan() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]

        _ = try await service.scan(folder)

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 2)
    }

    /// A file deleted on Drive must stop appearing, or the user taps a row that
    /// can never play.
    func testAFileRemovedFromDriveIsRemovedLocally() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]

        _ = try await service.scan(folder)

        let remaining = try library.context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(remaining.map(\.fileID), ["1"])
    }

    /// A failed scan must leave what was already there alone — otherwise one
    /// trip through a tunnel empties the list.
    func testAFailedScanKeepsTheExistingTracks() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 403, body: Data("{}".utf8))]

        do {
            _ = try await service.scan(folder)
            XCTFail("expected the scan to throw")
        } catch {
            XCTAssertEqual(error as? DriveError, .notShared)
        }
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }

    /// Drive supports multi-parent files: the same file can be a direct child
    /// of two folders the user links separately. Scanning the second folder
    /// must not construct-and-insert a fresh row for a `fileID` the first
    /// folder's scan already created — that would collide with the store-wide
    /// `@Attribute(.unique)` on `DriveTrack.fileID`, and SwiftData resolves the
    /// collision by keeping the row count at one while handing the survivor a
    /// freshly minted `id`, orphaning anything (e.g. a saved queue) that
    /// referenced the original. Mirrors
    /// `DriveModelTests.testInsertingTheSameFileIDTwiceKeepsOneRow`, but
    /// exercised through two `DriveFolder`s and two `scan` calls, because a
    /// row-count assertion alone would pass whether or not the `id` moved.
    func testScanningASecondFolderWithAnAlreadyKnownFileIDKeepsTheOriginalRow() async throws {
        let (service, library) = try makeService()
        let folderA = try service.link(folderID: "F1", displayName: "Folder A")
        StubURLProtocol.responses = [.init(status: 200, body: page([("shared-1", "shared.mp3")]))]
        _ = try await service.scan(folderA)

        let rowsAfterFirstScan = try library.context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(rowsAfterFirstScan.count, 1)
        let originalID = try XCTUnwrap(rowsAfterFirstScan.first).id

        let folderB = try service.link(folderID: "F2", displayName: "Folder B")
        StubURLProtocol.responses = [.init(status: 200, body: page([("shared-1", "shared.mp3")]))]
        _ = try await service.scan(folderB)

        let rowsAfterSecondScan = try library.context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(rowsAfterSecondScan.count, 1)
        XCTAssertEqual(rowsAfterSecondScan.first?.id, originalID)
    }

    func testUnlinkRemovesTheFolderAndItsTracks() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)

        try service.unlink(folder)

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveFolder>()).count, 0)
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 0)
    }
}
