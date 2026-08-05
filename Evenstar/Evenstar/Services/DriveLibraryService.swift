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
        let existing = try library.context.fetch(
            FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.folderID == folderID })
        )
        let existingByFileID = Dictionary(uniqueKeysWithValues: existing.map { ($0.fileID, $0) })
        let liveFileIDs = Set(files.map(\.id))

        for file in files where existingByFileID[file.id] == nil {
            library.context.insert(
                DriveTrack(fileID: file.id, folderID: folderID, fileName: file.name)
            )
        }
        for row in existing where !liveFileIDs.contains(row.fileID) {
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
