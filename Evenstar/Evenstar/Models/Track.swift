import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artistName: String
    var albumTitle: String
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double
    var relativePath: String
    var artworkRelativePath: String?
    var format: String
    var sampleRate: Int?
    var bitDepth: Int?
    var dateAdded: Date
    var playCount: Int
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
