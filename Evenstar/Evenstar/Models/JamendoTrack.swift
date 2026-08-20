import Foundation
import SwiftData

/// A Jamendo track the user saved.
///
/// Stores what the catalogue returned **at save time**. Rendering a row never
/// re-queries: a library that needs the network to draw itself is not a library.
///
/// **Không còn ràng buộc duy nhất nào trên bảng này** — CloudKit không chấp
/// nhận ràng buộc duy nhất (`unique`). Trước đây nó cũng chưa bao giờ là hàng rào thật:
/// khi va chạm, SwiftData upsert, và `id` của hàng sống sót *không nhất thiết*
/// là `id` gốc. `PlaybackState` giữ thành viên hàng đợi bằng `UUID` trần không
/// có quan hệ ngược, nên một hàng đổi `id` làm hàng đợi mất bài trong im lặng.
///
/// Thứ chống trùng thật là `JamendoLibraryService.inFlightSaves`, gom mọi
/// `save()` đồng thời cho cùng một `jamendoID` về một `Task` duy nhất. Nó từng
/// là dây an toàn thứ hai; **giờ nó là dây duy nhất**, nên đừng gỡ.
///
/// Ca mà `inFlightSaves` không với tới là hai máy cùng lưu một bài khi ngoại
/// tuyến — không có `Task` chung để gom. Đó là việc của `DuplicateSweep`.
@Model
final class JamendoTrack {
    /// Không còn ràng buộc duy nhất nào ở đây, và mặc định là bắt buộc — xem
    /// ghi chú tương ứng trong `Track`.
    var id: UUID = UUID()
    var jamendoID: String = ""
    var title: String = ""
    var artistName: String = ""
    var albumTitle: String = ""
    var durationSeconds: Double = 0
    var audioURLString: String = ""
    /// The licence this track is offered under. Shown to the user — CC-BY
    /// obliges visible credit — and `nil` only when the catalogue omitted it.
    var licenceURLString: String?
    /// The track's page on Jamendo, for the attribution link.
    var shareURLString: String?
    /// Documents-relative, downloaded when the track was saved. See
    /// `JamendoLibraryService.save`.
    var artworkRelativePath: String?
    var dateAdded: Date = Date()
    var playCount: Int = 0
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        jamendoID: String,
        title: String,
        artistName: String,
        albumTitle: String,
        durationSeconds: Double,
        audioURLString: String,
        licenceURLString: String? = nil,
        shareURLString: String? = nil,
        artworkRelativePath: String? = nil,
        dateAdded: Date = Date(),
        playCount: Int = 0,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.jamendoID = jamendoID
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.durationSeconds = durationSeconds
        self.audioURLString = audioURLString
        self.licenceURLString = licenceURLString
        self.shareURLString = shareURLString
        self.artworkRelativePath = artworkRelativePath
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }

    convenience init(from track: JamendoCatalogueTrack, artworkRelativePath: String?) {
        self.init(
            jamendoID: track.id,
            title: track.title,
            artistName: track.artistName,
            albumTitle: track.albumTitle,
            durationSeconds: track.durationSeconds,
            audioURLString: track.audioURL.absoluteString,
            licenceURLString: track.licenceURL?.absoluteString,
            shareURLString: track.shareURL?.absoluteString,
            artworkRelativePath: artworkRelativePath
        )
    }
}
