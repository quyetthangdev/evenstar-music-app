import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class DriveModelTests: XCTestCase {

    /// Both models must be in the container the app builds, not just the one
    /// the tests build — a model missing from the app's schema throws at
    /// launch, which no unit test would catch.
    func testBothModelsAreInTheInMemorySchema() throws {
        let library = try InMemoryLibrary.make()
        let folder = DriveFolder(folderID: "F1", displayName: "Chill mix")
        let track = DriveTrack(fileID: "A1", folderID: "F1", fileName: "01 - Song.mp3")
        library.context.insert(folder)
        library.context.insert(track)
        try library.save()

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveFolder>()).count, 1)
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }

    /// The title falls back to the file name without its extension, because at
    /// scan time that is genuinely all the app knows.
    func testTitleDefaultsToTheFileNameWithoutItsExtension() {
        let track = DriveTrack(fileID: "A1", folderID: "F1", fileName: "01 - Giây Tiếp Theo.mp3")
        XCTAssertEqual(track.title, "01 - Giây Tiếp Theo")
        XCTAssertFalse(track.metadataResolved)
        XCTAssertEqual(track.durationSeconds, 0)
    }

    func testAFileNameWithNoExtensionIsUsedWhole() {
        let track = DriveTrack(fileID: "A1", folderID: "F1", fileName: "Untitled")
        XCTAssertEqual(track.title, "Untitled")
    }

    /// **Renamed from `testInsertingTheSameFileIDTwiceKeepsOneRow`.** That
    /// test pinned SwiftData's `@Attribute(.unique)` upsert on `fileID` —
    /// Task 1 removed the attribute because CloudKit rejects it, so the old
    /// name and the old assertion are both false now: at this raw-model
    /// layer nothing stops two `DriveTrack` objects built with the same
    /// `fileID` from becoming two separate rows.
    ///
    /// The requirement this used to guard — one row per `fileID` — has not
    /// gone away, and is still pinned; just not here. `DriveLibraryService
    /// .scan` is who enforces it now: it fetches every existing `DriveTrack`
    /// by `fileID` before inserting and only inserts for a `fileID` it has
    /// not seen, never reconstructing-and-inserting for one it has. That
    /// fetch-then-mutate guard never depended on the removed attribute, so
    /// its tests needed no change — see `DriveLibraryServiceTests
    /// .testRescanningIsIdempotent` and
    /// `.testScanningASecondFolderWithAnAlreadyKnownFileIDKeepsTheOriginalRow`,
    /// which pin the no-duplicate-row guarantee (including that `id` is
    /// preserved, not silently reassigned) at the layer that actually owns
    /// it. This test now pins the new, weaker raw-model-layer behaviour
    /// explicitly, so a future reader sees it was a deliberate choice and not
    /// an oversight.
    func testTwoRawInsertsForOneFileIDNowProduceTwoRows() throws {
        let library = try InMemoryLibrary.make()
        let first = DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3")
        library.context.insert(first)
        try library.save()

        let second = DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3")
        library.context.insert(second)
        try library.save()

        let rows = try library.context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(
            rows.count, 2,
            "no @Attribute(.unique) means raw inserts no longer collapse a duplicate fileID — only DriveLibraryService.scan's fetch-then-mutate guard does that now"
        )
    }
}
