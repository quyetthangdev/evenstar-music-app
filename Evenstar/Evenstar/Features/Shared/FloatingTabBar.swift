import SwiftUI

enum LibraryTab: String, Identifiable {
    case songs, albums, artists, account, search
    var id: String { rawValue }

    /// The three that share the pill. Search is deliberately absent: it lives
    /// in its own circular button beside the pill.
    ///
    /// `CaseIterable` is deliberately NOT adopted. With it, `allCases` reads
    /// as the obvious way to lay out "the tabs", and using it would draw
    /// search twice — once in the pill and once in its own button. Leaving the
    /// conformance off makes that mistake impossible rather than merely
    /// warned against. Adding a destination means adding it here.
    static let pillTabs: [LibraryTab] = [.songs, .albums, .artists, .account]

    var label: String {
        switch self {
        case .songs:   "Bài hát"
        case .albums:  "Album"
        case .artists: "Nghệ sĩ"
        case .account: "Tài khoản"
        case .search:  "Tìm kiếm"
        }
    }

    var symbol: String {
        switch self {
        case .songs:   "music.note.list"
        case .albums:  "square.stack"
        case .artists: "music.mic"
        case .account: "person.crop.circle"
        case .search:  "magnifyingglass"
        }
    }
}

/// The floating tab bar beneath the collapsed Now Playing pill: a pill holding
/// three destinations, and a separate circular search button beside it.
///
/// Labels in the pill are never hidden behind a size class or Dynamic Type
/// check — three items have the room, and unlabelled symbols are worse for
/// someone opening the app for the first time. The search button is the one
/// exception, and it carries an explicit accessibility label to compensate.
struct FloatingTabBar: View {
    @Binding var selection: LibraryTab
    /// Drives the morph between the three-tab bar and the search field.
    @Binding var isSearching: Bool
    @Binding var query: String
    /// Mirrors the field's focus outward, so callers can react to the keyboard
    /// actually being up rather than guessing from `isSearching`. The two are
    /// not the same: search opens without the keyboard.
    @Binding var isEditing: Bool
    /// Drives the morph between the three-tab bar and the minimised circle,
    /// set by a caller watching scroll direction. Never true at the same time
    /// as `isSearching` — see `trailingButton`, which clears this before
    /// handing off to `onOpenSearch`.
    @Binding var isMinimised: Bool

    /// Called when the trailing button opens search.
    let onOpenSearch: () -> Void
    /// Called when search closes. `nil` means "back where you came from";
    /// a tab means go there explicitly. The bar does not know the tab history —
    /// `RootView` owns it — so it says what it wants rather than deciding.
    let onCloseSearch: (LibraryTab?) -> Void
    /// Called when the minimised circle is tapped. Restores the full bar —
    /// it does not navigate, even though it is drawn with the current tab's
    /// icon. See the type-level doc for why.
    let onRestore: () -> Void

    @FocusState private var queryFocused: Bool

    /// `isMinimised`/`onRestore` default so every existing call site — today
    /// only `RootView` — keeps compiling untouched. `RootView` starts driving
    /// scroll-based minimising in a later task; until then the bar simply
    /// never receives `isMinimised = true` and behaves exactly as before.
    /// The synthesized memberwise init cannot supply these defaults itself
    /// (`@Binding` has no `init(wrappedValue:)`), hence the explicit init.
    init(
        selection: Binding<LibraryTab>,
        isSearching: Binding<Bool>,
        query: Binding<String>,
        isEditing: Binding<Bool>,
        isMinimised: Binding<Bool> = .constant(false),
        onOpenSearch: @escaping () -> Void,
        onCloseSearch: @escaping (LibraryTab?) -> Void,
        onRestore: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self._isSearching = isSearching
        self._query = query
        self._isEditing = isEditing
        self._isMinimised = isMinimised
        self.onOpenSearch = onOpenSearch
        self.onCloseSearch = onCloseSearch
        self.onRestore = onRestore
    }

