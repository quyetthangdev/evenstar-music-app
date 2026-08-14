import SwiftUI
import SwiftData

/// The one copy of the local library every screen reads.
///
/// Five screens used to declare the same `@Query` over the whole `Track` table
/// — Bài hát, Album, Nghệ sĩ, Tài khoản and Tìm kiếm. `TabView` keeps a tab it
/// has built, so all five stayed alive at once and every insert, delete or save
/// cost five fetches and five localized sorts before a single pixel changed.
/// Importing forty files paid that forty times, on the main actor, during the
/// one flow that has to feel smooth.
///
/// So the fetch happens once, here, and the five screens read the result. What
/// they read is the same `Track` objects the query returns, not copies: a row
/// is `@Observable`, so a `SongRow` still redraws when the title behind it
/// changes without this array being touched at all.
///
/// Why a store rather than one `@Query` in `RootView` handed down through the
/// environment: `RootView.body` must not read anything that changes as often as
/// the library does. Its body builds the `TabView` and all five tabs for
/// SwiftUI to diff, and `PlayerExpansion.swift` documents in detail what that
/// cost looked like on screen the last time something frequently-changing was
/// read up there. A `@Query` only lives in a `View`, and a `View` that holds
/// one is invalidated by it — so the query goes in a view of its own that
/// renders nothing (`LibraryQueryBridge` below) and `RootView` stays ignorant.
@Observable
@MainActor
final class LibraryStore {
    /// Sorted by title with `.localizedStandard`, matching the query that fills
    /// it — the order Bài hát renders in, so no screen re-sorts on the way out.
    ///
    /// `private(set)`: `LibraryQueryBridge` is the only writer, through
    /// `replace(with:)`. A screen that could assign here would be publishing a
    /// library state the database does not agree with.
    private(set) var tracks: [Track]

    /// Seeded at launch from a plain fetch rather than left empty for the
    /// bridge to fill on the first update pass.
    ///
    /// Empty is not a neutral starting value on these screens: it is the empty
    /// state. Bài hát renders `EmptyLibraryView`, Album and Nghệ sĩ render
    /// "Chưa có album"/"Chưa có nghệ sĩ". Leaving the first frame to guess
    /// wrong risks showing a user with a full library the screen that says they
    /// have no music, for however long the first pass takes.
    init(tracks: [Track] = []) {
        self.tracks = tracks
    }

    /// Takes a fresh fetch, and ignores one that says nothing new.
    ///
    /// The guard matters because every assignment to an `@Observable` property
    /// wakes its readers whether or not the value moved, and the readers here
    /// are five screens. The comparison is by persistent identity — SwiftData
    /// rows are `Equatable` that way — so it answers "same rows, same order",
    /// which is exactly the question the screens care about.
    func replace(with fetched: [Track]) {
        guard fetched != tracks else { return }
        tracks = fetched
    }

