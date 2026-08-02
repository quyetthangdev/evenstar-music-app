import SwiftUI

/// The collapsed player's row: title, artist, transport. No artwork and no
/// background — `PlayerCard` owns both, because they must be continuous
/// across the morph rather than belonging to one end of it.
struct MiniPlayerChrome: View {
    let playback: PlaybackService

    var body: some View {
        if let current = playback.currentTrack {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(current.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Button {
                    playback.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(playback.queueIndex >= playback.queue.count - 1)
            }
        }
    }
}
