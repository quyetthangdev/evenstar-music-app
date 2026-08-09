import SwiftUI

/// Search, trending and genres, in one pushed screen.
///
/// Reached from the Jamendo chip's toolbar, the same shape the `+` uses to open
/// the file importer. It is not a tab: adding a fifth pill would re-divide
/// `FloatingTabBar`, whose 44pt hit targets and collapse morph are all computed
/// from the number of slots.
struct JamendoDiscoveryView: View {
    @Environment(JamendoLibraryService.self) private var jamendo
    @AppStorage(JamendoLicencePolicy.storageKey) private var commercialOnly =
        JamendoLicencePolicy.defaultCommercialOnly

    /// Owned by `RootView`, threaded here through both screens that push this
    /// one — `SongsView`'s toolbar link and `JamendoSongsList`'s empty state.
    ///
    /// A pushed screen scrolls under the same floating bars as a tab root, so
    /// it folds them the same way. `AlbumDetailView` carries this binding for
    /// exactly the same reason, and its doc comment records why: Đợt A's
    /// Critical defect was a pushed screen left out of a bottom-bar treatment
    /// the tab roots got. This screen was the next one left out.
    @Binding var isMinimised: Bool

    @State private var query = ""
    @State private var results: [JamendoCatalogueTrack] = []
    @State private var savedIDs: Set<String> = []
    @State private var isLoading = false
    /// A failure that left nothing to show. Rendered in place of the results,
    /// with a retry — see `statusRow`.
    @State private var loadError: String?
    /// A failure of one save, which is a different animal: the list around it
    /// is intact and still worth looking at, so this interrupts instead of
    /// replacing anything. Both used to be the same `errorMessage`, rendered
    /// as a red line at the top of the list, which meant a save that failed
    /// reported itself several rows away from the row it was about — and
    /// scrolled off screen.
    @State private var saveError: String?
    /// Bumped only by a save that succeeds, and only so `.sensoryFeedback` has
    /// something to fire on. `savedIDs.count` cannot serve: `load()` refills
    /// that set wholesale on every page, so the haptic would fire on searches
    /// and refreshes rather than on the one thing the user did.
    @State private var savedTick = 0
    @State private var genre: String?
    /// `false` until the first `load()` call actually finishes (success or
    /// error) — guards the empty-results row below from flashing on screen
    /// before the initial trending fetch has had a chance to return anything.
    /// Left untouched by a cancelled `load()`, so a superseded run never
    /// flips it back off a completed one.
    @State private var hasLoadedOnce = false
    /// Set by `load()` when the current query has real matches that
    /// `commercialOnly` filtered down to nothing — as opposed to a query with
    /// no matches at all. The two read as the same blank list without this,
    /// and only one of them is something the user can act on. See
    /// `emptyResultsRow`.
    @State private var filteredEverythingByLicence = false
    /// Tracks the in-flight load a genre tap started, so a second tap before
    /// the first request returns cancels it instead of letting both run and
    /// whichever answers last win — the ordinary `.task(id:)` cancellation
    /// `query` edits get, done by hand because a genre tap does not change
    /// `query`.
    @State private var genreLoadTask: Task<Void, Never>?

    private let client = JamendoClient()