    /// Drops a row that is about to be deleted, **before** it is deleted.
    ///
    /// `replace(with:)` cannot cover this one, and the difference is a crash.
    /// It is driven by `LibraryQueryBridge`'s `onChange`, and an `onChange`
    /// action runs *after* the update pass that triggered it — so between the
    /// `context.delete` and that action, this array still holds the dead row.
    /// Any body that runs inside that window and reads a stored property off it
    /// raises `NSObjectInaccessibleException`, an Objective-C exception that is
    /// uncatchable in Swift. `SongsView`'s `List` reads `track.id`, and
    /// `SongRow` reads `track.title`.
    ///
    /// What this does **not** cover: a screen that keeps its own array of rows
    /// rather than reading `tracks`. `SearchView` does exactly that — it draws
    /// the same `SongRow` over its own filtered list, and this method never
    /// touched it. That list has its own guard, `SearchResultsStore.remove(_:)`,
    /// called from the same hook for the same reason; `AlbumsView` and
    /// `ArtistsView` are covered differently again, by holding no rows at all
    /// (see `AlbumGroup`).
    ///
    /// That window is reachable, not theoretical. Deleting a track that is in
    /// the queue makes `PlaybackService.handleTrackDeleted` change
    /// `currentTrack`, which `RootView`'s body reads (`hasTrack:`), so `RootView`
    /// is invalidated *before* the row is deleted and the resulting pass rebuilds
    /// the tabs. `handleTrackDeleted` returns early for a track that is not in
    /// the queue, which is why the plain case looks fine and the "delete the song
    /// that is playing" case is the one that crashes.
    ///
    /// **Three** of the five screens used to be safe from this for free — Bài
    /// hát, Tài khoản and Tìm kiếm. Each held its own `@Query`, and `Query` is
    /// a `DynamicProperty` whose `update()` runs *before* the body of the view
    /// holding it, so a body could never read a pre-delete array. Moving the
    /// query out is what lost that for those three, and this is what buys it
    /// back for them.
    ///
    /// Album and Nghệ sĩ never had that safety, and the difference matters to
    /// whoever reads this next: it means handing a `@Query` back to a screen is
    /// *not* a way to make it safe. Both already kept their own `@State` cache
    /// of `[Track]`, refreshed by `onChange` — the same one-pass-late shape as
    /// this array — from before the queries were merged into one. That is why
    /// they are covered structurally instead, by holding no rows at all: see
    /// `AlbumGroup`.
    ///
    /// Called from `LibraryService.delete` through `onTrackWillBeDeleted` —
    /// the same hook, with the same "before the delete, while the row is still
    /// readable" contract, that already exists so `PlaybackService` can drop the
    /// row from its queue.
    func remove(_ track: Track) {
        let remaining = tracks.filter { $0 != track }
        // A row that was not in the array is not a mistake — the store can be
        // one update behind an insert — and must not wake five screens for a
        // change that did not happen.
        guard remaining.count != tracks.count else { return }
        tracks = remaining
    }
}

/// The single `@Query` on `Track` in the app. It draws nothing.
///
/// A `@Query` needs a `View` to live in, and it invalidates that view on every
/// change to the table. This is that view, deliberately reduced to nothing so
/// the invalidation lands on a body that costs one `Color.clear` to rebuild
/// instead of on `RootView`'s, which rebuilds the `TabView` and five tabs.
///
/// Why this rather than `store.refresh()` called from the places that change
/// data: what changes the set of rows today is `LibraryService.insert` and
/// `delete` — `ImportService` reaches the table through the first of those —
/// plus whoever writes `Track` next. (`DriveLibraryService` and
/// `JamendoLibraryService` are deliberately not on that list: they insert into
/// `DriveTrack` and `JamendoTrack`, different tables this query never sees.) A
/// refresh call is something a future writer has to remember, with no compiler
/// error and no failing test when they do not; the symptom would be a library
/// that quietly stops updating. SwiftData already notices every one of those
/// writes, so the trigger stays where it cannot be forgotten.
///
/// What this does NOT report is an edit to a property that is *not* in the
/// `SortDescriptor` below: rename an album or an artist and the array holds the
/// same rows in the same order, so `onChange` does not fire. A **title** edit
/// is not in that set — the query sorts by title, so renaming a song can move
/// its row and the array does change, which `LibraryStoreTests`
/// `testReplaceNotifiesOnAReorderAlone` pins. That is unchanged from before —
/// `LibraryService.metadataRevision` is the signal for the properties the sort
/// cannot see, and Album and Nghệ sĩ still listen to it.
struct LibraryQueryBridge: View {
    @Environment(LibraryStore.self) private var store
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)])
    private var tracks: [Track]

    var body: some View {
        // Zero-sized rather than `EmptyView`: an `EmptyView` is not guaranteed
        // to be materialised as a view at all, and a `@Query` that is never
        // updated fetches nothing.
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // `initial: true` covers the case the launch seed cannot: a
            // container that gains rows before this view is first updated, and
            // every remount — `RootView` carries `.id(language)`, so switching
            // language rebuilds this view from scratch.
            .onChange(of: tracks, initial: true) { _, updated in
                store.replace(with: updated)
            }
    }
}
