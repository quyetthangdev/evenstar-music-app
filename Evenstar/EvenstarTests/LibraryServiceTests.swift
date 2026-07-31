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
}
