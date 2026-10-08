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

    /// Cú kéo thẻ, gắn lại riêng trên hàng nút điều khiển với ngưỡng lớn hơn.
    ///
    /// Thẻ mở bắt kéo sau 2pt (`PlayerCard.dragThreshold`) để vuốt xuống không
    /// có vùng chết. Nhưng một cú chạm thật trên máy thường nhích 3–6pt, và
    /// ngay khi cú kéo của thẻ nhận, nó huỷ nút đang được chạm: nút "không
    /// ăn". Gắn ở đây, cử chỉ con được ưu tiên hơn cử chỉ của thẻ, nên trên
    /// hàng nút ngón tay có 10pt dung sai như một nút trong danh sách cuộn,
    /// còn vượt quá thì thẻ vẫn bám theo như cũ. `nil` khi không có thẻ nào
    /// để kéo (xem trước, test).
    var transportDrag: AnyGesture<Void>? = nil

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
    @State private var queueTaps = 0
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
    ///
    /// 34 rồi (2026-10-08): 44 cộng phần đệm của kiểu `.glass` thành vòng tròn
    /// ~58pt, to quá trên máy thật. Vòng tròn kính vẫn quanh ~48pt, nên vùng
    /// chạm vẫn trên 44 Apple yêu cầu.
    private static let transportGlyphFrame: CGFloat = 34

    /// Larger than the arrows beside it so it still reads as the primary
    /// control now that it has no ring to set it apart.
    ///
    /// 30 rồi (2026-10-08): 42 cho vòng tròn kính ~72pt, lấn át cả hàng.
    private static let playGlyphSize: CGFloat = 30

    /// Back/next là biểu tượng trần, không vòng kính (2026-10-08), như Apple
    /// Music. Biểu tượng to hơn bản có vòng để vẫn đọc ra là nút, và khung
    /// chạm rộng hơn hẳn biểu tượng: thiếu vòng tròn thì mắt không còn chỉ
    /// cho ngón tay chỗ bấm.
    private static let arrowGlyphSize: CGFloat = 24
    private static let arrowHitFrame: CGFloat = 60

    /// Khoảng chừa dưới hàng hẹn giờ/hàng đợi. Thẻ mở tràn tới mép vật lý,
    /// nên không có khoảng này thì hai nút nằm sát mép dưới, đè lên vạch home.
    /// Nằm trong chồng nội dung để `PlayerCardSmallScreenTests` đo cả nó.
    private static let bottomClearance: CGFloat = 24

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
        .padding(.bottom, Self.bottomClearance)
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
        HStack(spacing: 40) {
            Button {
                previousTaps += 1
                playback.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: Self.arrowGlyphSize))
                    .frame(width: Self.arrowHitFrame, height: Self.arrowHitFrame)
                    .contentShape(Circle())
            }
            .buttonStyle(BareGlyphButtonStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: previousTaps)
            .disabled(playback.currentTrack == nil)

            Button {
                playPauseTaps += 1
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Self.playGlyphSize))
                    .symbolReplace()
                    .frame(width: Self.playGlyphSize * 1.4, height: Self.playGlyphSize * 1.4)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .medium), trigger: playPauseTaps)
            .disabled(playback.currentTrack == nil)

            Button {
                nextTaps += 1
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: Self.arrowGlyphSize))
                    .frame(width: Self.arrowHitFrame, height: Self.arrowHitFrame)
                    .contentShape(Circle())
            }
            .buttonStyle(BareGlyphButtonStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: nextTaps)
            .disabled(!playback.canGoNext)
        }
        .padding(.top, 8)
        .modifier(OptionalDrag(gesture: transportDrag))
    }

    /// Bằng khung của nút back/next (2026-10-08): ba vòng tròn kính cỡ phụ
    /// cùng một cỡ ~48pt, chỉ nút play to hơn. 44 cho vòng ~58pt, to lệch
    /// hẳn so với hàng điều khiển vừa thu nhỏ.
    private static let queueGlyphFrame: CGFloat = transportGlyphFrame

    /// Vùng chạm của nút hẹn giờ: biểu tượng trần, không có vòng kính đệm
    /// thêm, nên tự giữ đủ 44pt Apple yêu cầu.
    private static let sleepTimerHitHeight: CGFloat = 44

    /// One icon, trailing. Apple Music puts three here — lyrics, AirPlay and
    /// the queue — and this app has nothing to put behind the other two.
    private var queueToggleRow: some View {
        // Hai nút, hai đầu, một khoảng trống ở giữa.
        //
        // Nút hàng đợi vốn đứng một mình nép phải. Thêm hẹn giờ vào nép trái
        // cho hàng một trục đối xứng: mắt đọc ra hai thứ ngang hàng nhau chứ
        // không phải một cái chính và một cái phụ vừa được nhét thêm. Hai việc
        // ấy đúng là ngang hàng — "xem gì sắp tới" và "bao giờ thì ngừng".
        HStack {
            sleepTimerButton
            Spacer()
            Button {
                queueTaps += 1
                withAnimation(BottomBarStyle.queue) {
                    showingQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: Self.queueGlyphFrame, height: Self.queueGlyphFrame)
            }
            .glassToggleStyle(isOn: showingQueue)
            .buttonBorderShape(.circle)
            .sensoryFeedback(.impact(weight: .light), trigger: queueTaps)
            .disabled(playback.currentTrack == nil)
            .accessibilityLabel(String(
                localized: "Hàng đợi",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            ))
            .accessibilityAddTraits(showingQueue ? [.isButton, .isSelected] : .isButton)
        }
    }

    /// Hẹn giờ ngủ, đối xứng với nút hàng đợi ở đầu kia hàng.
    ///
    /// `Menu` chứ không sheet: sáu mốc, một mục "hết bài này" và một nút tắt
    /// không đáng một màn hình, và một sheet dựng từ đây sẽ đẩy player card đi —
    /// thứ `PlayerExpansion` đã tốn nhiều công để nó đứng yên.
    ///
    /// Số phút đọc từ `minutesRemaining`, thứ chỉ đổi mỗi phút chứ không mỗi
    /// giây — xem `SleepTimer` về lý do nó là thuộc tính lưu trữ. Ở chế độ "hết
    /// bài này" nó là `nil` và nút chỉ còn glyph đặc, vì ở đó không có con số
    /// nào tồn tại để mà hiện.
    private var sleepTimerButton: some View {
        Menu {
            ForEach(SleepTimer.presetMinutes, id: \.self) { minutes in
                Button {
                    playback.sleepTimer.start(minutes: minutes)
                } label: {
                    Text("\(minutes) phút", bundle: AppLanguage.resolvedBundle)
                }
            }
            Divider()
            Button {
                playback.sleepTimer.startAtEndOfTrack()
            } label: {
                Text("Hết bài này", bundle: AppLanguage.resolvedBundle)
            }
            if playback.sleepTimer.isRunning {
                Divider()
                Button(role: .destructive) {
                    playback.sleepTimer.cancel()
                } label: {
                    Text("Tắt hẹn giờ", bundle: AppLanguage.resolvedBundle)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: playback.sleepTimer.isRunning ? "moon.fill" : "moon")
                    .font(.system(size: 18, weight: .semibold))
                if let minutes = playback.sleepTimer.minutesRemaining {
                    Text("\(minutes)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }
            // Cùng thang với nút hàng đợi bên kia: trắng đặc khi đang bật,
            // `.secondary` khi tắt, `.tertiary` khi không có gì để hẹn.
            .foregroundStyle(
                playback.currentTrack == nil ? AnyShapeStyle(.tertiary)
                    : playback.sleepTimer.isRunning ? AnyShapeStyle(Color.white)
                                                    : AnyShapeStyle(.secondary)
            )
            .frame(height: Self.sleepTimerHitHeight)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .disabled(playback.currentTrack == nil)
        .accessibilityLabel(String(
            localized: "Hẹn giờ ngủ",
            bundle: AppLanguage.resolvedBundle,
            locale: AppLanguage.resolvedLocale
        ))
        .accessibilityValue(
            playback.sleepTimer.minutesRemaining.map { "\($0)" } ?? String(
                localized: "Tắt",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            )
        )
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

/// Gắn một cú kéo nếu có. Xem `NowPlayingContent.transportDrag`.
private struct OptionalDrag: ViewModifier {
    let gesture: AnyGesture<Void>?

    func body(content: Content) -> some View {
        if let gesture {
            content.gesture(gesture)
        } else {
            content
        }
    }
}

/// Nút chỉ có biểu tượng: nhấn thì co lại và mờ đi, nhả ra bật về.
///
/// Không vòng kính nên không có hiệu ứng nhấn của `.glass` để dựa vào; đây là
/// phản hồi nhìn thấy được thay cho nó, cùng với rung nhẹ ở chỗ gọi.
private struct BareGlyphButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.3)
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
