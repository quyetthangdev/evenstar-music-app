import XCTest
import SwiftData
@testable import Evenstar

/// `LibraryStore` — the one copy of the local library the five screens read.
///
/// The test that matters here is
/// `testDeleteThroughTheHookLeavesTheStoreCleanWhenItReturns`.
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

    /// The rows are identical and only their order moved — the case
    /// `replace(with:)`'s equality guard is most likely to swallow by mistake.
    func testReplaceNotifiesOnAReorderAlone() throws {
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

        // Renaming a track can move it in a title sort without changing which
        // rows exist. The store has to publish that, or the songs list stays in
        // an order the database no longer agrees with.
        store.replace(with: [second, first])

        // Both halves, because the name promises the first one: waking the
        // readers is the part that gets the new order on screen, and asserting
        // only the array contents would test `filter` and call it notification.
        XCTAssertTrue(flag.didChange)
        XCTAssertEqual(store.tracks.map(\.title), ["Hai", "Một"])
    }

    // MARK: - The crash window

    // No delete-through-the-hook test here any more, and its absence is the
    // point rather than a gap.
    //
    // The version that stood here rebuilt `EvenstarApp`'s closure inside the
    // test body and then exercised the copy. A copy always agrees with itself:
    // deleting `store.remove(track)` from the app's real wiring left it green,
    // which is the opposite of what a test about a single point of failure is
    // for. The same shape had already cost this suite one test, for the same
    // reason — `as? Track` was likewise only checked against a copy.
    //
    // The closure now lives in `LibraryDeletionWiring.install`, a plain
    // function a test can call, and `LibraryDeletionWiringTests` calls exactly
    // it. Removing `store.remove(track)` turns
    // `testInstalledHookTakesTheDeletedRowOutOfTheLibraryStore` red.
    //
    // What stays over there rather than here: everything about the hook. What
    // stays here: `remove(_:)`'s own behaviour, above.
}
