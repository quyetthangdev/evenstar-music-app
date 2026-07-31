import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryService.self) private var library
    @Environment(ImportService.self) private var importer
    @Query(sort: \Track.title, order: .forward) private var tracks: [Track]

    @State private var showFileImporter = false
    @State private var pendingURLs: [URL] = []
    @State private var showImportSheet = false

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
                pendingURLs = secureScopedURLs(urls)
                showImportSheet = !pendingURLs.isEmpty
            case .failure:
                pendingURLs = []
            }
        }
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(urls: pendingURLs, importer: importer)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: { showFileImporter = true })
        } else {
            List(tracks) { track in
                SongRow(track: track)
            }
            .listStyle(.plain)
        }
    }

    /// Document Picker delivers security-scoped URLs. We start access here and
    /// stop it on sheet dismiss; the import work happens between those calls.
    private func secureScopedURLs(_ urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    private func stopAccessingURLs() {
        for url in pendingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        pendingURLs = []
    }
}
