import SwiftUI
import SwiftData

struct ArtistDetailView: View {
    let artist: ArtistGroup

    @Environment(PlaybackService.self) private var playback

    // The artist's tracks, grouped into albums and flattened: album order
    // comes from `albums(from:)`, running order within each album comes
    // from `sortedAlbumTracks` inside it. No second sort here — writing one
    // would risk disagreeing with the grouping and drifting out of step.
    private var orderedTracks: [Track] {
        LibraryGrouping.albums(from: artist.tracks).flatMap(\.tracks)
    }

    var body: some View {
        List {
            ForEach(orderedTracks) { track in
                SongRow(track: track)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playback.play(track, in: orderedTracks)
                    }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
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
    let artist = ArtistGroup(id: "Alpha", name: "Alpha", tracks: tracks)
    return NavigationStack {
        ArtistDetailView(artist: artist)
    }
    .environment(playback)
}
