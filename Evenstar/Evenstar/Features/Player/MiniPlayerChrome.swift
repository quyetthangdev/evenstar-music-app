import SwiftUI

/// The collapsed player's row: title, artist, transport. No artwork and no
/// background — `PlayerCard` owns both, because they must be continuous
/// across the morph rather than belonging to one end of it.
struct MiniPlayerChrome: View {
    let playback: PlaybackService

    /// Counts taps on Next so the tap effect retriggers on every press. A
    /// `Bool` would fire once and then sit at `true`, doing nothing for the
    /// second tap.
    @State private var nextTaps = 0

    var body: some View {
        if let current = playback.currentTrack {
            // Scaled to the shorter pill: type one step down, and 32pt hit
            // targets rather than 36. 32 is the floor here — below it the
            // buttons drop under the 44pt Apple asks for by more than the
            // surrounding pill can excuse.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.title)
                        .font(.footnote)
                        .lineLimit(1)
                    Text(current.artistName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Button {
                    nextTaps += 1
                    playback.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                        // Fires on the tap, not on the track changing:
                        // `playback.next()` at the end of a queue stops rather
                        // than advancing, and the button should still
                        // acknowledge the press it received.
                        .transportTapEffect(trigger: nextTaps, direction: 1)
                }
                .buttonStyle(.plain)
                .disabled(playback.queueIndex >= playback.queue.count - 1)
            }
        }
    }
}
