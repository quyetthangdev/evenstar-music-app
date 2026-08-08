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

    /// `.title3` rather than `.title2`, a step down.
    ///
    /// Named once because two places need the same value and they must agree:
    /// the title itself, and the hidden sibling that reserves its height. A
    /// mismatch there would reserve the wrong number of points and the whole
    /// stack below would sit a few points off — with nothing on screen saying
    /// why.
    private static let titleFont = Font.title3.bold()

    /// Larger than the `.subheadline` this started at: `repeat.1` carries a
    /// digit as well as the loop, and at the smaller size the digit was a
    /// smudge.
    private static let repeatGlyphSize: CGFloat = 22
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
            // Two lines of height, always — but the title sits at the BOTTOM of
            // them rather than the top.
            //
            // The reserved height is not negotiable: without it the block is one
            // line for most tracks and two for the rest, so the scrubber, the
            // transport row and the volume slider all shift by a line depending
            // on which track is playing. That is what `reservesSpace` was for.
            //
            // What `reservesSpace` gets wrong is *where* it puts the spare line.
            // It leaves it below the text, so a one-line title — most titles —
            // floated a full line clear of the artist beneath it, and the two
            // read as unrelated rather than as a pair. Holding the height with a
            // hidden sibling and aligning to `.bottomLeading` puts the spare
            // line above instead: a short title sits directly on the artist, a
            // long one grows upward into the space, and nothing below moves in
            // either case.
            ZStack(alignment: .bottomLeading) {
                Text(verbatim: " ")
                    .font(Self.titleFont)
                    .lineLimit(2, reservesSpace: true)
                    .hidden()
                    .accessibilityHidden(true)
                Text(playback.currentTrack?.title ?? "—")
                    .font(Self.titleFont)
                    .lineLimit(2)
            }
            // One line, whether it is carrying metadata or a failure — see
            // `PlayerSubtitle` for why a failure replaces the metadata instead
            // of being added below it, and `PlayerCard.artworkSide` for what
            // adding a sixth element to this stack would cost.
            //
            // `minimumScaleFactor` rather than a second line for the same
            // reason: the longest Vietnamese failure message is about 90
            // characters and would otherwise truncate mid-sentence, and a
            // truncated explanation is barely better than none. Shrinking keeps
            // the block exactly as tall as it has always been.
            Text(subtitle.text)
                .font(.subheadline)
                .foregroundStyle(
                    subtitle.isFailure
                        ? AnyShapeStyle(Color.red)
                        : AnyShapeStyle(HierarchicalShapeStyle.secondary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            jamendoCredit
        }
        // Leading, and greedy, so both lines start at the same x whatever their
        // length — a centred block makes the artist appear to move when the
        // title wraps.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The third of the three places the spec requires Jamendo attribution
    /// (see `JamendoResultRow`, `SongsView.jamendoContent`) and the only one
    /// that links back to the track's own page — what CC-BY actually obliges,
    /// rather than just naming the artist and licence.
    ///
    /// **A type check on `currentTrack`, not a new "which source" answer.**
    /// `PlayerSubtitle` faces a related question for the line above this one
    /// and resolves it by reading only what `Playable` exposes to every
    /// source alike — it never branches on the concrete type. That option
    /// does not exist here: `shareURLString` and `licenceURLString` are
    /// Jamendo-specific and are not part of `Playable`, so there is nothing
    /// for a protocol-level dispatch to read. Given that, `as? JamendoTrack`
    /// directly on `currentTrack` is the narrowest fix available — cheaper
    /// than adding a `sourceKind`-style case to `Playable` for a distinction
    /// only one of its three conformers needs, and it costs nothing when the
    /// cast fails: the whole row disappears, exactly as it should for a Drive
    /// or local track.
    @ViewBuilder
    private var jamendoCredit: some View {
        if let jamendo = playback.currentTrack as? JamendoTrack,
           let share = jamendo.shareURLString.flatMap(URL.init(string:)) {
            Link(destination: share) {
                Text(Self.creditLine(for: jamendo))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // HIG's 44×44pt minimum hit region, grown on the frame itself
            // rather than faked with an oversized invisible `contentShape` —
            // the same choice `JamendoResultRow`'s save button and
            // `JamendoDiscoveryView`'s `GenreChip` made, and for the same
            // reason given there: a region bigger than what is drawn is
            // still fine, but a region drawn no bigger than what a tester can
            // see is not. `.topLeading`, not centred, so the extra height
            // this buys sits below the credit line — in the gap before the
            // scrubber — rather than pushing the line itself away from the
            // metadata line directly above it.
            .frame(minHeight: 44, alignment: .topLeading)
            .contentShape(Rectangle())
        }
    }

    /// The credit line's text alone, pulled out of the view so it can be
    /// pinned by a test without instantiating SwiftUI — the same reason
    /// `PlayerSubtitle` was lifted out of this view in the first place.
    ///
    /// The licence-less fallback is `String(localized:)` against the app's
    /// own language, not the bare literal `"Jamendo"`: a plain `String`
    /// interpolated into the credit line does not localise on its own, and
    /// this project has shipped exactly that bug twice already. Reuses the
    /// catalogue's existing `"Jamendo"` entry (the brand name, already
    /// identical in both languages) rather than adding a second one.
    static func creditLine(for track: JamendoTrack) -> String {
        let licenceURL = track.licenceURLString.flatMap(URL.init(string:))
        let source = LicenceName.short(for: licenceURL) ?? String(
            localized: "Jamendo",
            bundle: AppLanguage.resolvedBundle,
            locale: AppLanguage.resolvedLocale
        )
        return "\(track.artistName) · \(source)"
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

    /// Moved into `PlayerSubtitle` so the collapsed player applies the identical
    /// rule and so the rule has a test. It had neither before.
    private var subtitle: PlayerSubtitle {
        PlayerSubtitle.line(
            track: playback.currentTrack,
            error: playback.stalledPlaybackError
        )
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
            // `repeat.1` hangs its digit outside the loop at the top right.
            // Composing it inside instead was tried on both the two-arrow
            // `repeat` and a single-arrow circular loop: the circle has a
            // hollow and reads well, but `repeat`'s interior is a narrow
            // horizontal slot between the two arrows, and a digit dropped in
            // there merges with both and reads as a bar joining them rather
            // than as a numeral. Two arrows won, so the digit goes outside.
            Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat")
                .font(.system(size: Self.repeatGlyphSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
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
