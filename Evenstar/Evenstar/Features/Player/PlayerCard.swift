import SwiftUI

/// The player. One card whose shape is a function of `progress`: 0 is the
/// collapsed bar above the library, 1 is the full screen.
///
/// Mini player and Now Playing are not separate views. They are this card at
/// two ends of one continuum, which is what lets the artwork grow continuously
/// instead of one view replacing another. `matchedGeometryEffect` cannot do
/// this: it interpolates between two discrete states as views appear and
/// disappear, and never tracks a finger.
struct PlayerCard: View {
    let playback: PlaybackService

    /// 0 collapsed on its own row above the tab bar, 1 slotted into the tab
    /// row between the leading circle and the search button. Interpolated
    /// rather than a `Bool` so the card can animate between the two.
    ///
    /// Three things read it and **all three must**: `collapsedSideMargin`,
    /// `collapsedBottomOffset`, and — through that offset — `dragTravel`.
    let minimised: Double

    // No explicit init. The one that stood here defaulted `minimised` to 0 so
    // `RootView` kept compiling while it was out of scope; it now passes a real
    // value, and a default of 0 would mean any future call site silently gets a
    // player that never joins the tab row — no compiler error, no failing test,
    // nothing visible. The synthesized memberwise init requires both arguments.

    /// The collapsed bar's own height. Lists do not read this directly — they
    /// apply `clearsBottomBar()`, which reaches
    /// `BottomBarMetrics.clearanceWithPlayer(bottomSafeAreaInset:)` and adds
    /// everything below the floating pill. Do not duplicate this as a literal.
    static let collapsedHeight: CGFloat = 54

    /// How far the collapsed pill is inset from each side of the safe area.
    ///
    /// Reads the bar's own margin rather than restating it. The pill and the
    /// tab bar are two floating surfaces one above the other, and their side
    /// edges have to line up; as two separate literals they lined up only for
    /// as long as nobody changed one of them.
    private static let pillSideMargin = BottomBarMetrics.sideMargin
    /// A true pill: half the collapsed height, so the caps are semicircles.
    private static let collapsedCornerRadius: CGFloat = collapsedHeight / 2

    private static let collapsedArtwork: CGFloat = 36
    /// How far the collapsed artwork sits in from the pill's leading edge.
    ///
    /// Larger than it looks like it needs to be, because the pill's leading
    /// cap is a semicircle and the visible gap is therefore not uniform: at
    /// mid-height the pill's edge is at x = 0, but level with the artwork's
    /// top and bottom edges the curve has already come in — at this height, to
    /// x ≈ 6.9. The eye judges that tightest point, not the generous gap in
    /// the middle, so the inset has to be set against it.
    ///
    /// At 18 the tightest gap is ~11pt and the artwork's corner sits 20.1pt
    /// from the cap's centre against a 27pt radius. Room remains to go further,
    /// but not indefinitely — the corner starts touching the curve around 27,
    /// and past that the artwork clips.
    ///
    /// These three numbers move together. Changing `collapsedHeight` or
    /// `collapsedArtwork` changes where the curve is at the artwork's edge, so
    /// the inset has to be re-derived rather than carried over.
    private static let collapsedArtworkInset: CGFloat = 18
    /// Between the collapsed artwork's trailing edge and the title.
    private static let collapsedArtworkGap: CGFloat = 10
    private static let expandedArtwork: CGFloat = 280
    private static let expandedCornerRadius: CGFloat = 38
    /// Gap between the top safe area and the expanded artwork.
    private static let expandedArtworkTopGap: CGFloat = 72

    /// Where the frosted layer in `background` stops being rendered at all.
    ///
    /// Tied to the opaque base's `min(1, progress * 3)`, which reaches 1 at
    /// exactly 1/3. Anything at or above that point is fully covered. A hair
    /// above 1/3 rather than 1/3 itself, so floating-point comparison at the
    /// boundary can only ever keep the layer a frame too long — never drop it a
    /// frame too early, which would be a visible flash.
    private static let materialCutoff: Double = 0.34

    /// Where the card rests: 0 collapsed, 1 expanded. Changed only on release.
    @State private var settled: Double = 0
    /// How far the in-flight drag has moved it. Zeroed when the drag settles.
    @State private var dragDelta: Double = 0
    /// Whether a drag is in flight. Sizes the hit region — see the note at the
    /// `.contentShape` call site for why that cannot be derived from
    /// `progress`. Deliberately not folded into `dragDelta != 0`: a drag that
    /// has clamped `progress` to 0 is still in flight and must keep the large
    /// region, which is precisely the case that broke.
    @State private var isDragging = false

    @State private var artwork: UIImage?
    @State private var tint: Color?

    private var progress: Double { min(max(settled + dragDelta, 0), 1) }

