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
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        // `collapsedClearance`, not `collapsedHeight`: the
                        // collapsed player is a pill floating above the
                        // safe area, so the last row must clear the gap
                        // beneath it as well as the bar itself.
                        .frame(height: playback.currentTrack == nil ? 0 : PlayerCard.collapsedClearance)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let artists = LibraryGrouping.artists(from: tracks)
        if artists.isEmpty {
            ContentUnavailableView(
                "No Artists",
                systemImage: "music.mic",
                description: Text("Import music to see your artists here.")
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
            .navigationDestination(for: ArtistGroup.self) { artist in
                ArtistDetailView(artist: artist)
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
