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

    /// `fileID` is unique so a rescan updates rather than duplicates — but the
    /// surviving row keeps the *second* object's `id`, not the first's. This
    /// is exactly why reconciling a scan against existing rows must fetch by
    /// `fileID` and mutate in place, never reconstruct-and-insert: doing the
    /// latter on every rescan mints a fresh `id` for an already-known
    /// `fileID` each time, and `PlaybackState`'s bare-`UUID` queue references
    /// have no relationship to fall back on when that happens.
    ///
    /// The `id`s are snapshotted into `let`s *before* saving because reading
    /// a property off an object already inserted into the context — even one
    /// that turned out to be a duplicate — reflects the current row state
    /// after the merge, not what was set at construction.
    func testInsertingTheSameFileIDTwiceKeepsOneRow() throws {
        let library = try InMemoryLibrary.make()
        let first = DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3")
        let firstID = first.id
        library.context.insert(first)
        try library.save()

        let second = DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3")
        let secondID = second.id
        library.context.insert(second)
        try library.save()

        let rows = try library.context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, secondID)
        XCTAssertNotEqual(rows[0].id, firstID)
    }
}
