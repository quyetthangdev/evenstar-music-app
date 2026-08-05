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
    @State private var repeatTaps = 0

    /// The transport glyphs' square frame. `forward.fill` at `.title2` is
    /// 32.3pt wide and 20pt tall, so an unframed button would give the tap
    /// effect a clip barely larger than the glyph, and its halo would be a 20pt
    /// circle rather than the round one the collapsed player shows. 44 is also
    /// the hit target Apple asks for, which these buttons did not previously
    /// have. Applied to `backward.fill` too, so the row stays symmetric about
    /// the play button.
    private static let transportGlyphFrame: CGFloat = 44

    /// Larger than the arrows beside it so it still reads as the primary
    /// control now that it has no ring to set it apart.
    private static let playGlyphSize: CGFloat = 42

    /// Larger than the `.subheadline` this started at, because the glyph now
    /// has to hold a legible digit inside its loop rather than just be
    /// recognised.
    private static let repeatGlyphSize: CGFloat = 22
    private static let repeatDigitSize: CGFloat = 12
    private static let repeatFrame: CGFloat = 36

    /// Dim when off, accent when armed — the glyph alone cannot carry it,
    /// because off and all share the `repeat` symbol and only `one` differs.
    ///
    /// Three branches, not two. `TransportButtonStyle` dims a disabled label to
    /// `.tertiary` from outside, but this view sets its colour inside the
    /// label, where the innermost `foregroundStyle` wins — so the style's
    /// dimming never lands and this has to do it.
    private var repeatTint: AnyShapeStyle {
        if playback.currentTrack == nil {
            return AnyShapeStyle(.tertiary)
        }
        return playback.repeatMode == .off
            ? AnyShapeStyle(.secondary)
            : AnyShapeStyle(Color.accentColor)
    }

    var body: some View {
        VStack(spacing: 24) {
            titleBlock
            scrubber
            transport
            volume
            repeatRow
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
            }
            .buttonStyle(.transportSkip(trigger: previousTaps, direction: -1))
            .disabled(playback.currentTrack == nil)

            Button {
                playPauseTaps += 1
                // NOT deferred, unlike the two arrows. For play/pause the
                // response *is* the state change: `isPlaying` flips and the
                // glyph swaps. Deferring that pushed the very thing being
                // acknowledged a turn later and made the button feel slower,
                // not faster. It can afford to run inline because it already
                // does nothing expensive — `pause()`/`resume()` defer their own
                // lock-screen push and disk write.
                playback.togglePlayPause()
            } label: {
                // The bare glyph, not `.circle.fill`. The ring was doing no
                // work the size and position were not already doing, and it
                // made this the only transport control with a filled backdrop.
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Self.playGlyphSize))
                    .contentTransition(.symbolEffect(.replace))
                    // No glyph handover: a handover says "that went somewhere",
                    // true of Previous and Next and false of this one, which
                    // toggles in place. Its own glyph already changes, which is
                    // feedback the arrows do not have. The halo now comes from
                    // the button style, along with the press physics.
            }
            .buttonStyle(.transportToggle(trigger: playPauseTaps))
            .disabled(playback.currentTrack == nil)

            Button {
                nextTaps += 1
                acknowledge { playback.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
            }
            .buttonStyle(.transportSkip(trigger: nextTaps, direction: 1))
            .disabled(!playback.canGoNext)
        }
        .padding(.top, 8)
    }

    private var repeatRow: some View {
        Button {
            repeatTaps += 1
            // Inline, not deferred. Like play/pause, the state change is the
            // feedback: both the glyph and its tint read from `repeatMode`.
            playback.cycleRepeatMode()
        } label: {
            // One arrowhead, not the two of `repeat`, and the digit sits in
            // the loop's own hollow. SF Symbols' `repeat.1` hangs its `1`
            // outside the loop at the top right, which is the one thing this
            // is not allowed to look like — so the digit is composed on top
            // rather than taken from a symbol.
            //
            // `arrow.trianglehead.clockwise` over `arrow.clockwise` because
            // its solid triangular head matches the arrowheads on the
            // transport glyphs beside it; the thin-stroked head reads as a
            // refresh control from a different family.
            Image(systemName: "repeat")
                .font(.system(size: Self.repeatGlyphSize, weight: .semibold))
                .overlay {
                    Text("1")
                        .font(.system(size: Self.repeatDigitSize, weight: .bold))
                        .opacity(playback.repeatMode == .one ? 1 : 0)
                        .scaleEffect(playback.repeatMode == .one ? 1 : 0.4)
                }
                // The base glyph no longer changes between modes, so there is
                // no symbol swap left to transition — only the digit arrives
                // and leaves, and it does so on the same short curve the other
                // small controls use.
                .animation(BottomBarStyle.control, value: playback.repeatMode)
                .foregroundStyle(repeatTint)
                .frame(width: Self.repeatFrame, height: Self.repeatFrame)
        }
        .buttonStyle(.transportToggle(trigger: repeatTaps))
        .disabled(playback.currentTrack == nil)
        .padding(.top, 4)
    }

    // The `.frame` modifiers this used to carry at the call site were a
    // no-op — `.frame(maxWidth: .infinity)` cannot widen a wrapped `UIView`;
    // see the note on `SystemVolumeSlider.sizeThatFits`, which now takes the
    // width out of the decision instead. The `HStack` below is fine: the
    // slider is the row's only flexible element, so it takes what the two
    // glyphs leave rather than being handed a width it would ignore.
    private var volume: some View {
        // Every child is given the slider's own height, so `HStack`'s centre
        // alignment puts all three on one axis. Left to their intrinsic
        // heights the glyphs centre on their own boxes, which are shorter than
        // the slider's and sit a little high against the bar.
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .frame(height: ScrubberBar.touchHeight)
            SystemVolumeSlider()
            Image(systemName: "speaker.wave.3.fill")
                .frame(height: ScrubberBar.touchHeight)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}
