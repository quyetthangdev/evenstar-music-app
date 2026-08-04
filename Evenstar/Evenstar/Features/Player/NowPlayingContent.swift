import SwiftUI

/// The expanded player's content: title, scrubber, transport. No artwork and
/// no background — `PlayerCard` owns both.
struct NowPlayingContent: View {
    let playback: PlaybackService

    /// Counts taps on Next, exactly as `MiniPlayerChrome` does and for the same
    /// reason — a `Bool` would fire once and then sit at `true`. Its own
    /// counter rather than one shared with the collapsed player: only one of
    /// the two is hit-testable at a time, so they never need to agree, and a
    /// shared count would have to live in `PlayerCard` purely to be passed back
    /// down.
    @State private var nextTaps = 0

    /// The transport glyphs' square frame. `forward.fill` at `.title2` is
    /// 32.3pt wide and 20pt tall, so an unframed button would give the tap
    /// effect a clip barely larger than the glyph, and its halo would be a 20pt
    /// circle rather than the round one the collapsed player shows. 44 is also
    /// the hit target Apple asks for, which these buttons did not previously
    /// have. Applied to `backward.fill` too, so the row stays symmetric about
    /// the play button.
    private static let transportGlyphFrame: CGFloat = 44

    var body: some View {
        VStack(spacing: 24) {
            titleBlock
            scrubber
            transport
            volume
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
                .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
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
                nextTaps += 1
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
                    // The same acknowledgement the collapsed player's Next
                    // gives. `PlayerCard` is one card at two ends of a
                    // continuum, so the same control cannot answer a press at
                    // one end and ignore it at the other.
                    //
                    // 40, not the collapsed 30: this frame is 44 and the glyph
                    // 32.3pt wide, so the glyph is fully outside the clip only
                    // past 22 + 16.2 = 38.2. See `transportTapEffect`.
                    .transportTapEffect(trigger: nextTaps, direction: 1, travel: 40)
            }
            .buttonStyle(.plain)
            .disabled(playback.queueIndex >= playback.queue.count - 1)
        }
        .padding(.top, 8)
    }

    // The `.frame` modifiers this used to carry at the call site were a
    // no-op — `.frame(maxWidth: .infinity)` cannot widen a wrapped `UIView`;
    // see the note on `SystemVolumeSlider.sizeThatFits`, which now takes the
    // width out of the decision instead.
    private var volume: some View {
        SystemVolumeSlider()
    }
}