    /// Fixed rather than fetched. Jamendo's tag vocabulary is thousands of
    /// words long; a row of six familiar ones is a starting point, and a tag
    /// list nobody can read is not.
    private static let genres = ["rock", "pop", "electronic", "jazz", "classical", "hiphop"]

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.genres, id: \.self) { name in
                                GenreChip(name: name, isSelected: genre == name) {
                                    genre = (genre == name) ? nil : name
                                    genreLoadTask?.cancel()
                                    genreLoadTask = Task { await load() }
                                }
                            }
                        }
                        // Inside the scroller, paired with the zeroed row
                        // insets below — that pairing is the whole point. The
                        // insets let the scroll view itself run edge to edge;
                        // this padding then holds the first and last chip off
                        // the edge while still letting both scroll past it.
                        // With the row's default insets instead, the scroller
                        // stopped at the list margin and the end chips were
                        // sliced off there — a horizontal carousel clipped at a
                        // list inset, which is a shape Apple does not ship.
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
            }

            // Headed, because three different queries land in the same list
            // and nothing else says which one you are looking at. A page of
            // trending tracks and a page of results for "piano" were pixel for
            // pixel the same screen; the header is what Apple Music uses to
            // tell them apart, and it costs one row.
            if !results.isEmpty {
                Section {
                    ForEach(results) { track in
                        JamendoResultRow(
                            track: track,
                            isSaved: savedIDs.contains(track.id)
                        ) {
                            Task { await save(track) }
                        }
                    }
                } header: {
                    resultsHeader
                }
            }

            statusRow
        }
        // Every other list in this app is `.plain` — `SearchView`,
        // `SongsView`, `DriveSongsList`, `JamendoSongsList`, and both detail
        // screens. Setting none here did not mean "no opinion": it took the
        // default inset-grouped look, so the one screen showing a music
        // catalogue rendered as rounded cards on grey, like Cài đặt, next to
        // five edge-to-edge lists of exactly the same thing.
        .listStyle(.plain)
        .minimisesBottomBar($isMinimised)
        .navigationTitle("Khám phá")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Tìm trên Jamendo"))
        // The keyboard covers roughly half the results it just produced, and
        // the first thing anyone does with a result list is scroll it. Every
        // system app treats that scroll as "I am done typing".
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await load() }
        // Saving is the one thing this screen does, and until the row flips it
        // is indistinguishable from a tap that missed.
        .sensoryFeedback(.success, trigger: savedTick)
        .overlay { if isLoading && results.isEmpty { ProgressView() } }
        .toolbar {
            // The overlay above only covers the first load, when there is
            // nothing to cover. Reloading a page that already has rows must
            // neither blank them nor dim them: with a 350ms debounce, a dim
            // would flash on every pause in typing. A bar spinner is what the
            // system apps use for "refreshing what you can already see".
            if isLoading && !results.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { ProgressView() }
            }
        }
        .alert(
            "Không lưu được",
            isPresented: Binding(get: { saveError != nil },
                                 set: { if !$0 { saveError = nil } }),
            presenting: saveError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .clearsBottomBar()
        // Keyed on `commercialOnly` as well as `query`: this screen can stay
        // pushed on the nav stack while the user backs out to Cài đặt, flips
        // "Chỉ nhạc dùng được cho mục đích thương mại", and returns. Keyed on
        // `query` alone, that toggle changing `commercialOnly` did not restart
        // this task — `.task(id:)` only restarts when its *id* changes, and
        // the id never mentioned the setting — so the list kept showing
        // results filtered under the setting the user had just changed, until
        // the next keystroke incidentally changed `query` too.
        .task(id: LoadKey(query: query, commercialOnly: commercialOnly)) {
            // Debounced: a request per keystroke would rate-limit the client id
            // in seconds. Cancellation of the previous `.task` is what makes a
            // plain sleep a debounce here.
            //
            // `try?` on the sleep swallows its own `CancellationError` rather
            // than propagating it, so without the explicit check below,
            // execution fell through to `load()` even when *this* task had
            // already been superseded by a newer keystroke — issuing a
            // request nobody would ever see the result of, racing whichever
            // `.task` run replaced it. The guard is what makes cancellation
            // actually stop work here, not just fail to report it.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Which of the three queries produced what is on screen.
    ///
    /// Trending, a genre and a search all render into the same list, and
    /// without this they are the same screen — a user who taps "jazz" and one
    /// who types nothing see identical rows under an identical title.
    @ViewBuilder
    private var resultsHeader: some View {
        if !query.isEmpty {
            Text("Kết quả")
        } else if let genre {
            // The tag verbatim from `Self.genres`, not a translated string:
            // these are Jamendo's own vocabulary, they go to the API as typed,
            // and inventing a Vietnamese name for a tag the catalogue does not
            // have one for would describe a filter this screen is not applying.
            Text(genre.capitalized)
        } else {
            Text("Thịnh hành")
        }
    }

    /// Rows of the `List`, not an overlay over the whole screen: the genre
    /// chips above must stay reachable when a genre or search turns up
    /// nothing, and an overlay would cover the very control that gets the user
    /// out of the empty state.
    ///
    /// Four states land here and three of them used to render identically —
    /// no matches, everything filtered out by `commercialOnly`, and a failed
    /// request, the last as a red footnote at the top of the list. Only one is
    /// something a toggle in Cài đặt fixes and only one is worth retrying, so
    /// each says which it is and offers what it can.
    @ViewBuilder
    private var statusRow: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Không tải được", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Thử lại") { Task { await load() } }
                    .buttonStyle(.prominentAction)
            }
            .listRowSeparator(.hidden)
        } else if hasLoadedOnce, results.isEmpty {
            if filteredEverythingByLicence {
                ContentUnavailableView {
                    Label("Không tìm thấy kết quả", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Không có bài nào phù hợp với cài đặt giấy phép hiện tại. Tắt “Chỉ nhạc dùng được cho mục đích thương mại” trong Cài đặt để xem thêm.")
                }
                .listRowSeparator(.hidden)
            } else {
                ContentUnavailableView {
                    Label("Không tìm thấy kết quả", systemImage: "magnifyingglass")
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        filteredEverythingByLicence = false
        defer { isLoading = false }
        do {
            results = try await fetch(commercialOnly: commercialOnly)
            hasLoadedOnce = true
            if results.isEmpty, commercialOnly {
                // Diagnostic-only re-fetch, permissive this time, to tell "no
                // matches" apart from "the licence filter removed every
                // match" for `statusRow`. Best-effort: `try?`, because this
                // call failing must not blank what is already a valid (if
                // empty) result, and must not override `loadError` — the
                // primary fetch above already succeeded.
                filteredEverythingByLicence = (try? await fetch(commercialOnly: false))?.isEmpty == false
            }
            // One round trip for the whole page rather than one per row —
            // see the doc comment on `JamendoLibraryService.savedIDs(among:)`.
            // `try?`, not `try`: a local persistence hiccup here must not
            // read as a search failure and blank a result list that loaded
            // fine — the search's own `catch` below is for the search.
            savedIDs = (try? jamendo.savedIDs(among: results.map(\.id))) ?? []
        } catch is CancellationError {
            // The previous `.task(id:)` run was superseded by a new query
            // before its request finished. Not a failure to report — matches
            // `DriveSongsList.rescanAll`'s handling of the same case.
            return
        } catch let error as URLError where error.code == .cancelled {
            // `JamendoClient.get` rethrows cancellation raw, unwrapped from
            // `JamendoError`, precisely so it never reaches a user. Touching
            // neither `results` nor `loadError` here is what keeps that
            // promise the one layer up: without this, typing "jaz" then
            // "jazz" cancelled the first request mid-flight and the list
            // flashed empty with a raw system cancellation string, on nearly
            // every keystroke.
            return
        } catch {
            results = []
            loadError = error.localizedDescription
            hasLoadedOnce = true
        }
    }

    private func fetch(commercialOnly: Bool) async throws -> [JamendoCatalogueTrack] {
        if !query.isEmpty {
            return try await client.search(query, commercialOnly: commercialOnly)
        } else if let genre {
            return try await client.tracks(inGenre: genre, commercialOnly: commercialOnly)
        } else {
            return try await client.trending(commercialOnly: commercialOnly)
        }
    }

    /// Flips the row first, then does the work, and puts the row back if the
    /// work fails.
    ///
    /// Saving is not a local operation: it downloads the cover art before it
    /// inserts anything, so on a slow connection the old order — insert, then
    /// flip — left the button looking like it had ignored the tap for as long
    /// as the download took. Optimism is the standard treatment for an action
    /// that almost always succeeds and is cheap to undo, and both halves of
    /// that hold here: the undo is one `Set` removal, and the failure is
    /// already surfaced by the alert.
    ///
    /// `JamendoLibraryService.save` coalesces concurrent saves of the same id
    /// (I7), so a double tap that beats the flip cannot produce two rows.
    private func save(_ track: JamendoCatalogueTrack) async {
        savedIDs.insert(track.id)
        do {
            _ = try await jamendo.save(track)
            savedTick += 1
        } catch {
            savedIDs.remove(track.id)
            saveError = error.localizedDescription
        }
    }
}

/// `.task(id:)` restarts only when this changes as a whole — see the doc
/// comment at that call site for why both fields have to be in it.
private struct LoadKey: Equatable {
    let query: String
    let commercialOnly: Bool
}

private struct GenreChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // `minHeight: 44` before the background/contentShape, not just a
            // roomier `.contentShape` around the same small pill: HIG's rule
            // on Buttons is a 44×44pt hit region, and the drafted padding
            // (14 horizontal / 7 vertical around `.subheadline`) resolves to
            // roughly 30pt tall. Growing the frame — not just the tap area —
            // keeps the visible capsule and its hit region the same shape,
            // which a padded-out `contentShape` alone would not: that would
            // leave a bigger invisible rectangle around a smaller pill.
            // Filled with the accent colour when selected, not a darker grey.
            // The previous pair — `Color.primary.opacity(0.12)` selected
            // against `Color(.tertiarySystemFill)` unselected — resolves to
            // very nearly the same value in both appearances, so the selected
            // chip was almost indistinguishable from its neighbours. A filter
            // control whose state cannot be read is not a filter control.
            //
            // `.white` rather than `.background` for the label: the fill is the
            // accent colour in both appearances, so a label that inverts with
            // the appearance would go black-on-blue in dark mode.
            Text(name.capitalized)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
