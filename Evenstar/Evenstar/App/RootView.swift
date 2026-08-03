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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                SongsView().tag(LibraryTab.songs)
                AlbumsView().tag(LibraryTab.albums)
                ArtistsView().tag(LibraryTab.artists)
                // The query lives here, not in the screen: the field that edits
                // it is in the tab bar, which is a sibling of the `TabView`.
                SearchView(query: query).tag(LibraryTab.search)
            }

            FloatingTabBar(
                selection: $tab,
                isSearching: $isSearching,
                query: $query,
                isEditing: $isEditing,
                // No `withAnimation` here on purpose. The bar staggers its own
                // pieces — the tab pill collapsing before the field grows, and
                // the reverse on the way out — with per-slot `.animation`
                // modifiers. A `withAnimation` around this would hand every
                // slot the same transaction and flatten that timing back into
                // one simultaneous move.
                onOpenSearch: {
                    tabBeforeSearch = tab
                    tab = .search
                    isSearching = true
                },
                onCloseSearch: { destination in
                    tab = destination ?? tabBeforeSearch
                    isSearching = false
                    query = ""
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
            PlayerCard(playback: playback)
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
                .accessibilityHidden(isEditing)
                .animation(FloatingTabBar.searchSpring, value: isEditing)
        }
        // Restoring the saved queue is an app-launch concern, so it belongs on
        // the root and not on any one tab. On Bài hát it would work only by
        // accident of that tab being selected first, and would silently stop
        // the day the default tab changes.
        .task { await playback.restoreFromPersistedState() }
    }
}
