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
    /// environment or a singleton: the six screens that write it are a fixed,
    /// known set, and a `Binding` says exactly which views take part.
    ///
    /// This flag alone does NOT mean minimised styling should render — see
    /// `isMinimisedActive` below, which is what every renderer actually reads.
    @State private var isMinimised = false
    /// How far the player has opened, 0 collapsed to 1 full screen.
    ///
    /// A `@State` reference type, not a value: `RootView`'s body never reads
    /// `progress`, so it is not invalidated when the card moves. Only the one
    /// modifier that applies the transform re-runs. See `PlayerExpansion.swift`
    /// — the version before this was a `Binding`, and rebuilding this body and
    /// its five tabs on every dragged frame is what made the recede stutter.
    @State private var expansion = PlayerExpansion()

    /// The window's bottom safe-area inset: 34 on a phone with a home
    /// indicator, 0 on one without.
    ///
    /// Measured here, once, and published to every screen through
    /// `\.bottomSafeAreaInset` — see `BottomBarClearance.swift` for why the
    /// environment rather than a parameter. The bottom bar itself does not read
    /// it: the bar is anchored to the screen and simply ignores the inset. Only
    /// the lists need it, to convert the bar's screen-relative position into the
    /// safe-area-relative one `.safeAreaInset(edge: .bottom)` speaks.
    ///
    /// It starts at 0 and is corrected on the first layout pass. That is the
    /// right way round: 0 is the true value on a device with no home indicator,
    /// and everywhere else it briefly asks for *more* clearance than needed
    /// rather than less, which no one can see at the top of a list.
    @State private var bottomSafeAreaInset: CGFloat = 0

    /// Whether minimised styling should actually apply, as opposed to what
    /// `isMinimised` merely holds.
    ///
    /// The two used to be treated as the same thing, and searching was the
    /// case that broke it: `SearchView`'s results list is on screen only
    /// while `isSearching` is true, and until Finding 1 of the whole-plan
    /// review it carried the scroll modifier too, so every scroll while
    /// searching set `isMinimised = true` behind `isSearching`. That call site
    /// is gone now, but the same collision is reachable from any future
    /// writer of `isMinimised` — a ninth screen, a new gesture — and nothing
    /// stops `isMinimised` from being `true` while `isSearching` is also
    /// `true` at the level of plain state. Rather than rely on every writer
    /// remembering to clear one flag before setting the other — the guarantee
    /// that just failed — this masks the read instead: both `FloatingTabBar`
    /// and `PlayerCard` below are constructed from this, never from the raw
    /// `isMinimised`, so a stray `true` underneath cannot reach either
    /// renderer while search is open. `RootView` is the only place this can
    /// live: it is the one place both flags are always in scope together, and
    /// the one place that constructs both consumers, so a future writer of
    /// `isMinimised` — wherever it lives — still has its effect filtered here
    /// on the way to the screen.
    private var isMinimisedActive: Bool { isMinimised && !isSearching }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The one place the window's bottom inset is measured. Invisible,
            // untappable, and behind everything.
            //
            // A greedy child of this ZStack is the layout position that reports
            // the real insets — the same position `PlayerCard`'s reader sits in,
            // and for the same reason: a reader that still respects the safe
            // area is the only one that can report it.
            //
            // `.ignoresSafeArea(.keyboard)` is load-bearing. Without it this
            // reports the *keyboard's* inset while the search field is up —
            // several hundred points — and every list underneath would drop its
            // clearance to 0 mid-edit and reflow. The container inset is what
            // the lists need, and it does not change when the keyboard does.
            Color.clear
                .ignoresSafeArea(.keyboard)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.safeAreaInsets.bottom
                } action: { inset in
                    bottomSafeAreaInset = inset
                }

            TabView(selection: $tab) {
                SongsView(isMinimised: $isMinimised).tag(LibraryTab.songs)
                AlbumsView(isMinimised: $isMinimised).tag(LibraryTab.albums)
                ArtistsView(isMinimised: $isMinimised).tag(LibraryTab.artists)
                AccountView(isMinimised: $isMinimised).tag(LibraryTab.account)
                // The query lives here, not in the screen: the field that edits
                // it is in the tab bar, which is a sibling of the `TabView`.
                // No `isMinimised` binding here: `SearchView` does not carry
                // the scroll modifier — see the comment on its results list —
                // so it has nothing to write.
                SearchView(query: query).tag(LibraryTab.search)
            }
            // The content recedes as the player opens. The transform lives in
            // the modifier, not here, so that changing it re-runs the modifier's
            // body and not this one — see `PlayerExpansion.swift`.
            .recedesBehindPlayer(expansion)
            // Reaches all seven screens, including the two pushed detail
            // screens declared inside `navigationDestination` closures, which a
            // parameter would have to be threaded to by hand.
            .environment(\.bottomSafeAreaInset, bottomSafeAreaInset)

            FloatingTabBar(
                selection: $tab,
                isSearching: $isSearching,
                query: $query,
                isEditing: $isEditing,
                // A masked binding, not `$isMinimised` directly. Every read
                // inside `FloatingTabBar` — `isCollapsed`, `restoreButton`'s
                // opacity and hit-testing — sees `isMinimisedActive`, so the
                // bar cannot render both the home glyph and the restore glyph
                // opaque at once no matter what the real `isMinimised` holds.
                // Writes still land on the real flag, so `trailingButton`'s
                // `isMinimised = false` and `ScrollMinimise`'s writes on the
                // six screens behave exactly as before.
                isMinimised: Binding(
                    get: { isMinimisedActive },
                    set: { isMinimised = $0 }
                ),
                // No `withAnimation` here on purpose. The bar staggers its own
                // pieces — the tab pill collapsing before the field grows, and
                // the reverse on the way out — with per-slot `.animation`
                // modifiers. A `withAnimation` around this would hand every
                // slot the same transaction and flatten that timing back into
                // one simultaneous move.
                // `trailingButton` still clears the real `isMinimised` before
                // handing off to `onOpenSearch` below, so the flag does not
                // snap back minimised the instant search closes without a
                // fresh scroll — but that write is belt-and-braces now, not
                // the guarantee. The guarantee that the two morphs never
                // render at once is `isMinimisedActive` above: it holds
                // whether or not this particular write ever ran.
                hasTrack: playback.currentTrack != nil,
                onOpenSearch: {
                    tabBeforeSearch = tab
                    // The bar morphs first; the tab switches on the next turn.
                    //
                    // `TabView` builds a tab's content lazily, so the first
                    // switch to `.search` constructs `SearchView` and runs its
                    // `@Query` over the whole library. Done in the same turn as
                    // `isSearching`, that work lands between the tap and the
                    // frame that would have shown the morph starting — so the
                    // bar visibly stalls, once per launch.
                    //
                    // Every tab pays that cost on its first open. Search is
                    // simply the only one with an animation attached, which is
                    // what makes the delay visible rather than reading as an
                    // ordinary tab switch.
                    //
                    // Splitting the two lets the morph start on the tap's own
                    // frame. For one turn the bar is in search mode over the
                    // previous tab's content, which is a frame nobody sees and
                    // is the right way round anyway: the old screen stays until
                    // the field is ready to replace it.
                    isSearching = true
                    Task { @MainActor in tab = .search }
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
                    withAnimation(BottomBarStyle.morph) {
                        isMinimised = false
                    }
                }
            )
            // Anchored to the screen, not to the safe area — Apple's own
            // floating tab bar sits 21pt in from the physical bottom edge on
            // every device, and deliberately intrudes into the bottom inset.
            //
            // All three lines are load-bearing, in this order.
            //
            // The greedy frame is not decoration and cannot be dropped.
            // `ignoresSafeArea` expands the region a view is *offered*; a view
            // that does not take the region it is offered does not move. With
            // the bar's own 71pt (bar plus padding) and no frame, the two lines
            // below compiled, changed nothing, and left the bar at 21 above the
            // safe area — 55 from the physical edge, measured. `PlayerCard`
            // gets this right for the same reason: its card is bottom-aligned
            // in a `maxHeight: .infinity` frame before it ignores anything.
            //
            // The padding is inside the frame, so it holds the bar clear of the
            // frame's bottom edge — which, once the safe area is ignored, is
            // the physical bottom of the display.
            //
            // `.container`, never `.all` and never a bare `ignoresSafeArea()`:
            // the keyboard is a separate safe-area region, and the bar rides
            // the keyboard by design. Ignoring that one too would leave the bar
            // buried under the keyboard while search is being typed into. Left
            // as `.container` the frame's bottom is the keyboard's top while
            // the keyboard is up, so the same 21pt gap is measured from
            // whatever the bottom of the usable screen currently is.
            //
            // The frame draws nothing and carries no `contentShape`, so it does
            // not hit-test: the library keeps every tap outside the bar itself.
            // See the long note at `PlayerCard`'s `.contentShape` call site for
            // what a hit region on a full-screen frame costs.
            .padding(.bottom, BottomBarMetrics.screenBottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)

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
            //
            // Reads `isMinimisedActive`, not `isMinimised` directly — the same
            // masking `FloatingTabBar` gets above, for the same reason: this
            // is the only call site that constructs `PlayerCard`, and the
            // minimised inset must not apply while `isSearching` is
            // true, or the pill lands on top of the 48pt search field. See
            // `isMinimisedActive`'s doc comment.
            PlayerCard(
                playback: playback,
                minimised: isMinimisedActive ? 1 : 0,
                expansion: expansion
            )
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
                .accessibilityHidden(isEditing)
                .animation(BottomBarStyle.morph, value: isEditing)
                // Every other writer of `isMinimised` — the scroll modifier and
                // `onRestore` above — already wraps its write in this spring,
                // and for those this modifier is a no-op restating the same
                // curve. The one that does not is the tab bar clearing the flag
                // as search opens (see `onOpenSearch` above): without this, that
                // path alone would snap the pill between the tab row and its own
                // row in a single frame while the bar beside it morphs smoothly.
                // Keyed on `isMinimisedActive`, matching the value actually fed
                // to `minimised:` above — `isSearching` toggling can change
                // that value even on a frame where the raw `isMinimised` does
                // not, and the animation must key on what the card receives.
                .animation(BottomBarStyle.morph, value: isMinimisedActive)
        }
        // Restoring the saved queue is an app-launch concern, so it belongs on
        // the root and not on any one tab. On Bài hát it would work only by
        // accident of that tab being selected first, and would silently stop
        // the day the default tab changes.
        .task { await playback.restoreFromPersistedState() }
    }
}
