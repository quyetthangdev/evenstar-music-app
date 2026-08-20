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
        XCTAssertEqual(TrackPresence.scan(musicFolder: folder), ["Music/a.mp3", "Music/b.flac"])
    }

    /// Người dùng chưa nhập bài nào thì thư mục `Music/` chưa tồn tại. Đó là
    /// trạng thái bình thường của một bản cài mới, không phải lỗi — trả tập
    /// rỗng chứ không ném.
    func testAMissingFolderIsAnEmptySetRatherThanAnError() {
        let missing = folder.appendingPathComponent("không-có-thật", isDirectory: true)
        XCTAssertEqual(TrackPresence.scan(musicFolder: missing), [])
    }

    func testAnEmptyFolderIsAnEmptySet() {
        XCTAssertEqual(TrackPresence.scan(musicFolder: folder), [])
    }

    func testAPathIsPresentOnlyWhenTheScanFoundIt() {
        let present: Set<String> = ["Music/a.mp3"]
        XCTAssertTrue(TrackPresence.isPresent("Music/a.mp3", in: present))
        XCTAssertFalse(TrackPresence.isPresent("Music/b.mp3", in: present))
        XCTAssertFalse(TrackPresence.isPresent("Music/a.mp3", in: []))
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
