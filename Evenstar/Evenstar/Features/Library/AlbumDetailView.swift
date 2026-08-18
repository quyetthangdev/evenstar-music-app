import SwiftUI
import SwiftData

struct AlbumDetailView: View {
    let album: AlbumGroup

    /// Owned by `RootView` and threaded here through `AlbumsView`'s
    /// `navigationDestination`. A pushed screen still scrolls under the same
    /// floating bars as a tab root, so it minimises them the same way — Đợt A's
    /// Critical defect was exactly this screen being left out of a bottom-bar
    /// treatment the four tab roots got.
    @Binding var isMinimised: Bool

    @Environment(PlaybackService.self) private var playback
    /// Where this screen's rows come from. `AlbumGroup` carries no `Track` any
    /// more — see its doc — so the album's tracks are resolved here, per pass,
    /// against the one array in the app that is guaranteed free of deleted
    /// rows: `LibraryStore.remove(_:)` drops a row *before* `context.delete`
    /// runs, synchronously, in the same call.
    ///
    /// A snapshot handed in at push time would have been cheaper and wrong in
    /// two ways at once: it would go stale the moment the album changed under
    /// a pushed screen, and it would put dead rows back in a view's hands —
    /// deleting the playing track is reachable from the row this very screen
    /// lists, through the player.
    @Environment(LibraryStore.self) private var store

    var body: some View {
        // Resolved once per pass and passed down, rather than recomputed by
        // three separate reads. The cost is one filter plus one sort of this
        // album's rows, on a body that runs when the library changes or when
        // `isMinimised` flips — which `ScrollMinimise` writes only on an
        // actual change, twice per scroll gesture at most, not per frame.
        let tracks = LibraryGrouping.tracks(inAlbum: album, from: store.tracks)
        return List {
            Section {
                VStack(spacing: 8) {
                    // Read off the live first row rather than
                    // `album.artworkRelativePath`, so replacing the cover
                    // shows here immediately instead of waiting for the value
                    // snapshotted on the navigation path to be rebuilt.
                    ArtworkThumbnail(relativePath: tracks.first?.artworkRelativePath, size: 200)
                    Text(album.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(album.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.vertical, 16)
            }
            // `tracks` already arrives in running order (disc, then track
            // number, then title) from `LibraryGrouping.tracks(inAlbum:from:)`
            // — it must not be sorted again here, and never sorted by title.
            Section {
                ForEach(tracks) { track in
                    SongRow(track: track)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playback.play(track, in: tracks)
                        }
                }
            }
        }
        .listStyle(.plain)
        .minimisesBottomBar($isMinimised)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        // See the note in `SongsView`: this hides the system tab bar
        // and must sit on the tab's content, not on the `TabView`.
        .toolbar(.hidden, for: .tabBar)
        .clearsBottomBar()
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
    let tracks = [
        Track(title: "Sunrise", artistName: "Alpha", albumTitle: "Greatest Hits",
              trackNumber: 1, discNumber: 1, durationSeconds: 180,
              relativePath: "a.mp3", format: "mp3"),
        Track(title: "Sunset", artistName: "Alpha", albumTitle: "Greatest Hits",
              trackNumber: 2, discNumber: 1, durationSeconds: 200,
              relativePath: "b.mp3", format: "mp3")
    ]
    for track in tracks {
        container.mainContext.insert(track)
    }
    let album = AlbumGroup(id: "Greatest Hits\u{0}Alpha",
                           title: "Greatest Hits",
                           artist: "Alpha",
                           artworkRelativePath: nil)
    return NavigationStack {
        AlbumDetailView(album: album, isMinimised: .constant(false))
    }
    .environment(playback)
    // Seeded by hand: `LibraryQueryBridge` lives in `RootView`, so a preview of
    // one screen has no query keeping the store in step with the container —
    // and this screen resolves its rows from the store.
    .environment(LibraryStore(tracks: tracks))
    .modelContainer(container)
}
