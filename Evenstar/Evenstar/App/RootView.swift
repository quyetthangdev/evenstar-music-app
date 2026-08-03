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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                SongsView().tag(LibraryTab.songs)
                AlbumsView().tag(LibraryTab.albums)
                ArtistsView().tag(LibraryTab.artists)
                SearchView().tag(LibraryTab.search)
            }

            FloatingTabBar(selection: $tab)
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
            PlayerCard(playback: playback)
        }
        // Restoring the saved queue is an app-launch concern, so it belongs on
        // the root and not on any one tab. On Bài hát it would work only by
        // accident of that tab being selected first, and would silently stop
        // the day the default tab changes.
        .task { await playback.restoreFromPersistedState() }
    }
}
