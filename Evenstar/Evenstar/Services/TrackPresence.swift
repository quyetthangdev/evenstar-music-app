import Foundation

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

    /// Một lượt đọc thư mục cho cả thư viện, không phải một `fileExists` cho
    /// mỗi hàng. Với một thư viện vài nghìn bài, cái sau là vài nghìn syscall
    /// trên luồng chính.
    ///
    /// Không đệ quy, vì `ImportService` để mọi file phẳng trong `Music/`.
    ///
    /// Thư mục chưa tồn tại trả tập rỗng chứ không ném: đó là trạng thái bình
    /// thường của một bản cài chưa nhập bài nào.
    ///
    /// - Parameter musicFolder: tham số hoá để test được với một thư mục tạm.
    static func scan(musicFolder: URL = FileLocation.musicFolderURL()) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: musicFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return Set(contents.map { musicPrefix + $0.lastPathComponent })
    }

    static func isPresent(_ relativePath: String, in present: Set<String>) -> Bool {
        present.contains(relativePath)
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
