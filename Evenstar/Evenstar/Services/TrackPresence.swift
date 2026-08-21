import Foundation
import OSLog

/// Bài nào thật sự có file trên **máy này**.
///
/// ─────────────────────────────────────────────────────────────────────────
/// VÌ SAO KHÔNG PHẢI MỘT THUỘC TÍNH CỦA `@Model`
/// ─────────────────────────────────────────────────────────────────────────
/// Sự có mặt của file là thuộc tính của **máy**, không phải của bài. Lưu nó vào
/// `Track` là sai ngay từ định nghĩa: máy A ghi `true`, CloudKit đồng bộ sang
/// máy B, và B đọc `true` cho một file nó không hề có.
///
/// Nên nó được tính tại chỗ, không lưu, và không bao giờ đi qua CloudKit.
///
/// Chỉ áp cho `Track`. `DriveTrack` và `JamendoTrack` là URL mạng — chúng không
/// có khái niệm "có trên máy này".
enum TrackPresence {

    /// Mọi `Track.relativePath` bắt đầu bằng đúng chuỗi này: `ImportService`
    /// dựng `"Music/\(id.uuidString).\(ext)"`. Tập trả về phải cùng dạng thì
    /// mới so thẳng được với `relativePath` mà không phải cắt gọt hai đầu.
    private static let musicPrefix = "Music/"

    /// Kết quả một lượt quét — và **hai ca này không được gộp làm một**.
    ///
    /// Bản đầu tiên của `scan` dùng `try?` rồi `?? []`, nghĩa là mọi lỗi đọc
    /// đều thành "không có bài nào trên máy này". Hậu quả của một tập rỗng sai:
    /// mọi hàng mờ đi, mọi cú chạm bị từ chối, và mọi lệnh xoá bật cảnh báo
    /// "gỡ khỏi mọi máy" — cho một thư viện mà file **đang nằm trên đĩa**.
    /// `LibraryStore` giữ tập rỗng ấy cho tới khi tập hàng đổi, mà tập hàng thì
    /// không đổi được vì người dùng không phát và không nhập được từ một màn
    /// hình đang từ chối mọi cú chạm. Một lỗi đọc thoáng qua khoá cứng thư viện.
    ///
    /// Ca ấy dễ chạm tới hơn kể từ Task 9: Background Modes → remote
    /// notifications cho phép app khởi động **ngầm** khi CloudKit đẩy dữ liệu
    /// xuống, kể cả trước lần mở khoá đầu tiên sau khi khởi động lại máy — đúng
    /// lúc một lượt đọc file có bảo vệ dữ liệu có thể thất bại.
    enum Snapshot: Equatable {
        /// Đọc được thư mục. Đây là đúng tập file đang có trên máy này.
        case known(Set<String>)
        /// Không đọc được vì một lý do **bất ngờ** — không phải "thư mục chưa
        /// tồn tại", ca đó là `.known([])`.
        ///
        /// Người đọc phải **mở khoá**: coi như mọi bài đều có, và để
        /// `AVAudioPlayer` phân xử khi thật sự phát. Vòng bỏ-qua trong
        /// `PlaybackService.loadCurrentAndPlay()` đã được ghim bởi
        /// `AbsentTrackPlaybackTests`, nên mở khoá tụt về đúng hành vi trước
        /// CloudKit chứ không phải về một thư viện hỏng.
        case unreadable
    }

