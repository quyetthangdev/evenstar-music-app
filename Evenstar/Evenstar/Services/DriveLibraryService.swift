import Foundation
import Observation
import SwiftData

/// Turns what `DriveClient` sees on Drive into rows in SwiftData.
///
/// The split matters: `DriveClient` is testable without a database and this is
/// testable without a network, and neither has to know how the other fails.
@Observable
@MainActor
final class DriveLibraryService {
    private let library: LibraryService
    private let client: DriveClient

    /// Non-nil while a scan is running, so the list can show progress. Reset in
    /// a `defer` so a thrown error cannot leave a spinner on screen forever.
    private(set) var scanningFolderID: String?
    private(set) var scannedFileCount: Int = 0

    init(library: LibraryService, client: DriveClient = DriveClient()) {
        self.library = library
        self.client = client
    }

    func link(folderID: String, displayName: String) throws -> DriveFolder {
        let folder = DriveFolder(folderID: folderID, displayName: displayName)
        library.context.insert(folder)
        try library.save()
        return folder
    }

    /// Reconciles the folder's rows with what Drive currently holds, and
    /// returns how many tracks it has afterwards.
    ///
    /// Nothing is written until the listing has arrived in full: a scan that
    /// throws leaves the existing rows exactly as they were, so losing signal
    /// mid-scan does not empty a user's list.
    @discardableResult
    func scan(_ folder: DriveFolder) async throws -> Int {
        scanningFolderID = folder.folderID
        scannedFileCount = 0
        defer { scanningFolderID = nil }

        let files = try await client.listAudioFiles(inFolder: folder.folderID)
        scannedFileCount = files.count

        let folderID = folder.folderID
        let existingInFolder = try library.context.fetch(
            FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.folderID == folderID })
        )
        let liveFileIDs = Set(files.map(\.id))

        // The insertion guard is deliberately store-wide, not folder-scoped:
        // `DriveTrack.fileID` carries `@Attribute(.unique)` across every linked
        // folder, because Drive supports multi-parent files — the same file
        // can be a direct child of two folders the user links separately. A
        // folder-scoped existence check would miss a `fileID` already known
        // under a *different* folder and construct-and-insert a second row
        // for it; SwiftData's uniqueness constraint then collapses the two
        // rows down to one, but hands the survivor a freshly minted `id`,
        // silently orphaning anything (e.g. a saved queue) that referenced
        // the original `id`. See `DriveTrack.swift`'s type-level doc comment.
        let existingAnywhere = try library.context.fetch(FetchDescriptor<DriveTrack>())
        let existingByFileIDAnywhere = Dictionary(uniqueKeysWithValues: existingAnywhere.map { ($0.fileID, $0) })

        // When a file already has a row under a different folder, that row is
        // left exactly as it is — not retagged to this folder. One
        // `DriveTrack` cannot represent membership in two folders at once
        // (there is a single `folderID` field, not a set), so there is no
        // representation of "also in this folder" to retag it to; the only
        // choice that never constructs-and-inserts for a known `fileID` is to
        // leave the existing row where it is. This does mean a file's row
        // "belongs" to whichever folder happened to scan it first, and
        // unlinking that folder deletes it even if the file is still visible
        // through a second linked folder — an accepted limitation, not a bug,
        // given `folderID` is a single value.
        for file in files where existingByFileIDAnywhere[file.id] == nil {
            library.context.insert(
                DriveTrack(fileID: file.id, folderID: folderID, fileName: file.name)
            )
        }

        // The deletion loop, in contrast, stays folder-scoped: a file leaving
        // this folder must not delete its row while the same `fileID` is
        // still live under a different linked folder.
        for row in existingInFolder where !liveFileIDs.contains(row.fileID) {
            library.context.delete(row)
        }

        folder.lastScannedAt = .now
        try library.save()
        return files.count
    }

    func unlink(_ folder: DriveFolder) throws {
        let folderID = folder.folderID
        let tracks = try library.context.fetch(
            FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.folderID == folderID })
        )
        for track in tracks { library.context.delete(track) }
        library.context.delete(folder)
        try library.save()
    }
}
