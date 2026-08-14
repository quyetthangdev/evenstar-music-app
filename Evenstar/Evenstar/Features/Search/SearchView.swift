import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(PlaybackService.self) private var playback
    /// The local library, fetched once for the whole app — see `LibraryStore`.
    ///
    /// Read only from the branch below that actually searches, so while the
    /// query is empty — which is most of this screen's life, including every
    /// moment it is not on screen and holding its last state — this screen has
    /// no dependency on the library and is not rebuilt when it changes.
    @Environment(LibraryStore.self) private var store

    /// Read-only, and owned by `RootView`. The field that edits it lives in the
    /// floating tab bar, which is a sibling of the `TabView` this screen sits
    /// in — so this screen cannot own it, and must not add a second search
    /// field of its own.
    let query: String

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tìm kiếm")
                // See the note in `SongsView`: this hides the system tab bar
                // and must sit on the tab's content, not on the `TabView`.
                .toolbar(.hidden, for: .tabBar)
                // Deliberately kept, unlike `minimisesBottomBar` below: this
                // screen does not fold the bar, but the bar is still on top of
                // its results and its last row still has to clear it.
                .clearsBottomBar()
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
            let results = LibraryGrouping.search(query, in: store.tracks)
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
                // Deliberately NOT `.minimisesBottomBar`. This list is on
                // screen only while `isSearching` is true, and by then the
                // bar is already collapsed into its three-slot search form —
                // there is no four-tab pill left to fold, so minimising here
                // has no meaning of its own. It used to carry the modifier
                // anyway, and scrolling the results set `isMinimised` true
                // behind `isSearching`: the leading capsule showed both the
                // home glyph and the restore glyph at once, the restore
                // button stole the tap meant to close search, and the 56pt
                // minimised player pill landed on top of the 48pt search
                // field and blocked it. Out of scope by design, the same way
                // `ImportProgressSheet` is never wired up: neither is one of
                // the screens the scroll modifier applies to. Do not add this
                // back "for coverage" — see Finding 1 of the whole-plan
                // review (2026-08-03).
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
    // Seeded by hand — see the same note in `AlbumsView`'s preview.
    return SearchView(query: "biển")
        .environment(library)
        .environment(playback)
        .environment(LibraryStore(tracks: tracksToInsert))
        .modelContainer(container)
}
