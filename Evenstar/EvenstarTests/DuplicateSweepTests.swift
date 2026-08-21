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

    /// `InMemoryLibrary.makeContainer()` chứ không dựng một cấu hình đơn tại
    /// chỗ: từ khi app tách làm hai kho, một cấu hình đơn trên cùng năm model
    /// không insert nổi `PlaybackState`. Lý do đầy đủ ở `InMemoryLibrary`.
    private func makeContext() throws -> ModelContext {
        ModelContext(try InMemoryLibrary.makeContainer())
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

    // MARK: - Khử trùng lặp trong hàng đợi đã lưu

    /// **Ca crash mà bước này chữa.** Trước lượt quét, cả hai hàng trùng đều
    /// thật và cả hai đều vào được hàng đợi. Trỏ lại xong, cùng một `id` nằm
    /// hai chỗ — và `QueuePanel.upcomingList` dựng
    /// `Dictionary(uniqueKeysWithValues:)` từ đúng mảng ấy, một khởi tạo trap
    /// khi khoá lặp. Nên lượt quét phải trả về một hàng đợi không có `id` lặp.
    func testARepointedQueueComesBackWithoutDuplicateIDs() throws {
        let context = try makeContext()
        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let other = UUID()
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        context.insert(jamendo(goneID, jamendoID: "j1", added: 200, plays: 0))
        context.insert(PlaybackState(
            currentTrackID: keptID,
            queueTrackIDs: [keptID, other, goneID],
            queueIndex: 0,
            unshuffledQueueTrackIDs: [goneID, keptID, other]
        ))
        try context.save()

        _ = try DuplicateSweep.run(context: context)

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<PlaybackState>()).first)
        XCTAssertEqual(state.queueTrackIDs, [keptID, other])
        XCTAssertEqual(Set(state.unshuffledQueueTrackIDs), Set(state.queueTrackIDs),
                       "Hai mảng phải còn là hoán vị của nhau — `restoreFromPersistedState` dựa vào đó.")
        XCTAssertEqual(state.unshuffledQueueTrackIDs.count, 2)
    }

    /// Chỉ số phải trỏ vào đúng **bài** cũ sau khi mảng ngắn lại, không phải
    /// đúng vị trí cũ. Ba ca ánh xạ được ghim riêng trong `DuplicateMergeTests`;
    /// đây là ca đi qua cả lượt quét thật.
    func testTheQueueIndexStillPointsAtTheSameTrackAfterDeduplication() throws {
        let context = try makeContext()
        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let after = UUID()
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        context.insert(jamendo(goneID, jamendoID: "j1", added: 200, plays: 0))
        context.insert(PlaybackState(
            currentTrackID: after,
            // Sau khi trỏ lại: [kept, kept, after]. Chỉ số 2 nằm **sau** bản
            // trùng bị bỏ, nên nó phải lùi về 1 — giữ nguyên 2 là trỏ ra ngoài
            // mảng hai phần tử.
            queueTrackIDs: [keptID, goneID, after],
            queueIndex: 2,
            unshuffledQueueTrackIDs: [keptID, goneID, after]
        ))
        try context.save()

        _ = try DuplicateSweep.run(context: context)

        let state = try XCTUnwrap(try context.fetch(FetchDescriptor<PlaybackState>()).first)
        XCTAssertEqual(state.queueTrackIDs, [keptID, after])
        XCTAssertEqual(state.queueIndex, 1)
        XCTAssertEqual(state.queueTrackIDs[state.queueIndex], after,
                       "Cùng bài, không phải cùng vị trí.")
    }

    // MARK: - Báo trước khi xoá

    /// **Hợp đồng của cả nhóm này.** Lượt quét từng là đường xoá duy nhất trong
    /// app không đi qua `onTrackWillBeDeleted`. Hàng đợi trong bộ nhớ giữ hàng
    /// của nó **mạnh**, nên một hàng xoá-rồi-lưu sau lưng `PlaybackService` làm
    /// lần đọc thuộc tính kế tiếp ném `NSObjectInaccessibleException` — ngoại lệ
    /// Objective-C, Swift không bắt được, nên nếu nó xảy ra thì cả bó test chết
    /// chứ không đỏ.
    ///
    /// Đọc `title` **bên trong** closure là phần ghim "hàng còn sống lúc báo":
    /// gọi sau `context.delete` + `save()` thì chính dòng ấy là chỗ nổ.
    func testEveryDeletedRowIsAnnouncedWhileItIsStillReadable() throws {
        let context = try makeContext()
        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        context.insert(jamendo(goneID, jamendoID: "j1", added: 200, plays: 0))
        context.insert(DriveTrack(fileID: "f1", folderID: "d", fileName: "a.mp3",
                                  dateAdded: Date(timeIntervalSince1970: 100)))
        let driveGone = DriveTrack(fileID: "f1", folderID: "d", fileName: "a.mp3",
                                   dateAdded: Date(timeIntervalSince1970: 200))
        context.insert(driveGone)
        try context.save()

        var announced: [UUID] = []
        var titles: [String] = []
        let removed = try DuplicateSweep.run(context: context) { row in
            announced.append(row.id)
            titles.append(row.title)
        }

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(Set(announced), [goneID, driveGone.id],
                       "Mỗi hàng bị xoá phải được báo đúng một lần, và chỉ hàng bị xoá.")
        XCTAssertEqual(titles.count, 2, "Đọc được `title` nghĩa là hàng còn sống lúc báo.")
    }

    /// Hàng đợi trong bộ nhớ đang giữ đúng hàng sắp bị xoá.
    ///
    /// Ca sinh ra nó là lúc khởi động, hồi `.task` khôi phục hàng đợi của
    /// `RootView` còn chạy song song với `.task` chạy lượt quét — SwiftUI không
    /// xếp thứ tự hai cái đó. Chỗ gọi nay đã chạy tuần tự, quét trước khôi phục
    /// sau (xem `EvenstarApp`), nên ở đường chạy thật hàng đợi còn rỗng lúc
    /// quét. Test này **vẫn ở lại**: cái móc báo trước là hợp đồng của
    /// `DuplicateSweep.run`, đúng cho mọi chỗ gọi, kể cả chỗ gọi tương lai chạy
    /// lượt quét khi hàng đợi đã có bài.
    ///
    /// Đây là bó test duy nhất chạy đúng dây nối mà `EvenstarApp` dựng, nên nó
    /// dựng cả `PlaybackService` thật chứ không đếm số lần gọi closure.
    func testTheInMemoryQueueLosesTheMergedAwayRowThroughTheHook() throws {
        let context = try makeContext()
        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let kept = jamendo(keptID, jamendoID: "j1", added: 100, plays: 0)
        let gone = jamendo(goneID, jamendoID: "j1", added: 200, plays: 0)
        context.insert(kept)
        context.insert(gone)
        try context.save()

        let library = try InMemoryLibrary.make()
        let playback = PlaybackService(player: MockAudioPlayer(),
                                       nowPlaying: MockNowPlayingPublisher(),
                                       library: library)
        playback.play(kept, in: [kept, gone])
        XCTAssertEqual(playback.queue.count, 2)

        _ = try DuplicateSweep.run(context: context) { playback.handleTrackDeleted($0) }

        XCTAssertEqual(playback.queue.map(\.id), [keptID],
                       "Hàng bị gộp đi phải rời hàng đợi trong bộ nhớ, không chỉ rời cơ sở dữ liệu.")
    }

    /// `JamendoLibraryService.unsave` xoá file bìa cùng với hàng; lượt quét đi
    /// vòng qua nó, nên trước bản sửa này **mỗi** hàng Jamendo bị gộp để lại
    /// vĩnh viễn một JPEG không còn gì trỏ tới.
    func testAMergedAwayJamendoRowTakesItsDownloadedCoverWithIt() throws {
        let context = try makeContext()
        let folder = FileLocation.artworkFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "sweep-\(UUID().uuidString).jpg"
        let relative = "Artwork/\(name)"
        let url = FileLocation.absoluteURL(forRelative: relative)
        try Data([0xFF, 0xD8]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        let gone = jamendo(goneID, jamendoID: "j1", added: 200, plays: 0)
        gone.artworkRelativePath = relative
        context.insert(gone)
        try context.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        _ = try DuplicateSweep.run(context: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "File bìa của hàng bị gộp phải đi theo hàng, như `unsave` vẫn làm.")
    }

    // MARK: - Trình tự lúc khởi động, và thứ không test được

    /// **Ghim kết quả, KHÔNG ghim thứ tự.** Test này tự gọi lượt quét rồi tự
    /// gọi khôi phục, theo đúng trình tự `EvenstarApp` chạy lúc mở app, và
    /// khẳng định kết quả *khi đã có* trình tự ấy. Nó **không** kiểm chuyện
    /// `EvenstarApp` có thật sự chạy hai việc theo trình tự ấy hay không: đổi
    /// chỗ gọi về hai `.task` anh em thì test này vẫn xanh.
    ///
    /// Và không có test nào làm được chuyện đó. SwiftUI không cho quan sát thứ
    /// tự của hai `.task`, nên **thứ tự ấy hiện không được test nào canh** —
    /// thứ duy nhất giữ nó là ghi chú dài ở chỗ gọi trong `EvenstarApp`. Ai
    /// định dọn chỗ ấy cho app mở nhanh hơn thì phải đọc ghi chú kia, vì bó
    /// test sẽ không kêu.
    ///
    /// Cái nó ghim thật, trên đúng ca xấu nhất: hàng bị gộp đi là bài **đang
    /// phát**, nằm **cuối** hàng đợi, repeat **tắt**. Chạy khôi phục trước thì
    /// hàng đợi trong bộ nhớ giữ hàng sắp chết, lượt quét báo qua
    /// `handleTrackDeleted`, chỗ ấy rơi vào `queueIndex >= queue.count`, gọi
    /// `stopPlayback()` và ghi đè `PlaybackState` bằng hàng đợi rỗng — người
    /// dùng mất sạch hàng đợi lẫn vị trí đang nghe. Chạy quét trước thì
    /// `PlaybackState` đã được trỏ lại xong lúc khôi phục đọc nó, nên bài ấy
    /// quay lại dưới `id` của hàng được giữ, và đó là thứ bốn khẳng định dưới
    /// đây đo.
    func testQuetRoiKhoiPhucGiuNguyenHangDoiVaViTri() async throws {
        let context = try makeContext()
        let library = LibraryService(context: context)

        let keptID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let goneID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        context.insert(jamendo(keptID, jamendoID: "j1", added: 100, plays: 0))
        context.insert(jamendo(goneID, jamendoID: "j1", added: 200, plays: 0))

        // Hàng đợi đã lưu ở phiên trước: đúng một bài, và nó là hàng sắp bị gộp
        // đi. `queueIndex = 0` trên một mảng một phần tử là "đang phát, và là
        // bài cuối" — nhánh mà `handleTrackDeleted` dừng nhạc.
        let state = library.playbackState
        state.queueTrackIDs = [goneID]
        state.unshuffledQueueTrackIDs = [goneID]
        state.queueIndex = 0
        state.currentTrackID = goneID
        state.positionSeconds = 42
        state.repeatModeRaw = RepeatMode.off.rawValue
        try library.save()

        let playback = PlaybackService(player: MockAudioPlayer(),
                                       nowPlaying: MockNowPlayingPublisher(),
                                       library: library)

        // Đúng thứ tự của `EvenstarApp.task`.
        _ = try DuplicateSweep.run(context: context) { playback.handleTrackDeleted($0) }
        await playback.restoreFromPersistedState()

        XCTAssertEqual(playback.queue.map(\.id), [keptID],
                       "Hàng đợi phải sống sót, trỏ sang hàng được giữ.")
        XCTAssertEqual(playback.currentTrack?.id, keptID)
        XCTAssertEqual(playback.position, 42, accuracy: 0.001,
                       "Vị trí đang nghe phải còn nguyên.")
        XCTAssertEqual(library.playbackState.queueTrackIDs, [keptID],
                       "Và hàng đã lưu cũng vậy — không bị ghi đè bằng mảng rỗng.")
    }
}