    /// Một lượt đọc thư mục cho cả thư viện, không phải một `fileExists` cho
    /// mỗi hàng. Với một thư viện vài nghìn bài, cái sau là vài nghìn syscall
    /// trên luồng chính.
    ///
    /// Không đệ quy, vì `ImportService` để mọi file phẳng trong `Music/`.
    ///
    /// **Thư mục chưa tồn tại là `.known([])`, mọi lỗi khác là `.unreadable`.**
    /// Ca đầu là trạng thái bình thường của một bản cài chưa nhập bài nào —
    /// rỗng thật, và trả lời "không có bài nào" là đúng. Ca sau không biết gì
    /// cả, và nói "không có bài nào" khi không biết là chỗ hỏng mà `Snapshot`
    /// được dựng ra để chặn.
    ///
    /// **Đây là chỗ đảo lại một phán quyết cũ trong chính đợt này.** Bản trước
    /// lập luận "fail-closed mới đúng ở đây": thà mờ nhầm một bài có thật còn
    /// hơn mời người dùng chạm vào một bài không phát được. Cái nhìn toàn nhánh
    /// đổi kết luận, và lý do nằm ở chỗ **hậu quả không đối xứng**: mở khoá
    /// nhầm thì người dùng chạm vào một bài rồi vòng bỏ-qua đi tiếp — đúng hành
    /// vi app đã có từ trước CloudKit. Khoá nhầm thì cả thư viện chết cứng và
    /// không có thao tác nào trong app gỡ ra được. Đừng lật lại lần nữa.
    ///
    /// - Parameter musicFolder: tham số hoá để test được với một thư mục tạm.
    static func scan(musicFolder: URL = FileLocation.musicFolderURL()) -> Snapshot {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: musicFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return .known(Set(contents.map { musicPrefix + $0.lastPathComponent }))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Bản cài chưa nhập bài nào. Rỗng, và rỗng là câu trả lời đúng.
            return .known([])
        } catch {
            // Ghi log chứ không im lặng: `.unreadable` không nhìn thấy được
            // trên màn hình (mọi thứ trông như bình thường), nên dòng log này
            // là dấu vết duy nhất còn lại.
            AppLog.library.error(
                "Không đọc được thư mục nhạc, coi như mọi bài đều có: \(error.localizedDescription, privacy: .public)"
            )
            return .unreadable
        }
    }

    /// `.unreadable` trả `true` cho mọi đường dẫn — xem `Snapshot.unreadable`.
    static func isPresent(_ relativePath: String, in snapshot: Snapshot) -> Bool {
        switch snapshot {
        case .known(let present): return present.contains(relativePath)
        case .unreadable: return true
        }
    }

    /// File của **một** bài có nằm trong `musicFolder` không — một lệnh `stat`,
    /// không phải một lượt đọc cả thư mục.
    ///
    /// Sinh ra cho `LibraryStore.replace(with:)`: một bài vừa nhập xong có thể
    /// được thêm vào tập có mặt mà không phải đọc lại cả thư mục. Xem doc
    /// comment ở đó về vì sao đọc lại cả thư mục cho mỗi file nhập là hình dạng
    /// O(N²) mà `LibraryStore` tồn tại để dẹp.
    ///
    /// Trả `false` cho đường dẫn không đúng dạng `"Music/<tên>"`: `scan` chỉ
    /// sinh ra khoá dạng ấy, nên một đường dẫn khác dạng cũng không bao giờ
    /// nằm trong tập nó trả về — hai hàm phải trả lời giống nhau.
    static func isOnDisk(_ relativePath: String,
                         musicFolder: URL = FileLocation.musicFolderURL()) -> Bool {
        guard relativePath.hasPrefix(musicPrefix) else { return false }
        let name = String(relativePath.dropFirst(musicPrefix.count))
        guard !name.isEmpty, !name.contains("/") else { return false }
        return FileManager.default.fileExists(
            atPath: musicFolder.appendingPathComponent(name).path
        )
    }

    /// Xoá bài này có phải hỏi lại không.
    ///
    /// Mỏng, và cố ý mỏng — giá trị nằm ở **tên**, không ở phép tính. Ở chỗ gọi,
    /// `case .confirmFirst` đọc ra là một quyết định; `if !isPresent` đọc ra là
    /// một điều kiện, và điều kiện thì dễ bị đảo ngược trong một lần sửa vội mà
    /// không ai nhận ra.
    enum DeleteAction: Equatable {
        case deleteNow
        case confirmFirst
    }

    /// Xoá một bài vắng mặt trông như dọn một hàng rác, nhưng nó gỡ bài khỏi
    /// **mọi máy** — kể cả máy đang giữ file thật.
    static func deleteAction(isPresent: Bool) -> DeleteAction {
        isPresent ? .deleteNow : .confirmFirst
    }
}
