import Foundation
import SwiftData
import SwiftUI

/// Unreachable in practice — `save`'s internal `Task` either throws (and
/// that error propagates to every caller awaiting it) or inserts and saves a
/// row before returning normally. Exists only so the "joined a save that
/// somehow left no row" branch has something honest to throw instead of a
/// force-unwrap.
enum JamendoLibraryError: Error {
    case saveDidNotPersist
}

/// Saving Jamendo tracks into the library, and taking them out again.
///
/// Mirrors `DriveLibraryService`: it owns the `ModelContext` writes for its
/// source so no view does its own persistence.
@Observable
@MainActor
final class JamendoLibraryService {
    private let library: LibraryService
    private let session: URLSession

    /// One in-flight save `Task` per Jamendo id, so a second `save()` call
    /// that lands while the first is still awaiting its cover download joins
    /// the same work instead of racing it.
    ///
    /// **Why this exists — the `existingRow` check alone is not atomic.**
    /// `save` used to check `existingRow`, `await` the cover download, then
    /// insert. Nothing holds the actor between the check and the `await`:
    /// two overlapping calls (e.g. a double-tap on the save button, whose
    /// `isSaved` only flips after the whole round trip completes — see
    /// `JamendoDiscoveryView.save(_:)`) both see no existing row, both
    /// download a cover, and both insert a `JamendoTrack`. `jamendoID` no
    /// longer carries `@Attribute(.unique)` — CloudKit rejects it — so there
    /// is no SwiftData-level upsert left to collapse those two rows into one;
    /// both inserts simply stand as two separate rows. A `PlaybackState` that
    /// captured one of their `id`s a moment earlier now points at a row that
    /// may not be the one the user expects, which is exactly the restore
    /// failure C1 fixes. The loser's downloaded cover is also orphaned on
    /// disk, with nothing left pointing at it. Coalescing concurrent calls
    /// onto one `Task` per id makes the second call a no-op that returns the
    /// first call's row, rather than a second attempt racing it — and, since
    /// this task removed the attribute, is now the *only* thing preventing
    /// the duplicate row.
    ///
    /// `Task<Void, Error>`, not `Task<JamendoTrack, Error>`: `JamendoTrack`
    /// is a `@Model` class, which SwiftData does not make `Sendable`, and
    /// `Task.value` crossing out of this actor-isolated context requires a
    /// `Sendable` result under Swift 6's strict concurrency checking even
    /// though both ends of that "crossing" are this same `@MainActor`. The
    /// joining call re-fetches the row by `jamendoID` after the `Task`
    /// completes instead of carrying it through the `Task`'s result.
    private var inFlightSaves: [String: Task<Void, Error>] = [:]

    /// Called with the `JamendoTrack` this service is about to delete, while
    /// the row is still live.
    ///
    /// **Wired to `PlaybackService.handleTrackDeleted` in `EvenstarApp`, and
    /// without it `unsave` corrupts playback.** `queue` and `currentTrack`
    /// hold their rows strongly, so deleting one behind the service's back
    /// leaves the queue pointing at a deleted-and-saved `PersistentModel`:
    /// the 30-second play-count write, the periodic `queue.map(\.id)`
    /// persist and a tap on Next all then read a property off it and raise
    /// `NSObjectInaccessibleException` — an Objective-C exception,
    /// uncatchable in Swift. `DriveLibraryService.onTrackWillBeDeleted`
    /// carries the same contract for Drive, for the same reason.
    ///
    /// A closure rather than a stored `PlaybackService`, matching
    /// `DriveLibraryService`: this service stays testable without one, and
    /// the dependency points a single direction.
    ///
    /// Fired **before** `context.delete(_:)` and before the enclosing
    /// `save()` — the handler reads `track.id`, and after the save there is
    /// no id left to read.
    var onTrackWillBeDeleted: (@MainActor (any Playable) -> Void)?

    init(library: LibraryService, session: URLSession = .shared) {
        self.library = library
        self.session = session
    }

