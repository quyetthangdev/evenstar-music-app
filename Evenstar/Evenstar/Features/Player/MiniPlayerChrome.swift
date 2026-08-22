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

    /// How far the artwork's **centre** sits from the pill's leading edge —
    /// `collapsedArtworkInset + collapsedArtwork / 2`, computed by `PlayerCard`
    /// from constants that are private to it.
    ///
    /// Passed rather than restated because this row's trailing inset is defined
    /// as its mirror: see `trailingInset`.
    let artworkCentreInset: CGFloat

    /// Lề của ô bìa tính từ mép trái viên pill — thứ nút transport cuối hàng
    /// soi vào để cân. Xem `trailingInset`.
    let artworkLeadingInset: CGFloat

    /// Counts taps on Next so the tap effect retriggers on every press. A
    /// `Bool` would fire once and then sit at `true`, doing nothing for the
    /// second tap.
    @State private var nextTaps = 0
    @State private var playPauseTaps = 0

    private static let buttonSize: CGFloat = 32
    private static let buttonGap: CGFloat = 10

    /// With Next present: 16, enough for it to clear the pill's rounded right
    /// cap.
    private static let expandedTrailingInset: CGFloat = 16

    /// Where the trailing button's frame ends, measured from the pill's
    /// trailing edge.
    ///
    /// Minimised, Next is gone and play/pause becomes the last thing on the
    /// row — so it should balance the artwork at the other end. Balanced by
    /// **centres**, not by edges: the two are different sizes (36 against 32)
    /// and, more to the point, the glyph inside the button does not fill it and
    /// `play.fill` is not the same width as `pause.fill`. Matching visible
    /// edges would put the button in a different place depending on whether
    /// music happened to be playing.
    ///
    /// **Cân theo mép KHUNG, không theo tâm.** Đoạn trên là lập luận cũ và nó
    /// đúng một nửa: cân theo mép *glyph* thì hỏng, vì `play.fill` và
    /// `pause.fill` khác bề rộng nên nút sẽ đứng hai chỗ khác nhau tuỳ nhạc có
    /// đang chạy hay không. Nhưng cân theo mép **khung nút** thì không dính
    /// chuyện đó — khung luôn 32pt, bất kể glyph nào nằm trong.
    ///
    /// Cân theo tâm cho `36 - 16 = 20`, trong khi ô bìa cách mép trái 18. Hai
    /// con số ấy lệch 2pt, và mắt đọc mép chứ không đọc tâm: bên phải trông
    /// lỏng hơn bên trái. Lấy thẳng lề của ô bìa thì hai mép bằng nhau.
    private var trailingInset: CGFloat {
        Self.expandedTrailingInset
            + (artworkLeadingInset - Self.expandedTrailingInset) * minimised
    }

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
            HStack(spacing: Self.buttonGap) {
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
                        .symbolReplace()
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
                .frame(width: Self.buttonSize * (1 - minimised))
                .opacity(1 - minimised)
                .clipped()
                .allowsHitTesting(minimised < 0.5)
                // Eats the gap in front of it on the way out.
                //
                // Zeroing a button's width does not remove the `HStack` spacing
                // that preceded it, so without this play/pause would stop a
                // whole `buttonGap` short of where `trailingInset` puts it,
                // held off by the space reserved for a neighbour that is no
                // longer there. Leading rather than trailing, so what collapses
                // is the gap this button owns.
                .padding(.leading, -Self.buttonGap * minimised)
            }
            // Owned here rather than by `PlayerCard`, which used to apply a flat
            // 16. It is a statement about these buttons — which one is last, how
            // wide it is, and what it has to balance against — so it belongs
            // where they are. See `trailingInset`.
            .padding(.trailing, trailingInset)
        }
    }
}
