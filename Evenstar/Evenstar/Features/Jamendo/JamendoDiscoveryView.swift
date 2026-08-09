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
    @State private var errorMessage: String?
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
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

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

            ForEach(results) { track in
                JamendoResultRow(
                    track: track,
                    isSaved: savedIDs.contains(track.id)
                ) {
                    Task { await save(track) }
                }
            }

            emptyResultsRow
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
        .refreshable { await load() }
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

    /// One row of `List`, not a `ContentUnavailableView` swapped in for the
    /// whole screen: the genre chips above must stay reachable when a genre
    /// or search turns up nothing, so there has to be a `List` to hold them
    /// either way.
    ///
    /// Three states currently render identically without this: no matches at
    /// all, every match filtered out by `commercialOnly`, and an API error.
    /// The error case already has its own red line above; this row covers
    /// the other two, and tells them apart — only one is something a toggle
    /// in Cài đặt can fix.
    @ViewBuilder
    private var emptyResultsRow: some View {
        if hasLoadedOnce, errorMessage == nil, results.isEmpty {
            Text(filteredEverythingByLicence
                 ? String(localized: "Không có bài nào phù hợp với cài đặt giấy phép hiện tại. Tắt “Chỉ nhạc dùng được cho mục đích thương mại” trong Cài đặt để xem thêm.",
                          bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
                 : String(localized: "Không tìm thấy kết quả",
                          bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        filteredEverythingByLicence = false
        defer { isLoading = false }
        do {
            results = try await fetch(commercialOnly: commercialOnly)
            hasLoadedOnce = true
            if results.isEmpty, commercialOnly {
                // Diagnostic-only re-fetch, permissive this time, to tell "no
                // matches" apart from "the licence filter removed every
                // match" for `emptyResultsRow`. Best-effort: `try?`, because
                // this call failing must not blank what is already a valid
                // (if empty) result, and must not override `errorMessage` —
                // the primary fetch above already succeeded.
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
            // neither `results` nor `errorMessage` here is what keeps that
            // promise the one layer up: without this, typing "jaz" then
            // "jazz" cancelled the first request mid-flight and the list
            // flashed empty with a raw system cancellation string, on nearly
            // every keystroke.
            return
        } catch {
            results = []
            errorMessage = error.localizedDescription
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

    private func save(_ track: JamendoCatalogueTrack) async {
        do {
            _ = try await jamendo.save(track)
            savedIDs.insert(track.id)
        } catch {
            errorMessage = error.localizedDescription
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