    /// Publishes `progress` outward so the content behind the card can recede
    /// with it, the way a sheet pushes its presenting screen back.
    ///
    /// This state was private for most of the card's life, and deliberately: an
    /// earlier request to hide the tab bar behind the expanded card was turned
    /// down rather than exposing it, because the expanded card is opaque and
    /// full-screen and already covers the bar. The recede is different — it is
    /// visible for the whole transition, and there is no way to draw it from
    /// outside without knowing how far the card has travelled.
    ///
    /// Written from the gesture and from `expand()`/`collapse()`, never from an
    /// `onChange` on `progress`. That distinction is what made the recede smooth:
    /// an `onChange` runs *after* this view's body, so every dragged frame cost
    /// a second update pass, and the write invalidated whoever held the other
    /// end. Writing where the value actually changes keeps it to one pass.
    ///
    /// During the settle spring this is set once, to the destination, inside the
    /// same `withAnimation`. The recede then runs its own spring with the same
    /// parameters and lands with the card, rather than being driven frame by
    /// frame from here.
    let expansion: PlayerExpansion

    /// How far the collapsed pill is inset from each edge of the **safe area**
    /// *at collapsed rest*: `pillSideMargin` (21) on its own row, widening to
    /// `BottomBarMetrics.minimisedPlayerInset` (79) as the pill slots into the
    /// tab row between the leading circle and the search button.
    ///
    /// Safe-area-relative, and it stays that way even though the vertical
    /// measurements are now screen-relative: `FloatingTabBar` divides up the
    /// safe-area width (its `.padding(.horizontal,)` is applied inside the safe
    /// area), so the slot this pill has to land in is measured from there.
    ///
    /// Safe area, not screen: this is the space `FloatingTabBar` divides up,
    /// and the pill has to land in the slot the bar reserved. `card(size:insets:)`
    /// adds `insets.leading`/`insets.trailing` to convert it into the physical
    /// coordinates this view actually lays out in — separately per side, since
    /// those two are not equal in landscape. See the note there.
    ///
    /// Deliberately free of `progress`. The card's own layout multiplies it by
    /// `(1 - progress)` at the call site so an expanded card is unaffected; the
    /// hit region must NOT, and reads this resting value directly behind its
    /// drag-state gate — see the note at the `.contentShape` call site.
    private var collapsedSideMargin: CGFloat {
        Self.pillSideMargin
            + (BottomBarMetrics.minimisedPlayerInset - Self.pillSideMargin) * CGFloat(minimised)
    }

    /// **Physical screen** bottom edge up to the collapsed pill's bottom edge:
    /// `BottomBarMetrics.playerBottomOffset` (79) on its own row above the tab
    /// bar, dropping to `BottomBarMetrics.screenBottomInset` (21) as the pill
    /// joins that row.
    ///
    /// The screen, not the safe area. Both endpoints are measured from the
    /// physical edge now, matching where the tab bar itself is anchored, and
    /// this view is the right place for that: the card `.ignoresSafeArea()`, so
    /// it already lays out in physical coordinates and this offset is already
    /// in the units the padding below needs. That is why `insets.bottom` no
    /// longer appears in either the padding or `dragTravel` — adding it back
    /// would push the pill 34pt above where the bar reserved room for it on a
    /// phone with a home indicator, and leave it correct on an SE, which is the
    /// worst way for this to be wrong.
    ///
    /// **This is the one expression both the bottom padding and `dragTravel`
    /// read.** It exists as a single value precisely because those two have
    /// drifted apart twice already, and it is now worse than a forgotten
    /// constant: this distance changes continuously while the user scrolls, so
    /// a `dragTravel` left reading the literal `playerBottomOffset` would lag
    /// the finger by 58pt while minimised and by a fraction of that mid-morph.
    /// Do not restate either half of it anywhere.
    private var collapsedBottomOffset: CGFloat {
        BottomBarMetrics.playerBottomOffset
            + (BottomBarMetrics.screenBottomInset - BottomBarMetrics.playerBottomOffset)
            * CGFloat(minimised)
    }

    // The spring that used to live here is now `BottomBarStyle.settle`, shared
    // with `expand()` and with the fade that accompanies `collapse()` when the
    // queue ends (F7), so the card disappears on the same curve it moves on.
    //
    // `expand()` used to define its own inline, described in a comment as
    // "slightly snappier". Converted to the same units the rest of the app uses
    // — 0.42/0.14 against 0.45/0.15 — the two differed by three hundredths of a
    // second, and the "snappier" one was the slower. The distinction was not
    // real, so there is now one spring.

