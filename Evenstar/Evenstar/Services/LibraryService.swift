import Foundation
import SwiftData
import Observation

enum LibraryError: LocalizedError {
    case persistenceFailed(underlying: Error)
    case artworkWriteFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let error):
            return "Không lưu được thay đổi: \(error.localizedDescription)"
        case .artworkWriteFailed(let error):
            return "Không lưu được ảnh bìa: \(error.localizedDescription)"
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
        // Filesystem cleanup failures are deliberately ignored. The user's intent is to remove
        // the track from the library database, which must always succeed. If files are already
        // missing or inaccessible, the track record is still cleared; polished error reporting
        // for orphaned files is a Phase 2d concern. This best-effort approach ensures the DB
        // is never blocked by filesystem state.
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

    /// Replaces a track's cover with an image the user picked.
    ///
    /// **Writes to a fresh filename every time, and never overwrites the old
    /// one.** That is not tidiness, it is the whole correctness of the feature:
    /// `ArtworkStore` caches decoded images under `path@pixelSize`, so writing
    /// new bytes to the *same* relative path leaves every cached size still
    /// serving the previous picture. The user would pick an image, see nothing
    /// change, and pick again. A new UUID makes a new key, so the change is
    /// visible on the next render with no cache to invalidate.
    ///
    /// Order matters in the failure paths, and both directions were considered:
    ///
    ///   - the old file is removed only *after* `save()` succeeds, so a failed
    ///     save leaves the track pointing at artwork that still exists rather
    ///     than at a hole;
    ///   - the new file is removed *if* `save()` fails, so a rejected write
    ///     does not leave an orphan in `Artwork/` that nothing references and
    ///     `delete(_:)` will never clean up.
    ///
    /// Removing the old file is best-effort, matching `delete(_:)`: the user's
    /// intent is the new cover, and a stale file left on disk must not fail an
    /// operation that has already succeeded.
    @discardableResult
    func setArtwork(_ jpegData: Data, for track: Track) throws -> String {
        let folder = FileLocation.artworkFolderURL(fileManager)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let previous = track.artworkRelativePath
        let relative = "Artwork/\(UUID().uuidString).jpg"
        let url = FileLocation.absoluteURL(forRelative: relative, fileManager: fileManager)
        do { try jpegData.write(to: url) }
        catch { throw LibraryError.artworkWriteFailed(underlying: error) }

        track.artworkRelativePath = relative
        do { try context.save() }
        catch {
            try? fileManager.removeItem(at: url)
            throw LibraryError.persistenceFailed(underlying: error)
        }

        if let previous, previous != relative {
            let oldURL = FileLocation.absoluteURL(forRelative: previous, fileManager: fileManager)
            try? fileManager.removeItem(at: oldURL)
        }
        return relative
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

    /// The Drive half of session restore. `PlaybackState` stores bare `UUID`s
    /// with no note of which table they came from, so restoring a mixed queue
    /// has to ask both.
    func findDriveTrack(byID id: UUID) throws -> DriveTrack? {
        var descriptor = FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
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

    /// Commits all pending changes in the shared `ModelContext` — not only
    /// `PlaybackState` edits. `Track` and `PlaybackState` share one context,
    /// so this also persists things like `Track.playCount` and
    /// `Track.lastPlayedAt` mutations made elsewhere (e.g. `PlaybackService`).
    func save() throws {
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }
}
