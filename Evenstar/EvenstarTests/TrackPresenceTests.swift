import XCTest
@testable import Evenstar

/// Bài nào thật sự có file trên máy này.
///
/// Nền của cả nhóm test: CloudKit đồng bộ *hàng dữ liệu* chứ không đồng bộ
/// *file nhạc*. Nên một máy nhận về hàng mô tả bài nó không có, và phải nói ra
/// điều đó thay vì chạm vào rồi im lặng không phát.
final class TrackPresenceTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("presence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func touch(_ name: String) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    /// Tập trả về phải cùng dạng với `Track.relativePath` thì mới so thẳng
    /// được — `ImportService` dựng `"Music/\(id.uuidString).\(ext)"`.
    func testScanReportsPathsInTheSameShapeAsRelativePath() throws {
        try touch("a.mp3")
        try touch("b.flac")
        XCTAssertEqual(TrackPresence.scan(musicFolder: folder),
                       .known(["Music/a.mp3", "Music/b.flac"]))
    }

    /// Người dùng chưa nhập bài nào thì thư mục `Music/` chưa tồn tại. Đó là
    /// trạng thái bình thường của một bản cài mới, không phải lỗi — trả tập
    /// rỗng chứ không ném, và **rỗng thật** chứ không phải "không biết".
    func testAMissingFolderIsAKnownEmptySetRatherThanAnError() {
        let missing = folder.appendingPathComponent("không-có-thật", isDirectory: true)
        XCTAssertEqual(TrackPresence.scan(musicFolder: missing), .known([]))
    }

    func testAnEmptyFolderIsAKnownEmptySet() {
        XCTAssertEqual(TrackPresence.scan(musicFolder: folder), .known([]))
    }

    /// **Nhánh thứ hai, và là cả lý do `Snapshot` tồn tại.** Một lỗi đọc
    /// **không phải** "thư mục chưa có" không được trả về tập rỗng: tập rỗng
    /// nghĩa là mọi hàng mờ đi, mọi cú chạm bị từ chối, và mọi lệnh xoá bật
    /// cảnh báo "gỡ khỏi mọi máy" — cho một thư viện mà file đang nằm trên đĩa.
    /// Và `LibraryStore` giữ tập ấy cho tới khi tập hàng đổi, mà tập hàng thì
    /// không đổi được vì không phát và không nhập được nữa.
    ///
    /// Ca dựng ở đây là một đường dẫn tồn tại nhưng **không phải thư mục** —
    /// `NSCocoaErrorDomain` 256, không phải 260. Nó tất định trên mọi máy, khác
    /// với chmod 000 vốn phụ thuộc vào quyền của tiến trình chạy test.
    func testAnUnexpectedReadErrorFailsOpenRatherThanReportingAnEmptyLibrary() throws {
        let notADirectory = folder.appendingPathComponent("tôi-là-file")
        try Data().write(to: notADirectory)

        let snapshot = TrackPresence.scan(musicFolder: notADirectory)

        XCTAssertEqual(snapshot, .unreadable)
        XCTAssertTrue(TrackPresence.isPresent("Music/bất-kỳ.mp3", in: snapshot),
                      "Mở khoá: coi như mọi bài đều có, để `AVAudioPlayer` phân xử.")
        XCTAssertEqual(TrackPresence.deleteAction(
            isPresent: TrackPresence.isPresent("Music/bất-kỳ.mp3", in: snapshot)
        ), .deleteNow, "Và không được hỏi lại — cảnh báo sai mỗi lần xoá là chỗ đau nhất.")
    }

    func testAPathIsPresentOnlyWhenTheScanFoundIt() {
        let present = TrackPresence.Snapshot.known(["Music/a.mp3"])
        XCTAssertTrue(TrackPresence.isPresent("Music/a.mp3", in: present))
        XCTAssertFalse(TrackPresence.isPresent("Music/b.mp3", in: present))
        XCTAssertFalse(TrackPresence.isPresent("Music/a.mp3", in: .known([])))
    }

    // MARK: - isOnDisk(_:musicFolder:)

    /// Một lệnh `stat` cho một bài, dùng ở đường nhập — xem
    /// `LibraryStore.replace(with:)`.
    func testIsOnDiskAnswersForASingleFileWithoutReadingTheFolder() throws {
        try touch("a.mp3")
        XCTAssertTrue(TrackPresence.isOnDisk("Music/a.mp3", musicFolder: folder))
        XCTAssertFalse(TrackPresence.isOnDisk("Music/b.mp3", musicFolder: folder))
    }

    /// Phải trả lời **giống** `scan`: `scan` chỉ sinh khoá dạng `"Music/<tên>"`,
    /// nên đường dẫn khác dạng cũng không bao giờ nằm trong tập nó trả về.
    func testIsOnDiskRejectsPathsThatScanCouldNeverProduce() throws {
        try touch("a.mp3")
        XCTAssertFalse(TrackPresence.isOnDisk("a.mp3", musicFolder: folder))
        XCTAssertFalse(TrackPresence.isOnDisk("Music/", musicFolder: folder))
        XCTAssertFalse(TrackPresence.isOnDisk("Music/sub/a.mp3", musicFolder: folder))
    }

    /// Xoá một bài **có mặt** là chuyện thường ngày và không được hỏi lại —
    /// hỏi lại mọi lần làm người dùng bấm qua mà không đọc, và đúng lúc lời
    /// cảnh báo quan trọng thì họ cũng bấm qua nốt.
    func testDeletingAPresentTrackAsksNothing() {
        XCTAssertEqual(TrackPresence.deleteAction(isPresent: true), .deleteNow)
    }

    /// Xoá một bài **vắng mặt** trông như dọn một hàng rác, nhưng nó gỡ bài
    /// khỏi **mọi máy**, kể cả máy đang giữ file thật. Đó là chỗ duy nhất trong
    /// app mà một thao tác nhỏ có hậu quả trên máy khác.
    func testDeletingAnAbsentTrackMustBeConfirmed() {
        XCTAssertEqual(TrackPresence.deleteAction(isPresent: false), .confirmFirst)
    }
}
