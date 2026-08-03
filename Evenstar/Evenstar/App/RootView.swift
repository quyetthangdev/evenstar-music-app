import SwiftUI

/// The app's root: the four library destinations behind a custom floating tab
/// bar, with the player card on top of both.
///
/// A `TabView` carries the tabs — not a hand-rolled switch — so each
/// destination keeps its own scroll position and navigation depth when you
/// leave and come back. Its system bar is hidden with
/// `.toolbar(.hidden, for: .tabBar)`, which applies to the content *inside*
/// each tab rather than to the `TabView`; that modifier therefore lives on each
/// tab's root view, not here. If the system bar ever reappears beneath the
/// custom one, that placement is the first thing to check.
struct RootView: View {
    @Environment(PlaybackService.self) private var playback
    @State private var tab: LibraryTab = .songs
    @State private var isSearching = false
    @State private var query = ""
    /// The keyboard is up, which is narrower than `isSearching` — search opens
    /// without it, and stays open after the field is dismissed.
    @State private var isEditing = false
    /// Where closing search returns to. Captured on the way in, because by the
    /// time the user closes, `tab` is already `.search` and the origin is gone.
    @State private var tabBeforeSearch: LibraryTab = .songs
    /// The bottom bar is collapsed into a single row: the tab pill is a circle
    /// and the collapsed player has slotted in beside it.
    ///
    /// Owned here because it drives two siblings — `FloatingTabBar` and
    /// `PlayerCard` — and is set by a third place entirely, the scroll modifier
    /// on each screen. It is passed down as a `Binding` rather than put in the
    /// environment or a singleton: the seven screens that write it are a fixed,
    /// known set, and a `Binding` says exactly which views take part.
    @State private var isMinimised = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                SongsView(isMinimised: $isMinimised).tag(LibraryTab.songs)
                AlbumsView(isMinimised: $isMinimised).tag(LibraryTab.albums)
                ArtistsView(isMinimised: $isMinimised).tag(LibraryTab.artists)
                AccountView(isMinimised: $isMinimised).tag(LibraryTab.account)
                // The query lives here, not in the screen: the field that edits
                // it is in the tab bar, which is a sibling of the `TabView`.
                SearchView(query: query, isMinimised: $isMinimised).tag(LibraryTab.search)
            }

            FloatingTabBar(
                selection: $tab,
                isSearching: $isSearching,
                query: $query,
                isEditing: $isEditing,
                isMinimised: $isMinimised,
                // No `withAnimation` here on purpose. The bar staggers its own
                // pieces — the tab pill collapsing before the field grows, and
                // the reverse on the way out — with per-slot `.animation`
                // modifiers. A `withAnimation` around this would hand every
                // slot the same transaction and flatten that timing back into
                // one simultaneous move.
                // Nothing here clears `isMinimised`: the bar writes it through
                // the binding immediately before calling this, in the same
                // action, so the two flags are never both true in any render.
                // Restating it here would look like the enforcement while the
                // real guarantee lived elsewhere.
                onOpenSearch: {
                    tabBeforeSearch = tab
                    tab = .search
                    isSearching = true
                },
                onCloseSearch: { destination in
                    tab = destination ?? tabBeforeSearch
                    isSearching = false
                    query = ""
                },
                // Wrapped, unlike the two search closures above: `isMinimised`
                // has no per-slot `.animation` inside the bar staggering it, so
                // the caller supplies the curve — the same spring the search
                // morph uses, so the two bottom-bar transitions read as one
                // system. `ScrollMinimise` wraps its own writes identically.
                onRestore: {
                    withAnimation(FloatingTabBar.searchSpring) {
                        isMinimised = false
                    }
                }
            )
            .padding(.bottom, BottomBarMetrics.tabBarBottomGap)

            // Order here is load-bearing: `PlayerCard` must be LAST so that
            // expanding it covers the tab bar — the expanded card is opaque and
            // full-screen, so no extra state is needed to hide the bar.
            //
            // Being last is safe because the card's collapsed hit region is
            // only the pill itself, not the whole screen: read the long comment
            // at its `.contentShape` call site before changing anything near
            // this. If that region ever grows back to the full screen at rest,
            // the tab bar becomes untappable from launch.
            // Hidden while the keyboard is up — keyed on `isEditing`, NOT on
            // `isSearching`. The tab bar rides the keyboard, and the pill would
            // ride with it: two floating surfaces stacked over the results the
            // user is reading. Search itself opens without the keyboard, so
            // hiding on `isSearching` would take the mini player away for the
            // whole time they are only browsing results. Playback is
            // unaffected either way; only the card moves.
            // `minimised` is 0 or 1 rather than a fraction because the flag
            // driving it is a `Bool`; the card takes a `Double` so the move
            // between the two can be animated, which is what the modifier
            // below supplies.
            PlayerCard(playback: playback, minimised: isMinimised ? 1 : 0)
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
                .accessibilityHidden(isEditing)
                .animation(FloatingTabBar.searchSpring, value: isEditing)
                // Every other writer of `isMinimised` — the scroll modifier and
                // `onRestore` above — already wraps its write in this spring,
                // and for those this modifier is a no-op restating the same
                // curve. The one that does not is the tab bar clearing the flag
                // as search opens (see `onOpenSearch` above): without this, that
                // path alone would snap the pill between the tab row and its own
                // row in a single frame while the bar beside it morphs smoothly.
                .animation(FloatingTabBar.searchSpring, value: isMinimised)
        }
        // Restoring the saved queue is an app-launch concern, so it belongs on
        // the root and not on any one tab. On Bài hát it would work only by
        // accident of that tab being selected first, and would silently stop
        // the day the default tab changes.
        .task { await playback.restoreFromPersistedState() }
    }
}