    /// The expanded artwork's actual side, derived from the space available
    /// rather than trusting the `expandedArtwork` constant blindly.
    ///
    /// The constant alone put the title/scrubber/transport row below the
    /// card's own bottom edge in landscape on an iPhone 12 — `expandedContent`
    /// offset the content by a fixed `expandedArtworkTopGap + expandedArtwork
    /// + 40`, which exceeded the card's full landscape height, so everything
    /// below the artwork was clipped away and the expanded player had no
    /// controls at all. See F2.
    ///
    /// `440` is a rough allowance for everything `NowPlayingContent` stacks
    /// below the artwork — a starting point, like the other constants here, not
    /// a measured minimum. The stack is five elements in a
    /// `VStack(spacing: 24)`:
    ///
    ///   1. the title block — two reserved `.title2` lines + a `.subheadline`,
    ///      measured at 81pt
    ///   2. `ScrubberBar`, ~53pt with its time labels
    ///   3. the transport row, ~82pt — **not** the 44pt glyph frame plus its
    ///      8pt top padding. The play button is `.font(.system(size: 64))` and
    ///      draws ~74pt tall, which is what actually sizes the `HStack`. Sizing
    ///      this row from `transportGlyphFrame` under-counts it by 30pt.
    ///   4. the repeat row — 32pt frame + `.padding(.top, 4)` = 36pt
    ///   5. `SystemVolumeSlider`, 44pt
    ///
    /// The five elements are the title block (81), scrubber (53), transport
    /// row (82), volume row (28) and repeat row (40, being a 36pt frame plus
    /// 4pt of top padding). With four 24pt gaps that is **~380pt**.
    ///
    /// The transport row is 82 and not the 44 of `transportGlyphFrame`: the
    /// play button is `.font(.system(size: 64))` with no frame of its own, so
    /// it, not its neighbours, sizes that `HStack`. The heights here were
    /// measured off a screenshot of the real expanded player, not estimated.
    ///
    /// Its history is a list of the same mistake. It was raised from 350 when
    /// the volume slider was added, but only by the slider's own 44pt — the
    /// extra `VStack` gap that came with a fourth element (+24pt) was
    /// forgotten, leaving it 18pt short and clipping the slider on a two-line
    /// title on a 4.7" device. It was then left at 380 when the repeat row was
    /// added as a fifth element, which is another 36 + 24 = 60pt, and clipped
    /// the volume slider again on a 4.7" device in portrait and on every
    /// iPhone in landscape. Hence 440.
    ///
    /// 440 was kept when the volume row later shrank from 44 to
    /// `ScrubberBar.touchHeight` (28) and the repeat row grew by 4, a net −12.
    /// The number did not need to move — this is the direction that is always
    /// safe — and the slack it buys is spent below.
    ///
    /// **Adding anything else to that stack means raising this by the new
    /// element's height *plus* the 24pt `VStack` spacing, not just the
    /// element's height.** That omission is the mistake this number has now
    /// been corrected for twice.
    ///
    /// Why the value is what the content actually gets: when the height term
    /// below binds, `artworkSide == fullSize.height - insets.top -
    /// expandedArtworkTopGap - 440`, and `expandedContent` offsets by
    /// `insets.top + expandedArtworkTopGap + artworkSide + 40`. Those cancel,
    /// so the region left below the artwork is exactly `440 - 40 = 400pt`,
    /// whatever the device. Against a ~380pt stack that leaves ~20pt. Do not
    /// read that as headroom: `NowPlayingContent` has no `.dynamicTypeSize`
    /// cap, so one step up in accessibility text grows the two `.title2` lines
    /// and the `.subheadline` beneath them by more than 20pt and clips the
    /// bottom again on a 4.7" screen. The durable fix is to measure the stack
    /// instead of allowing for it; until then this constant is a floor, not a
    /// margin. At 380
    /// the region was 340pt, 52pt short, and the whole volume slider sat below
    /// the card's bottom edge where it could not be dragged.
    ///
    /// Verified by screenshot rather than by arithmetic alone, on both ends of
    /// the change: at 380 the repeat glyph landed 15pt above the bottom edge on
    /// a 4.7" screen in portrait (and 17pt on an iPhone 17 in landscape), with
    /// no room for the 24pt gap and 44pt slider that follow it; at 440 it
    /// landed 75pt above, which fits them both.
    ///
    /// One case this cannot fix, and it is worth knowing before the number is
    /// nudged again: a 375pt-tall screen in landscape (a 4.7" device rotated)
    /// has less height than the stack needs, so something is always clipped
    /// there. At 380 it was the volume slider; at 440 it is the title — and
    /// not merely its top line. At that width the title fits on one line, so
    /// the whole line sits above the card and only the tips of its descenders
    /// show. The artist and album line, scrubber, transport, volume and repeat
    /// rows all survive.
    ///
    /// Losing the title is still the better end to lose: it is information the
    /// user can get elsewhere, where an unreachable volume slider is a control
    /// they cannot operate at all. But it is a real regression on a supported
    /// orientation, not a cosmetic trim, and no value of this constant fixes
    /// it — a stack that tall does not fit a screen that short. Landscape on
    /// every taller iPhone fits at 440.
    ///
    /// This value is deliberately allowed to go negative for tall constants
    /// against a short `fullSize.height` (e.g. landscape on a compact
    /// device); see the note on the negative case at the call sites in
    /// `expandedContent` and `loadArtwork` — SwiftUI clamps a negative frame
    /// side to zero, but `expandedContent`'s offset consumes this *signed*
    /// value directly, and that is the only reason landscape still reserves
    /// its full content region instead of being pushed down and clipped.
    /// Clamping this to zero at the source (e.g. wrapping the `min(...)` in
    /// `max(0, …)`) would leave the artwork looking unchanged while silently
    /// breaking landscape — do not do that.
    private static func artworkSide(fullSize: CGSize, insets: EdgeInsets) -> CGFloat {
        min(
            Self.expandedArtwork,
            fullSize.height - insets.top - Self.expandedArtworkTopGap - 440,
            fullSize.width - 48
        )
    }

