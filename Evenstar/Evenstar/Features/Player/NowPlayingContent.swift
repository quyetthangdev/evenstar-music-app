import SwiftUI

/// The expanded player's content: title, scrubber, transport. No artwork and
/// no background — `PlayerCard` owns both.
struct NowPlayingContent: View {
    let playback: PlaybackService

    /// Counts taps on each transport control, exactly as `MiniPlayerChrome`
    /// does for Next and for the same
    /// reason — a `Bool` would fire once and then sit at `true`. Its own
    /// counter rather than one shared with the collapsed player: only one of
    /// the two is hit-testable at a time, so they never need to agree, and a
    /// shared count would have to live in `PlayerCard` purely to be passed back
    /// down.
    @State private var nextTaps = 0
    @State private var previousTaps = 0
    @State private var playPauseTaps = 0

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
        VStack(alignment: .leading, spacing: 4) {
            // `reservesSpace` is the whole answer to a long title. Without it
            // the block is one line tall for most tracks and two for the rest,
            // so everything below — the scrubber, the transport row, the volume
            // slider — shifts by a line depending on which track is playing, and
            // `PlayerCard.artworkSide`'s fixed allowance has to be sized for a
            // case it cannot see. With it the block is always two lines, so the
            // layout is identical for every track and a title longer than that
            // truncates instead of pushing the controls down.
            Text(playback.currentTrack?.title ?? "—")
                .font(.title2.bold())
                .lineLimit(2, reservesSpace: true)
            Text(metadataSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // Leading, and greedy, so both lines start at the same x whatever their
        // length — a centred block makes the artist appear to move when the
        // title wraps.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Runs a transport command on the next main-actor turn, so the tap's own
    /// acknowledgement renders first.
    ///
    /// SwiftUI renders a button's action *after* it returns, so anything
    /// synchronous in there sits between the tap and the first frame of the tap
    /// effect. `next()` loads an `AVAudioPlayer` from disk; `previous()` seeks,
    /// which persists. Neither can be made free, and neither needs to happen
    /// inside that frame: audio starting one turn later is inaudible, while the
    /// animation starting one turn later is the thing being complained about.
    ///
    /// Ordering is safe — main-actor tasks run in the order they are enqueued —
    /// so holding Next still advances one track per tap, in order.
    private func acknowledge(_ command: @escaping () -> Void) {
        Task { @MainActor in command() }
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
            Button {
                previousTaps += 1
                acknowledge { playback.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
                    // `direction: -1`, so the glyph travels the way its own
                    // arrow points. Same travel as Next: same glyph mirrored,
                    // same frame.
                    .transportTapEffect(trigger: previousTaps, direction: -1, travel: 40)
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)

            Button {
                playPauseTaps += 1
                acknowledge { playback.togglePlayPause() }
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .contentTransition(.symbolEffect(.replace))
                    // `travel: 0` — the halo, without the slide.
                    //
                    // The wrap says "that went somewhere", which is true of
                    // Previous and Next and false of this one: play/pause
                    // toggles in place and has no direction to travel in. A
                    // zero travel makes the offset track a no-op while the halo
                    // still blooms, so all three buttons acknowledge a press in
                    // the same visual language and only the directional two
                    // move.
                    .transportTapEffect(trigger: playPauseTaps, direction: 1, travel: 0)
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)

            Button {
                nextTaps += 1
                acknowledge { playback.next() }
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