    /// "The leading capsule is a circle." True for either morph that shrinks
    /// the four-tab pill down to one glyph. Everything that only cares about
    /// the capsule's *shape* reads this instead of `isSearching` directly, so
    /// minimising reuses the exact same collapse path rather than a second
    /// one. What still must stay keyed to `isSearching` alone — the search
    /// field's width, the trailing button's glyph/label, and the bar's
    /// height — does not go near this value.
    private var isCollapsed: Bool { isSearching || isMinimised }

    private static let symbolSize: CGFloat = 17
    /// The selected item's backing. Drawn over the material rather than
    /// replacing it, so it reads as a slightly darker patch of the same
    /// surface. `.primary` rather than a fixed grey so it inverts with the
    /// colour scheme: a 10% black wash in light mode, 10% white in dark, both
    /// separating the selected item from the bar around it.
    private static let selectionWash = 0.10

    /// How far the selected item's capsule sits inside the pill, on every side.
    ///
    /// A uniform inset is what makes the two shapes **concentric**, which is
    /// how the real thing looks. The pill is `tabBarHeight` tall, so its caps
    /// have radius `tabBarHeight / 2` = 28 and its leading cap is centred at
    /// (28, 28). Inset the inner capsule by 6 on every side and it is 44 tall,
    /// radius 22, with its leading cap centred at (6 + 22, 6 + 22) — the same
    /// point. The two curves stay parallel instead of drifting apart.
    ///
    /// This only holds if the selected item's backing fills its whole slot and
    /// is then inset. Sizing it to hug the icon and label instead — padding
    /// around the content — makes its width depend on how long each label is
    /// and pulls its leading edge away from the pill's curve, which is what
    /// this replaced.
    private static let selectionInset: CGFloat = 6

    /// The morph between the tab row and the search field. Owned here rather
    /// than by each caller so the bar cannot animate on two different curves
    /// depending on which button was pressed.
    ///
    /// Written as `duration`/`bounce` rather than `response`/`dampingFraction`.
    /// The two describe the same family of springs, but this pair says what it
    /// does: `duration` is roughly how long the move takes, and `bounce` is how
    /// far it overshoots before settling — 0 stops dead on arrival, 0.3 gives a
    /// visible spring past the target and back. The older pair inverts that
    /// second axis (higher damping means *less* bounce), which is what makes it
    /// awkward to tune by feel.
    ///
    /// The bounce is what keeps the collapse from reading as a mechanical
    /// slide. Raise it for more spring; much past 0.4 the bar starts to wobble
    /// rather than settle.
    static let searchSpring = Animation.spring(duration: 0.45, bounce: 0.32)

    /// How far the field's growth trails the tab pill's collapse, and the
    /// reverse on the way back. Short enough that the bar still feels like one
    /// gesture — much more and the two halves read as separate events.
    private static let stagger = 0.10

    /// How far each tab's reveal trails the one before it as the pill grows
    /// back. The pill expands from its leading edge, so its trailing edge
    /// sweeps past Bài hát, then Album, then Nghệ sĩ — and each tab should
    /// arrive as the edge reaches it, not before, or it appears in space the
    /// pill has not covered yet.
    ///
    /// Chosen to sit roughly where the sweeping edge is, not derived from it:
    /// reading the capsule's live width mid-animation would need a
    /// `GeometryReader` feeding state back into the same layout pass. Tune by
    /// eye — larger if the tabs still arrive early.
    private static let tabRevealStep = 0.08

    /// What each tab grows from. Small enough to read as arriving, large
    /// enough that the glyph never looks like a dot.
    private static let tabRevealScale = 0.55

    /// Shorter while searching: one text field needs less room than an icon
    /// stacked over a label.
    private var barHeight: CGFloat {
        isSearching ? BottomBarMetrics.searchBarHeight : BottomBarMetrics.tabBarHeight
    }