    var body: some View {
        // `outer` must NOT itself ignore the safe area: only a reader that
        // still respects it reports real `safeAreaInsets`. `ignoresSafeArea()`
        // is applied to the card view produced from it instead, so the card
        // can still visually reach the physical edges while the insets we
        // read to lay it out stay correct. See F2 in the Phase 2a task-2
        // review for why the naive `GeometryReader { }.ignoresSafeArea()`
        // ordering zeroes the insets.
        GeometryReader { outer in
            card(size: outer.size, insets: outer.safeAreaInsets)
                .ignoresSafeArea()
                // Attached here, rather than outside the reader, so the
                // artwork's target size can be derived from the same
                // `outer` geometry the card lays out with. See F2.
                .task(id: playback.currentTrack?.id) {
                    await loadArtwork(safeAreaSize: outer.size, insets: outer.safeAreaInsets)
                }
        }
        .opacity(playback.currentTrack == nil ? 0 : 1)
        .animation(BottomBarStyle.settle, value: playback.currentTrack == nil)
        .allowsHitTesting(playback.currentTrack != nil)
        // Nothing is announced or focusable while the card is invisible —
        // without this a screen reader can still reach the "—" title, the
        // scrubber and the transport buttons of a card no one can see. See F4.
        .accessibilityHidden(playback.currentTrack == nil)
        .onChange(of: playback.currentTrack?.id) { _, id in
            if id == nil { collapse() }
        }
    }

