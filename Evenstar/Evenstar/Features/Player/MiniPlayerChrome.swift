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
    @State private var playPauseTaps = 0

    /// See `NowPlayingContent.acknowledge`: SwiftUI renders a button's action
    /// after it returns, so synchronous playback work sits between the tap and
    /// the first frame of its acknowledgement.
    private func acknowledge(_ command: @escaping () -> Void) {
        Task { @MainActor in command() }
    }

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
                    // The same substitution the expanded player makes, from the
                    // same rule — see `PlayerSubtitle`. It matters more here,
                    // not less: the collapsed pill is the screen a user is on
                    // while browsing, so it is where a stalled Drive track is
                    // most likely to be discovered. Replacing the artist line
                    // rather than adding one keeps the pill exactly 54pt tall.
                    let subtitle = PlayerSubtitle.collapsedLine(
                        track: current,
                        error: playback.stalledPlaybackError
                    )
                    Text(subtitle.text)
                        .font(.caption2)
                        .foregroundStyle(
                            subtitle.isFailure
                                ? AnyShapeStyle(Color.red)
                                : AnyShapeStyle(HierarchicalShapeStyle.secondary)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Button {
                    playPauseTaps += 1
                    // Inline, not deferred — see the note in `NowPlayingContent`:
                    // for this button the state change is the response.
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.transportToggle(trigger: playPauseTaps))
                Button {
                    nextTaps += 1
                    acknowledge { playback.next() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                // A shorter throw than the expanded player's: this button is
                // 32pt inside a pill, not 44 in open space, so the full kick
                // would carry it into its neighbour.
                .buttonStyle(.transportSkip(trigger: nextTaps, direction: 1, translate: 4))
                .disabled(!playback.canGoNext)
            }
        }
    }
}
