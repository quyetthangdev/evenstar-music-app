import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(PlaybackService.self) private var playback
    /// The local library, fetched once for the whole app — see `LibraryStore`.
    ///
    /// Read only from inside the `.task(id:)` below, after it has already
    /// confirmed the query is non-empty — so while the query is empty, which
    /// is most of this screen's life, including every moment it is not on
    /// screen and holding its last state, this screen has no dependency on
    /// the library and is not rebuilt when it changes. A `Task` body reading
    /// an `@Observable` property does not register as a `body` dependency
    /// the way a synchronous read would, so moving the read off the render
    /// pass and into the task does not reopen that cost.
    @Environment(LibraryStore.self) private var store

    /// What this screen is showing, and the query it answers.
    ///
    /// Both were `@State` here. They are an object in the environment now for
    /// one reason: deleting a track has to be able to drop it from this list
    /// *before* the row dies, and nothing outside a view can write that view's
    /// `@State` — so the list a delete has to reach cannot live in one. See
    /// `SearchResultsStore` for the crash that forced the move, and for why an
    /// `onChange` here would not have closed it.
    ///
    /// Nothing about how the list is filled changed with it: the debounce, the
    /// keep-or-drop rule and the wiped-query case below are the same three
    /// decisions in the same order, made through the store's methods instead of
    /// through two `@State` assignments.
    @Environment(SearchResultsStore.self) private var searchResults

    /// Owned by `RootView`, edited by this screen's own `.searchable` field.
    @Binding var query: String

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Tìm kiếm")
                .searchable(text: $query, prompt: Text("Bài hát, nghệ sĩ, album"))
                // Restarts on every keystroke, because `id: query` changes on
                // every keystroke — and `.task(id:)` cancels the in-flight
                // task from the previous id before starting the new one. So
                // typing ten characters in a row starts and cancels nine
                // waits and lets exactly one run to completion: the one
                // behind the character the user was still on 150ms later.
                // `LibraryGrouping.search` itself never runs on that
                // cancelled path.
                .task(id: query) {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        // The query was wiped, not just changed — the one
                        // case that must NOT keep a stale list on screen:
                        // `content` needs to fall back to the "type something"
                        // prompt, not to the last answer to a question that no
                        // longer exists. See `SearchResultsStore.clear()`.
                        searchResults.clear()
                        return
                    }
                    // Whether the old list stays on screen while this wait
                    // runs depends on what produced it, not on whether it
                    // merely exists: it is kept only when this `query` extends
                    // the one it answers ("queen" → "queena"), and dropped for
                    // a deleted character or a different word. The rule and
                    // the reasoning behind it live on
                    // `SearchResultsStore.dropStaleResults(for:)`; what
                    // matters here is that it is decided *before* the wait,
                    // so a stale list is never on screen while a new query
                    // is being answered.
                    searchResults.dropStaleResults(for: query)
                    // `Task.sleep` throws `CancellationError` when this task
                    // is cancelled — which happens the moment `query` changes
                    // again, per the note on `.task(id:)` above. `.task(id:)`
                    // requires a non-throwing closure, so that error cannot
                    // propagate out on its own the way it would from a
                    // throwing function; it has to be caught here. The catch
                    // block deliberately does nothing but `return` — it does
                    // NOT fall through to the filter below the way `try?`
                    // would. That is what keeps the debounce cancellable: a
                    // stale wait must never reach `LibraryGrouping.search`
                    // and overwrite `results` with an answer to a query the
                    // user already typed past.
                    do {
                        try await Task.sleep(for: .milliseconds(150))
                    } catch {
                        return
                    }
                    // `LibraryGrouping.search` owns matching — case- and
                    // diacritic-insensitive — so this view never
                    // re-implements it, and never runs it from `body`.
                    searchResults.record(
                        LibraryGrouping.search(query, in: store.tracks),
                        for: query
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Tìm trong thư viện",
                systemImage: "magnifyingglass",
                description: Text("Tìm theo tên bài hát, nghệ sĩ hoặc album.")
            )
        } else if let results = searchResults.results {
            if results.isEmpty {
                // Hand-written rather than `ContentUnavailableView.search(text:)`.
                // That convenience draws its title and description from the
                // framework, resolved against the app's declared localizations —
                // and this app declares none, with `developmentRegion = en`. So
                // it renders an English "No Results" between a Vietnamese title
                // above it and a Vietnamese prompt one state away, on a
                // Vietnamese user's device, no matter what the system language
                // is. Any other system-supplied string added here has the same
                // problem until the project gains a `vi` localization.
                ContentUnavailableView(
                    "Không tìm thấy kết quả",
                    systemImage: "magnifyingglass",
                    description: Text("Không có bài hát, nghệ sĩ hay album nào khớp với “\(query)”.")
                )
            } else {
                List(results) { track in
                    SongRow(track: track, isAbsent: !store.isPresent(track))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Xem ghi chú cùng chỗ trong `AlbumDetailView`.
                            guard store.isPresent(track) else { return }
                            // The queue is the current result set, not the
                            // whole library, so the "next" track is the one
                            // below the tapped row in this list.
                            playback.play(track, in: results)
                        }
                }
                .listStyle(.plain)
            }
        } else {
            // Reached whenever there is no `results` list safe to keep
            // showing while the task above computes the next one: the first
            // search of a session (nothing has ever been found yet), or any
            // search whose query is not a continuation of the one that
            // produced the previous list — see the task's comment above for
            // which is which. Neither "type something" nor "no results" is
            // true in this gap, so a spinner is shown rather than either; a
            // spinner says nothing false, "Không tìm thấy kết quả" here
            // would.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Track.self, PlaybackState.self,
            // `.none` chứ không để mặc định `.automatic`: mặc định đọc
            // entitlement iCloud của target, nên một preview mở ra trên máy
            // đã đăng nhập iCloud sẽ dựng cả CloudKit — và đẩy lược đồ lên
            // môi trường Development, thứ chỉ thêm được chứ không sửa được.
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
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
    // Seeded by hand — see the same note in `AlbumsView`'s preview.
    return SearchView(query: .constant("biển"))
        .environment(library)
        .environment(playback)
        // `presence` phải kể tên đường dẫn của mấy bài mẫu — xem ghi chú trong
        // preview của `AlbumDetailView`.
        .environment(LibraryStore(tracks: tracksToInsert,
                                  presence: .known(["a.mp3", "c.mp3"])))
        // Empty here, and filled by the screen's own task the way it is in the
        // app — in `EvenstarApp` this object is also what the delete hook
        // prunes, which a preview has no delete to exercise.
        .environment(SearchResultsStore())
        .modelContainer(container)
}
