import XCTest
import SwiftData
@testable import Evenstar

/// `SearchResultsStore` — the list Tìm kiếm shows, and the rules about when it
/// survives the next keystroke.
///
/// Two separate things are pinned here, and they arrived from opposite
/// directions.
///
/// The delete tests are the same crash as `LibraryStoreTests`: a cached row
/// outliving `context.delete`, and a body reading a property off it raising
/// `NSObjectInaccessibleException`, which Swift cannot catch. This cache was
/// the worst of the three, because it is refreshed by *typing* rather than by
/// an update pass — a dead row could sit in it for as long as the user did not
/// search again.
///
/// The keep-or-drop tests are older behaviour that had never been testable:
/// while these two values were `@State` on `SearchView`, the only way to
/// exercise them was to type into a running app. Moving them out for the crash
/// fix is what made them reachable, so they are pinned here rather than left to
/// the next reader to re-derive from the comments.
@MainActor
final class SearchResultsStoreTests: XCTestCase {

    /// Records whether an `@Observable` property actually notified, so the
    /// "does not wake its reader" claims below are tested rather than asserted.
    private final class ChangeFlag {
        var didChange = false
    }

    private func watchResults(_ store: SearchResultsStore) -> ChangeFlag {
        let flag = ChangeFlag()
        withObservationTracking {
            _ = store.results
        } onChange: {
            flag.didChange = true
        }
        return flag
    }

    // MARK: - remove(_:)

    func testRemoveDropsOnlyTheGivenRow() throws {
        let library = try InMemoryLibrary.make()
        let keep = InMemoryLibrary.makeTrack(title: "Giữ", relativePath: "Music/a.mp3")
        let drop = InMemoryLibrary.makeTrack(title: "Xoá", relativePath: "Music/b.mp3")
        try library.insert(keep)
        try library.insert(drop)
        let store = SearchResultsStore()
        store.record([keep, drop], for: "a")

        store.remove(drop)

        XCTAssertEqual(store.results?.map(\.title), ["Giữ"])
    }

    func testRemoveWithNoSearchInFlightDoesNotNotify() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Xoá", relativePath: "Music/a.mp3")
        try library.insert(track)
        let store = SearchResultsStore()

        let flag = watchResults(store)

        store.remove(track)

