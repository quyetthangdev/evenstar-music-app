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

    /// `link` must fetch-existing-or-insert against `library.context`
    /// directly — not rely on a caller's `@Query` snapshot — so a retry with
    /// the same `folderID` never double-inserts, and a retyped display name
    /// is honored on the existing row rather than silently dropped. See
    /// `DriveLibraryService.link`'s doc comment.
    func testLinkingTheSameFolderIDTwiceReusesTheRowAndUpdatesTheName() throws {
        let (service, library) = try makeService()
        let first = try service.link(folderID: "F1", displayName: "Old name")

        let second = try service.link(folderID: "F1", displayName: "New name")

        let rows = try library.context.fetch(FetchDescriptor<DriveFolder>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(second.persistentModelID, first.persistentModelID)
        XCTAssertEqual(second.displayName, "New name")
        XCTAssertEqual(rows.first?.displayName, "New name")
    }

    // MARK: - Deleting a row must reach the playing queue

    /// The wiring `EvenstarApp` installs, reproduced so these tests exercise the
    /// same contract the app relies on rather than a test-only shortcut.
    private func makePlayback(_ library: LibraryService,
                              notifiedBy service: DriveLibraryService) -> PlaybackService {
        let playback = PlaybackService(
            player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(), library: library
        )
        service.onTrackWillBeDeleted = { playback.handleTrackDeleted($0) }
        return playback
    }

    private func scannedTracks(_ library: LibraryService) throws -> [DriveTrack] {
        try library.context
            .fetch(FetchDescriptor<DriveTrack>())
            .sorted { $0.fileID < $1.fileID }
    }

    /// Swipe "Gỡ" on the folder whose track is playing.
    ///
    /// `AVPlayer` holds the item, so the audio carries on regardless — and until
    /// this wiring existed the queue carried on too, holding
    /// deleted-and-saved rows. The 30-second play-count write, the ≤5s
    /// `queue.map(\.id)` persist and a tap on Next then each read a property off
    /// one, which raises `NSObjectInaccessibleException`: an Objective-C
    /// exception, so uncatchable in Swift and unhelped by `try?`. It presents as
    /// intermittent because a row whose attributes are still materialised
    /// answers quietly for a while.
    func testUnlinkingAFolderTakesItsPlayingTrackOutOfTheQueue() async throws {
        let (service, library) = try makeService()
        let playback = makePlayback(library, notifiedBy: service)
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        _ = try await service.scan(folder)
        let tracks = try scannedTracks(library)
        playback.play(tracks[0], in: tracks)
        XCTAssertEqual(playback.queue.count, 2)

        try service.unlink(folder)

        XCTAssertTrue(playback.queue.isEmpty, "the queue must not hold deleted rows")
        XCTAssertNil(playback.currentTrack)
        XCTAssertTrue(
            library.playbackState.queueTrackIDs.isEmpty,
            "and the persisted queue must not resurrect them on the next launch"
        )
    }

    /// The other deletion path: a rescan that finds the playing track gone from
    /// Drive. The queue must move on to a row that still exists rather than keep
    /// pointing at the one just deleted.
    func testARescanThatDropsThePlayingTrackTakesItOutOfTheQueue() async throws {
        let (service, library) = try makeService()
        let playback = makePlayback(library, notifiedBy: service)
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        _ = try await service.scan(folder)
        let tracks = try scannedTracks(library)
        let survivorID = tracks[1].id
        playback.play(tracks[0], in: tracks)

        // "1" has been deleted from the folder on Drive.
        StubURLProtocol.responses = [.init(status: 200, body: page([("2", "b.mp3")]))]
        _ = try await service.scan(folder)

        XCTAssertEqual(playback.queue.count, 1)
        XCTAssertEqual(playback.currentTrack?.id, survivorID)
        XCTAssertEqual(library.playbackState.queueTrackIDs, [survivorID])
    }

    /// A track that is merely *in* the queue rather than playing must be dropped
    /// too — it is just as deleted, and `persistImmediately` reads every id in
    /// the queue, not only the current one.
    func testARescanDropsAQueuedTrackThatIsNotTheCurrentOne() async throws {
        let (service, library) = try makeService()
        let playback = makePlayback(library, notifiedBy: service)
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        _ = try await service.scan(folder)
        let tracks = try scannedTracks(library)
        let playingID = tracks[0].id
        playback.play(tracks[0], in: tracks)

        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)

        XCTAssertEqual(playback.queue.map(\.id), [playingID])
        XCTAssertEqual(playback.currentTrack?.id, playingID, "the playing track must be undisturbed")
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
