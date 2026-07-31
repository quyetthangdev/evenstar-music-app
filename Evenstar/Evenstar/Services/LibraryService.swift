import Foundation
import SwiftData
import Observation

enum LibraryError: LocalizedError {
    case persistenceFailed(underlying: Error)
    case fileDeleteFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let error):
            return "Couldn't save changes: \(error.localizedDescription)"
        case .fileDeleteFailed(let url, let error):
            return "Couldn't delete file \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

@Observable
@MainActor
final class LibraryService {
    let context: ModelContext
    private let fileManager: FileManager

    init(context: ModelContext, fileManager: FileManager = .default) {
        self.context = context
        self.fileManager = fileManager
    }

    // MARK: - Track CRUD

    func insert(_ track: Track) throws {
        context.insert(track)
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }

    func delete(_ track: Track) throws {
        let audioURL = FileLocation.absoluteURL(forRelative: track.relativePath, fileManager: fileManager)
        try? fileManager.removeItem(at: audioURL)
        if let artworkPath = track.artworkRelativePath {
            let artworkURL = FileLocation.absoluteURL(forRelative: artworkPath, fileManager: fileManager)
            try? fileManager.removeItem(at: artworkURL)
        }
        context.delete(track)
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }

    func fetchAllTracks(sortedByTitle: Bool = true) throws -> [Track] {
        var descriptor = FetchDescriptor<Track>()
        if sortedByTitle {
            descriptor.sortBy = [SortDescriptor(\Track.title, comparator: .localizedStandard)]
        }
        return try context.fetch(descriptor)
    }

    func findTrack(byID id: UUID) throws -> Track? {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func findExistingTrack(title: String, artist: String, duration: Double) throws -> Track? {
        // SwiftData #Predicate has limited string + math support; do the work in Swift
        // after fetching candidates with the same rounded duration.
        let rounded = duration.rounded()
        let descriptor = FetchDescriptor<Track>()
        let candidates = try context.fetch(descriptor)
        let titleLower = title.lowercased()
        let artistLower = artist.lowercased()
        return candidates.first { t in
            t.title.lowercased() == titleLower
                && t.artistName.lowercased() == artistLower
                && t.durationSeconds.rounded() == rounded
        }
    }

    // MARK: - PlaybackState singleton

    var playbackState: PlaybackState {
        let descriptor = FetchDescriptor<PlaybackState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let newState = PlaybackState()
        context.insert(newState)
        try? context.save()
        return newState
    }

    func savePlaybackState() throws {
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }
}
