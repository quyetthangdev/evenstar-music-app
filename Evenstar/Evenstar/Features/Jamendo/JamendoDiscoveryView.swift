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

    @State private var query = ""
    @State private var results: [JamendoCatalogueTrack] = []
    @State private var savedIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var genre: String?

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
                                    Task { await load() }
                                }
                            }
                        }
                    }
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
        }
        .navigationTitle("Khám phá")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Tìm trên Jamendo"))
        .overlay { if isLoading && results.isEmpty { ProgressView() } }
        .task(id: query) {
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

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if !query.isEmpty {
                results = try await client.search(query, commercialOnly: commercialOnly)
            } else if let genre {
                results = try await client.tracks(inGenre: genre, commercialOnly: commercialOnly)
            } else {
                results = try await client.trending(commercialOnly: commercialOnly)
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
            Text(name.capitalized)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(isSelected ? Color.primary.opacity(0.12) : Color(.tertiarySystemFill),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
