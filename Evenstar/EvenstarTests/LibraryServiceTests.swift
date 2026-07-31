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
}