    /// - Parameter size: the *safe-area* size of the reader (not the full
    ///   screen — see the note on `outer` above).
    /// - Parameter insets: the reader's real safe-area insets.
    private func card(size: CGSize, insets: EdgeInsets) -> some View {
        let fullHeight = size.height + insets.top + insets.bottom
        // Same reconstruction as the height, mirrored horizontally: `size`
        // is the safe-area size, so in landscape (where the horizontal
        // insets are nonzero) `size.width` alone is narrower than the
        // screen. Every site that used to read `size.width` reads
        // `fullWidth` instead. See R1.
        let fullWidth = size.width + insets.leading + insets.trailing
        let fullSize = CGSize(width: fullWidth, height: fullHeight)
        let travel = max(fullHeight - Self.collapsedHeight, 1)
        let height = Self.collapsedHeight + travel * progress
        // The collapsed card is a floating pill inset from each edge of the
        // SAFE AREA; the expanded card still spans the whole display.
        //
        // The safe area, not the physical screen, and the two are not the same
        // space. This view reconstructs `fullWidth` and sits inside
        // `.ignoresSafeArea()`, so its own coordinates start at the physical
        // edge — but `FloatingTabBar`, whose row the pill has to slot into,
        // applies its `.padding(.horizontal, sideMargin)` OUTSIDE its
        // `GeometryReader` and never ignores the safe area, so the bar divides
        // up the *safe-area* width. Measuring the pill from the physical edge
        // therefore placed it `insets.leading`/`insets.trailing` outside the
        // slot the bar had reserved for it. In portrait those insets are 0 and
        // the two spaces coincide, which is why this looked correct; in
        // landscape on an iPhone 17 they are 59, and the minimised pill
        // overhung the leading circle and the search button by 59pt on each
        // side — and, being last in `RootView`'s `ZStack`, ate their taps,
        // including the only tap-to-restore affordance. Đợt A's Critical
        // defect again, in a supported orientation.
        //
        // **Leading and trailing are computed separately and never averaged.**
        // A single symmetric margin cannot express this: rotate a notched
        // device one way and the notch's inset lands on one side while the
        // other side gets only the rounded-corner allowance, so the two are
        // genuinely unequal. Averaging them, or taking `max`, would centre the
        // pill in a slot the bar has not centred and reintroduce the overhang
        // on one side at half the size — harder to see and no less wrong.
        //
        // Both are scaled by `(1 - progress)` and so are exactly 0 at
        // progress 1: `cardWidth == fullWidth` when expanded, the card still
        // reaches both physical edges, and every layout inside it is unchanged
        // there. Minimisation, like the pill margin it generalises, applies
        // only while the card is collapsed.
        let collapsedLeadingMargin = insets.leading + collapsedSideMargin
        let collapsedTrailingMargin = insets.trailing + collapsedSideMargin
        let leadingMargin = collapsedLeadingMargin * (1 - progress)
        let trailingMargin = collapsedTrailingMargin * (1 - progress)
        let cardWidth = fullWidth - leadingMargin - trailingMargin
        // The size everything laid out *inside* the card measures against.
        // Note this is deliberately NOT what `artworkSide` below is given —
        // see the comment there.
        let cardSize = CGSize(width: cardWidth, height: fullHeight)
        // `fullSize`, never `cardSize`: this is the artwork's *expanded*
        // target side, which must not vary with `progress`. Feeding it the
        // interpolating `cardWidth` would make the artwork pulse through the
        // morph, and `loadArtwork` computes its decode target by calling
        // `artworkSide(fullSize:insets:)` from its own geometry — the two must
        // agree or the decoded image no longer matches what is drawn.
        let artworkSide = Self.artworkSide(fullSize: fullSize, insets: insets)
        // Distinct from `travel` above: that one sizes the frame so it
        // still reaches exactly `fullHeight` at progress 1. This one is
        // only the pixel-to-progress divisor for the gesture below. The
        // card's top edge doesn't actually travel the full `travel`
        // distance — the bottom padding shortens the visible range by
        // `collapsedBottomOffset` (the tab bar, its gap below the screen edge,
        // and the gap between the bar and the pill — shrinking to just that
        // first gap as the pill joins the tab row) — so using `travel` there
        // made the card trail the finger by exactly that much. The same term
        // must appear here and in that padding, or they drift apart again —
        // which has now happened twice. See R2.
        //
        // `insets.bottom` used to be a third term in both, and is now in
        // neither. It was there while `collapsedBottomOffset` was measured from
        // the safe area and had to be converted into the physical coordinates
        // this view lays out in; the offset is measured from the screen now, so
        // the conversion is gone. Adding it back to one site alone puts the
        // card 34pt behind the finger on a phone with a home indicator and
        // leaves it exactly right on an iPhone SE — do not.
        //
        // The offset is not a constant somebody can forget to update in one of
        // the two places either: it moves continuously with `minimised` while
        // the user scrolls. That is why it is written once, as
        // `collapsedBottomOffset`, and read here and by the padding rather than
        // restated. Substituting the literal `playerBottomOffset` back into
        // either site puts the card 58pt behind the finger while minimised.
        //
        // The derivation that keeps them honest, with the card bottom-aligned
        // in a full-screen frame whose height this padding shortens, writing
        // `B` for `collapsedBottomOffset`, `H` for `fullHeight` and `C` for
        // `collapsedHeight`. The padding is applied outside that frame, so it
        // shortens the region rather than moving the card inside it: the
        // region's bottom, and hence the card's bottom, lands at H − B(1−p),
        // and the card's height is C + (H − C)p. Therefore
        //
        //   top(p) = H − B(1−p) − C − (H − C)p
        //   top(0) = H − B − C
        //   top(1) = H − C − (H − C) = 0
        //
        // Visible travel is top(0) − top(1) = H − C − B, which is exactly the
        // expression below, term for term, for *every* value of `B` and hence
        // of `minimised`. The slope is what the finger actually feels, and it
        // is constant rather than merely right at the ends:
        //
        //   d top / d p = B − (H − C) = −(H − C − B) = −dragTravel
        //
        // so one point of upward finger travel raises the card by exactly one
        // point at every progress, at either end of `minimised` and mid-morph.
        //
        // On an iPhone 17 (H 874, C 50, insets.bottom 34 — which appears
        // nowhere): at minimised 0, B 79, top(0) 745 and dragTravel 745; at
        // minimised 1, B 21, top(0) 803 and dragTravel 803. If you change one,
        // change the other.
        let dragTravel = max(
            fullHeight - Self.collapsedHeight - collapsedBottomOffset,
            1
        )

        return ZStack(alignment: .topLeading) {
            background
            miniChrome(width: cardWidth)
            expandedContent(size: cardSize, topInset: insets.top, artworkSide: artworkSide)
            artworkView(size: cardSize, topInset: insets.top, artworkSide: artworkSide)
            grabber(topInset: insets.top)
        }
        .frame(width: cardWidth, height: height, alignment: .top)
        .clipShape(
            UnevenRoundedRectangle(
                // Collapsed the card is a pill — all four corners at
                // `collapsedCornerRadius`. Expanded it is the Now Playing
                // card: 38pt top corners, square bottom against the display
                // edge. The top corners therefore interpolate 32 -> 38 and are
                // never 0; the bottom two interpolate 32 -> 0.
                topLeadingRadius: Self.collapsedCornerRadius
                    + (Self.expandedCornerRadius - Self.collapsedCornerRadius) * progress,
                bottomLeadingRadius: Self.collapsedCornerRadius * (1 - progress),
                bottomTrailingRadius: Self.collapsedCornerRadius * (1 - progress),
                topTrailingRadius: Self.collapsedCornerRadius
                    + (Self.expandedCornerRadius - Self.collapsedCornerRadius) * progress
            )
        )
        // Lifts the collapsed pill off the list behind it, with the same shadow
        // the tab bar's surfaces use — they share a screen, and while minimised
        // they share a row, so a lift on one and none on the other is visible
        // immediately. Shared rather than restated so a surface added later
        // cannot land with a slightly different one.
        //
        // Its colour, radius and offset are constant by design and must not be
        // interpolated with `progress`: this view moves every frame during a
        // drag, and animating a shadow forces a fresh offscreen pass each time.
        // No fade-out is needed — expanded, the card fills the screen and the
        // shadow is occluded anyway.
        .floatingBarShadow()
        // Positions the card horizontally. It cannot be centred in the frame
        // below any more: with `leadingMargin` and `trailingMargin` unequal —
        // which is exactly the landscape case this pair exists for — centring
        // would split the difference and put the pill in neither the slot the
        // bar reserved nor anywhere principled. Padding one side and aligning
        // to the other states the asymmetry directly: the card's leading edge
        // lands at `leadingMargin`, its trailing edge at `fullWidth -
        // trailingMargin`, whatever those two happen to be. When they are
        // equal (every portrait case) this is identical to the centring it
        // replaces.
        //
        // Inside the flexible frame, not outside it, for the same reason the
        // bottom padding is outside: this one must move the card *within* the
        // full-width region, while that one must shorten the region itself.
        .padding(.leading, leadingMargin)
        // The card is laid out bottom-aligned in a full-screen frame, and
        // hit-testing binds to *that* frame rather than to the card, so the
        // region's size is ours to choose instead of being whatever the card
        // currently measures. The frame still spans the full width — only the
        // alignment moved, from `.bottom` to `.bottomLeading`, so the padding
        // above resolves against the leading edge rather than being centred
        // away.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // This line has now been wrong in BOTH directions, so read before you
        // touch it.
        //
        // Attached to the full-screen frame with a plain `Rectangle()`, a
        // collapsed card hit-tests the whole display and the library behind it
        // becomes untappable: rows expand the player instead of playing, the
        // toolbar `+` is unreachable, and the list neither scrolls nor swipes
        // to delete — from launch, since restoring persisted state sets a
        // current track. That was F1 (Critical).
        //
        // Attached to the card-sized view instead, the region SHRINKS WITH THE
        // CARD. During a collapse the card's top edge rises past the finger,
        // the finger falls outside the region, and the in-flight drag is
        // dropped and re-recognised — frames "held back", continuous flicker.
        // Expanding grows the card towards the finger and is unaffected, which
        // is why only collapsing stuttered. Four probes ruled out drawing
        // entirely: even a bare resizing `Rectangle` dropped frames.
        //
        // Both versions shared one assumption — that the region should track
        // the card's size. It must not. It keys on whether a drag is in
        // flight: while dragging (or whenever the card is off its collapsed
        // rest) the region is the whole screen and cannot shrink out from
        // under the finger; at collapsed rest it is exactly the bar, so the
        // library stays fully usable. Do not re-derive this height from
        // `progress` alone.
        //
        // The same reasoning governs the horizontal dimension, added with the
        // floating pill: at collapsed rest the region is inset by
        // `collapsedSideMargin` so the strips beside the pill fall through to
        // the library — without it, tapping near a screen edge expands the
        // player. But the inset must come from this same drag-state gate, NOT
        // from the interpolated `sideMargin`: derived from `progress` it would
        // narrow the region mid-drag and drop the finger sideways, exactly the
        // failure described above in the vertical direction.
        //
        // `collapsedSideMargin` widens 12 -> 76 with `minimised`, and the rest
        // inset must follow it. Left at the bare `pillSideMargin`, a minimised
        // player hit-tests the full width of the row and swallows both the
        // leading circle and the search button — Đợt A's Critical defect, one
        // layer down. Note this changes only the region's *horizontal extent at
        // rest*: `minimised` is not `progress`, it does not move during a drag,
        // and the `isDragging || progress > 0` gate on all three dimensions is
        // untouched, so the region is still the whole screen for the entire
        // duration of a drag.
        //
        // The two sides are passed separately and read the *collapsed* margins,
        // not `leadingMargin`/`trailingMargin`: those carry the `(1 - progress)`
        // factor, and a region that narrows with `progress` would drop the
        // finger sideways mid-drag — the failure described above, in the
        // horizontal direction. These two are functions of `minimised` and the
        // safe area only. They must match the card's own edges exactly, or the
        // region and the pill disagree about where the pill is.
        //
        // Moving the bar's anchor from the safe area to the screen changed
        // nothing here, and that is worth stating rather than leaving to be
        // rediscovered. The horizontal insets read `collapsedSideMargin`, which
        // is still safe-area-relative because the tab bar still divides up the
        // safe-area width — they took the 12 -> 21 change through
        // `pillSideMargin` and needed nothing else. The vertical dimension
        // follows the anchor on its own: `BottomHitRegion` measures `height` up
        // from `rect.maxY`, and `rect` is the frame the bottom padding below
        // shortens, so the region's bottom edge *is* the card's bottom edge at
        // whatever the offset now says — which is exactly why that padding has
        // to stay outside this frame.
        .contentShape(
            BottomHitRegion(
                height: isDragging || progress > 0 ? fullHeight : Self.collapsedHeight,
                leadingInset: isDragging || progress > 0 ? 0 : collapsedLeadingMargin,
                trailingInset: isDragging || progress > 0 ? 0 : collapsedTrailingMargin
            )
        )
        .gesture(drag(travel: dragTravel))
        .onTapGesture { if progress < 0.5 { expand() } }
        // At progress 0 this holds the card's bottom `collapsedBottomOffset`
        // above the **physical** bottom edge, so the pill floats clear of the
        // floating tab bar — which is anchored to that same edge — and matches
        // where every list's `clearsBottomBar` spacer stops; or, once
        // minimised, drops onto the tab row itself. At progress 1 it goes to 0
        // so the expanded card reaches the physical bottom edge. See F3.
        // `dragTravel` above subtracts exactly this same term, reading the very
        // same `collapsedBottomOffset` — see the note there. No `insets.bottom`
        // in either: this view lays out in physical coordinates and the offset
        // is already stated in them.
        //
        // It must stay *outside* the frame and the hit region above. Applied
        // here it shortens the height proposed to that frame, so the frame's
        // bottom edge lands exactly where the card's bottom edge is, and
        // `BottomHitRegion` — which measures up from `rect.maxY` — lines up
        // with the collapsed bar. Moved inside (padding the card itself), the
        // frame would still span the full screen and the collapsed region
        // would sit `insets.bottom` too low, missing the top of the bar.
        .padding(.bottom, collapsedBottomOffset * (1 - progress))
    }

