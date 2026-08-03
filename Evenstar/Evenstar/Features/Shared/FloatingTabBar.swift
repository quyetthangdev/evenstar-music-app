import SwiftUI

enum LibraryTab: String, Identifiable {
    case songs, albums, artists, search
    var id: String { rawValue }

    /// The three that share the pill. Search is deliberately absent: it lives
    /// in its own circular button beside the pill.
    ///
    /// `CaseIterable` is deliberately NOT adopted. With it, `allCases` reads
    /// as the obvious way to lay out "the tabs", and using it would draw
    /// search twice — once in the pill and once in its own button. Leaving the
    /// conformance off makes that mistake impossible rather than merely
    /// warned against. Adding a destination means adding it here.
    static let pillTabs: [LibraryTab] = [.songs, .albums, .artists]

    var label: String {
        switch self {
        case .songs:   "Bài hát"
        case .albums:  "Album"
        case .artists: "Nghệ sĩ"
        case .search:  "Tìm kiếm"
        }
    }

    var symbol: String {
        switch self {
        case .songs:   "music.note.list"
        case .albums:  "square.stack"
        case .artists: "music.mic"
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

    /// Called when the trailing button opens search.
    let onOpenSearch: () -> Void
    /// Called when search closes. `nil` means "back where you came from";
    /// a tab means go there explicitly. The bar does not know the tab history —
    /// `RootView` owns it — so it says what it wants rather than deciding.
    let onCloseSearch: (LibraryTab?) -> Void

    @FocusState private var queryFocused: Bool

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
    static let searchSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// Shorter while searching: one text field needs less room than an icon
    /// stacked over a label.
    private var barHeight: CGFloat {
        isSearching ? BottomBarMetrics.searchBarHeight : BottomBarMetrics.tabBarHeight
    }

    var body: some View {
        HStack(spacing: BottomBarMetrics.tabBarSearchGap) {
            pill
            trailingButton
        }
        .padding(.horizontal, BottomBarMetrics.sideMargin)
        // The field is in the hierarchy in both states so the pill's frame can
        // animate through the change instead of one subtree being torn down and
        // another built. Focus therefore has to be driven explicitly — an
        // offscreen field neither takes nor gives up the keyboard on its own.
        .onChange(of: isSearching) { _, searching in
            queryFocused = searching
        }
    }

    /// Both rows exist at all times, cross-fading, with the capsule's height
    /// animating underneath them. Swapping them with `if`/`else` instead would
    /// tear one subtree down and build the other, and SwiftUI cannot animate a
    /// frame across that — the bar would jump between the two heights.
    ///
    /// The hidden row is taken out of hit-testing and out of accessibility.
    /// Opacity alone leaves it tappable and readable by VoiceOver, so the tabs
    /// would still respond behind the search field and vice versa.
    private var pill: some View {
        ZStack {
            tabsRow
                .opacity(isSearching ? 0 : 1)
                .allowsHitTesting(!isSearching)
                .accessibilityHidden(isSearching)

            searchRow
                .opacity(isSearching ? 1 : 0)
                .allowsHitTesting(isSearching)
                .accessibilityHidden(!isSearching)
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
        .background(.regularMaterial, in: Capsule())
    }

    private var tabsRow: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.pillTabs) { tab in
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
            }
        }
    }

    /// Searching: a way home on the left, the field filling the rest.
    private var searchRow: some View {
        HStack(spacing: 10) {
            Button {
                onCloseSearch(.songs)
            } label: {
                Image(systemName: LibraryTab.songs.symbol)
                    .font(.system(size: Self.symbolSize))
                    .foregroundStyle(.secondary)
                    // Inset from the capsule by the same amount the selected
                    // tab's backing is, so this circle is concentric with the
                    // pill's leading cap too.
                    .frame(
                        width: barHeight - Self.selectionInset * 2,
                        height: barHeight - Self.selectionInset * 2
                    )
                    .background(Circle().fill(Color.primary.opacity(Self.selectionWash)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Về \(LibraryTab.songs.label)")

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

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.blue, .purple, .orange],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            FloatingTabBar(
                selection: $selection,
                isSearching: $isSearching,
                query: $query,
                onOpenSearch: {
                    withAnimation(FloatingTabBar.searchSpring) {
                        selection = .search
                        isSearching = true
                    }
                },
                onCloseSearch: { destination in
                    withAnimation(FloatingTabBar.searchSpring) {
                        selection = destination ?? .albums
                        isSearching = false
                        query = ""
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
