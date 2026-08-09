import SwiftUI

/// The collapsed player's row: title, artist, transport. No artwork and no
/// background — `PlayerCard` owns both, because they must be continuous
/// across the morph rather than belonging to one end of it.
struct MiniPlayerChrome: View {
    let playback: PlaybackService

    /// 0 on its own row above the tab bar, 1 slotted into it. The same number
    /// `PlayerCard` interpolates every other collapsed dimension from, passed
    /// down rather than recomputed so the button leaves in step with the pill
    /// that is squeezing it.
    let minimised: Double

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
                TouchDownButton {
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
                TouchDownButton {
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
                // Gone by the time the pill has slotted into the tab bar.
                //
                // Minimised, the pill loses 58pt of width to the tab bar beside
                // it, and what is left has to carry a title, an artist and two
                // 32pt buttons. Play/pause earns its place there — it is the
                // one control whose absence would be felt. Next does not: the
                // expanded player is one tap away and has a full-size one.
                //
                // Interpolated on `minimised` rather than switched on a
                // threshold, so the button shrinks and fades with the pill it
                // lives in instead of vanishing part-way through the morph.
                // `clipped()` because the glyph does not shrink with the frame
                // — without it the arrow would spill out of a box narrower
                // than itself while still half visible.
                .frame(width: 32 * (1 - minimised))
                .opacity(1 - minimised)
                .clipped()
                .allowsHitTesting(minimised < 0.5)
                // Eats the `HStack`'s own 10pt gap on the way out.
                //
                // Zeroing the button's width leaves that gap behind, so
                // play/pause stopped 26pt short of the pill's inner trailing
                // edge — 16pt of padding plus 10pt of spacing for a neighbour
                // that is no longer there. It read as hanging back from the
                // edge rather than sitting against it. At -10 the gap closes
                // with the button and play/pause lands 16pt in, near enough to
                // the artwork's own 18pt inset on the other end for the pill to
                // look balanced.
                .padding(.trailing, -10 * minimised)
            }
        }
    }
}
