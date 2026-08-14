import XCTest
import SwiftData
@testable import Evenstar

/// `LibraryStore` — the one copy of the local library the five screens read.
///
/// The test that matters here is `testDeleteThroughTheHookDropsTheRowBeforeItDies`.
/// Five screens used to hold their own `@Query`, and `Query` is a
/// `DynamicProperty`: its `update()` runs *before* the body of the view holding
/// it, so no body could ever read an array still containing a row that had just
/// been deleted. Moving the query into `LibraryQueryBridge` gave that up —
/// `onChange` actions run *after* the update pass — and opened a window where a
/// body reads a deleted-and-saved row and raises `NSObjectInaccessibleException`,
/// an Objective-C exception `try?` cannot catch.
///
/// The window is only reachable when the deleted track is in the playing queue:
/// `PlaybackService.handleTrackDeleted` returns early otherwise, and it is that
/// early return which keeps the ordinary delete looking fine. Deleting the song
/// that is currently playing is the case that crashes, so it is the case pinned
/// here.
@MainActor
final class LibraryStoreTests: XCTestCase {

    /// Records whether an `@Observable` property actually notified, so the
    /// "does not wake its readers" claims below are tested rather than asserted.
    private final class ChangeFlag {
        var didChange = false
    }

    // MARK: - remove(_:)

    func testRemoveDropsOnlyTheGivenRow() throws {
        let library = try InMemoryLibrary.make()
        let keep = InMemoryLibrary.makeTrack(title: "Giữ", relativePath: "Music/a.mp3")
        let drop = InMemoryLibrary.makeTrack(title: "Xoá", relativePath: "Music/b.mp3")
        try library.insert(keep)
        try library.insert(drop)
        let store = LibraryStore(tracks: [keep, drop])

        store.remove(drop)

        XCTAssertEqual(store.tracks.map(\.title), ["Giữ"])
    }

    func testRemoveOfAnAbsentRowDoesNotNotify() throws {
        let library = try InMemoryLibrary.make()
        let present = InMemoryLibrary.makeTrack(title: "Có", relativePath: "Music/a.mp3")
        let absent = InMemoryLibrary.makeTrack(title: "Không", relativePath: "Music/b.mp3")
        try library.insert(present)
        try library.insert(absent)
        let store = LibraryStore(tracks: [present])

        let flag = ChangeFlag()
        withObservationTracking {
            _ = store.tracks
        } onChange: {
            flag.didChange = true
        }

        store.remove(absent)

        // The store can legitimately be one update behind an insert, so being
        // asked to drop a row it never had is not an error — but waking five
        // screens for a change that did not happen is waste.
        XCTAssertFalse(flag.didChange)
        XCTAssertEqual(store.tracks.map(\.title), ["Có"])
    }

    // MARK: - replace(with:)

    func testReplaceWithAnIdenticalFetchDoesNotNotify() throws {
        let library = try InMemoryLibrary.make()
        let first = InMemoryLibrary.makeTrack(title: "Một", relativePath: "Music/a.mp3")
        let second = InMemoryLibrary.makeTrack(title: "Hai", relativePath: "Music/b.mp3")
        try library.insert(first)
        try library.insert(second)
        let store = LibraryStore(tracks: [first, second])

        let flag = ChangeFlag()
        withObservationTracking {
            _ = store.tracks
        } onChange: {
            flag.didChange = true
        }

        store.replace(with: [first, second])

        // This is what makes the launch path quiet: the seed in `EvenstarApp`
        // and the bridge's first `initial: true` pass carry the same rows, so
        // that pass must not write state back into a view update.
        XCTAssertFalse(flag.didChange)
    }

    func testReplaceNotifiesWhenTheRowsActuallyChange() throws {
        let library = try InMemoryLibrary.make()
        let first = InMemoryLibrary.makeTrack(title: "Một", relativePath: "Music/a.mp3")
        let second = InMemoryLibrary.makeTrack(title: "Hai", relativePath: "Music/b.mp3")
        try library.insert(first)
        try library.insert(second)
        let store = LibraryStore(tracks: [first])

        let flag = ChangeFlag()
        withObservationTracking {
            _ = store.tracks
        } onChange: {
            flag.didChange = true
        }

        store.replace(with: [first, second])

        XCTAssertTrue(flag.didChange)
        XCTAssertEqual(store.tracks.count, 2)
    }

    func testReplaceNotifiesOnAReorderAlone() throws {
        let library = try InMemoryLibrary.make()
        let first = InMemoryLibrary.makeTrack(title: "Một", relativePath: "Music/a.mp3")
        let second = InMemoryLibrary.makeTrack(title: "Hai", relativePath: "Music/b.mp3")
        try library.insert(first)
        try library.insert(second)
        let store = LibraryStore(tracks: [first, second])

        // Renaming a track can move it in a title sort without changing which
        // rows exist. The store has to publish that, or the songs list stays in
        // an order the database no longer agrees with.
        store.replace(with: [second, first])

        XCTAssertEqual(store.tracks.map(\.title), ["Hai", "Một"])
    }

    // MARK: - The crash window

    /// Wires the delete hook exactly the way `EvenstarApp` does, then deletes.
    ///
    /// The assertion is that the store no longer holds the row **after
    /// `delete(_:)` returns** — not after some later update pass. In the app it
    /// is `RootView` reading `playback.currentTrack` that gets invalidated
    /// mid-delete and drags the five tabs into a pass before the bridge's
    /// `onChange` has run; here the point is simply that nothing has to run
    /// afterwards for the store to be honest.
    func testDeleteThroughTheHookDropsTheRowBeforeItDies() throws {
        let library = try InMemoryLibrary.make()
        let keep = InMemoryLibrary.makeTrack(title: "Giữ", relativePath: "Music/a.mp3")
        let doomed = InMemoryLibrary.makeTrack(title: "Xoá", relativePath: "Music/b.mp3")
        try library.insert(keep)
        try library.insert(doomed)
        let store = LibraryStore(tracks: [keep, doomed])
        let doomedID = doomed.persistentModelID
        library.onTrackWillBeDeleted = { playable in
            if let track = playable as? Track { store.remove(track) }
        }

        try library.delete(doomed)

        XCTAssertFalse(store.tracks.contains { $0.persistentModelID == doomedID })
        // Reading a stored property off every surviving row is the part that
        // would raise `NSObjectInaccessibleException` — and take the whole test
        // process with it, since the exception is uncatchable — if the deleted
        // row were still in this array. It is the same read `SongRow` does.
        XCTAssertEqual(store.tracks.map(\.title), ["Giữ"])
    }

    /// The hook must not fire `remove` for rows belonging to the other two
    /// tables: `DriveTrack` and `JamendoTrack` are not in this store, and the
    /// cast in `EvenstarApp` is what keeps them out.
    func testDeletingADriveRowLeavesTheLocalStoreAlone() throws {
        let library = try InMemoryLibrary.make()
        let local = InMemoryLibrary.makeTrack(title: "Giữ", relativePath: "Music/a.mp3")
        try library.insert(local)
        let store = LibraryStore(tracks: [local])
        let drive = DriveTrack(fileID: "f1", folderID: "folder", fileName: "remote.mp3")
        library.context.insert(drive)

        // The same closure body `EvenstarApp` installs, handed a non-`Track`.
        let hook: @MainActor (any Playable) -> Void = { playable in
            if let track = playable as? Track { store.remove(track) }
        }
        hook(drive)

        XCTAssertEqual(store.tracks.map(\.title), ["Giữ"])
    }
}
