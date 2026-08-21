import SwiftUI

/// The expanded player's content: title, scrubber, transport. No artwork and
/// no background — `PlayerCard` owns both.
struct NowPlayingContent: View {
    let playback: PlaybackService

    /// Owned by `PlayerCard`, which swaps the artwork for `QueuePanel` when it
    /// is true. A `Binding` rather than local state because two views have to
    /// agree about it: the icon that flips it lives here, and the region that
    /// changes lives there.
    @Binding var showingQueue: Bool

    /// Khối tiêu đề dời lên bao nhiêu để bám theo mép dưới tấm bìa đang co về
    /// header. Tính ở `PlayerCard.queueTitleTravel` — chỗ duy nhất biết đường
    /// bay của tấm bìa.
    var titleTravel: CGFloat = 0
    /// Độ đục của khối tiêu đề, tan ở đoạn cuối hành trình ấy.
    ///
    /// Truyền vào chứ không suy ra từ `showingQueue`: một `Bool` chỉ cho hai
    /// giá trị và cú tan phải xảy ra **muộn hơn** cú dời, không cùng lúc với
    /// nó. Xem `PlayerCard.queueTitleFadeStart`.
    var titleOpacity: Double = 1

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
    @State private var volumeTaps = 0
    /// Ngón tay đang đè trên thanh âm lượng. Đọc ngược từ `MPVolumeView` vì
    /// cú phồng được vẽ ở phía SwiftUI — xem chỗ dùng.
    @State private var volumePressed = false

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

