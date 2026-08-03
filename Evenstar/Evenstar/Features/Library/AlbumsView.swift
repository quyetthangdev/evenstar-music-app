import SwiftUI
import SwiftData

struct AlbumsView: View {
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Album")
                // Hoisted above the empty/non-empty branch in `content` so it
                // stays attached to the navigation path even if the library
                // empties while an album detail screen is pushed — a
                // destination declared only inside one branch leaves the
                // hierarchy with the branch, stranding a value on the path.
                .navigationDestination(for: AlbumGroup.self) { album in
                    AlbumDetailView(album: album)
                }
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
        let albums = LibraryGrouping.albums(from: tracks)
        if albums.isEmpty {
            ContentUnavailableView(
                "Chưa có album",
                systemImage: "square.stack",
                description: Text("Nhập nhạc để thấy album ở đây.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumCell(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
    }
}

private struct AlbumCell: View {
    let album: AlbumGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ArtworkThumbnail(relativePath: album.tracks.first?.artworkRelativePath, size: geometry.size.width)
            }
            // Square cell: width comes from the grid column, height matches it.
            .aspectRatio(1, contentMode: .fit)
            Text(album.title)
                .font(.subheadline)
                .lineLimit(1)
            Text(album.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        Track(title: "Sunset", artistName: "Alpha", albumTitle: "Greatest Hits",
              trackNumber: 2, discNumber: 1, durationSeconds: 200,
              relativePath: "b.mp3", format: "mp3"),
        Track(title: "Nocturne", artistName: "Beta", albumTitle: "Night Songs",
              trackNumber: 1, discNumber: 1, durationSeconds: 220,
              relativePath: "c.mp3", format: "mp3")
    ]
    for track in tracksToInsert {
        container.mainContext.insert(track)
    }
    return AlbumsView()
        .environment(library)
        .environment(playback)
        .modelContainer(container)
}