    /// Downloads the cover, then inserts the row.
    ///
    /// **Dedupe is by Jamendo's id.** A track already saved is returned as-is
    /// rather than inserted a second time — the user re-tapping "save" on
    /// something already in their library must leave one row, not a second
    /// one they then have to delete individually. See `inFlightSaves` for how
    /// this stays true even when the two calls overlap in time.
    ///
    /// **The cover is fetched before the insert and its failure is swallowed.**
    /// The user asked for the music; losing the picture is not a reason to
    /// refuse them the track. `artworkRelativePath` stays `nil` and every
    /// consumer already handles that — it is the state every Drive track is in.
    @discardableResult
    func save(_ track: JamendoCatalogueTrack) async throws -> JamendoTrack {
        if let existing = try existingRow(jamendoID: track.id) { return existing }

        // A save for this id is already in flight — join it rather than
        // starting a second download+insert. Everything from here to the
        // `inFlightSaves[track.id] = task` line below runs with no `await`
        // in between, so two calls landing back-to-back on the main actor
        // cannot both fall through this check and both start a `Task`.
        if let inFlight = inFlightSaves[track.id] {
            try await inFlight.value
            if let existing = try existingRow(jamendoID: track.id) { return existing }
            // The task we joined finished without leaving a row behind it —
            // not expected in practice (it either throws, in which case
            // `inFlight.value` above already rethrew, or it inserts and
            // saves before returning), but falls through to attempting our
            // own save rather than returning something invented.
        }

        // Captures `self` strongly on purpose: the only thing that releases
        // this `Task` is its own completion (the `defer` below clears the
        // dictionary entry), so the cycle is self-breaking and never
        // outlives the save it represents. The service itself is owned for
        // the app's lifetime regardless.
        let task = Task { @MainActor in
            defer { self.inFlightSaves[track.id] = nil }
            let artworkPath = await self.downloadCover(track)
            let row = JamendoTrack(from: track, artworkRelativePath: artworkPath)
            self.library.context.insert(row)
            try self.library.save()
        }
        inFlightSaves[track.id] = task
        try await task.value
        guard let saved = try existingRow(jamendoID: track.id) else {
            throw JamendoLibraryError.saveDidNotPersist
        }
        return saved
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
        onTrackWillBeDeleted?(track)
        Self.removeDownloadedArtwork(for: track)
        library.context.delete(track)
        try library.save()
    }

    /// Xoá ảnh bìa mà `save` đã tải về cho hàng này. Best-effort, `try?` — xem
    /// `unsave` về lý do một file bìa không xoá được không bao giờ được phép
    /// chặn một lệnh xoá.
    ///
    /// Tách ra khỏi `unsave` và để `static` chỉ vì **`DuplicateSweep` cần
    /// đúng hành vi này mà không có `JamendoLibraryService` nào trong tay.**
    /// Lượt gộp trùng xoá hàng `JamendoTrack` thẳng qua `ModelContext`, nên
    /// trước khi có hàm này, mỗi hàng bị gộp đi để lại vĩnh viễn một file JPEG
    /// mà không còn `artworkRelativePath` nào trỏ tới — chính cái rò rỉ mà
    /// `unsave` được viết ra để chặn. Hai chỗ xoá hàng thì phải cùng một chỗ
    /// dọn file; đừng viết lại nó ở chỗ thứ hai.
    static func removeDownloadedArtwork(for track: JamendoTrack) {
        guard let artworkPath = track.artworkRelativePath else { return }
        try? FileManager.default.removeItem(
            at: FileLocation.absoluteURL(forRelative: artworkPath)
        )
    }

    func isSaved(jamendoID: String) throws -> Bool {
        try existingRow(jamendoID: jamendoID) != nil
    }

    /// Which of a page of catalogue ids are already saved — one fetch, not
    /// one per id.
    ///
    /// `JamendoDiscoveryView` used to call `isSaved(jamendoID:)` once per
    /// result to build its "already saved" set. Jamendo's page limit is 50,
    /// so a single debounced search issued up to 50 separate `FetchDescriptor`
    /// round-trips through this same `ModelContext`, synchronously on
    /// `@MainActor`, on every keystroke that survived the debounce. This is
    /// the same lookup, expressed as one round trip regardless of how many
    /// ids are asked about.
    func savedIDs(among jamendoIDs: [String]) throws -> Set<String> {
        guard !jamendoIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<JamendoTrack>(
            predicate: #Predicate { jamendoIDs.contains($0.jamendoID) }
        )
        return Set(try library.context.fetch(descriptor).map(\.jamendoID))
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
