import SwiftUI
import SwiftData

struct AlbumDetailView: View {
    let album: AlbumGroup

    @Environment(PlaybackService.self) private var playback

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    ArtworkThumbnail(relativePath: album.tracks.first?.artworkRelativePath, size: 200)
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
            // `album.tracks` already arrives in running order (disc, then
            // track number, then title) from `LibraryGrouping` — it must not
            // be sorted again here, and never sorted by title.
            Section {
                ForEach(album.tracks) { track in
                    SongRow(track: track)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playback.play(track, in: album.tracks)
                        }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
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
    let album = AlbumGroup(id: "Greatest Hits\u{0}Alpha", title: "Greatest Hits", artist: "Alpha", tracks: tracks)
    return NavigationStack {
        AlbumDetailView(album: album)
    }
    .environment(playback)
}