    /// Three slots whose widths carry the whole morph.
    ///
    /// Closed: the leading capsule takes all the room as the three-tab pill,
    /// the search capsule is zero-wide, and the trailing circle is the search
    /// button. Open: the leading capsule shrinks to a circle holding the way
    /// home, the search capsule grows into the gap it leaves, and the trailing
    /// circle becomes the close button.
    ///
    /// The two are **staggered**, which is what makes it read as one thing
    /// becoming another rather than everything sliding at once: opening, the
    /// tab pill collapses first and the field grows into the space afterwards;
    /// closing runs it backwards, the field folding away before the tabs
    /// return. Hence `.animation` per slot with a delay keyed on the direction,
    /// rather than one `withAnimation` at the call site — a single wrapper
    /// cannot give two subviews different timing.
    var body: some View {
        // Measured so the tabs can be laid out at the width the pill will
        // *end* at, rather than at whatever width it happens to be mid-morph.
        // See `leadingCapsule(expandedWidth:)` for why that matters.
        //
        // The outer fixed height keeps the reader from growing to fill the
        // screen, and the inner `alignment: .bottom` keeps the bar's bottom
        // edge still while its height changes — it is anchored to the bottom
        // of the screen, so shrinking should move its top, not lift it.
        GeometryReader { geo in
            content(availableWidth: geo.size.width)
                .frame(
                    width: geo.size.width,
                    height: BottomBarMetrics.tabBarHeight,
                    alignment: .bottom
                )
        }
        .frame(height: BottomBarMetrics.tabBarHeight)
        .padding(.horizontal, BottomBarMetrics.sideMargin)
        // Opening search deliberately does NOT raise the keyboard: the user
        // sees the field and taps it when they want to type. Closing does have
        // to drop focus explicitly, or the keyboard outlives the field that
        // owns it — the field stays in the hierarchy at opacity 0 rather than
        // being torn down, so it never loses focus on its own.
        .onChange(of: isSearching) { _, searching in
            if !searching { queryFocused = false }
        }
        .onChange(of: queryFocused) { _, focused in
            isEditing = focused
        }
    }

