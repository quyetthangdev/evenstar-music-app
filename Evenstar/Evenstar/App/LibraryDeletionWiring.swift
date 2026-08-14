import Foundation

/// Hangs the three riders that must run before a local `Track` is deleted.
///
/// This is the single point of failure for the whole class of crash that
/// `LibraryStore.remove(_:)`, `SearchResultsStore.remove(_:)` and
/// `PlaybackService.handleTrackDeleted(_:)` exist to prevent. All three are
/// driven by one closure, `LibraryService.onTrackWillBeDeleted`, whose contract
/// is that it runs synchronously *before* `context.delete` while the row is
/// still readable. Anyone holding a `Track` that outlives the delete —
/// the playing queue, the songs list, Tìm kiếm's filtered list — reads a
/// property off a deleted-and-saved row and raises
/// `NSObjectInaccessibleException`, an Objective-C exception Swift cannot
/// catch.
///
/// It lives in a plain type rather than inline in `EvenstarApp.init`, and the
/// reason is only testability — the behaviour is identical. A closure built
/// inside `App.init` is not reachable from a test: constructing an `App` is not
/// something a unit test can do, so the two test suites that cover this bug
/// each rebuilt the closure inside the test body and then exercised the copy.
/// That is a tautology — a copy always agrees with itself — and it meant
/// deleting any one of the three lines below left every test green. The suite
/// pinned to *this* function is the only thing that goes red for it, and
/// `LibraryDeletionWiringTests` is that suite.
enum LibraryDeletionWiring {

    /// Installs the handler on `library`, replacing anything already there.
    ///
    /// The order inside the closure is the order the app has always run, and
    /// nothing depends on it: the three riders touch three disjoint arrays and
    /// none of them can see another's. It is kept stable anyway, so a future
    /// rider that *does* care has an existing sequence to be inserted into
    /// rather than a coin toss.
    ///
    /// `[weak playback]`, unlike the other two captures, and the difference is
    /// real rather than defensive: `PlaybackService` holds `LibraryService` (it
    /// reads and writes `PlaybackState` through it), so a strong capture would
    /// close the loop — playback → library → this closure → playback. Neither
    /// `store` nor `search` holds a reference back to `library`, so there is no
    /// loop for them to break and a strong capture is what keeps them alive for
    /// as long as the hook can fire.
    @MainActor
    static func install(
        on library: LibraryService,
        playback: PlaybackService,
        store: LibraryStore,
        search: SearchResultsStore
    ) {
        library.onTrackWillBeDeleted = { [weak playback] playable in
            playback?.handleTrackDeleted(playable)
            // Always a `Track`: this hook belongs to `LibraryService.delete`,
            // whose parameter is one. The two remote services fire their own
            // hooks for their own tables, and no row of theirs is in either of
            // the two arrays below.
            if let track = playable as? Track {
                store.remove(track)
                search.remove(track)
            }
        }
    }
}
