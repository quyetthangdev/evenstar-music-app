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
                        // Driven by the tap counter, not by the track changing.
                        // The acknowledgement then lands in the same frame as
                        // the press rather than waiting on the load, and — the
                        // reason it is a counter — a second tap during the
                        // first animation retriggers it instead of being
                        // swallowed, which is what holding Next feels like.
                        //
                        // It is not here to cover a press that fails to
                        // advance: the `.disabled` below means the last track
                        // takes no taps at all.
                        //
                        // 30 clears the 32pt frame above: `forward.fill` at
                        // `.body` is 25pt wide, so it is fully outside past
                        // 16 + 12.5 = 28.5. See `transportTapEffect`.
                        .transportTapEffect(trigger: nextTaps, direction: 1, travel: 30)
                }
                .buttonStyle(.plain)
                .disabled(playback.queueIndex >= playback.queue.count - 1)
            }
        }
    }
}
