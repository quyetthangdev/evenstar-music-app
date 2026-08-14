import SwiftUI
import SwiftData

/// The Jamendo half of the Bài hát tab: saved tracks only — the catalogue
/// itself lives behind `JamendoDiscoveryView`, reached from this screen's
/// toolbar button while the Jamendo chip is selected.
///
/// A separate view, not a `@ViewBuilder` branch inlined in `SongsView`, for
/// the same reason `DriveSongsList` already is one: `SongsView`'s
/// `switch source` only mounts the branch matching the selected chip, so an
/// `@Query` declared here is live — SwiftData observing every insert and
/// delete of a `JamendoTrack` — only while the Jamendo chip is actually on
/// screen. Declared directly on `SongsView` instead, as it used to be, it ran
/// for the lifetime of the whole tab no matter which chip the user was
/// looking at.
struct JamendoSongsList: View {
    @Environment(JamendoLibraryService.self) private var jamendo
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\JamendoTrack.dateAdded, order: .reverse)])
    private var jamendoTracks: [JamendoTrack]

    @Binding var isMinimised: Bool

    var body: some View {
        if jamendoTracks.isEmpty {
            ContentUnavailableView {
                Label("Chưa lưu bài nào từ Jamendo", systemImage: "music.note.list")
            } description: {
                Text("Jamendo là kho nhạc Creative Commons miễn phí.")
            } actions: {
                // `.prominentAction`, matching `EmptyLibraryView` and
                // `DriveSongsList.empty`'s own call-to-action button — this
                // was the one empty state of the three still missing it.
                NavigationLink("Khám phá Jamendo") {
                    JamendoDiscoveryView(isMinimised: $isMinimised)
                }
                .buttonStyle(.prominentAction)
            }
        } else {
            List(jamendoTracks) { track in
                SongRow(track: track, subtitle: subtitle(for: track))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playback.play(track, in: jamendoTracks)
                    }
                    // Same gesture, same wording, same "commit immediately, no
                    // confirmation dialog" behaviour as the local list's swipe
                    // in `SongsView` — Jamendo was the one source with no way
                    // back out of the library once saved: `JamendoResultRow`'s
                    // own save button disables itself once `isSaved`, offering
                    // no un-save, and this list had neither `.onDelete` nor
                    // `.swipeActions`. One mis-tap on the discovery screen's
                    // "+" put a track in the library permanently.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteJamendoTrack(track)
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.plain)
            .minimisesBottomBar($isMinimised)
        }
    }

    /// `artist · licence`, the same shape `JamendoResultRow` shows in the
    /// discovery screen — CC-BY obliges visible credit, and a saved track
    /// keeps it here rather than only on the way in. `nil`, not the bare
    /// artist name, when there is no licence to show: `SongRow` already
    /// falls back to `track.artistName` on a `nil` subtitle.
    private func subtitle(for track: JamendoTrack) -> String? {
        guard let licenceURLString = track.licenceURLString,
              let licence = LicenceName.short(for: URL(string: licenceURLString))
        else { return nil }
        return "\(track.artistName) · \(licence)"
    }

    /// Tells playback while the row is still live, then removes it.
    ///
    /// `jamendo.unsave` does its own `onTrackWillBeDeleted` call (it must, for
    /// the delete paths that don't go through this view), so this one is
    /// redundant in practice — a repeat call to a "remove from queue if
    /// present" method is harmless, unlike a missing one. `SongsView.deleteTrack`
    /// no longer has its counterpart: `LibraryService.delete(_:)` gained the
    /// same hook, so the local path stopped needing a view to remember.
    private func deleteJamendoTrack(_ track: JamendoTrack) {
        playback.handleTrackDeleted(track)
        do {
            try jamendo.unsave(track)
        } catch {
            // 2a: log only. A polished alert is part of 2d.
            print("Delete failed: \(error)")
        }
    }
}
