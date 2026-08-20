import XCTest
import SwiftData
@testable import Evenstar

/// Lượt quét gộp trùng chạy trên hàng thật.
///
/// Ca sinh ra nó: hai máy ngoại tuyến cùng lưu một bài Jamendo. Không có `Task`
/// chung để gom như `JamendoLibraryService.inFlightSaves` làm trong một tiến
/// trình, và từ Task 1 thì cũng không còn `@Attribute(.unique)` nào để va vào.
/// Nên hai hàng cùng lên mây, và cái dọn chúng là chỗ này.
@MainActor
final class DuplicateSweepTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self, JamendoTrack.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func jamendo(_ id: UUID, jamendoID: String, added: TimeInterval, plays: Int) -> JamendoTrack {
        JamendoTrack(
            id: id,
            jamendoID: jamendoID,
            title: "Bài",
            artistName: "Nghệ sĩ",
            albumTitle: "Album",
            durationSeconds: 180,
            audioURLString: "https://example.invalid/\(jamendoID).mp3",
            dateAdded: Date(timeIntervalSince1970: added),
            playCount: plays
        )
    }

    func testTwoRowsWithOneJamendoIDCollapseToOne() throws {
        let context = try makeContext()
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 100, plays: 3))
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 200, plays: 4))
        try context.save()

        let removed = try DuplicateSweep.run(context: context)

        XCTAssertEqual(removed, 1)
        let rows = try context.fetch(FetchDescriptor<JamendoTrack>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.playCount, 7, "Lượt nghe của cả hai máy phải cộng lại.")
    }

    /// Hai bài **khác nhau** không được gộp chỉ vì cùng bảng.
    func testDistinctJamendoIDsAreLeftAlone() throws {
        let context = try makeContext()
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 100, plays: 1))
        context.insert(jamendo(UUID(), jamendoID: "j2", added: 100, plays: 1))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JamendoTrack>()).count, 2)
    }

    func testTwoRowsWithOneFileIDCollapseToOne() throws {
        let context = try makeContext()
        context.insert(DriveTrack(fileID: "f1", folderID: "d", fileName: "a.mp3",
                                  dateAdded: Date(timeIntervalSince1970: 100), playCount: 2))
        context.insert(DriveTrack(fileID: "f1", folderID: "d", fileName: "a.mp3",
                                  dateAdded: Date(timeIntervalSince1970: 200), playCount: 5))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 1)
        let rows = try context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.playCount, 7)
    }

    /// **Ghim một quyết định, không phải một chỗ sót.** Hai hàng `Track` cùng
    /// tên trên hai máy KHÔNG phải trùng lặp: `relativePath` của chúng chứa `id`
    /// của chính hàng ấy (xem `ImportService`), nên chúng là hai file thật ở hai
    /// chỗ thật. Gộp chúng làm hàng sống sót giữ **một** đường dẫn, và máy kia
    /// mất luôn hàng trỏ tới file nó đang có.
    func testLocalTracksAreNeverMerged() throws {
        let context = try makeContext()
        context.insert(Track(title: "Bài", artistName: "Nghệ sĩ", albumTitle: "Album",
                             durationSeconds: 180, relativePath: "Music/a.mp3", format: "mp3"))
        context.insert(Track(title: "Bài", artistName: "Nghệ sĩ", albumTitle: "Album",
                             durationSeconds: 180, relativePath: "Music/b.mp3", format: "mp3"))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Track>()).count, 2)
    }

    /// Cùng lý do tất định như `DuplicateMergeTests`: `DriveFolder` không có
    /// trường nào phân biệt hai hàng cùng `folderID`, nên không có tiêu chí cắt
    /// hoà tất định. Hai máy có thể chọn giữ hai hàng khác nhau, mỗi máy xoá
    /// hàng kia, và cả hai lệnh xoá cùng lên mây.
    func testDriveFoldersAreNeverMerged() throws {
        let context = try makeContext()
        context.insert(DriveFolder(folderID: "d1", displayName: "Nhạc"))
        context.insert(DriveFolder(folderID: "d1", displayName: "Nhạc"))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DriveFolder>()).count, 2)
    }

    /// Bước dễ quên nhất. Hàng đợi giữ `UUID` trần; nếu không trỏ lại, nó trỏ
    /// vào một hàng vừa bị xoá và bài ấy biến mất khỏi hàng đợi trong im lặng.
    func testThePlayingQueueIsRepointedAtTheSurvivor() throws {
        let context = try makeContext()
        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let other = UUID()
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        context.insert(jamendo(goneID, jamendoID: "j1", added: 200, plays: 0))
        context.insert(PlaybackState(
            currentTrackID: goneID,
            queueTrackIDs: [other, goneID],
            queueIndex: 1,
            unshuffledQueueTrackIDs: [goneID, other]
        ))
        try context.save()

        _ = try DuplicateSweep.run(context: context)

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<PlaybackState>()).first)
        XCTAssertEqual(state.currentTrackID, keptID)
        XCTAssertEqual(state.queueTrackIDs, [other, keptID])
        XCTAssertEqual(state.unshuffledQueueTrackIDs, [keptID, other])
        XCTAssertEqual(state.queueIndex, 1, "Độ dài mảng không đổi, nên chỉ số không được xê dịch.")
    }

    /// Chạy lại trên dữ liệu đã sạch không được đổi gì. Lượt quét chạy ở **mỗi**
    /// lần khởi động, nên nó phải rẻ và vô hại khi không có việc.
    func testASecondSweepChangesNothing() throws {
        let context = try makeContext()
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 100, plays: 3))
        context.insert(jamendo(UUID(), jamendoID: "j1", added: 200, plays: 4))
        try context.save()

        XCTAssertEqual(try DuplicateSweep.run(context: context), 1)
        XCTAssertEqual(try DuplicateSweep.run(context: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<JamendoTrack>()).first?.playCount, 7,
                       "Lượt thứ hai không được cộng dồn lần nữa.")
    }
}
