import SwiftUI
import SwiftData

struct ArtistsView: View {
    // No `PlaybackService` here any more: the only thing this screen read it
    // for was choosing between the two bottom clearances, and `clearsBottomBar`
    // now owns that decision along with the arithmetic behind it.
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]

    /// Owned by `RootView`. Written by `minimisesBottomBar` on this screen's
    /// grid, and **passed on to `ArtistDetailView`** — that screen is a pushed
    /// destination declared here, so this is the only route the flag has to
    /// reach it. Đợt A shipped a Critical defect by treating the four tab roots
    /// and missing the two pushed detail screens.
    @Binding var isMinimised: Bool

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
                    ArtistDetailView(artist: artist, isMinimised: $isMinimised)
                }
                // See the note in `SongsView`: this hides the system tab bar
                // and must sit on the tab's content, not on the `TabView`.
                .toolbar(.hidden, for: .tabBar)
                .clearsBottomBar()
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
            // On the `ScrollView` itself rather than on the branch above it,
            // so what the modifier observes is unambiguous.
            .minimisesBottomBar($isMinimised)
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
    return ArtistsView(isMinimised: .constant(false))
        .environment(library)
        .environment(playback)
        .modelContainer(container)
}
