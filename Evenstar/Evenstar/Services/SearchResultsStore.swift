import Foundation

/// The list Tìm kiếm is showing, held outside the view so a delete can reach it.
///
/// These two values used to be `@State` on `SearchView` — `results` and
/// `resultsQuery`. How they are filled is unchanged, down to the rule below
/// about when the old list may stay on screen; what moved, and the only reason
/// it moved, is *who is able to write them*.
///
/// `LibraryStore.remove(_:)` closes the deleted-row window for `store.tracks`
/// by ordering: it is called from `onTrackWillBeDeleted`, synchronously,
/// *before* `context.delete`, so no body can read an array that still holds the
/// dead row. That fix could not reach this list while it lived in the view: a
/// `@State` array is writable only from inside the view that declares it, so
/// nothing on the delete path could prune it — not late, not at all.
///
/// And the window here was the widest of the three. `AlbumsView` and
/// `ArtistsView` cache too, but their caches are rebuilt by `onChange` on the
/// next update pass, so a dead row sat in them for one pass. This list changes
/// only when the user *types*, so a dead row could sit in it indefinitely —
/// until a next keystroke that may never come — and every draw of the search
/// tab in between reads `track.title` off it through `SongRow`.
///
/// Two things follow from the state living here rather than in the view, and
/// both are the point:
///
/// - The prune lands in the same window `LibraryStore.remove(_:)` uses, before
///   `context.delete`, rather than in an `onChange` action — which runs *after*
///   the pass that triggered it, i.e. inside the very window being closed.
/// - It lands whether or not `SearchView` is being updated, or exists. The
///   search tab may be built but sitting behind another tab, or never built at
///   all. A cleanup that only reaches a view SwiftUI happens to be updating
///   closes nothing; an object nobody is looking at is pruned all the same, and
///   whatever builds `SearchView` next reads the pruned list.
///
/// Not merged into `LibraryStore`: that type is the one copy of the *library*,
/// read by five screens and written only by the query bridge. This is one
/// screen's answer to one question, with a lifetime and an invalidation set of
/// its own, and giving `LibraryStore` a second array with different rules would
/// blur what `private(set) var tracks` currently promises.
@Observable
@MainActor
final class SearchResultsStore {

    /// The outcome of filtering the library against a query, or `nil` while
    /// that filter has not produced an answer yet — either `SearchView`'s 150ms
    /// debounce is still waiting, or a keystroke cancelled the wait and a fresh
    /// one just started.
    ///
    /// `nil` is a distinct state from "filtered and found nothing": collapsing
    /// the two would show "Không tìm thấy kết quả" for a query the app has not
    /// actually finished checking, which is wrong for as long as the debounce
    /// is in flight.
    ///
    /// `private(set)`: every write goes through one of the four methods below,
    /// so the rule about which of them keeps a list and which drops it lives in
    /// one file rather than in whichever view got there first.
    private(set) var results: [Track]?

    /// The exact query string `results` answers.
    ///
    /// Needed because by the time `SearchView`'s task runs again, its `query`
    /// already holds the *new* value — there is no other way left to ask "what
    /// was the old list an answer to?", which is the question
    /// `dropStaleResults(for:)` decides on.
    ///
    /// Private, unlike `results`: no view needs to see it, and every use of it
    /// is one of the methods below.
    private var answeredQuery: String?

    /// The query was wiped, not just changed.
    ///
    /// The one case that must NOT keep a stale list: `SearchView` needs to fall
    /// back to its "type something" prompt, not to the last answer to a
    /// question that no longer exists.
    func clear() {
        // Nothing to publish when nothing is held. Every assignment to an
        // `@Observable` property wakes its readers whether or not the value
        // moved, and the first pass of a session arrives here with both already
        // `nil`.
        guard results != nil || answeredQuery != nil else { return }
        results = nil
        answeredQuery = nil
    }

    /// Drops the list on screen unless `query` is a continuation of the one it
    /// answers.
    ///
    /// Whether the old list stays up while the next one is computed depends on
    /// what produced it, not on whether it merely exists. Keep it only when the
    /// new query *extends* `answeredQuery` — the user typed further past a set
    /// that is still a superset of whatever the longer query will match, e.g.
    /// "queen" → "queena".
    ///
    /// Drop it for anything else: a character deleted ("queenx" → "queen",
    /// where the old list is now a *subset* and missing rows), or a different
    /// word typed over a selection ("queen" → "abba", where the old list has no
    /// relationship to the new query at all). Showing Queen's songs while
    /// "abba" sits in the field, with no sign anything is stale, is a worse lie
    /// than a spinner — that was the actual bug this rule replaced.
    ///
    /// `answeredQuery` is deliberately left alone when the list is dropped: it
    /// still records what the *last computed* answer was about, and the next
    /// call has to be able to ask the same question of it.
    func dropStaleResults(for query: String) {
        if let answeredQuery, query.hasPrefix(answeredQuery) { return }
        guard results != nil else { return }
        results = nil
    }

    /// Takes a finished answer. Called only from the far side of the debounce,
    /// on the one task per query that was not cancelled.
    func record(_ found: [Track], for query: String) {
        results = found
        answeredQuery = query
    }

    /// Drops a row that is about to be deleted, **before** it is deleted.
    ///
    /// The mirror of `LibraryStore.remove(_:)`, riding the same
    /// `onTrackWillBeDeleted` hook in the same synchronous window, against the
    /// same crash — see that comment for the full account of why the window
    /// exists and why deleting the song that is *playing* is the case that
    /// reaches it.
    ///
    /// The shortened list is still an honest answer to `answeredQuery`: a row
    /// that no longer exists cannot match anything, so nothing that belongs in
    /// the answer left with it. That is why the query is kept, and why the
    /// "keep it while the user types further" rule above still holds over it.
    func remove(_ track: Track) {
        guard let current = results else { return }
        let remaining = current.filter { $0 != track }
        // A row that was not in the list is the ordinary case — most deletes
        // happen with no search in flight at all — and must not wake the screen
        // for a change that did not happen.
        guard remaining.count != current.count else { return }
        results = remaining
    }
}
