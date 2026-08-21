import SwiftUI
import SwiftData

struct ArtistDetailView: View {
    let artist: ArtistGroup

    /// Owned by `RootView` and threaded here through `ArtistsView`'s
    /// `navigationDestination`. A pushed screen still scrolls under the same
    /// floating bars as a tab root, so it minimises them the same way — Đợt A's
    /// Critical defect was exactly this screen being left out of a bottom-bar
    /// treatment the four tab roots got.
    @Binding var isMinimised: Bool

    @Environment(PlaybackService.self) private var playback
    /// Where this screen's rows come from. See the same property on
    /// `AlbumDetailView` for why they are resolved here rather than carried
    /// inside `ArtistGroup`.
    @Environment(LibraryStore.self) private var store

    var body: some View {
        // The artist's tracks, grouped into albums and flattened: album order
        // and running order both come from
        // `LibraryGrouping.tracks(byArtist:from:)`, which shares its grouping
        // with `albums(from:)`. No second sort here — writing one would risk
        // disagreeing with the grouping and drifting out of step.
        let tracks = LibraryGrouping.tracks(byArtist: artist, from: store.tracks)
        return List {
            ForEach(tracks) { track in
                SongRow(track: track, isAbsent: !store.isPresent(track))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Xem ghi chú cùng chỗ trong `AlbumDetailView`.
                        guard store.isPresent(track) else { return }
                        playback.play(track, in: tracks)
                    }
            }
        }
        .listStyle(.plain)
        .minimisesBottomBar($isMinimised)
        .navigationTitle(artist.name)
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
              relativePath: "b.mp3", format: "mp3"),
        Track(title: "Encore", artistName: "Alpha", albumTitle: "Live",
              trackNumber: 1, discNumber: 1, durationSeconds: 210,
              relativePath: "c.mp3", format: "mp3")
    ]
    for track in tracks {
        container.mainContext.insert(track)
    }
    let artist = ArtistGroup(id: "Alpha", name: "Alpha", artworkRelativePath: nil)
    return NavigationStack {
        ArtistDetailView(artist: artist, isMinimised: .constant(false))
    }
    .environment(playback)
    // Seeded by hand — see the same note in `AlbumDetailView`'s preview,
    // including why `presence` has to name the sample tracks' paths.
    .environment(LibraryStore(tracks: tracks,
                              presence: .known(["a.mp3", "b.mp3", "c.mp3"])))
    .modelContainer(container)
}
