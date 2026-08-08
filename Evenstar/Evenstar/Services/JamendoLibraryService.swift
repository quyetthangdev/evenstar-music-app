import Foundation
import SwiftData
import SwiftUI

/// Saving Jamendo tracks into the library, and taking them out again.
///
/// Mirrors `DriveLibraryService`: it owns the `ModelContext` writes for its
/// source so no view does its own persistence.
@Observable
@MainActor
final class JamendoLibraryService {
    private let library: LibraryService
    private let session: URLSession

    init(library: LibraryService, session: URLSession = .shared) {
        self.library = library
        self.session = session
    }

    /// Downloads the cover, then inserts the row.
    ///
    /// **Dedupe is by Jamendo's id.** A track already saved is returned as-is
    /// rather than inserted a second time — the user re-tapping "save" on
    /// something already in their library must leave one row, not a second
    /// one they then have to delete individually.
    ///
    /// **The cover is fetched before the insert and its failure is swallowed.**
    /// The user asked for the music; losing the picture is not a reason to
    /// refuse them the track. `artworkRelativePath` stays `nil` and every
    /// consumer already handles that — it is the state every Drive track is in.
    @discardableResult
    func save(_ track: JamendoCatalogueTrack) async throws -> JamendoTrack {
        if let existing = try existingRow(jamendoID: track.id) { return existing }

        let artworkPath = await downloadCover(track)
        let row = JamendoTrack(from: track, artworkRelativePath: artworkPath)
        library.context.insert(row)
        try library.save()
        return row
    }

    /// Removes the row and, best-effort, the cover `save` downloaded for it.
    ///
    /// Mirrors `LibraryService.delete(_:)`: filesystem cleanup is `try?`,
    /// deliberately. The user's intent is to remove the track from the
    /// library, which must always succeed even if the artwork file is
    /// already missing or inaccessible — polished error reporting for an
    /// orphaned file is not worth blocking a delete over. Without this the
    /// JPEG `downloadCover` wrote to `Documents/Artwork/` has no path
    /// pointing at it once the row is gone, and every save→unsave cycle
    /// would leave one more unreachable file on the device permanently.
    func unsave(_ track: JamendoTrack) throws {
        if let artworkPath = track.artworkRelativePath {
            try? FileManager.default.removeItem(
                at: FileLocation.absoluteURL(forRelative: artworkPath)
            )
        }
        library.context.delete(track)
        try library.save()
    }

    func isSaved(jamendoID: String) throws -> Bool {
        try existingRow(jamendoID: jamendoID) != nil
    }

    func savedCount() throws -> Int {
        try library.context.fetchCount(FetchDescriptor<JamendoTrack>())
    }

    // MARK: - Private

    private func existingRow(jamendoID: String) throws -> JamendoTrack? {
        var descriptor = FetchDescriptor<JamendoTrack>(
            predicate: #Predicate { $0.jamendoID == jamendoID }
        )
        descriptor.fetchLimit = 1
        return try library.context.fetch(descriptor).first
    }

    /// `nil` on any failure, deliberately. See `save`: a cover the user never
    /// sees is a worse outcome than a save that failed outright would be, but
    /// far better than a save the user never gets because a JPEG did not load.
    private func downloadCover(_ track: JamendoCatalogueTrack) async -> String? {
        guard let url = track.coverURL else { return nil }
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        guard let jpeg = await ArtworkStore.jpegForStorage(from: data) else { return nil }

        let folder = FileLocation.artworkFolderURL()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "jamendo-\(track.id)-\(UUID().uuidString).jpg"
        let destination = folder.appendingPathComponent(name)
        guard (try? jpeg.write(to: destination)) != nil else { return nil }
        return "Artwork/\(name)"
    }
}