    private func content(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            leadingCapsule(
                expandedWidth: availableWidth
                    - BottomBarMetrics.tabBarSearchGap
                    - BottomBarMetrics.tabBarHeight
            )
            .animation(
                Self.searchSpring.delay(isCollapsed ? 0 : Self.stagger),
                value: isCollapsed
            )

            // Fixed, so the gap between the leading capsule and whatever
            // follows never collapses. The search capsule's own trailing gap
            // is conditional instead — at zero width it must contribute
            // nothing, or the closed bar would carry a phantom 8pt.
            //
            // The height is not decoration. `Color` is greedy in any axis left
            // unconstrained, so a width-only frame here stretches the whole
            // `HStack` to the height of its container and the bar ends up
            // centred in the middle of the screen instead of sitting at the
            // bottom.
            Color.clear.frame(width: BottomBarMetrics.tabBarSearchGap, height: barHeight)

            // The row's one flexible element while collapsed by either mode.
            // With `leadingCapsule` clamped to `barHeight` and `trailingButton`
            // fixed, *something* between them has to be greedy or the HStack
            // shrinks to its intrinsic width and the outer `.frame(width:
            // geo.size.width, alignment: .bottom)` — `.bottom` only pins the
            // vertical axis — centres that short row instead of pinning the
            // two circles to the leading and trailing edges. `searchCapsule`
            // already played this role for search; keying its width on
            // `isCollapsed` instead of `isSearching` lets minimising reuse it
            // rather than adding a second flexible element that would have to
            // be kept in lockstep with this one.
            //
            // The width this resolves to is not incidental: with `leadingCapsule`
            // at `tabBarHeight` (56) and this gap at `tabBarSearchGap` (8) on
            // each side, this capsule spans exactly
            // `[64, W − 64]` in the bar's own (post-`sideMargin`) coordinate
            // space — the same span Task 2 slots the collapsed player pill
            // into via `BottomBarMetrics.minimisedPlayerInset`. Landing on a
            // different span here would leave the player visibly out of line
            // with the two circles, with nothing in a build or a test to
            // catch it.
            searchCapsule
                .padding(.trailing, isCollapsed ? BottomBarMetrics.tabBarSearchGap : 0)
                .animation(
                    Self.searchSpring.delay(isCollapsed ? Self.stagger : 0),
                    value: isCollapsed
                )

            trailingButton
                .animation(Self.searchSpring, value: isSearching)
        }
    }

    /// The three-tab pill, collapsing to a circular way home.
    ///
    /// Both rows exist at all times and cross-fade, with the capsule's frame
    /// animating underneath them. Swapping them with `if`/`else` would tear one
    /// subtree down and build the other, and SwiftUI cannot animate a frame
    /// across that — the capsule would jump between its two widths instead of
    /// collapsing.
    ///
    /// The hidden row leaves hit-testing and accessibility too. Opacity alone
    /// keeps it tappable and readable by VoiceOver, so the tabs would still
    /// respond from behind the collapsed circle.
    /// - Parameter expandedWidth: the width this capsule reaches when the bar
    ///   is closed. The tabs are laid out at **that** width at all times, not
    ///   at the capsule's current one, and the capsule clips them.
    ///
    ///   Laying them out in the live width is what made them slide: collapsed,
    ///   four tabs sharing a 48pt circle are 12pt each and bunched at the left,
    ///   and every one of their centres travels rightwards as the capsule
    ///   grows. Pinned to the final width instead, each tab simply sits where
    ///   it belongs and the expanding clip uncovers it, so it can scale up in
    ///   place with nothing to slide.
    private func leadingCapsule(expandedWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // No opacity here: each tab fades and scales on its own schedule,
            // inside `tabsRow`. Hit-testing and accessibility stay at row
            // level, since those flip for the whole row at once.
            tabsRow
                .frame(width: expandedWidth, alignment: .leading)
                .allowsHitTesting(!isCollapsed)
                .accessibilityHidden(isCollapsed)

            // Two circles occupy the same spot and cross-fade, exactly like
            // `tabsRow`/`homeButton` above: mutual exclusion (`isCollapsed`'s
            // two branches) guarantees at most one of them is ever opaque, so
            // there is nothing to arbitrate between them.
            homeButton
                .opacity(isSearching ? 1 : 0)
                .allowsHitTesting(isSearching)
                .accessibilityHidden(!isSearching)

            restoreButton
                .opacity(isMinimised ? 1 : 0)
                .allowsHitTesting(isMinimised)
                .accessibilityHidden(!isMinimised)
        }
        // `maxWidth` rather than `width`: closed it takes everything the HStack
        // will give, open (searching or minimised) it is exactly as wide as it
        // is tall, which is what makes the capsule resolve to a circle.
        //
        // `alignment: .leading` is required, not tidy-up. `.frame(maxWidth:)`
        // centres its content, and this content is deliberately wider than the
        // frame while collapsed — centred, it overhangs equally on both sides
        // and the home glyph, which sits at the content's leading edge, ends up
        // outside the clip entirely. The circle renders empty.
        .frame(maxWidth: isCollapsed ? barHeight : .infinity, alignment: .leading)
        .frame(height: barHeight)
        .background(.regularMaterial, in: Capsule())
        // Load-bearing, not cosmetic: `tabsRow` is deliberately wider than this
        // capsule while it is collapsed, and without the clip those tabs draw
        // straight across the search field beside it.
        .clipShape(Capsule())
    }

    /// Sized to the collapsed circle rather than filling. In a leading-aligned
    /// `ZStack` whose other child is deliberately over-wide, `maxWidth:
    /// .infinity` would stretch this across that whole width and put the glyph
    /// somewhere off in the middle of the search field.
    private var homeButton: some View {
        Button {
            onCloseSearch(.songs)
        } label: {
            Image(systemName: LibraryTab.songs.symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(.secondary)
                .frame(width: barHeight, height: barHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Về \(LibraryTab.songs.label)")
    }

    /// The minimised circle. Shows the **currently selected tab's** icon
    /// rather than a fixed glyph — it says where you are, which a fixed icon
    /// cannot — but tapping it does not navigate there. It restores the full
    /// bar. Nothing else on screen offers a way back other than scrolling up,
    /// and a circle that looks tappable and only navigates would be a trap.
    ///
    /// The accessibility label says what the tap *does*, not where the icon
    /// points: read on its own, a bare tab glyph announces a destination, and
    /// this button does not go there.
    private var restoreButton: some View {
        Button {
            onRestore()
        } label: {
            Image(systemName: selection.symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(.secondary)
                .frame(width: barHeight, height: barHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hiện thanh điều hướng")
    }

    /// Zero-wide when closed, so it takes up no room and contributes no gap;
    /// flexible whenever the row is collapsed — by search **or** by
    /// minimising, so this stays the row's one flexible slot in either mode
    /// rather than a second one being added. `.clipShape` matters at zero
    /// width — without it the field and its icon spill out of a capsule that
    /// has no room for them.
    ///
    /// Content, visibility, hit-testing and accessibility all stay keyed to
    /// `isSearching` alone: while minimised this is reserved, invisible
    /// space — there is no field to show or interact with, only room held
    /// open for the collapsed player (Task 2) to occupy from outside this
    /// view.
    private var searchCapsule: some View {
        searchRow
            .frame(maxWidth: isCollapsed ? .infinity : 0)
            .frame(height: barHeight)
            .background(.regularMaterial, in: Capsule())
            .clipShape(Capsule())
            .opacity(isSearching ? 1 : 0)
            .allowsHitTesting(isSearching)
            .accessibilityHidden(!isSearching)
    }

    /// Each tab scales up in place as the pill's edge reaches it, rather than
    /// the row cross-fading as one — which put all three on screen while the
    /// pill was still a circle, in space it had not grown into yet.
    private var tabsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(LibraryTab.pillTabs.enumerated()), id: \.element.id) { index, tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: Self.symbolSize))
                        Text(tab.label)
                            .font(.caption2)
                    }
                    .foregroundStyle(selection == tab ? .primary : .secondary)
                    // Fill the slot first, then inset the backing — see
                    // `selectionInset`. Doing it the other way round (padding
                    // the content and letting the capsule hug it) sizes the
                    // backing to the label's length and breaks the concentric
                    // curve at the pill's leading edge.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Color.primary.opacity(Self.selectionWash))
                                .padding(Self.selectionInset)
                        }
                    }
                }
                .buttonStyle(.plain)
                // `.isButton` is restated alongside `.isSelected` only so
                // both branches of the ternary share one type — `Button`
                // already carries `.isButton` on its own, and
                // `accessibilityAddTraits` is additive, so this never removes
                // it. `.isSelected` is what makes VoiceOver announce which
                // tab is current.
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                // Scaled about its own centre, so it grows where it belongs
                // instead of sliding in from anywhere. Keyed on `isCollapsed`,
                // not `isSearching` alone — this is the tab reveal, and it
                // must run identically whichever mode collapsed the pill.
                .scaleEffect(isCollapsed ? Self.tabRevealScale : 1)
                .opacity(isCollapsed ? 0 : 1)
                .animation(
                    Self.searchSpring.delay(Self.tabRevealDelay(index, isCollapsed: isCollapsed)),
                    value: isCollapsed
                )
            }
        }
    }

    /// Collapsing, the three go together and get out of the way — the pill is
    /// shrinking past them and anything left behind would be clipped mid-fade.
    /// Expanding, they arrive one after another, trailing the capsule's own
    /// delay so the first tab is not already there when the pill starts to
    /// grow. Applies the same whether the pill is expanding out of search or
    /// out of minimised — both grow through the identical clip.
    private static func tabRevealDelay(_ index: Int, isCollapsed: Bool) -> Double {
        isCollapsed ? 0 : stagger + Double(index) * tabRevealStep
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: LibraryTab.search.symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(.secondary)

            TextField("Bài hát, nghệ sĩ, album", text: $query)
                .textFieldStyle(.plain)
                .focused($queryFocused)
                .submitLabel(.search)
                // A library search is over titles and names the user already
                // has; autocorrecting "Biển" into a dictionary word, or
                // capitalising a lowercase artist name, only fights them.
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.leading, Self.selectionInset)
        .padding(.trailing, 16)
    }

    /// Opens search, then becomes the way out of it. Square frame at the bar's
    /// own height clipped to a circle, so it stays circular at either height
    /// and always matches the pill beside it.
    private var trailingButton: some View {
        Button {
            if isSearching {
                onCloseSearch(nil)
            } else {
                // Mutual exclusion enforced here, not hoped for from the
                // caller: minimised and searching both drive the leading
                // capsule, so opening search restores the bar first. This
                // binding write happens before `onOpenSearch()` sets
                // `isSearching`, in the same action, so the two flags are
                // never both true in any render this view produces.
                isMinimised = false
                onOpenSearch()
            }
        } label: {
            Image(systemName: isSearching ? "xmark" : LibraryTab.search.symbol)
                .font(.system(size: Self.symbolSize))
                // The one glyph that changes meaning mid-animation, so it
                // swaps on the same curve as the bar rather than popping.
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(selection == .search ? .primary : .secondary)
                .frame(width: barHeight, height: barHeight)
                .background {
                    ZStack {
                        Circle().fill(.regularMaterial)
                        if selection == .search {
                            Circle().fill(Color.primary.opacity(Self.selectionWash))
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        // Never carries visible text, and its meaning flips, so the label has
        // to flip with it. Without one, VoiceOver reads the symbol's own
        // description — "magnifying glass", or "xmark" — instead of what the
        // button does.
        .accessibilityLabel(isSearching ? "Đóng tìm kiếm" : LibraryTab.search.label)
        .accessibilityAddTraits(selection == .search ? [.isButton, .isSelected] : .isButton)
    }
}

/// `.regularMaterial` needs content behind it to read as translucent rather
/// than flat grey — a gradient stands in for the library content that sits
/// behind the real bar. A wrapper view (rather than `@Previewable @State`)
/// so the binding has somewhere to live.
private struct FloatingTabBarPreview: View {
    @State private var selection: LibraryTab = .albums
    @State private var isSearching = false
    @State private var query = ""
    @State private var isEditing = false
    @State private var isMinimised = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.blue, .purple, .orange],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Stands in for the real trigger — `RootView`'s scroll detection,
            // Task 3 — so the minimised mode can be seen in the canvas.
            // Wrapped in the same spring the bar itself uses, matching how
            // `RootView` will drive `isMinimised` in Task 4: unlike
            // `isSearching`, nothing inside `FloatingTabBar` owns this
            // transition's timing on the caller's behalf.
            VStack {
                Button(isMinimised ? "Restore" : "Minimise") {
                    withAnimation(FloatingTabBar.searchSpring) {
                        isMinimised.toggle()
                    }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.top, 60)

            FloatingTabBar(
                selection: $selection,
                isSearching: $isSearching,
                query: $query,
                isEditing: $isEditing,
                isMinimised: $isMinimised,
                // Unwrapped, matching `RootView` — the bar owns its own timing,
                // and a `withAnimation` here would flatten the stagger.
                onOpenSearch: {
                    selection = .search
                    isSearching = true
                },
                onCloseSearch: { destination in
                    selection = destination ?? .albums
                    isSearching = false
                    query = ""
                },
                onRestore: {
                    withAnimation(FloatingTabBar.searchSpring) {
                        isMinimised = false
                    }
                }
            )
            .padding(.bottom, BottomBarMetrics.tabBarBottomGap)
        }
    }
}

#Preview {
    FloatingTabBarPreview()
}
