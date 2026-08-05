import SwiftUI
import SwiftData

/// The Drive half of the Bài hát tab: the four states behind the Drive chip —
/// no folder linked, a scan in flight, a linked folder with nothing in it, and
/// a list of tracks. A failure is not a fifth state; it is a banner over
/// whichever of those is on screen.
struct DriveSongsList: View {
    @Environment(DriveLibraryService.self) private var driveLibrary
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\DriveFolder.linkedAt)]) private var folders: [DriveFolder]
    @Query(sort: [SortDescriptor(\DriveTrack.title, comparator: .localizedStandard)])
    private var tracks: [DriveTrack]

    @Binding var isMinimised: Bool
    @State private var showManager = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if folders.isEmpty {
                empty
            } else {
                list
            }
        }
        .sheet(isPresented: $showManager) {
            DriveFoldersView()
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Chưa có thư mục nào")
                .font(.title3.bold())
            // The privacy cost, stated plainly at the moment it is incurred.
            // This is a product requirement, not copy — see the spec.
            Text("Nhạc trên Drive được phát trực tiếp, không tốn dung lượng máy. Thư mục phải được chia sẻ ở chế độ “bất kỳ ai có liên kết”, nghĩa là ai có link cũng xem được.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Thêm thư mục") { showManager = true }
                .buttonStyle(.prominentAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            // Same entry point as the list below it. Without this the `…`
            // button vanishes exactly when there is nothing else on screen to
            // reach the manager from except the one button in the middle —
            // and it reappears the moment a folder exists, which reads as the
            // toolbar flickering rather than as a deliberate state.
            ToolbarItem(placement: .topBarLeading) {
                Button { showManager = true } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var list: some View {
        List {
            if let bannerMessage {
                Text(bannerMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if tracks.isEmpty {
                // Without this the list draws nothing at all: a linked folder
                // holding no audio files renders an empty `List`, which is a
                // blank screen with no explanation and no clue that pulling
                // down would do anything.
                Text("Không có bài hát nào trong thư mục đã liên kết. Kéo xuống để quét lại, hoặc mở ⋯ để thêm thư mục khác.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(tracks) { track in
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                    Text(folderName(for: track))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { playback.play(track, in: tracks) }
            }
        }
        .listStyle(.plain)
        .refreshable { await rescanAll() }
        .minimisesBottomBar($isMinimised)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showManager = true } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    /// What the one status line says.
    ///
    /// **Deliberately counts rows on screen, never `scannedFileCount`.** That
    /// counter — and `scan(_:)`'s return value — are the number of *files Drive
    /// listed*, which is not the number of rows this list shows: Drive files can
    /// have several parents, and a file already known under another linked
    /// folder keeps its original row rather than gaining a second one (see
    /// `DriveLibraryService.scan`). Reporting "đã quét 40" above a list of 38
    /// would be a number the user can see is wrong and cannot explain. The row
    /// count is the one figure that is true by construction.
    private var summary: String {
        driveLibrary.scanningFolderID != nil ? "Đang quét…" : "\(tracks.count) bài hát"
    }

    /// The one red line, from whichever source has something to say.
    ///
    /// The scan error wins because it is the more recent thing the user did —
    /// they pulled to refresh — and because a playback error they have already
    /// seen must not outrank a fresh failure to list the folder.
    ///
    /// This is the first and only consumer of `PlaybackService.lastPlaybackError`
    /// anywhere in the app. Until it existed, `DriveError`'s Vietnamese
    /// messages — a missing API key, an offline device, a mid-track stall —
    /// were recorded and then thrown away, and a Drive track that would not
    /// start simply stopped with no explanation. `lastPlaybackError` clears
    /// itself the moment anything plays successfully, so the banner does not
    /// need to be dismissed.
    private var bannerMessage: String? {
        errorMessage ?? playback.lastPlaybackError?.localizedDescription
    }

    private func folderName(for track: DriveTrack) -> String {
        folders.first { $0.folderID == track.folderID }?.displayName ?? "Drive"
    }

    @MainActor
    private func rescanAll() async {
        errorMessage = nil
        for folder in folders {
            do {
                try await driveLibrary.scan(folder)
            } catch is CancellationError {
                // Pulling to refresh and then navigating away cancels this. Not
                // a failure to report — `DriveClient.fetch` rethrows
                // `URLError.cancelled` raw for the same reason.
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }
}
