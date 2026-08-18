import SwiftUI
import SwiftData

struct AlbumsView: View {
    // No `PlaybackService` here any more: the only thing this screen read it
    // for was choosing between the two bottom clearances, and `clearsBottomBar`
    // now owns that decision along with the arithmetic behind it.
    @Environment(LibraryService.self) private var library
    /// The local library, fetched once for the whole app — see `LibraryStore`.
    /// This screen never held the query for the rows themselves, only to know
    /// when to regroup, and that trigger is unchanged: the store publishes the
    /// same array, from the same fetch, in the same order.
    @Environment(LibraryStore.self) private var store

    /// Owned by `RootView`. Written by `minimisesBottomBar` on this screen's
    /// grid, and **passed on to `AlbumDetailView`** — that screen is a pushed
    /// destination declared here, so this is the only route the flag has to
    /// reach it. Đợt A shipped a Critical defect by treating the four tab roots
    /// and missing the two pushed detail screens.
    @Binding var isMinimised: Bool

    /// The grouped library, recomputed only when `tracks` actually changes.
    ///
    /// **This array is allowed to be one update stale, and that is only safe
    /// because an `AlbumGroup` holds no `Track`.** The staleness is structural:
    /// `onChange`'s action runs *after* the update pass that triggered it, so
    /// between a `context.delete` + `save()` and the regroup below, this holds
    /// groups built before the delete. When those groups held rows, `AlbumCell`
    /// read a stored property off a dead one and raised
    /// `NSObjectInaccessibleException`. Now the worst a stale group can do is
    /// draw a title for an album that no longer exists, for one pass. See
    /// `AlbumGroup`.
    ///
    /// `LibraryGrouping.albums` is a `Dictionary(grouping:)` plus a sort of
    /// every group plus a sort of the groups. Computed inline in `content` — a
    /// computed property — it ran on **every** body pass, and this view's body
    /// runs far more often than the library changes: `isMinimised` lives in
    /// `RootView`, whose body reads it, so every scroll past the 12pt threshold
    /// rebuilds all five tabs and regroups the whole library mid-scroll. That
    /// cost scales with library size, which is exactly the direction Drive
    /// streaming pushes it.
    ///
    /// **`onChange(of: store.tracks)` alone is not enough, and that is why
    /// there are two triggers below.** It compares `Track` by identity (models
    /// are `Hashable` by persistent identity), so it fires on insert, delete and
    /// reorder but NOT on a property edited in place — the array holds the same
    /// objects in the same order after a rename.
    ///
    /// This doc used to end "whoever adds metadata editing must revisit this".
    /// `TrackMetadataEditor` is that editing, and the revisit is
    /// `LibraryService.metadataRevision`.
    @State private var albums: [AlbumGroup] = []

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            content
                // `initial: true` because the first body pass runs before any
                // change: without it the grid renders empty once and the empty
                // state flashes on every launch.
                .onChange(of: store.tracks, initial: true) { _, updated in
                    albums = paddedForScrollTesting(LibraryGrouping.albums(from: updated))
                }
                // A second trigger, because `store.tracks` cannot report the
                // first one. Editing a track's album changes no element of that
                // array — same objects, same order — so `onChange` above never
                // fires and this screen would keep showing the album the track
                // used to be in. See `LibraryService.metadataRevision`.
                .onChange(of: library.metadataRevision) { _, _ in
                    albums = paddedForScrollTesting(LibraryGrouping.albums(from: store.tracks))
                }
                .navigationTitle("Album")
                // Hoisted above the empty/non-empty branch in `content` so it
                // stays attached to the navigation path even if the library
                // empties while an album detail screen is pushed — a
                // destination declared only inside one branch leaves the
                // hierarchy with the branch, stranding a value on the path.
                .navigationDestination(for: AlbumGroup.self) { album in
                    AlbumDetailView(album: album, isMinimised: $isMinimised)
                }
                // See the note in `SongsView`: this hides the system tab bar
                // and must sit on the tab's content, not on the `TabView`.
                .toolbar(.hidden, for: .tabBar)
                .clearsBottomBar()
        }
    }

    @ViewBuilder
    private var content: some View {
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
            // On the `ScrollView` itself rather than on the branch above it,
            // so what the modifier observes is unambiguous.
            .minimisesBottomBar($isMinimised)
        }
    }

    // MARK: - Scroll-testing scaffold
    //
    // TEMPORARY. Delete this section and the call in `content` once the bottom
    // bar's scroll-minimising has been checked on a tab other than the first,
    // which is the only thing it exists for. It is not a feature, and it puts
    // albums that do not exist in front of anyone running a debug build.
    //
    // Debug-only and behind a flag, so a release build cannot show it and
    // flipping one boolean gets the real library — and its empty state — back.

    #if DEBUG
    /// Set to `false` to see the real library, including its empty state.
    private static let padAlbumsForScrollTesting = true
    /// Enough cells to overflow a phone screen twice over, so there is real
    /// travel to scroll rather than a few points of rubber band.
    private static let scrollTestAlbumCount = 24

    private func paddedForScrollTesting(_ albums: [AlbumGroup]) -> [AlbumGroup] {
        guard Self.padAlbumsForScrollTesting,
              albums.count < Self.scrollTestAlbumCount else { return albums }

        let filler = (albums.count..<Self.scrollTestAlbumCount).map { index in
            // No cover, and no album behind the title either: tapping one
            // opens a detail screen with no rows, because nothing in the
            // library matches this title and artist. That is honest.
            AlbumGroup(
                id: "scroll-test-\(index)",
                title: "Album thử \(index + 1)",
                artist: "Nghệ sĩ thử",
                artworkRelativePath: nil
            )
        }
        return albums + filler
    }
    #else
    private func paddedForScrollTesting(_ albums: [AlbumGroup]) -> [AlbumGroup] { albums }
    #endif
}

private struct AlbumCell: View {
    let album: AlbumGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                // A `String?` copied out of the library when the grouping was
                // built, not a property read off a row this cell holds. That
                // difference is the fix in `AlbumGroup` — read it before
                // reaching for a `Track` here again.
                ArtworkThumbnail(relativePath: album.artworkRelativePath, size: geometry.size.width)
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
    // Seeded by hand: `LibraryQueryBridge` lives in `RootView`, so a preview of
    // one screen has no query keeping the store in step with the container.
    return AlbumsView(isMinimised: .constant(false))
        .environment(library)
        .environment(playback)
        .environment(LibraryStore(tracks: tracksToInsert))
        .modelContainer(container)
}
