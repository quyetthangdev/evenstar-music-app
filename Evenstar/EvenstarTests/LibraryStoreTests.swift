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
    ///
    /// `withObservationTracking`'s `onChange` is a `@Sendable` closure, so under
    /// Swift 6 this flag has to be `Sendable` to be written from inside one.
    /// Locked rather than annotated: in these tests the notification does fire
    /// on the test's own thread, so a bare `@unchecked Sendable` would be true
    /// today — but it would be an assertion about *when Observation calls back*,
    /// which is not this file's to make and not one a reader could check. A lock
    /// makes it true regardless, and a test flag is the last place where the
    /// cost of one could matter.
    private final class ChangeFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var didChange: Bool {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
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

    // MARK: - presence / isPresent(_:)

    /// Hàng có file trên máy này thì phát được; hàng đến từ máy khác thì không.
    func testAtrackIsPresentOnlyWhenItsFileIsInTheScannedSet() throws {
        let here = InMemoryLibrary.makeTrack(relativePath: "Music/here.mp3")
        let elsewhere = InMemoryLibrary.makeTrack(relativePath: "Music/elsewhere.mp3")
        let store = LibraryStore(
            tracks: [here, elsewhere],
            presence: .known(["Music/here.mp3"])
        )
        XCTAssertTrue(store.isPresent(here))
        XCTAssertFalse(store.isPresent(elsewhere))
    }

    /// Vừa nhập xong một bài mà nó hiện mờ với chữ "không có trên máy này" là
    /// một lỗi nhìn thấy ngay, và nó xảy ra nếu tập có mặt chỉ được nạp một lần
    /// lúc khởi động. Nên nó được quét lại mỗi khi tập hàng đổi.
    func testTheScannedSetIsRefreshedWhenTheRowSetChanges() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = LibraryStore(musicFolder: folder)
        let imported = InMemoryLibrary.makeTrack(relativePath: "Music/new.mp3")
        XCTAssertFalse(store.isPresent(imported), "Chưa có file thì chưa có mặt.")

        try Data().write(to: folder.appendingPathComponent("new.mp3"))
        store.replace(with: [imported])

        XCTAssertTrue(store.isPresent(imported), "Sau khi tập hàng đổi, phải quét lại.")
    }

    /// Một lỗi đọc bất ngờ **không** được làm cả thư viện trông như vắng mặt —
    /// xem `TrackPresence.Snapshot`. Đây là nửa của `LibraryStore` trong cùng
    /// một quyết định: mở khoá phải đi hết đường tới `isPresent`.
    func testAnUnreadableScanMakesEveryTrackCountAsPresent() throws {
        let track = InMemoryLibrary.makeTrack(relativePath: "Music/here.mp3")
        let store = LibraryStore(tracks: [track], presence: .unreadable)
        XCTAssertTrue(store.isPresent(track))
    }
}
