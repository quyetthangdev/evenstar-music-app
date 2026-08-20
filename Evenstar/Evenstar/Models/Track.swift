import Foundation
import SwiftData

@Model
final class Track {
    /// Mọi thuộc tính dưới đây hoặc optional hoặc mang giá trị mặc định, và
    /// **không được bỏ mặc định đi**: CloudKit đọc bản ghi do máy khác ghi, kể
    /// cả bản ghi cũ chưa có cột này, và một cột không-optional không mặc định
    /// là một bản ghi không giải mã được. Cùng lý do bốn thuộc tính của
    /// `PlaybackState` đã mang mặc định từ trước.
    ///
    /// Ràng buộc này được ghim bởi `ModelCloudKitConformanceTests`.
    var id: UUID = UUID()
    var title: String = ""
    var artistName: String = ""
    var albumTitle: String = ""
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double = 0
    var relativePath: String = ""
    var artworkRelativePath: String?
    var format: String = ""
    var sampleRate: Int?
    var bitDepth: Int?
    var dateAdded: Date = Date.now
    var playCount: Int = 0
    var lastPlayedAt: Date?

    init(id: UUID = UUID(),
         title: String,
         artistName: String,
         albumTitle: String,
         trackNumber: Int? = nil,
         discNumber: Int? = nil,
         durationSeconds: Double,
         relativePath: String,
         artworkRelativePath: String? = nil,
         format: String,
         sampleRate: Int? = nil,
         bitDepth: Int? = nil,
         dateAdded: Date = .now,
         playCount: Int = 0,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.durationSeconds = durationSeconds
        self.relativePath = relativePath
        self.artworkRelativePath = artworkRelativePath
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }
}
