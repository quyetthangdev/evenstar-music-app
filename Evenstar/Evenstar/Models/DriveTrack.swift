import Foundation
import SwiftData

/// One audio file inside a linked `DriveFolder`.
///
/// Deliberately not a variant of `Track`. Sharing that model would be cheaper
/// in the playback layer but would force every existing `@Query` to grow a
/// filter, and missing one would leak Drive rows into the local library. Two
/// models make the compiler enforce the split instead of a reviewer.
///
/// **Mọi lượt quét lại phải fetch theo `fileID` rồi sửa tại chỗ — không bao giờ
/// dựng một `DriveTrack(fileID:...)` mới và insert cho một `fileID` có thể đã
/// tồn tại.** Trước đây `@Attribute(.unique)` giữ số hàng ở một dù làm cách nào;
/// **ràng buộc ấy đã bị bỏ** vì CloudKit không chấp nhận nó, nên giờ một lượt
/// insert lặp lại thực sự sinh ra hàng thứ hai.
///
/// Kể cả khi còn `unique` thì cách ấy vẫn sai: khi va chạm, chính `id` chứ
/// không phải người gọi quyết định hàng sống sót mang `id` nào, và nó không
/// nhất thiết là `id` gốc. `PlaybackState` giữ thành viên hàng đợi bằng `UUID`
/// trần không có quan hệ ngược, nên không ai nối lại hộ khi một hàng đổi `id` —
/// hàng đợi khôi phục xong mất bài trong im lặng. Xem
/// `DriveModelTests.testTwoRawInsertsForOneFileIDNowProduceTwoRows` cho hành
/// vi ở tầng model, và `DriveLibraryServiceTests
/// .testScanningASecondFolderWithAnAlreadyKnownFileIDKeepsTheOriginalRow` cho
/// nơi ràng buộc thật sự được giữ.
@Model
final class DriveTrack {
    /// What `PlaybackState` persists to identify a queued track. Distinct
    /// from `fileID`, which is Google's.
    ///
    /// *Not* stable across a `fileID` collision — see the type-level doc
    /// comment. Only stable if every reconcile fetches the existing row by
    /// `fileID` and mutates it, rather than reconstructing and inserting.
    /// Không còn ràng buộc duy nhất nào ở đây, và mặc định là bắt buộc — xem
    /// ghi chú tương ứng trong `Track`.
    var id: UUID = UUID()
    var fileID: String = ""
    var folderID: String = ""
    var fileName: String = ""
    var title: String = ""
    /// Stored optional, because "not read yet" is real and distinct from
    /// "read, and the file has no artist tag". `Playable` exposes non-optional
    /// `artistName`/`albumTitle` computed from these — see `Playable.swift`.
    var artistNameOrNil: String?
    var albumTitleOrNil: String?
    /// 0 until `metadataResolved`. Not optional: `Playable` needs a number, and
    /// two ways to say "unknown" in one row is one too many.
    var durationSeconds: Double = 0
    /// False until the track has been played once and its real tags read over
    /// the network. Scanning deliberately does not read tags — see the spec.
    var metadataResolved: Bool = false
    var dateAdded: Date = Date.now
    var playCount: Int = 0
    var lastPlayedAt: Date?

    init(id: UUID = UUID(),
         fileID: String,
         folderID: String,
         fileName: String,
         title: String? = nil,
         artistName: String? = nil,
         albumTitle: String? = nil,
         durationSeconds: Double = 0,
         metadataResolved: Bool = false,
         dateAdded: Date = .now,
         playCount: Int = 0,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.fileID = fileID
        self.folderID = folderID
        self.fileName = fileName
        self.title = title ?? Self.titleFromFileName(fileName)
        self.artistNameOrNil = artistName
        self.albumTitleOrNil = albumTitle
        self.durationSeconds = durationSeconds
        self.metadataResolved = metadataResolved
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }

    /// `(NSString as NSString).deletingPathExtension` rather than splitting on
    /// ".", so a title containing a dot keeps it.
    static func titleFromFileName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}
