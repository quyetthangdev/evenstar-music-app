import XCTest
import SwiftData
@testable import Evenstar

/// `LibraryDeletionWiring.install(on:playback:store:search:)` — the single
/// point of failure for the deleted-row crash.
///
/// Three separate caches can outlive a `context.delete`: the playing queue, the
/// songs list (`LibraryStore`), and Tìm kiếm's filtered list
/// (`SearchResultsStore`). Each has its own unit tests, and each of those
/// suites passes with the rider that drives it unhooked — they call
/// `remove(_:)` themselves. What none of them can see is whether the app
/// actually hangs all three on `LibraryService.onTrackWillBeDeleted`. Delete
/// one line from that closure and every other test in the project stays green
/// while the app crashes on the next delete of a playing track.
///
/// So this suite exercises the real installer and asserts one rider each. It is
/// the only place where removing `store.remove(track)`, `search.remove(track)`
/// or `playback?.handleTrackDeleted(playable)` turns something red.
///
/// The previous attempt at this coverage lived inside `LibraryStoreTests` and
/// `SearchResultsStoreTests` as a hand-rebuilt copy of the closure. A copy
/// always agrees with itself; that is why it was removed rather than kept
/// alongside this.
@MainActor
final class LibraryDeletionWiringTests: XCTestCase {

    /// Everything the installer needs, plus a track that is about to die and a
    /// track that must survive it.
    ///
    /// The doomed row is seeded into all three caches, because the point of the
    /// suite is that one delete has to reach all three.
    private struct Wired {
        let library: LibraryService
        let playback: PlaybackService
        let store: LibraryStore
        let search: SearchResultsStore
        let keep: Track
        let doomed: Track
        let doomedID: PersistentIdentifier
    }

    private func makeWiredApp() throws -> Wired {
        let library = try InMemoryLibrary.make()
        let keep = InMemoryLibrary.makeTrack(title: "Giữ", relativePath: "Music/a.mp3")
        let doomed = InMemoryLibrary.makeTrack(title: "Xoá", relativePath: "Music/b.mp3")
        try library.insert(keep)
        try library.insert(doomed)

        let playback = PlaybackService(
            player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(), library: library
        )
        let store = LibraryStore(tracks: [keep, doomed])
        let search = SearchResultsStore()
        search.record([keep, doomed], for: "x")
        // Playing `keep` rather than `doomed`, so the delete removes a queue
        // member without also tearing playback down — the queue is then left
        // with exactly one row to check, and nothing else could have emptied it.
        playback.play(keep, in: [keep, doomed])

        LibraryDeletionWiring.install(
            on: library, playback: playback, store: store, search: search
        )

        return Wired(
            library: library, playback: playback, store: store, search: search,
            keep: keep, doomed: doomed, doomedID: doomed.persistentModelID
        )
    }

    /// Rider 1 of 3. Red if `playback?.handleTrackDeleted(playable)` is removed.
    func testInstalledHookTakesTheDeletedRowOutOfThePlayingQueue() throws {
        let app = try makeWiredApp()
        XCTAssertEqual(app.playback.queue.count, 2)

        try app.library.delete(app.doomed)

        XCTAssertEqual(app.playback.queue.count, 1)
        XCTAssertEqual(app.playback.queue.map(\.title), ["Giữ"])
    }

    /// Rider 2 of 3. Red if `store.remove(track)` is removed.
    func testInstalledHookTakesTheDeletedRowOutOfTheLibraryStore() throws {
        let app = try makeWiredApp()
        XCTAssertEqual(app.store.tracks.count, 2)

        try app.library.delete(app.doomed)

        XCTAssertFalse(app.store.tracks.contains { $0.persistentModelID == app.doomedID })
        // Reading a stored property off every surviving row is the read that
        // would raise `NSObjectInaccessibleException` — and take the test
        // process with it, the exception being uncatchable — if the dead row
        // were still here. It is the read `SongRow` does.
        XCTAssertEqual(app.store.tracks.map(\.title), ["Giữ"])
    }

    /// Rider 3 of 3. Red if `search.remove(track)` is removed.
    func testInstalledHookTakesTheDeletedRowOutOfTheSearchResults() throws {
        let app = try makeWiredApp()
        XCTAssertEqual(app.search.results?.count, 2)

        try app.library.delete(app.doomed)

        XCTAssertFalse(app.search.results?.contains { $0.persistentModelID == app.doomedID } ?? false)
        XCTAssertEqual(app.search.results?.map(\.title), ["Giữ"])
    }

    /// All three at once, on the case that actually crashes in the app.
    ///
    /// Deleting the track that is *playing* is what makes `RootView` rebuild
    /// the tabs mid-delete — `handleTrackDeleted` clears `currentTrack`, and
    /// `RootView.body` reads it — so the dead row is read by a body before any
    /// `onChange` can run. The other three tests keep playback out of the way to
    /// isolate a rider each; this one puts it back.
    func testDeletingThePlayingTrackLeavesAllThreeCachesClean() throws {
        let app = try makeWiredApp()
        app.playback.play(app.doomed, in: [app.keep, app.doomed])

        try app.library.delete(app.doomed)

        XCTAssertFalse(app.playback.queue.contains { $0.id == app.doomed.id })
        XCTAssertEqual(app.store.tracks.map(\.title), ["Giữ"])
        XCTAssertEqual(app.search.results?.map(\.title), ["Giữ"])
    }

    /// The `as? Track` cast, from the other side.
    ///
    /// A `DriveTrack` reaching this hook must leave both local caches alone —
    /// no row of theirs is in either — while still being announced to playback,
    /// which does hold rows of every source. Not expressible by handing a
    /// `DriveTrack` to `remove(_:)`: those take a `Track`, so the compiler
    /// refuses. It is expressible here, through the installed closure.
    func testARemoteRowAnnouncedToTheHookLeavesTheLocalCachesAlone() throws {
        let app = try makeWiredApp()
        let remote = DriveTrack(fileID: "A1", folderID: "F1", fileName: "Từ Drive.mp3")
        app.library.context.insert(remote)

        app.library.onTrackWillBeDeleted?(remote)

        XCTAssertEqual(app.store.tracks.count, 2)
        XCTAssertEqual(app.search.results?.count, 2)
    }
}
