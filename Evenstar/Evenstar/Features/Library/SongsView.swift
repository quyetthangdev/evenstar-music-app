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

    /// Which source the list is showing. Local by default — the Drive chip is
    /// an opt-in, and a user with no linked folder should never land on an
    /// empty screen they did not ask for.
    @State private var source: LibrarySource = .local

    enum LibrarySource: String, CaseIterable {
        case local, drive
        var label: String {
            switch self {
            case .local: "Trên máy"
            case .drive: "Drive"
            }
        }
    }

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
            "Không mở được file",
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
        VStack(spacing: 0) {
            Picker("Nguồn", selection: $source) {
                ForEach(LibrarySource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            // `.clearsBottomBar()` sits on each branch rather than on this
            // `VStack`, and that placement is load-bearing.
            // `.safeAreaInset(edge: .bottom)` inserts its spacer into the safe
            // area of the view it is applied to: on the stack it would shrink
            // the stack and leave the list ending in a band of empty
            // background, instead of extending the list's own scroll inset so
            // the last row can scroll clear of the floating bar. Applied here,
            // `localContent` receives exactly the modifier chain it had before
            // the picker existed.
            switch source {
            case .local:
                localContent
                    .clearsBottomBar()
            case .drive:
                DriveSongsList(isMinimised: $isMinimised)
                    .clearsBottomBar()
            }
        }
    }

    @ViewBuilder
    private var localContent: some View {
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
                            Label("Xoá", systemImage: "trash")
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
