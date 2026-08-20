import Foundation
import SwiftData
import Observation

enum LibraryError: LocalizedError {
    case persistenceFailed(underlying: Error)
    case artworkWriteFailed(underlying: Error)
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let error):
            return String(localized: "Không lưu được thay đổi: \(error.localizedDescription)", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .artworkWriteFailed(let error):
            return String(localized: "Không lưu được ảnh bìa: \(error.localizedDescription)", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        case .emptyTitle:
            return String(localized: "Tên bài hát không được để trống.", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
        }
    }
}

@Observable
@MainActor
final class LibraryService {
    let context: ModelContext
    private let fileManager: FileManager

    /// Announced a track that is about to be deleted, so playback can drop it
    /// from the queue while its row is still readable.
    ///
    /// The local twin of `DriveLibraryService.onTrackWillBeDeleted` and
    /// `JamendoLibraryService.onTrackWillBeDeleted`, and it exists for exactly
    /// the reason those two do: after `context.delete(_:)` and the save that
    /// flushes it, reading any property off the row — `queue.map(\.id)` on the
    /// next persist tick is enough — raises `NSObjectInaccessibleException`, an
    /// Objective-C exception that is uncatchable in Swift and unhelped by
    /// `try?`. It presents as intermittent because a row whose attributes are
    /// still materialised answers quietly for a while.
    ///
    /// This was the one source without the hook. The rule lived in
    /// `SongsView.deleteTrack` instead — one call site remembering to call
    /// `playback.handleTrackDeleted` first, by hand, in the right order — so the
    /// second caller of `delete(_:)` (a batch delete, a "remove all local
    /// files", an import reconciling duplicates) would have crashed with no
    /// compiler warning and no failing test.
    ///
    /// Fired **before** `context.delete(_:)` and before the enclosing `save()`,
    /// which is the whole contract: the handler reads `track.id`, and after the
    /// save there is no id left to read.
    /// `@MainActor` on the closure type itself, not merely inherited from the
    /// class: a stored closure's type is independent of its container's
    /// isolation, so without the annotation the handler would be non-isolated
    /// and could not call `PlaybackService`'s main-actor API.
    var onTrackWillBeDeleted: (@MainActor (any Playable) -> Void)?

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
        // First, while the row is still live: see `onTrackWillBeDeleted`. Above
        // the filesystem work as well as the database work, because the file
        // removal below is what makes a queue still holding this track
        // unplayable even before the row dies.
        onTrackWillBeDeleted?(track)
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
        // After the save, for the same reason `updateMetadata` bumps it there
        // and not earlier. Album and Nghệ sĩ used to need no announcement for a
        // cover: their cells reached through the group into the `Track` and
        // read `artworkRelativePath` live, so an edit redrew them for free.
        // That reach is exactly what `AlbumGroup` no longer allows — the path
        // is copied into the group at grouping time — so a new cover is now a
        // change only a regroup can see, and this is what asks for one.
        metadataRevision += 1
        return relative
    }

    /// Bumped every time a track's tags **or cover** change in place.
    ///
    /// **This exists because SwiftData gives no other signal for it.** A
    /// `@Query` publishes inserts, deletes and reorders; editing a property of a
    /// row already in the array changes nothing the array can report, because
    /// the array holds the same objects in the same order. `AlbumsView` and
    /// `ArtistsView` cache their grouping and rebuild it on `onChange(of:
    /// tracks)`, which compares by persistent identity — so without this a
    /// rename would leave both screens showing the old album and the old artist
    /// until the app was relaunched.
    ///
    /// That gap was written down before it could be hit: the doc on
    /// `AlbumsView.albums` says "whoever adds metadata editing must revisit
    /// this". This is that revisit.
    ///
    /// `setArtwork` bumps it too, and only had to start once `AlbumGroup`
    /// stopped carrying `Track` rows — see the comment at that call site. The
    /// rule to keep: **anything a grouping copies out of a row must announce
    /// itself here when it changes**, because a copied value cannot observe
    /// the row it came from.
    private(set) var metadataRevision: Int = 0

    /// Replaces a track's tags.
    ///
    /// Blank artist and album fall back to the same placeholders `ImportService`
    /// writes for an untagged file, rather than being stored empty. Two ways to
    /// say "unknown" would split every grouping in two — one bucket named
    /// "Unknown Artist" and one named "", sitting next to each other in the
    /// Nghệ sĩ tab.
    ///
    /// A blank title throws instead. There is no sensible placeholder for it:
    /// the row would be a blank line in every list, and unlike the artist it is
    /// the thing the user picks the track by.
    func updateMetadata(
        title: String,
        artistName: String,
        albumTitle: String,
        for track: Track
    ) throws {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAlbum = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { throw LibraryError.emptyTitle }

        track.title = newTitle
        track.artistName = newArtist.isEmpty ? MetadataPlaceholder.artist : newArtist
        track.albumTitle = newAlbum.isEmpty ? MetadataPlaceholder.album : newAlbum

        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
        // After the save, never before: a revision announcing a change that did
        // not reach disk would have every screen regroup onto values that are
        // about to be rolled back.
        metadataRevision += 1
    }

    func fetchAllTracks(sortedByTitle: Bool = true) throws -> [Track] {
        var descriptor = FetchDescriptor<Track>()
        if sortedByTitle {
            descriptor.sortBy = [SortDescriptor(\Track.title, comparator: .localizedStandard)]
        }
        return try context.fetch(descriptor)
    }

    /// The local half of session restore, and the first of the three asked —
    /// see `findDriveTrack` and `findJamendoTrack`, which share its shape.
    ///
    /// `fetchLimit = 1` for the same reason they carry it: `id` is never
    /// deliberately reused, so one row is all there should be, and saying so
    /// lets SwiftData stop looking rather than materialise every remaining
    /// `Track` to hand back a list this throws away. (`Track.id` no longer
    /// carries `@Attribute(.unique)` — CloudKit rejects it — so this is now a
    /// convention this method trusts rather than a constraint the database
    /// enforces; a genuine duplicate would just silently return whichever row
    /// SwiftData happens to fetch first.) It was the only one of the three
    /// without it — the outlier, on the table most likely to be the largest.
    func findTrack(byID id: UUID) throws -> Track? {
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
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

    /// The Jamendo half of session restore — same shape as `findDriveTrack`,
    /// for the same reason: `PlaybackState` stores bare `UUID`s with no note
    /// of which table they came from, so restoring a mixed queue has to ask
    /// every source in turn.
    func findJamendoTrack(byID id: UUID) throws -> JamendoTrack? {
        var descriptor = FetchDescriptor<JamendoTrack>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Whether the library already holds this track, by the import's own
    /// definition of "the same one": title and artist case-insensitively equal,
    /// and durations that round to the same second.
    ///
    /// **The fetch is narrowed to a duration window, and that window is what
    /// makes bulk import usable.** `ImportService` calls this once per file, on
    /// the main actor. It used to fetch `FetchDescriptor<Track>()` with no
    /// predicate and no limit — every row in the library, fully materialised —
    /// and then do the comparison in Swift. Importing N files into a library of
    /// M tracks was therefore N×M row materialisations on the main thread: a
    /// progress bar that stalls, gets worse with every file already in the
    /// batch, and worse again every time the library grows.
    ///
    /// The window is `(rounded - 1, rounded + 1)` rather than the rounding rule
    /// itself, because `#Predicate` has no `rounded()` to offer. It is a strict
    /// superset of it — every `x` with `x.rounded() == rounded` lies in
    /// `[rounded - 0.5, rounded + 0.5)` — so the Swift-side comparison below
    /// still decides, unchanged, and the answer is identical to what a full
    /// scan would have given. `LibraryServiceTests` pins both sides of that
    /// edge (180.4 and 180.6 against 181).
    ///
    /// The title/artist half stays in Swift: `#Predicate` has no
    /// case-insensitive comparison that SwiftData can translate, and duration
    /// alone already cuts the candidate set to the handful of tracks that share
    /// a length.
    func findExistingTrack(title: String, artist: String, duration: Double) throws -> Track? {
        let rounded = duration.rounded()
        let lower = rounded - 1
        let upper = rounded + 1
        let descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { $0.durationSeconds > lower && $0.durationSeconds < upper }
        )
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
