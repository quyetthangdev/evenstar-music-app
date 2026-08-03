import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]

    /// Read-only, and owned by `RootView`. The field that edits it lives in the
    /// floating tab bar, which is a sibling of the `TabView` this screen sits
    /// in — so this screen cannot own it, and must not add a second search
    /// field of its own.
    let query: String

    /// Owned by `RootView`, which drives both the tab bar and the player from
    /// it. Written here only by `minimisesBottomBar` on this screen's results
    /// list.
    @Binding var isMinimised: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tìm kiếm")
                // See the note in `SongsView`: this hides the system tab bar
                // and must sit on the tab's content, not on the `TabView`.
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        // Never 0: the floating tab bar is always present, so
                        // the last row must clear it whether or not a track is
                        // loaded.
                        .frame(
                            height: playback.currentTrack == nil
                                ? BottomBarMetrics.clearanceTabBarOnly
                                : BottomBarMetrics.clearanceWithPlayer
                        )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Tìm trong thư viện",
                systemImage: "magnifyingglass",
                description: Text("Tìm theo tên bài hát, nghệ sĩ hoặc album.")
            )
        } else {
            // `LibraryGrouping.search` owns matching — case- and
            // diacritic-insensitive — so this view never re-implements it.
            let results = LibraryGrouping.search(query, in: tracks)
            if results.isEmpty {
                // Hand-written rather than `ContentUnavailableView.search(text:)`.
                // That convenience draws its title and description from the
                // framework, resolved against the app's declared localizations —
                // and this app declares none, with `developmentRegion = en`. So
                // it renders an English "No Results" between a Vietnamese title
                // above it and a Vietnamese prompt one state away, on a
                // Vietnamese user's device, no matter what the system language
                // is. Any other system-supplied string added here has the same
                // problem until the project gains a `vi` localization.
                ContentUnavailableView(
                    "Không tìm thấy kết quả",
                    systemImage: "magnifyingglass",
                    description: Text("Không có bài hát, nghệ sĩ hay album nào khớp với “\(query)”.")
                )
            } else {
                List(results) { track in
                    SongRow(track: track)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // The queue is the current result set, not the
                            // whole library, so the "next" track is the one
                            // below the tapped row in this list.
                            playback.play(track, in: results)
                        }
                }
                .listStyle(.plain)
                // On the scrollable container itself rather than on the branch
                // above it, so what the modifier observes is unambiguous.
                .minimisesBottomBar($isMinimised)
            }
        }
    }
}

#Preview {
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Track.self, PlaybackState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create preview ModelContainer: \(error)")
    }
    let library = LibraryService(context: container.mainContext)
    let playback = PlaybackService(
        player: AVAudioPlayerWrapper(),
        nowPlaying: NowPlayingService(),
        library: library
    )
    let tracksToInsert = [
        Track(title: "Sunrise", artistName: "Alpha", albumTitle: "Greatest Hits",
              trackNumber: 1, discNumber: 1, durationSeconds: 180,
              relativePath: "a.mp3", format: "mp3"),
        Track(title: "Biển nhớ", artistName: "Beta", albumTitle: "Night Songs",
              trackNumber: 1, discNumber: 1, durationSeconds: 220,
              relativePath: "c.mp3", format: "mp3")
    ]
    for track in tracksToInsert {
        container.mainContext.insert(track)
    }
    return SearchView(query: "biển", isMinimised: .constant(false))
        .environment(library)
        .environment(playback)
        .modelContainer(container)
}
