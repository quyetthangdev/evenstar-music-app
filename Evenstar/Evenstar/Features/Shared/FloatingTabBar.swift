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
                    // Padding then background then the flexible frame, in that
                    // order: the wash hugs the icon and label, while the
                    // button still fills its share of the width so the whole
                    // column stays tappable rather than only the wash.
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background {
                        if selection == tab {
                            Capsule().fill(Color.primary.opacity(Self.selectionWash))
                        }
                    }
                    .frame(maxWidth: .infinity)
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
