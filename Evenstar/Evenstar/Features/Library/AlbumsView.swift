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
        let albums = LibraryGrouping.albums(from: tracks)
        if albums.isEmpty {
            ContentUnavailableView(
                "No Albums",
                systemImage: "square.stack",
                description: Text("Import music to see your albums here.")
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
            .navigationDestination(for: AlbumGroup.self) { album in
                AlbumDetailView(album: album)
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

/// `NavigationLink(value:)` requires `Hashable`. `AlbumGroup` lives in
/// `LibraryGrouping.swift`, which this task must not modify, so the
/// conformance is added here instead. Identity follows `id` — the same
/// title+artist key `LibraryGrouping` already uses to keep albums distinct.
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
