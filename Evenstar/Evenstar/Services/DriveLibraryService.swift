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

    /// Called with each `DriveTrack` this service is about to delete, while the
    /// row is still live.
    ///
    /// **Wired to `PlaybackService.handleTrackDeleted` in `EvenstarApp`, and
    /// without it the two delete paths below corrupt playback.** `queue` and
    /// `currentTrack` hold their rows strongly, so deleting one behind the
    /// service's back leaves the queue pointing at a deleted-and-saved
    /// `PersistentModel`: the 30-second play-count write, the ≤5s
    /// `queue.map(\.id)` persist and a tap on Next all then read a property off
    /// it and raise `NSObjectInaccessibleException` — an Objective-C exception,
    /// uncatchable in Swift. The local library already had this covered;
    /// `SongsView.deleteTrack` calls `handleTrackDeleted` before
    /// `library.delete`, for exactly the same reason.
    ///
    /// A closure rather than a stored `PlaybackService`, so this service stays
    /// testable without one and so the dependency points in a single direction:
    /// `PlaybackService` knows nothing about Drive scanning, and nothing here
    /// retains it beyond what the app already owns.
    ///
    /// Fired **before** `context.delete(_:)` and before the enclosing `save()`,
    /// which is the whole contract: the handler reads `track.id`, and after the
    /// save there is no id left to read.
    /// `@MainActor` on the closure type itself, not merely inherited from the
    /// class: a stored closure's type is independent of its container's
    /// isolation, so without the annotation the handler would be non-isolated
    /// and could not call `PlaybackService`'s main-actor API.
    var onTrackWillBeDeleted: (@MainActor (any Playable) -> Void)?

    init(library: LibraryService, client: DriveClient = DriveClient()) {
        self.library = library
        self.client = client
    }

    /// Fetches an existing folder linked under this `folderID` and reuses it
    /// instead of constructing a second row.
    ///
    /// This check used to live in `DriveFoldersView`, reading its `@Query`
    /// snapshot — the array SwiftUI had assembled for the *last* render pass,
    /// not a live fetch. It worked there only because every call path
    /// happened to force a re-render before a retry read it; that is an
    /// accident of one call site's timing, not a contract, and "do not
    /// double-insert on retry" is business logic that belongs on the service
    /// regardless of which view calls it or when that view last redrew.
    /// Fetching `library.context` directly here is correct no matter what any
    /// view has or has not rendered yet.
    ///
    /// A retyped display name is honored even when the folder is reused,
    /// rather than dropped. Silently keeping the old name would be exactly
    /// the failure `unlink` below is written to avoid: the user retypes a
    /// name, taps Liên kết, the fields clear as if it worked, and the row
    /// still shows the stale name with no signal the edit never landed.
    /// - Parameter displayName: `nil` or blank means the user did not name it.
    ///   For a folder already linked that keeps whatever name it has — blanking
    ///   the field must not wipe a name the user chose earlier, which is what a
    ///   non-optional parameter forced. For a new one it takes
    ///   `defaultDisplayName(existing:)`.
    ///
    ///   The decision lives here rather than in the view because only this
    ///   method knows whether the folder already exists, and the answer differs
    ///   entirely between the two cases.
    func link(folderID: String, displayName: String?) throws -> DriveFolder {
        let chosen = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = try library.context.fetch(
            FetchDescriptor<DriveFolder>(predicate: #Predicate { $0.folderID == folderID })
        ).first
        if let existing {
            if let chosen, !chosen.isEmpty { existing.displayName = chosen }
            try library.save()
            return existing
        }
        let name: String
        if let chosen, !chosen.isEmpty {
            name = chosen
        } else {
            let taken = try library.context.fetch(FetchDescriptor<DriveFolder>())
                .map(\.displayName)
            name = Self.defaultDisplayName(existing: taken)
        }
        let folder = DriveFolder(folderID: folderID, displayName: name)
        library.context.insert(folder)
        try library.save()
        return folder
    }

    /// What to call a folder the user did not name.
    ///
    /// Exists so the display name can stop being a required field. Making a
    /// user invent a label before they are allowed to do the thing they came to
    /// do is the kind of required input the interface guidelines ask to be
    /// removed, and there is nothing here that needs their answer — the name is
    /// only a label in a list.
    ///
    /// Numbered from the second, so the common case of a single folder reads
    /// "Thư mục Drive" rather than "Thư mục Drive 1". Gaps are ignored on
    /// purpose: after linking three and unlinking the second, the next is 4, not
    /// 2. Reusing a freed number would give a new folder the name a different
    /// folder had five minutes ago, which is worse than a gap nobody can see.
    ///
    /// `nonisolated` because it is a pure function of its argument. The class is
    /// `@MainActor` for the SwiftData context it holds, and nothing about
    /// choosing a string needs that.
    nonisolated static func defaultDisplayName(existing: [String]) -> String {
        let base = "Thư mục Drive"
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// Reconciles the folder's rows with what Drive currently holds, and
    /// returns **the number of audio files Drive listed in this folder**.
    ///
    /// That is not the number of rows the folder has afterwards, and the two
    /// genuinely differ: a Drive file can have several parents, and one whose
    /// `fileID` is already known under another linked folder keeps its existing
    /// row rather than gaining a second one (see the insertion guard below). So
    /// a listing of 40 files can leave 38 rows. `DriveSongsList` counts rows on
    /// screen for its status line and never this value — see the note there.
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

        // The insertion guard is deliberately store-wide, not folder-scoped,
        // because Drive supports multi-parent files — the same file can be a
        // direct child of two folders the user links separately. A
        // folder-scoped existence check would miss a `fileID` already known
        // under a *different* folder and construct-and-insert a second row
        // for it. `DriveTrack.fileID` no longer carries `@Attribute(.unique)`
        // — CloudKit rejects it — so there is no SwiftData-level uniqueness
        // constraint left to collapse that duplicate: this fetch is now the
        // only thing that keeps one `fileID` to one row across folders, and
        // without it a second insert would silently orphan anything (e.g. a
        // saved queue) that referenced the original `id`. See
        // `DriveTrack.swift`'s type-level doc comment.
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
        //
        // Playback is told first, while the row is still readable — see
        // `onTrackWillBeDeleted`. The notification is inside the loop rather
        // than a pass beforehand so a row can never be deleted without having
        // been announced, whatever is edited here later.
        for row in existingInFolder where !liveFileIDs.contains(row.fileID) {
            onTrackWillBeDeleted?(row)
            library.context.delete(row)
        }

        folder.lastScannedAt = .now
        try library.save()
        return files.count
    }

    /// Removes the folder and every row that belongs to it.
    ///
    /// Each track is announced to `onTrackWillBeDeleted` before it is deleted,
    /// so a folder swiped away while one of its tracks is playing takes that
    /// track out of the queue instead of leaving the queue holding a deleted
    /// row. `AVPlayer` keeps the audio going on its own — the item is already
    /// loaded — so without this the user hears music whose row no longer exists.
    func unlink(_ folder: DriveFolder) throws {
        let folderID = folder.folderID
        let tracks = try library.context.fetch(
            FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.folderID == folderID })
        )
        for track in tracks {
            onTrackWillBeDeleted?(track)
            library.context.delete(track)
        }
        library.context.delete(folder)
        try library.save()
    }
}
