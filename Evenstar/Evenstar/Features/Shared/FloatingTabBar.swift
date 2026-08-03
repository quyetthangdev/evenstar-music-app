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

    var body: some View {
        HStack(spacing: BottomBarMetrics.tabBarSearchGap) {
            pill
            searchButton
        }
        .padding(.horizontal, BottomBarMetrics.sideMargin)
    }

    private var pill: some View {
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
        .frame(maxWidth: .infinity)
        .frame(height: BottomBarMetrics.tabBarHeight)
        .background(.regularMaterial, in: Capsule())
    }

    /// Square frame at the bar's own height, clipped to a circle, so the button
    /// is exactly as tall as the pill it sits beside and stays circular
    /// wherever `tabBarHeight` goes.
    private var searchButton: some View {
        Button {
            selection = .search
        } label: {
            Image(systemName: LibraryTab.search.symbol)
                .font(.system(size: Self.symbolSize))
                .foregroundStyle(selection == .search ? .primary : .secondary)
                .frame(
                    width: BottomBarMetrics.tabBarHeight,
                    height: BottomBarMetrics.tabBarHeight
                )
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
        // The only item in the bar with no visible text. Without this,
        // VoiceOver falls back to the symbol's own description — "magnifying
        // glass" — instead of the destination's name.
        .accessibilityLabel(LibraryTab.search.label)
        .accessibilityAddTraits(selection == .search ? [.isButton, .isSelected] : .isButton)
    }
}

/// `.regularMaterial` needs content behind it to read as translucent rather
/// than flat grey — a gradient stands in for the library content that sits
/// behind the real bar. A wrapper view (rather than `@Previewable @State`)
/// so the binding has somewhere to live.
private struct FloatingTabBarPreview: View {
    @State private var selection: LibraryTab = .albums

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.blue, .purple, .orange],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            FloatingTabBar(selection: $selection)
                .padding(.bottom, BottomBarMetrics.tabBarBottomGap)
        }
    }
}

#Preview {
    FloatingTabBarPreview()
}