    var body: some View {
        VStack(spacing: 24) {
            // Invisible in queue mode, **not removed from the layout.**
            //
            // Hiding it is right: `QueuePanel`'s header already carries the
            // title and artist, and drawing both prints the same two strings
            // twice on one screen. Taking it out of the stack was not. This
            // `VStack` is positioned by `.offset(y: contentOffset(fullSize:))`,
            // which pins its *top*, so dropping the first child pulled the
            // scrubber, the transport row, the volume slider and the queue
            // toggle up by the title block's height plus a 24pt gap — the whole
            // player jumped every time the queue opened, and jumped back when
            // it closed.
            //
            // The design note that used to sit here claimed the removal "buys
            // the list its room". It bought nothing. `QueuePanel` is capped at
            // `contentOffset`, and this block lives *below* `contentOffset` —
            // the panel could never have used the space. All the removal ever
            // did was move the controls.
            // **Đi theo tấm bìa, rồi mới tan.**
            //
            // Trước đây chỉ là `opacity(showingQueue ? 0 : 1)`: khối chữ đứng
            // yên và mờ đi tại chỗ, trong khi tấm bìa ngay trên nó bay lên
            // header. Hai thứ vốn đọc thành một cặp bỗng làm hai việc khác
            // nhau, và cặp ấy tan ra đúng lúc đáng ra nó phải di chuyển cùng
            // nhau.
            //
            // `.offset` chứ không phải đổi bố cục: khối chữ giữ nguyên chỗ nó
            // chiếm trong stack, nên thanh tua và khối điều khiển bên dưới
            // không nhích một điểm nào suốt cú chuyển cảnh.
            //
            // `.clipped()` của vùng panel lo phần cắt: khối chữ đi lên cao thì
            // bị xén ở mép trên vùng nội dung thay vì đè lên header.
            titleBlock
                .offset(y: titleTravel)
                .opacity(titleOpacity)
                .allowsHitTesting(!showingQueue)
                .accessibilityHidden(showingQueue)
            scrubber
            transport
            volume
            queueToggleRow
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
        // One animating unit, not three.
        //
        // `PlayerCard` grows this block from the collapsed pill by driving an
        // offset and an opacity ramp on its parent. Without this, each child of
        // the `VStack` resolves its own frame against that moving parent
        // independently, so the title, the artist and the credit each land on
        // their final position a frame or two apart — three lines arriving in
        // sequence where one block should have arrived whole. `geometryGroup`
        // is precisely the fix for that: it makes the container resolve its
        // children's geometry together and hand the result down as a unit.
        //
        // The three-line case is where it shows, because that is where the
        // stagger has the most to stagger — a Jamendo track, whose credit line
        // is the third child.
        .geometryGroup()
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
    /// Half of the invisible margin added on each side to reach HIG's 44pt
    /// minimum hit height from a `.caption2` line — see `jamendoCredit`.
    /// 16 rather than a computed `(44 - lineHeight) / 2`: `.caption2`'s line
    /// height already exceeds 12pt at every Dynamic Type size the app ships
    /// (it only grows from there), so a fixed 16 clears 44 with room at the
    /// default size and more room at every larger one — never less.
    private static let creditHitPad: CGFloat = 16

    @ViewBuilder
    private var jamendoCredit: some View {
        if let jamendo = playback.currentTrack as? JamendoTrack,
           let share = jamendo.shareURLString.flatMap(URL.init(string:)) {
            // HIG's 44×44pt minimum hit region, met by enlarging only the
            // *hit-test* shape rather than the real, laid-out frame — the
            // opposite of what `JamendoResultRow`'s save button and
            // `JamendoDiscoveryView`'s `GenreChip` do, and deliberately so
            // here.
            //
            // Those two grow their actual frame because nothing downstream
            // depends on their size staying small. This one does:
            // `jamendoCredit` is a third child of `titleBlock`'s `VStack`,
            // and `titleBlock` is element #1 of the five-element stack
            // `PlayerCard.contentBudget` reserves ~400pt for, with the doc
            // on that constant measuring only ~16pt of slack against the
            // existing five — already spoken for by one step of Dynamic
            // Type, by that same comment. A real `.frame(minHeight: 44)`
            // here added +48pt (44 plus the 4pt `VStack` gap) to that
            // budget and clipped the fifth element — the pill row, at the
            // time this was measured; `queueToggleRow` occupies that slot
            // today — and part of the volume slider off an iPhone SE
            // screen — confirmed in the simulator, portrait and landscape,
            // before this was rewritten. Two
            // alternatives were rejected instead of raising the budget to
            // match:
            //   - Raising `contentBudget` itself, per its own documented
            //     rule ("adding anything else means raising this by the new
            //     element's height plus spacing"), fixes the clip but taxes
            //     *every* track, not only a Jamendo one — the artwork's
            //     dissolve point would move up by ~48pt permanently to
            //     cover a line that most tracks never show.
            //   - Overlaying the credit line instead of stacking it avoids
            //     growing `titleBlock` at all, but the only unclaimed space
            //     near it is the 24pt `VStack` gap shared with the
            //     scrubber immediately below, and a 44pt overlay does not
            //     fit inside a 24pt gap without its hit region reaching
            //     into the scrubber's own — trading one overlap bug for
            //     another, harder to see one.
            //
            // The padding-then-cancelled-padding pair below is what makes
            // "enlarge the hit shape without enlarging the frame" possible:
            // `.padding` grows the view AND `contentShape` captures that
            // grown rectangle as the hit-test shape; the second `.padding`,
            // negative, then shrinks what this whole subtree *reports* to
            // `titleBlock`'s `VStack` back down to the bare text's own
            // size — the parent lays out as if the enlargement never
            // happened, while the already-fixed hit shape still extends
            // `creditHitPad` beyond it on every side (SwiftUI does not clip
            // a view to the frame its parent proposes, only to an explicit
            // `.clipShape`/`.clipped()`, and this card applies neither
            // here). The overflow this leaves is real but small — at most
            // `creditHitPad` into the 4pt gap above (the subtitle line,
            // which has no gesture of its own to conflict with) and into
            // the 24pt gap below (well short of the scrubber's own hit
            // area) — nothing like the 48pt a real frame cost.
            Link(destination: share) {
                Text(Self.creditLine(for: jamendo))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
            .padding(.vertical, Self.creditHitPad)
            .contentShape(Rectangle())
            .padding(.vertical, -Self.creditHitPad)
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
        PlaybackScrubber(playback: playback)
    }

    private var transport: some View {
        HStack(spacing: 48) {
            TouchDownButton {
                previousTaps += 1
                acknowledge { playback.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: Self.transportGlyphFrame, height: Self.transportGlyphFrame)
            }
            .buttonStyle(.transportSkip(trigger: previousTaps, direction: -1))
            .disabled(playback.currentTrack == nil)

            TouchDownButton {
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
                    .symbolReplace()
                    // No glyph handover: a handover says "that went somewhere",
                    // true of Previous and Next and false of this one, which
                    // toggles in place. Its own glyph already changes, which is
                    // feedback the arrows do not have. The halo now comes from
                    // the button style, along with the press physics.
            }
            .buttonStyle(.transportToggle(trigger: playPauseTaps))
            .disabled(playback.currentTrack == nil)

            TouchDownButton {
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

    /// The glyph frame. 44pt, so the hit region needs no tricks — unlike the
    /// pills, this row replaces nothing and can afford its own height.
    private static let queueGlyphFrame: CGFloat = 44

    /// Mảng nền của nút hàng đợi nở ra từ đâu: 0,7 khi tắt, **1** khi giảm
    /// chuyển động.
    ///
    /// Cùng đường với `BottomBarStyle.pressedScale` và
    /// `QueueToggleStyle.pressedScale` — cái phải bỏ là cú phóng, không phải
    /// cú hiện. `.opacity(showingQueue ? 1 : 0)` ngay trên giữ nguyên, nên nền
    /// vẫn xuất hiện và vẫn biến mất, chỉ là nó không còn nở ra nữa.
    ///
    /// Nhỏ, và vẫn tính: nó nổ cùng lúc với cú bay của tấm bìa, tức là ngay
    /// giữa chỗ đợt này đang dọn.
    ///
    /// Nội bộ chứ không `private`, cùng lý do `QueueToggleStyle.pressedScale`
    /// và `QueuePanel.riseDistance` là vậy: một nhánh Giảm chuyển động chỉ tồn
    /// tại trong diff là đúng loại nhánh đợt này đã để lọt năm lần.
    @MainActor static var queueBadgeScale: CGFloat {
        BottomBarStyle.reduceMotion ? queueBadgeScaleFlat : queueBadgeScaleFull
    }
    private static let queueBadgeScaleFull: CGFloat = 0.7
    private static let queueBadgeScaleFlat: CGFloat = 1

    /// One icon, trailing. Apple Music puts three here — lyrics, AirPlay and
    /// the queue — and this app has nothing to put behind the other two.
    private var queueToggleRow: some View {
        HStack {
            Spacer()
            TouchDownButton {
                withAnimation(BottomBarStyle.queue) {
                    showingQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        // Literal white, not the accent, when the queue is
                        // open: this glyph sits on the now-playing card, over
                        // artwork the darkening overlay already keeps dark, so
                        // white is legible there and only there — it is not a
                        // statement about what the accent colour should be.
                        playback.currentTrack == nil ? AnyShapeStyle(.tertiary)
                            : showingQueue ? AnyShapeStyle(Color.white)
                                           : AnyShapeStyle(.secondary)
                    )
                    .frame(width: Self.queueGlyphFrame, height: Self.queueGlyphFrame)
                    // Nền chỉ có khi hàng đợi đang mở, và **rất nhẹ**.
                    //
                    // Bản đầu dùng `.ultraThinMaterial` đục hoàn toàn: nó đọc
                    // ra như cái nút đang bị nhấn giữ, nên đã bỏ đi. Nhưng bỏ
                    // hẳn thì mất luôn thứ Apple Music có ở đây — một mảng mờ
                    // nói "chế độ này đang bật", cùng ngôn ngữ với hai viên
                    // thuốc trong panel.
                    //
                    // Khác nhau ở độ đậm chứ không ở việc có hay không: 0.14
                    // của `Color.primary` đủ để thấy là có nền, nhạt hơn hẳn
                    // một viên thuốc đang bật, nên nó không tranh chỗ.
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.14))
                            .opacity(showingQueue ? 1 : 0)
                            .scaleEffect(showingQueue ? 1 : Self.queueBadgeScale)
                            .animation(BottomBarStyle.content, value: showingQueue)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.queueToggle)
            .disabled(playback.currentTrack == nil)
            .accessibilityLabel(String(
                localized: "Hàng đợi",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            ))
            .accessibilityAddTraits(showingQueue ? [.isButton, .isSelected] : .isButton)
        }
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
            // **Cú phồng nằm ở đây, không ở trong `MPVolumeView`.**
            //
            // Bản trước vẽ lại ảnh track dày hơn khi chạm. Ảnh bitmap không nội
            // suy được, nên nó nhảy một bậc — trong khi thanh tua ngay trên nó
            // đổi chiều cao qua `.animation(BottomBarStyle.control)` và nở ra
            // mượt. Hai thanh cùng dáng, cùng độ dày, khác hẳn nhau ở đúng cái
            // khoảnh khắc ngón tay chạm vào.
            //
            // `scaleEffect(y:)` thì nội suy được, và tỉ lệ đúng bằng tỉ lệ hai
            // chiều cao — nên kết quả trùng khít con số mà thanh tua đạt tới.
            // Chỉ kéo theo trục dọc, nên vị trí và bề ngang không đổi.
            SystemVolumeSlider(
                onTouchDown: { volumeTaps += 1 },
                onPressChanged: { volumePressed = $0 }
            )
            .scaleEffect(y: volumePressed
                         ? ScrubberBar.activeHeight / ScrubberBar.restingHeight : 1)
            .animation(BottomBarStyle.control, value: volumePressed)
            Image(systemName: "speaker.wave.3.fill")
                .frame(height: ScrubberBar.touchHeight)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .sensoryFeedback(.impact(weight: .light), trigger: volumeTaps)
    }
}

/// Đọc `position`/`duration` trong thân riêng của nó, tách khỏi
/// `NowPlayingContent`.
///
/// Với `@Observable`, theo dõi xảy ra theo lượt gọi *thân view* — đọc hai
/// thuộc tính này ngay trong thân `NowPlayingContent` thì cả cây bên dưới nó
/// (tiêu đề, ba nút transport, thanh âm lượng, hàng nút hàng đợi) dựng lại mỗi
/// khi `PlaybackService` ghi vị trí, tức 0.5 giây một lần lúc đang phát — kể
/// cả khi player đang đóng. Đẩy phần đọc xuống view con này thì lượt ghi ấy
/// chỉ khiến thân của riêng nó dựng lại. Cùng nguyên lý với `Slot` trong
/// `ReorderableStack.swift`.
///
/// Nhận cả `playback`, không chỉ hai con số, vì `onSeek` phải gọi
/// `playback.seek(to:)`. Điều đó không tự kéo theo việc theo dõi cả đối
/// tượng: `@Observable` theo dõi khi thuộc tính bị *đọc trong thân*, không
/// phải khi tham chiếu được giữ trong scope. Thân dưới đây chỉ đọc `position`
/// và `duration`, nên chỉ hai thuộc tính đó bị theo dõi ở view này.
private struct PlaybackScrubber: View {
    let playback: PlaybackService

    var body: some View {
        ScrubberBar(
            position: playback.position,
            duration: playback.duration,
            onSeek: { playback.seek(to: $0) }
        )
    }
}
