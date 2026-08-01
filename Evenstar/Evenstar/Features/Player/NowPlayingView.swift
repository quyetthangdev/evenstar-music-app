import SwiftUI

struct NowPlayingView: View {
    let playback: PlaybackService

    @Environment(\.dismiss) private var dismiss
    @State private var draggingPosition: TimeInterval?
    @State private var artworkImage: UIImage?

    private static let artworkSize: CGFloat = 280

    var body: some View {
        VStack(spacing: 24) {
            handle
            Spacer(minLength: 0)
            artwork
            titleBlock
            scrubber
            transport
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var handle: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .padding(8)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var artwork: some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.artworkSize * 0.12))
        .shadow(radius: 10, y: 4)
        .task(id: playback.currentTrack?.id) {
            await loadArtwork()
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.artworkSize * 0.12)
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "music.note")
                .font(.system(size: Self.artworkSize * 0.5))
                .foregroundStyle(.secondary)
        }
    }

    /// Loads the current track's artwork once per track change (driven by
    /// `.task(id:)`), rather than on every body re-evaluation. `body`
    /// re-evaluates every 0.5s while `playback.position` ticks, so relying on
    /// `ArtworkThumbnail`'s own synchronous decode-on-every-render behavior
    /// here — appropriate at 44pt in a list row — would mean a repeating
    /// main-thread disk read/decode of a full-size image while this screen
    /// stays open.
    ///
    /// `.task(id:)` cancellation is cooperative, and `Data(contentsOf:)`
    /// never checks `Task.isCancelled`, so a slow load for a track the user
    /// has since navigated away from can still complete. Before writing the
    /// result we confirm `playback.currentTrack?.id` still matches the track
    /// this load was started for; if the user has moved on, the stale result
    /// is discarded rather than overwriting newer (or already-correct) art.
    private func loadArtwork() async {
        let trackID = playback.currentTrack?.id
        let path = playback.currentTrack?.artworkRelativePath
        let image = await Self.decodeImage(relativePath: path)
        guard !Task.isCancelled, playback.currentTrack?.id == trackID else { return }
        artworkImage = image
    }

    private static func decodeImage(relativePath: String?) async -> UIImage? {
        guard let relativePath else { return nil }
        let url = FileLocation.absoluteURL(forRelative: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(playback.currentTrack?.title ?? "—")
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(metadataSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metadataSubtitle: String {
        guard let track = playback.currentTrack else { return "" }
        if track.albumTitle == "Unknown Album" { return track.artistName }
        return "\(track.artistName) · \(track.albumTitle)"
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { draggingPosition ?? playback.position },
                    set: { draggingPosition = $0 }
                ),
                in: 0...max(playback.duration, 0.001),
                onEditingChanged: { editing in
                    if !editing, let target = draggingPosition {
                        playback.seek(to: target)
                        draggingPosition = nil
                    }
                }
            )
            HStack {
                Text(formatTime(draggingPosition ?? playback.position))
                Spacer()
                Text("-" + formatTime(max(0, playback.duration - (draggingPosition ?? playback.position))))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var transport: some View {
        HStack(spacing: 48) {
            Image(systemName: "backward.fill")
                .font(.title2)
                .foregroundStyle(.tertiary)
                // previous deferred to 2c

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)

            Button {
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(playback.queueIndex >= playback.queue.count - 1)
        }
        .padding(.top, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
