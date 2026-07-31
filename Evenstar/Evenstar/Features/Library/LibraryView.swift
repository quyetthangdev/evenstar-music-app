import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryService.self) private var library
    @Environment(ImportService.self) private var importer
    @Environment(PlaybackService.self) private var playback
    @Query(sort: \Track.title, order: .forward) private var tracks: [Track]

    @State private var showFileImporter = false
    @State private var accessibleURLs: [URL] = []
    @State private var inaccessibleFailures: [(url: URL, error: ImportError)] = []
    @State private var showImportSheet = false
    @State private var pickerErrorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
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
            .presentationDetents([.medium])
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
            }
            .listStyle(.plain)
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
}
