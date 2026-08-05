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

    /// `fileID` is unique so a rescan updates rather than duplicates.
    func testInsertingTheSameFileIDTwiceKeepsOneRow() throws {
        let library = try InMemoryLibrary.make()
        library.context.insert(DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3"))
        try library.save()
        library.context.insert(DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3"))
        try library.save()

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }
}
