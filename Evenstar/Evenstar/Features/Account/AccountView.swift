import SwiftUI
import SwiftData

/// What the library adds up to, plus what build this is.
///
/// Named "Tài khoản" because that is where an Apple Music sign-in will go in
/// Phase 3. Until then it is deliberately only what is true today — counts,
/// storage, version. No signed-out account row promising something that does
/// not exist.
struct AccountView: View {
    // No `PlaybackService` here any more: the only thing this screen read it
    // for was choosing between the two bottom clearances, and `clearsBottomBar`
    // now owns that decision along with the arithmetic behind it.
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]

    /// Owned by `RootView`, which drives both the tab bar and the player from
    /// it. Written here only by `minimisesBottomBar` on this screen's list.
    @Binding var isMinimised: Bool

    /// `nil` until the first sum finishes. Distinguishing "not measured yet"
    /// from "measured, and it is zero" is the difference between showing a
    /// progress spinner and telling a user with a full library that they have
    /// no files.
    @State private var bytesOnDisk: Int64?

    /// `nil` until the first count finishes, same distinction `bytesOnDisk`
    /// draws above: a library with hundreds of albums showing `0` while the
    /// first `.task` is still running would be a lie, not a loading state.
    ///
    /// Counts only, not the grouped arrays `AlbumsView`/`ArtistsView` keep —
    /// this screen never renders an album or artist, just their tally, so
    /// there's no reason to hold the groups themselves in state.
    ///
    /// Recomputed in the same `.task(id: tracks.count)` below that already
    /// drives `bytesOnDisk`, not in `body`: `LibraryGrouping.albums` is a
    /// `Dictionary(grouping:)` over the whole library plus a localized sort,
    /// and `body` reruns on every `@Query` change — one inserted track was
    /// paying for a full regrouping just to show an integer. Keyed on
    /// `tracks.count` rather than `tracks` itself for the same reason
    /// `bytesOnDisk` is: cheap, but blind to an edit that changes an album
    /// name without changing how many tracks there are — this count can be
    /// briefly stale after a rename, same as the byte count already
    /// tolerates for the file set.
    @State private var albumCount: Int?

    /// Same reasoning as `albumCount`, for `LibraryGrouping.artists`.
    @State private var artistCount: Int?

    var body: some View {
        NavigationStack {
            List {
                Section("Thư viện") {
                    row("Bài hát", value: "\(tracks.count)")
                    row("Album", value: albumCountText)
                    row("Nghệ sĩ", value: artistCountText)
                    row("Dung lượng", value: storageText)
                }

                // One row rather than the appearance control inline.
                //
                // This screen was three unrelated things in one list: what the
                // library adds up to, where its music comes from, and how the
                // app behaves. Settings are the part that grows, so they get
                // their own screen and everything added later lands there
                // instead of as another section wedged between the storage
                // figure and the version number.
                Section {
                    NavigationLink("Cài đặt") { SettingsView() }
                }

                Section("Nguồn nhạc") {
                    // `showsDoneButton: false` — this `NavigationLink` pushes
                    // onto the `NavigationStack` this screen already owns, so
                    // the pushed bar's native back chevron is the way out.
                    // `DriveFoldersView`'s default `true` is for its other
                    // call site, `DriveSongsList`'s sheet, which has no back
                    // chevron to rely on. See `DriveFoldersView`'s doc
                    // comment on `showsDoneButton`.
                    NavigationLink("Thư mục Drive") {
                        DriveFoldersView(showsDoneButton: false)
                    }
                }

                Section("Ứng dụng") {
                    row("Phiên bản", value: Self.versionText)
                }
            }
            .minimisesBottomBar($isMinimised)
            .navigationTitle("Tài khoản")
            // See the note in `SongsView`: this hides the system tab bar
            // and must sit on the tab's content, not on the `TabView`.
            .toolbar(.hidden, for: .tabBar)
            .clearsBottomBar()
            // Keyed on the count so importing or deleting re-measures. It is a
            // cheap proxy: editing a track's tags does not change what is on
            // disk, and nothing else alters the file set.
            //
            // `albumCount`/`artistCount` ride along here rather than getting
            // a `.task` of their own: they're synchronous and cheap next to
            // the disk scan below, and sharing the one trigger keeps the
            // "keyed on count, not content" tradeoff in a single place
            // instead of explaining it twice.
            .task(id: tracks.count) {
                albumCount = LibraryGrouping.albums(from: tracks).count
                artistCount = LibraryGrouping.artists(from: tracks).count
                bytesOnDisk = await Self.bytesOnDisk(for: filePaths)
            }
        }
    }

    /// `LocalizedStringKey`, not `String`.
    ///
    /// As `String` this compiled, read correctly in Vietnamese, and silently
    /// refused to translate: only a string *literal* becomes a translation key,
    /// and a literal passed to a `String` parameter has already collapsed to
    /// plain text by the time `Text` sees it. The screen proved it — "Account"
    /// and "Library" translated, and every row between them stayed Vietnamese.
    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var storageText: String {
        guard let bytesOnDisk else { return "…" }
        return bytesOnDisk.formatted(.byteCount(style: .file))
    }

    private var albumCountText: String {
        guard let albumCount else { return "…" }
        return "\(albumCount)"
    }

    private var artistCountText: String {
        guard let artistCount else { return "…" }
        return "\(artistCount)"
    }

    /// Audio and artwork both count — artwork is copied into the app's
    /// container at import, so leaving it out would under-report what deleting
    /// the library would actually reclaim.
    ///
    /// Collected here, on the main actor, as plain strings. `Track` is a
    /// SwiftData `@Model`, which is neither `Sendable` nor safe to touch from
    /// another executor, so the paths must be lifted out before the work hops
    /// off.
    private var filePaths: [String] {
        tracks.map(\.relativePath) + tracks.compactMap(\.artworkRelativePath)
    }

    /// `@concurrent` rather than a bare `nonisolated async`.
    ///
    /// Under this project's `SWIFT_APPROACHABLE_CONCURRENCY` setting, a
    /// `nonisolated async` function inherits its *caller's* executor — called
    /// from a view's `.task`, it would stat every file on the main thread and
    /// stutter the whole screen on a large library. `@concurrent` is what
    /// actually forces the hop. Same reasoning as `ArtworkStore`.
    ///
    /// A file that cannot be measured contributes zero rather than failing the
    /// total: a library missing one file should report slightly low, not
    /// refuse to report at all.
    @concurrent
    private static func bytesOnDisk(for relativePaths: [String]) async -> Int64 {
        var total: Int64 = 0
        for path in relativePaths {
            let url = FileLocation.absoluteURL(forRelative: path)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            total += Int64(size ?? 0)
        }
        return total
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        guard let build else { return short }
        return "\(short) (\(build))"
    }
}

#Preview {
    let container: ModelContainer
    do {
        // `DriveFolder`/`DriveTrack` are registered here even though this screen
        // queries neither: Task 8 gave it a `NavigationLink` to
        // `DriveFoldersView`, which `@Query`s both. Pushing that row in a
        // preview against a container that does not know those models traps at
        // the point of the push — a preview that looks fine until the one row
        // this section exists for is tapped.
        container = try ModelContainer(
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self,
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
        Track(title: "Biển nhớ", artistName: "Beta", albumTitle: "Night Songs",
              trackNumber: 1, discNumber: 1, durationSeconds: 220,
              relativePath: "c.mp3", format: "mp3")
    ]
    for track in tracksToInsert {
        container.mainContext.insert(track)
    }
    // Same reason as the two extra models above: the pushed `DriveFoldersView`
    // reads `DriveLibraryService` out of the environment, so without this the
    // Nguồn nhạc row crashes the preview rather than showing the screen.
    let driveLibrary = DriveLibraryService(library: library)
    return AccountView(isMinimised: .constant(false))
        .environment(library)
        .environment(playback)
        .environment(driveLibrary)
        .modelContainer(container)
}
