import Foundation
import SwiftData
@testable import Evenstar

@MainActor
enum InMemoryLibrary {
    static func make() throws -> LibraryService {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self,
            configurations: config
        )
        return LibraryService(context: ModelContext(container))
    }

    static func makeTrack(title: String = "Sample",
                          artistName: String = "Unknown Artist",
                          albumTitle: String = "Unknown Album",
                          durationSeconds: Double = 180,
                          relativePath: String = "Music/sample.mp3",
                          artworkRelativePath: String? = nil,
                          format: String = "mp3") -> Track {
        Track(
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            durationSeconds: durationSeconds,
            relativePath: relativePath,
            artworkRelativePath: artworkRelativePath,
            format: format
        )
    }
}