        // The ordinary delete: nothing has been searched for, so there is
        // nothing to prune and no screen to wake.
        XCTAssertFalse(flag.didChange)
        XCTAssertNil(store.results)
    }

    func testRemoveOfARowOutsideTheResultsDoesNotNotify() throws {
        let library = try InMemoryLibrary.make()
        let shown = InMemoryLibrary.makeTrack(title: "Trong kết quả", relativePath: "Music/a.mp3")
        let unrelated = InMemoryLibrary.makeTrack(title: "Ngoài", relativePath: "Music/b.mp3")
        try library.insert(shown)
        try library.insert(unrelated)
        let store = SearchResultsStore()
        store.record([shown], for: "trong")

        let flag = watchResults(store)

        store.remove(unrelated)

        // A search is showing, but the deleted row is not in it — the common
        // case for any query narrower than the whole library.
        XCTAssertFalse(flag.didChange)
        XCTAssertEqual(store.results?.map(\.title), ["Trong kết quả"])
    }

    /// A pruned list is still an answer to the query that produced it, so the
    /// "keep it while the user types further" rule has to survive the prune.
    func testAPrunedListIsStillKeptWhenTheQueryIsExtended() throws {
        let library = try InMemoryLibrary.make()
        let keep = InMemoryLibrary.makeTrack(title: "Queen I", relativePath: "Music/a.mp3")
        let doomed = InMemoryLibrary.makeTrack(title: "Queen II", relativePath: "Music/b.mp3")
        try library.insert(keep)
        try library.insert(doomed)
        let store = SearchResultsStore()
        store.record([keep, doomed], for: "queen")

        store.remove(doomed)
        store.dropStaleResults(for: "queen i")

        XCTAssertEqual(store.results?.map(\.title), ["Queen I"])
    }

    // MARK: - The crash window

    /// Wires the delete hook the way `EvenstarApp` does, then deletes.
    ///
    /// What this pins: by the time `delete(_:)` returns, the list is already
    /// clean — no keystroke, no update pass, no `onChange` has to run for it to
    /// be honest. That is the whole difference between this and a cleanup
    /// driven from the view, which would arrive after the pass that kills the
    /// row and only for a `SearchView` that SwiftUI happens to be updating.
    ///
    /// What this does NOT pin, exactly as in `LibraryStoreTests`: that `remove`
    /// runs *before* `context.delete`. It only reads the end state. The
    /// ordering itself is pinned by `LibraryServiceTests`
    /// `testDeleteAnnouncesTheTrackWhileItIsStillLive`.
    func testDeleteThroughTheHookLeavesTheResultsCleanWhenItReturns() throws {
        let library = try InMemoryLibrary.make()
        let keep = InMemoryLibrary.makeTrack(title: "Giữ", relativePath: "Music/a.mp3")
        let doomed = InMemoryLibrary.makeTrack(title: "Xoá", relativePath: "Music/b.mp3")
        try library.insert(keep)
        try library.insert(doomed)
        let store = SearchResultsStore()
        store.record([keep, doomed], for: "xo")
        let doomedID = doomed.persistentModelID
        library.onTrackWillBeDeleted = { playable in
            if let track = playable as? Track { store.remove(track) }
        }

        try library.delete(doomed)

        XCTAssertFalse(store.results?.contains { $0.persistentModelID == doomedID } ?? false)
        // Reading a stored property off every surviving row is the part that
        // would raise `NSObjectInaccessibleException` — and take the whole test
        // process with it, since the exception is uncatchable — if the deleted
        // row were still in this list. It is the same read `SongRow` does for
        // every row of the results list.
        XCTAssertEqual(store.results?.map(\.title), ["Giữ"])
    }

    // MARK: - Keeping or dropping the list on screen

    func testResultsAreKeptWhenTheNewQueryExtendsTheAnsweredOne() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Queen", relativePath: "Music/a.mp3")
        try library.insert(track)
        let store = SearchResultsStore()
        store.record([track], for: "queen")

        store.dropStaleResults(for: "queena")

        // Still a superset of whatever the longer query will match, so it stays
        // on screen while the next answer is computed.
        XCTAssertEqual(store.results?.map(\.title), ["Queen"])
    }

    func testResultsAreDroppedWhenACharacterIsDeleted() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Queen", relativePath: "Music/a.mp3")
        try library.insert(track)
        let store = SearchResultsStore()
        store.record([track], for: "queenx")

        store.dropStaleResults(for: "queen")

        // The old list is now a *subset* of the right answer: keeping it would
        // show a shrunk list with no sign that rows are missing.
        XCTAssertNil(store.results)
    }

    func testResultsAreDroppedWhenADifferentQueryIsTyped() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Queen", relativePath: "Music/a.mp3")
        try library.insert(track)
        let store = SearchResultsStore()
        store.record([track], for: "queen")

        store.dropStaleResults(for: "abba")

        // Queen's songs under the word "abba" was the actual bug this rule
        // replaced.
        XCTAssertNil(store.results)
    }

    func testClearDropsTheList() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Queen", relativePath: "Music/a.mp3")
        try library.insert(track)
        let store = SearchResultsStore()
        store.record([track], for: "queen")

        store.clear()

        // The field was wiped: `SearchView` has to fall back to its "type
        // something" prompt, not to the last answer.
        XCTAssertNil(store.results)
    }

    func testClearWithNothingHeldDoesNotNotify() {
        let store = SearchResultsStore()

        let flag = watchResults(store)

        store.clear()

        // The first pass of a session arrives here with an empty field and
        // nothing held; it must not write state back into a view update.
        XCTAssertFalse(flag.didChange)
    }
}
