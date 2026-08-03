import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SongsView: View {
    @Environment(LibraryService.self) private var library
    @Environment(ImportService.self) private var importer
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\Track.title, comparator: .localizedStandard)]) private var tracks: [Track]

    /// Owned by `RootView`, which drives both the tab bar and the player from
    /// it. Written here only by `minimisesBottomBar` on this screen's list.
    @Binding var isMinimised: Bool

    @State private var showFileImporter = false
    @State private var accessibleURLs: [URL] = []
    @State private var inaccessibleFailures: [(url: URL, error: ImportError)] = []
    @State private var showImportSheet = false
    @State private var pickerErrorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Bài hát")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
                // The system tab bar is hidden in favour of `FloatingTabBar`.
                // This modifier applies to the content *inside* a tab, never
                // to the `TabView` itself, which is why it lives here on each
                // tab's root view rather than in `RootView`.
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        // Never 0: the floating tab bar is always present, so
                        // the last row must clear it whether or not a track is
                        // loaded. With a track the pill sits above the bar and
                        // the clearance grows by the pill and its gap.
                        .frame(
                            height: playback.currentTrack == nil
                                ? BottomBarMetrics.clearanceTabBarOnly
                                : BottomBarMetrics.clearanceWithPlayer
                        )
                }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let (accessible, inaccessible) = partitionByScopeAccess(urls)
                accessibleURLs = accessible
                inaccessibleFailures = inaccessible
                showImportSheet = !urls.isEmpty
            case .failure(let error):
                accessibleURLs = []
                inaccessibleFailures = []
                pickerErrorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(
                urls: accessibleURLs,
                inaccessibleFailures: inaccessibleFailures,
                importer: importer
            )
            // Drag indicator lives inside ImportProgressSheet — it depends on importer.isImporting.
            .presentationDetents([.medium, .large])
        }
        .alert(
            "Couldn't open files",
            isPresented: Binding(
                get: { pickerErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { pickerErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pickerErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: { showFileImporter = true })
        } else {
            List(tracks) { track in
                SongRow(track: track)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playback.play(track, in: tracks)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTrack(track)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.plain)
            // On the scrollable container itself rather than on the branch
            // above it, so what the modifier observes is unambiguous.
            .minimisesBottomBar($isMinimised)
        }
    }

    /// Document Picker delivers security-scoped URLs. We start access here and
    /// stop it on sheet dismiss; the import work happens between those calls.
    /// URLs whose access could not be started are reported as import failures
    /// rather than silently dropped from the summary.
    private func partitionByScopeAccess(
        _ urls: [URL]
    ) -> (accessible: [URL], inaccessible: [(url: URL, error: ImportError)]) {
        var accessible: [URL] = []
        var inaccessible: [(url: URL, error: ImportError)] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                accessible.append(url)
            } else {
                inaccessible.append((url, .fileNotAccessible(url)))
            }
        }
        return (accessible, inaccessible)
    }

    private func stopAccessingURLs() {
        for url in accessibleURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessibleURLs = []
        inaccessibleFailures = []
    }

    private func deleteTrack(_ track: Track) {
        // Queue adjustment is persisted before the DB delete below runs (identity
        // must be read off `track` while it's still live). If `library.delete`
        // then throws, the row can survive pointing at already-adjusted playback
        // state and possibly-removed files. Recovering from that is Phase 2d's job.
        playback.handleTrackDeleted(track)
        do {
            try library.delete(track)
        } catch {
            // 2a: log only. A polished alert is part of 2d.
            print("Delete failed: \(error)")
        }
    }
}
