import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class LibraryServiceTests: XCTestCase {

    func testInsertPersistsTrack() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Hello")

        try library.insert(track)

        let all = try library.fetchAllTracks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Hello")
    }

    func testFetchAllTracksSortsAlphabetically() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(title: "Charlie"))
        try library.insert(InMemoryLibrary.makeTrack(title: "alpha"))
        try library.insert(InMemoryLibrary.makeTrack(title: "Bravo"))

        let titles = try library.fetchAllTracks().map(\.title)

        XCTAssertEqual(titles, ["alpha", "Bravo", "Charlie"])
    }

    func testFindTrackByID() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)

        let found = try library.findTrack(byID: track.id)

        XCTAssertEqual(found?.id, track.id)
    }

    func testFindExistingTrackMatchesByLowercaseTupleAndRoundedDuration() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(
            title: "Bohemian Rhapsody",
            artistName: "Queen",
            durationSeconds: 354.27
        ))

        let hit = try library.findExistingTrack(
            title: "bohemian rhapsody",
            artist: "QUEEN",
            duration: 354.0
        )
        let miss = try library.findExistingTrack(
            title: "Another One Bites the Dust",
            artist: "Queen",
            duration: 354.0
        )

        XCTAssertNotNil(hit)
        XCTAssertNil(miss)
    }

    /// Pins the rounding rule, because the fetch behind it was narrowed from
    /// "every `Track` in the library" to a duration window and the two must
    /// agree exactly at the edges. 180.6 and 181.0 both round to 181, so the
    /// import is a duplicate even though the numbers differ by more than the
    /// window's own precision.
    func testFindExistingTrackMatchesADurationThatRoundsToTheSameSecond() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(
            title: "Boundary", artistName: "Rounder", durationSeconds: 180.6
        ))

        let hit = try library.findExistingTrack(title: "Boundary", artist: "Rounder", duration: 181.0)

        XCTAssertNotNil(hit)
    }

    /// The other side of the same edge: 180.4 rounds to 180, so it is a
    /// different track from a 181-second one and must import rather than be
    /// swallowed as a duplicate.
    func testFindExistingTrackRejectsADurationThatRoundsToADifferentSecond() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(
            title: "Boundary", artistName: "Rounder", durationSeconds: 180.4
        ))

        let miss = try library.findExistingTrack(title: "Boundary", artist: "Rounder", duration: 181.0)

        XCTAssertNil(miss)
    }

    /// Same title and artist, wholly different length — a live version, or a
    /// radio edit. Not a duplicate, and now not even fetched as a candidate.
    func testFindExistingTrackRejectsTheSameTitleAtADifferentLength() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(
            title: "Boundary", artistName: "Rounder", durationSeconds: 240
        ))

        let miss = try library.findExistingTrack(title: "Boundary", artist: "Rounder", duration: 181.0)

        XCTAssertNil(miss)
    }

    func testPlaybackStateAutoCreatesSingleton() throws {
        let library = try InMemoryLibrary.make()

        let first = library.playbackState
        let second = library.playbackState

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
    }

    func testDeleteRemovesTrackFromDB() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)

        try library.delete(track)

        XCTAssertEqual(try library.fetchAllTracks().count, 0)
    }

    func testDeleteRemovesFilesFromDisk() throws {
        let fileManager = FileManager.default
        let trackID = UUID()
        let musicRelativePath = "Music/\(trackID).mp3"
        let artworkRelativePath = "Artwork/\(trackID).jpg"

        let musicURL = FileLocation.absoluteURL(forRelative: musicRelativePath, fileManager: fileManager)
        let artworkURL = FileLocation.absoluteURL(forRelative: artworkRelativePath, fileManager: fileManager)

        defer {
            try? fileManager.removeItem(at: musicURL)
            try? fileManager.removeItem(at: artworkURL)
            try? fileManager.removeItem(at: musicURL.deletingLastPathComponent())
            try? fileManager.removeItem(at: artworkURL.deletingLastPathComponent())
        }

        // Create directories and write dummy files
        try fileManager.createDirectory(at: musicURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artworkURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Data("dummy audio".utf8).write(to: musicURL)
        try Data("dummy artwork".utf8).write(to: artworkURL)

        XCTAssertTrue(fileManager.fileExists(atPath: musicURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: artworkURL.path))

        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(
            relativePath: musicRelativePath,
            artworkRelativePath: artworkRelativePath
        )
        try library.insert(track)

        try library.delete(track)

        XCTAssertFalse(fileManager.fileExists(atPath: musicURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: artworkURL.path))
        XCTAssertEqual(try library.fetchAllTracks().count, 0)
    }

    // MARK: - Deleting a row must reach the playing queue

    /// The local counterpart of `DriveLibraryServiceTests`' unlink tests.
    ///
    /// `DriveLibraryService` and `JamendoLibraryService` both announce a row to
    /// `onTrackWillBeDeleted` before deleting it, so no caller can forget. The
    /// local library had no such hook: the only thing keeping a deleted `Track`
    /// out of the queue was `SongsView.deleteTrack` calling
    /// `playback.handleTrackDeleted` by hand, in the right order. A second
    /// caller of `delete(_:)` — a batch delete, a "remove all local files", an
    /// import reconciling duplicates — got no such courtesy, and the queue was
    /// left holding a deleted-and-saved row, which raises
    /// `NSObjectInaccessibleException` the next time anything reads a property
    /// off it: an Objective-C exception, so uncatchable in Swift.
    func testDeleteTakesThePlayingTrackOutOfTheQueue() throws {
        let library = try InMemoryLibrary.make()
        let playback = PlaybackService(
            player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(), library: library
        )
        library.onTrackWillBeDeleted = { playback.handleTrackDeleted($0) }
        let first = InMemoryLibrary.makeTrack(title: "First")
        let second = InMemoryLibrary.makeTrack(title: "Second")
        try library.insert(first)
        try library.insert(second)
        playback.play(first, in: [first, second])
        XCTAssertEqual(playback.queue.count, 2)

        try library.delete(first)

        XCTAssertEqual(playback.queue.count, 1)
        XCTAssertEqual(playback.currentTrack?.id, second.id)
    }

    /// The hook fires *before* `context.delete(_:)` and before the save that
    /// flushes it — the same contract `DriveLibraryService` documents. A handler
    /// that ran afterwards would read `track.id` off a dead row, which is the
    /// crash the hook exists to prevent.
    func testDeleteAnnouncesTheTrackWhileItIsStillLive() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Still here")
        try library.insert(track)
        var titleSeenByHandler: String?
        var rowCountSeenByHandler: Int?
        library.onTrackWillBeDeleted = { announced in
            titleSeenByHandler = announced.title
            rowCountSeenByHandler = (try? library.fetchAllTracks().count)
        }

        try library.delete(track)

        XCTAssertEqual(titleSeenByHandler, "Still here")
        XCTAssertEqual(rowCountSeenByHandler, 1)
    }
}
