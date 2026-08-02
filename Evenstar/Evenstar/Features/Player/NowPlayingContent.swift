import SwiftUI

/// The expanded player's content: title, scrubber, transport. No artwork and
/// no background — `PlayerCard` owns both.
struct NowPlayingContent: View {
    let playback: PlaybackService

    var body: some View {
        VStack(spacing: 24) {
            titleBlock
            scrubber
            transport
            SystemVolumeSlider()
                .frame(height: 44)
        }
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
        ScrubberBar(
            position: playback.position,
            duration: playback.duration,
            onSeek: { playback.seek(to: $0) }
        )
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
                    .contentTransition(.symbolEffect(.replace))
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
}