    /// The bottom `height` points of whatever it is applied to, inset by
    /// `leadingInset` and `trailingInset` on the respective sides.
    ///
    /// Used instead of `Rectangle()` so the hit region's size can be chosen
    /// by state rather than inherited from the card's current size. See the
    /// note at the `.contentShape` call site.
    ///
    /// The two insets are separate rather than one `horizontalInset` because
    /// the safe area they now include is not symmetric: in landscape on a
    /// notched device one side carries the notch's inset and the other does
    /// not. A single number would have to average them and would leave the
    /// region overhanging the tab bar's circles on one side.
    ///
    /// `path(in:)` has no access to the environment, so `leadingInset` is
    /// applied at `rect.minX` — correct under a left-to-right layout, which is
    /// the only direction this app currently ships. If it is ever localised
    /// right-to-left the card's own `.padding(.leading, …)` would flip and this
    /// would not, so the two would have to be reconciled here.
    private struct BottomHitRegion: Shape {
        var height: CGFloat
        var leadingInset: CGFloat
        var trailingInset: CGFloat

        func path(in rect: CGRect) -> Path {
            Path(
                CGRect(
                    x: rect.minX + leadingInset,
                    y: rect.maxY - height,
                    width: rect.width - leadingInset - trailingInset,
                    height: height
                )
            )
        }
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            // Opaque base: the two layers above cross-fade via opacity, which
            // composites rather than sums, so without this the card is
            // translucent through the whole middle of the morph (F4). Gated
            // on progress rather than always-on, so the collapsed bar keeps
            // its frosted look instead of sitting on a flat grey rectangle —
            // `min(1, progress * 3)` reaches full opacity at progress ≈ 1/3,
            // the same point miniChrome's `1 - progress * 3` fade reaches
            // zero, and the material layer alone is fully opaque (1 - 0 = 1)
            // at progress 0, so the base contributes nothing there and the
            // list is genuinely visible, blurred, through the resting bar.
            // See R3.
            Color(.systemGroupedBackground)
                .opacity(min(1, progress * 3))
            // Dropped entirely — not merely faded — once the opaque base above
            // reaches full opacity at progress = 1/3.
            //
            // A material is a live blur of everything behind it, recomputed
            // every frame, and it costs the same at opacity 0.01 as at 1. Held
            // at `1 - progress` alone it stayed alive for the whole drag, so
            // two thirds of every expand was spent blurring a layer sitting
            // underneath a fully opaque one. Nothing on screen changes: at the
            // moment it is removed it is already completely covered.
            if progress < Self.materialCutoff {
                Rectangle()
                    .fill(.thinMaterial)
                    .opacity(1 - progress)
            }
            LinearGradient(
                colors: [tint ?? Color(.systemGroupedBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)
        }
    }

