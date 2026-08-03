import SwiftUI
import SwiftData

struct ArtistsView: View {
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Nghệ sĩ")
                // Hoisted above the empty/non-empty branch in `content` so it
                // stays attached to the navigation path even if the library
                // empties while an artist detail screen is pushed — a
                // destination declared only inside one branch leaves the
                // hierarchy with the branch, stranding a value on the path.
                .navigationDestination(for: ArtistGroup.self) { artist in
                    ArtistDetailView(artist: artist)
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
        let artists = LibraryGrouping.artists(from: tracks)
        if artists.isEmpty {
            ContentUnavailableView(
                "Chưa có nghệ sĩ",
                systemImage: "music.mic",
                description: Text("Nhập nhạc để thấy nghệ sĩ ở đây.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            ArtistCell(artist: artist)
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

private struct ArtistCell: View {
    let artist: ArtistGroup

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ArtworkThumbnail(relativePath: artist.tracks.first?.artworkRelativePath, size: geometry.size.width)
                    .clipShape(Circle())
            }
            // Square cell: width comes from the grid column, height matches it.
            .aspectRatio(1, contentMode: .fit)
            Text(artist.name)
                .font(.subheadline)
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
    return ArtistsView()
        .environment(library)
        .environment(playback)
        .modelContainer(container)
}
