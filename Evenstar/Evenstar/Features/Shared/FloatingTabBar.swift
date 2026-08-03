import SwiftUI

enum LibraryTab: String, CaseIterable, Identifiable {
    case songs, albums, artists, search
    var id: String { rawValue }

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

/// The floating pill tab bar beneath the collapsed Now Playing pill.
///
/// Labels are never hidden behind a size class or Dynamic Type check — a
/// four-item bar has the room, and unlabelled symbols are worse for someone
/// opening the app for the first time.
struct FloatingTabBar: View {
    @Binding var selection: LibraryTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20))
                        Text(tab.label)
                            .font(.caption2)
                    }
                    .foregroundStyle(selection == tab ? .primary : .secondary)
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
        .frame(height: BottomBarMetrics.tabBarHeight)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, BottomBarMetrics.sideMargin)
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