    /// Hints that the expanded card can be dragged away, the way the
    /// `.sheet` this replaced showed `.presentationDragIndicator(.visible)`.
    /// Fades in with `progress` so it is invisible while collapsed. See F8.
    private func grabber(topInset: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary)
            .opacity(0.4)
            .frame(width: 36, height: 5)
            .padding(.top, topInset + 8)
            .frame(maxWidth: .infinity, alignment: .top)
            .opacity(progress)
            .allowsHitTesting(false)
    }

    private func miniChrome(width: CGFloat) -> some View {
        MiniPlayerChrome(playback: playback)
            // Derived rather than a literal so the text cannot drift out of
            // step with the artwork: this is where the artwork ends, plus the
            // gap. The old `collapsedArtwork + 24` folded the inset and the
            // gap into one number, so moving the artwork silently changed the
            // gap instead of moving the text with it.
            .padding(.leading, Self.collapsedArtworkInset + Self.collapsedArtwork + Self.collapsedArtworkGap)
            // 16 rather than 12 so the forward button clears the pill's
            // rounded right cap.
            .padding(.trailing, 16)
            .frame(width: width, height: Self.collapsedHeight)
            .opacity(max(0, 1 - progress * 3))
            .allowsHitTesting(progress < 0.1)
    }

    private func expandedContent(size: CGSize, topInset: CGFloat, artworkSide: CGFloat) -> some View {
        NowPlayingContent(playback: playback)
            .padding(.horizontal, 24)
            .frame(width: size.width)
            .offset(y: topInset + Self.expandedArtworkTopGap + artworkSide + 40)
            .opacity(max(0, (progress - 0.5) * 2))
            .allowsHitTesting(progress > 0.9)
    }

