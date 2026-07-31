import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Track.title, order: .forward) private var tracks: [Track]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            // Wired in Task 6
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .disabled(true)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: {})
        } else {
            List(tracks) { track in
                SongRow(track: track)
            }
            .listStyle(.plain)
        }
    }
}