    private func artworkView(size: CGSize, topInset: CGFloat, artworkSide: CGFloat) -> some View {
        let side = Self.collapsedArtwork
            + (artworkSide - Self.collapsedArtwork) * progress
        let collapsedCentre = CGPoint(
            x: Self.collapsedArtworkInset + Self.collapsedArtwork / 2,
            y: Self.collapsedHeight / 2
        )
        let expandedCentre = CGPoint(
            x: size.width / 2,
            y: topInset + Self.expandedArtworkTopGap + artworkSide / 2
        )
        let centre = CGPoint(
            x: collapsedCentre.x + (expandedCentre.x - collapsedCentre.x) * progress,
            y: collapsedCentre.y + (expandedCentre.y - collapsedCentre.y) * progress
        )

        return Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color(.tertiarySystemFill))
                    // `.font(size:)` isn't animatable, so during the expand
                    // spring the glyph would otherwise jump to its final size
                    // immediately while the surrounding frame is still
                    // interpolating 40 -> 280. Render it at a fixed base size
                    // and use `.scaleEffect`, which does animate, to track
                    // `side` continuously. Ratio matches ArtworkThumbnail's
                    // placeholder (size * 0.5). See F6.
                    Image(systemName: "music.note")
                        .font(.system(size: Self.expandedArtwork * 0.5))
                        .foregroundStyle(.secondary)
                        .scaleEffect(side / Self.expandedArtwork)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.12))
        // Constant, for the same reason the card's own shadow is constant —
        // see the note at `.floatingBarShadow()` above. This was
        // `radius: 10 * progress, y: 4 * progress`, which broke that rule on
        // the one view in the card that has it worst: the artwork changes
        // *size* every frame as well as position, so an interpolated shadow
        // could not be cached between frames even in principle. It had to be
        // regenerated from scratch, 36pt to 280pt, for the whole drag.
        //
        // Constant means the collapsed thumbnail now carries the shadow too,
        // where it used to fade to nothing. At 36pt under a 6pt radius that
        // reads as the same lift the pill itself has, which is the intent —
        // one lighting model for every surface on this screen.
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .position(centre)
    }

    // MARK: - Gesture

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Guarded rather than assigned unconditionally: this fires on
                // every touch move, and a redundant `@State` write would
                // invalidate the view again for nothing.
                if !isDragging { isDragging = true }
                // Written here rather than from an `onChange` on `progress` —
                // see the note on `expansion`.
                defer { expansion.progress = progress }
                // No rubber-band past either end: `progress` (settled +
                // dragDelta, clamped) is rigid at 0 and 1. An earlier version
                // of this method shaved the excess off `delta` here to fake
                // give, but that landed after the clamp already applied, so
                // it had no visible effect at any input — the code and its
                // comment disagreed. See F5; overshoot geometry was judged
                // more risk than the interaction is worth for this pass.
                dragDelta = -value.translation.height / travel
            }
            .onEnded { value in
                // Cleared outside the `withAnimation` below: the hit region
                // is not an animatable property, and the settle should hand
                // the screen back as soon as the finger lifts.
                isDragging = false
                // Decide on the predicted end, not the current offset, so a
                // quick flick settles the card even though the finger barely
                // moved. Comparing raw distance is what makes hand-rolled
                // sheets feel heavy.
                let predicted = settled - value.predictedEndTranslation.height / travel
                withAnimation(BottomBarStyle.settle) {
                    settled = predicted > 0.5 ? 1 : 0
                    dragDelta = 0
                    expansion.progress = settled
                }
            }
    }

    private func expand() {
        withAnimation(BottomBarStyle.expand) {
            settled = 1
            dragDelta = 0
            expansion.progress = 1
        }
    }

    private func collapse() {
        withAnimation(BottomBarStyle.expand) {
            settled = 0
            dragDelta = 0
            expansion.progress = 0
        }
    }

    /// - Parameter safeAreaSize / insets: the same geometry `card(size:insets:)`
    ///   lays out with, so the decode target matches what `artworkView` will
    ///   actually draw. See F2.
    private func loadArtwork(safeAreaSize: CGSize, insets: EdgeInsets) async {
        // Bail rather than clear: when the last track in the queue finishes,
        // `currentTrack` goes nil and this re-fires with a nil id while the
        // card is still mid collapse-and-fade. Clearing `artwork`/`tint` here
        // would flash a bare placeholder for that whole animation. Leaving
        // the last frame's artwork in place instead means it fades away with
        // the rest of the card. See F3.
        guard playback.currentTrack != nil else { return }

        let fullSize = CGSize(
            width: safeAreaSize.width + insets.leading + insets.trailing,
            height: safeAreaSize.height + insets.top + insets.bottom
        )
        let artworkSide = Self.artworkSide(fullSize: fullSize, insets: insets)

        let path = playback.currentTrack?.artworkRelativePath
        async let image = ArtworkStore.image(
            for: path,
            maxPixel: artworkSide * UIScreen.main.scale
        )
        async let colour = ArtworkStore.dominantColor(for: path)
        let (loadedImage, loadedColour) = await (image, colour)

        guard playback.currentTrack?.artworkRelativePath == path else { return }
        artwork = loadedImage
        tint = loadedColour
    }
}
