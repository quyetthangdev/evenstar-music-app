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
    /// Reference size for the placeholder glyph's `.scaleEffect`, and nothing
    /// else. Any fixed number works — see the note at the placeholder in
    /// `artworkView` for why the glyph is drawn at a constant `.font(size:)`
    /// and scaled rather than sized directly. It is emphatically **not** the
    /// expanded artwork's size any more; that is
    /// `artworkHeight(fullSize:)` and it varies by device.
    private static let placeholderGlyphBase: CGFloat = 280
    private static let expandedCornerRadius: CGFloat = 38

    /// How much of the artwork's own height dissolves into the background
    /// beneath it, at full expansion.
    ///
    /// The artwork is full-bleed, so it has to end *somewhere*; a hard edge
    /// across the screen would read as a seam. Its bottom is therefore masked
    /// away into the drifting field of its own colours beneath it, so nothing
    /// about the transition is a boundary the eye can find.
    ///
    /// Its history, because the number has moved twice and each move was for a
    /// different reason:
    ///
    /// **0.30 → 0.42** fixed *where* the dissolve ended. At 0.30 it finished
    /// well clear of the title, so the eye had a band of pure background to
    /// compare against and the cover read as cut off above it rather than
    /// dissolved into it. Ending near the title leaves nothing in between for
    /// the comparison.
    ///
    /// **0.42 → 0.55** widens the blend itself. The end was in the right place
    /// but the band was still narrow enough to read as a region — a stretch of
    /// screen where the picture was visibly *becoming* the background. Over
    /// more than half the artwork's height there is no stretch to point at.
    ///
    /// The cost is real and is the reason this is not simply maximised: every
    /// point of fade is a point of cover that is no longer crisp. At 0.55 the
    /// sharp region is 45% of the artwork's height — on an iPhone 12, 224pt of
    /// the 498 it occupies.
    private static let artworkFadeFraction: Double = 0.55

    /// The dissolve's alpha ramp, eased rather than linear.
    ///
    /// **The shape matters more than the length.** A two-stop gradient is a
    /// straight line in alpha, and a straight line has corners at both ends: the
    /// rate of change jumps from nothing to constant where it starts, and back
    /// to nothing where it finishes. Those two corners are exactly what the eye
    /// picks up as edges — the same first-derivative discontinuity that put the
    /// crease above the title, one layer further in. Lengthening a linear ramp
    /// moves the corners apart; it does not remove them.
    ///
    /// These five stops sample smoothstep, `t² · (3 − 2t)`, whose slope is zero
    /// at both ends. The dissolve now begins and finishes without announcing
    /// either.
    ///
    /// `LinearGradient` interpolates linearly between stops, so each pair is
    /// still a straight segment and what this really builds is a polyline.
    /// Seven points, raised from five when `artworkFadeFraction` went to 0.55:
    /// what has to stay small is the slope change at each joint, and stretching
    /// the same five points over a third more screen makes each segment longer
    /// and every joint sharper. The count follows the span rather than being a
    /// number that was once right.
    private static func dissolveStops(progress: Double) -> [Gradient.Stop] {
        let span = Self.artworkFadeFraction * progress
        let start = 1 - span
        let steps = 6
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            return Gradient.Stop(
                color: .white.opacity(1 - eased),
                location: start + span * t
            )
        }
    }

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
    /// Nine colours from the cover, laid out 3×3, driving the expanded
    /// background. See `ArtworkStore.meshPalette(for:)` and `AmbientMesh`.
    @State private var meshColours: [Color]?

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

    /// The height reserved below the artwork for everything
    /// `NowPlayingContent` stacks there. The artwork gets what is left.
    ///
    /// This is what makes the artwork's size derived from the space available
    /// rather than fixed. A fixed size alone put the title/scrubber/transport
    /// row below the card's own bottom edge in landscape on an iPhone 12 —
    /// `expandedContent` offset the content by a constant that exceeded the
    /// card's full landscape height, so everything below the artwork was
    /// clipped away and the expanded player had no controls at all. See F2.
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
    /// of this used to bind, the region left below the artwork came to exactly
    /// `440 - 40 = 400pt`. It is now that 400pt directly and unconditionally:
    /// `contentOffset(fullSize:)` measures up from the card's bottom, so the
    /// region is the same on every device and no longer depends on the artwork
    /// at all. Against a ~380pt stack that leaves ~20pt. Do not
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
    /// **This no longer bounds the artwork, and that is the change.** The two
    /// regions overlap now: the controls are anchored to the bottom of the card
    /// and the artwork reaches down behind them, dissolved to near-nothing by
    /// the time it gets there. Before, the artwork stopped where this region
    /// began, which is what held it to a square on every phone.
    private static let contentBudget: CGFloat = 440

    /// The gap between where the artwork's frame ends and where the content
    /// starts, back when the two could not overlap. Kept as the amount the
    /// content region is *smaller* than `contentBudget`, so the region below the
    /// controls stays exactly the 400pt every measurement in that doc was taken
    /// against.
    private static let contentInset: CGFloat = 40

    /// How tall the expanded artwork is, as a fraction of the card.
    ///
    /// **Taller than it is wide, which means the cover is cropped left and
    /// right.** That is a deliberate trade, chosen over the alternative:
    /// a square full-bleed cover can only ever reach the card's *width* down the
    /// screen — 46% on an iPhone 12 — and everything below that is background.
    /// Reaching further down the screen requires a taller frame, and
    /// `scaledToFill` pays for extra height by cropping width. At 0.59 a square
    /// cover keeps 78% of its width.
    ///
    /// Not pushed further: at the 0.67 that would put the background in the
    /// bottom third exactly, the cover keeps only 69% — enough to cut a face or
    /// the artist's name off both sides of a typical sleeve.
    private static let artworkHeightFraction: CGFloat = 0.59

    /// The artwork's height. Its width is always the card's full width.
    ///
    /// Clamped so that something of the card is always left below it. The
    /// fraction alone is safe in portrait but not in landscape, where the card
    /// is short and 59% of it can be less than the dissolve needs to work with.
    private static func artworkHeight(fullSize: CGSize) -> CGFloat {
        min(
            fullSize.height * Self.artworkHeightFraction,
            max(fullSize.height - 120, 0)
        )
    }

    /// Where `NowPlayingContent` starts, measured from the card's top.
    ///
    /// **Anchored to the bottom of the card, not to the artwork.** It used to be
    /// `artworkHeight + 40`, which was correct only while the artwork could not
    /// reach the controls; with the two overlapping, that expression would push
    /// the stack off the bottom. Measuring from the bottom also makes the
    /// controls sit in the same place on every track and every device, which the
    /// old form only did by coincidence of the artwork being square.
    ///
    /// Allowed to go negative on a card shorter than the content region — see
    /// `contentBudget`'s note on landscape. The offset consumes the signed
    /// value, which is what keeps a short screen reserving its full region
    /// rather than being pushed down and clipped.
    private static func contentOffset(fullSize: CGSize) -> CGFloat {
        fullSize.height - (Self.contentBudget - Self.contentInset)
    }

    /// What has to change for the card to reload its artwork.
    ///
    /// **The path, not only the track ID.** Keyed on the ID alone — which is
    /// what this was — the card kept whatever picture it had loaded when the
    /// track started, because a `Track`'s `id` does not change when its cover
    /// does. Changing a cover from the list updated the row (`ArtworkThumbnail`
    /// keys on the path) and left the mini pill and the expanded player showing
    /// the old one, for as long as that track stayed loaded.
    ///
    /// Same class of bug as the one `LibraryService.setArtwork`'s fresh-filename
    /// rule exists to prevent, in the one place that rule could not reach: the
    /// card has its own copy of the image, so a new path on disk means nothing
    /// until something tells the card to go and read it.
    private struct ArtworkIdentity: Equatable {
        let trackID: UUID?
        let artworkPath: String?
    }

    private var artworkIdentity: ArtworkIdentity {
        ArtworkIdentity(
            trackID: playback.currentTrack?.id,
            artworkPath: playback.currentTrack?.artworkRelativePath
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
                .task(id: artworkIdentity) {
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
        // Picking a track from a list opens the full player.
        //
        // Keyed on `explicitSelections`, NOT on `currentTrack` changing. The
        // track changes for reasons the user did not ask for and must not be
        // interrupted by: auto-advance when one finishes, Next from the lock
        // screen, a skip past a file that failed to load. Yanking the screen
        // open on any of those would be hostile — the phone is in a pocket for
        // most of them. `explicitSelections` counts only the one gesture that
        // means "show me this": a row tapped in a list.
        //
        // No `guard progress < 1`: `expand()` from an already-expanded card
        // animates 1 to 1, which is a no-op the spring resolves on its first
        // frame. Adding the guard would only skip work that costs nothing, and
        // would be one more branch to get wrong.
        .onChange(of: playback.explicitSelections) { _, _ in
            expand()
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
        // Note this is deliberately NOT what `artworkHeight` below is given —
        // see the comment there.
        let cardSize = CGSize(width: cardWidth, height: fullHeight)
        // `fullSize`, never `cardSize`: this is the artwork's *expanded*
        // target side, which must not vary with `progress`. Feeding it the
        // interpolating `cardWidth` would make the artwork pulse through the
        // morph, and `loadArtwork` computes its decode target by calling
        // `artworkHeight(fullSize:)` from its own geometry — the two must
        // agree or the decoded image no longer matches what is drawn.
        let artworkHeight = Self.artworkHeight(fullSize: fullSize)
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
            expandedContent(size: cardSize)
            artworkView(size: cardSize, artworkHeight: artworkHeight)
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
        .gesture(drag(travel: dragTravel, threshold: Self.dragThreshold(progress: progress)))
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
            // The cover's own colours as a slowly drifting mesh.
            //
            // This replaced a flat `tintColour` held down the card and blended
            // away below the artwork, and that is what removed the crease above
            // the title. The crease was never a colour mismatch — both sides of
            // the artwork's bottom edge were the same colour. It was a mismatch
            // in *slope*: above the edge the colour was constant, and below it
            // the gradient started moving immediately. The eye reads a
            // discontinuity in the first derivative as a line (a Mach band),
            // and no amount of matching the colours themselves removes it. A
            // field that varies continuously through the seam has no slope to
            // break.
            //
            // Gated on `progress` rather than merely faded by it: `AmbientMesh`
            // drives a `TimelineView`, which would otherwise keep redrawing the
            // whole card thirty times a second behind a collapsed pill nobody
            // is looking at.
            if let meshColours, progress > 0 {
                AmbientMesh(colours: meshColours)
                    .opacity(progress)
            } else if meshColours == nil {
                // No cover to take colours from, so there is nothing to be
                // continuous *with* and the flat gradient is right here.
                LinearGradient(
                    colors: [tintColour, Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(progress)
            }
            // Darkens everything below the artwork so the controls stay
            // readable.
            //
            // Needed now that the background is the cover rather than a colour
            // this view chose: a pale cover would otherwise put white text — the
            // card forces dark styling, see `PlayerChromeScheme` — on a pale
            // field. The first build anchored this at `.center`, which measured
            // wrong: the title sits *above* the card's midpoint, so it got no
            // darkening at all and sat white on bright green.
            //
            // Starts at 0.42 — just above where the artwork ends on a phone in
            // portrait — so the ramp is already underway by the time the title
            // arrives. Beginning it inside the artwork rather than at its edge
            // is deliberate: a ramp that starts exactly where the artwork stops
            // puts a slope change at the same line the mask is dissolving, and
            // that is how the crease got there in the first place. Up here the
            // alpha is still near zero, so the change of slope has nothing to
            // show.
            // Three stops, because two were not enough where it mattered. A
            // straight ramp from 0.42 to 0.5 black at the bottom is still under
            // 8% black at 0.50, which is where the title sits — measured off a
            // screenshot, the title looked no different with the ramp than
            // without it. The middle stop front-loads the darkening so the
            // controls get most of it, and the tail keeps going for the volume
            // and repeat rows below.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.38),
                    .init(color: .black.opacity(0.35), location: 0.56),
                    .init(color: .black.opacity(0.6), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)
        }
    }

    /// The artwork's average colour, or the plain background when there is no
    /// artwork to take one from.
    ///
    /// Only reached when there is no cover at all; with one, the background is
    /// the blurred cover itself and no averaged colour is involved.
    private var tintColour: Color {
        tint ?? Color(.systemGroupedBackground)
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

    private func expandedContent(size: CGSize) -> some View {
        NowPlayingContent(playback: playback)
            .padding(.horizontal, 24)
            .frame(width: size.width)
            // Measured from the card's bottom, not from the artwork — see
            // `contentOffset(fullSize:)`. The artwork reaches down behind this,
            // dissolved to almost nothing by the time it arrives.
            .offset(y: Self.contentOffset(fullSize: size))
            .opacity(max(0, (progress - 0.5) * 2))
            .allowsHitTesting(progress > 0.9)
    }

    private func artworkView(size: CGSize, artworkHeight: CGFloat) -> some View {
        // Width and height interpolate separately now that the expanded artwork
        // is not square. Collapsed it still is: both start at
        // `collapsedArtwork`, so the pill's thumbnail is unchanged and only the
        // destination differs.
        let width = Self.collapsedArtwork
            + (size.width - Self.collapsedArtwork) * progress
        let height = Self.collapsedArtwork
            + (artworkHeight - Self.collapsedArtwork) * progress
        let collapsedCentre = CGPoint(
            x: Self.collapsedArtworkInset + Self.collapsedArtwork / 2,
            y: Self.collapsedHeight / 2
        )
        // Flush with the card's top edge: the artwork's centre sits exactly
        // half its own height down, with no safe-area term. The status bar is
        // drawn over it, in white — see `PlayerChromeScheme`, which forces the
        // whole window dark while the card is open.
        let expandedCentre = CGPoint(
            x: size.width / 2,
            y: artworkHeight / 2
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
                    // interpolating. Render it at a fixed base size and use
                    // `.scaleEffect`, which does animate, to track `side`
                    // continuously. Ratio matches ArtworkThumbnail's
                    // placeholder (size * 0.5). See F6.
                    Image(systemName: "music.note")
                        .font(.system(size: Self.placeholderGlyphBase * 0.5))
                        .foregroundStyle(.secondary)
                        .scaleEffect(min(width, height) / Self.placeholderGlyphBase)
                }
            }
        }
        .frame(width: width, height: height)
        // Dissolves the artwork's bottom edge into the background colour
        // beneath it as the card opens.
        //
        // An overlay, deliberately, and not a `.mask`. A mask forces an
        // offscreen pass over this view every frame, and this is the one view
        // in the card that moves *and* resizes on every frame of a drag — the
        // same reason its shadow had to stop being interpolated. Painting the
        // background's own colour on top costs nothing and is
        // indistinguishable, because the colour is the same on both sides of
        // the seam: `background` holds `tintColour` flat down to
        // `backgroundTintHold`, which is below where the artwork ends.
        //
        // A mask, so the artwork genuinely becomes transparent at its bottom
        // and the drifting colour field behind it shows through.
        //
        // This was an overlay painting flat `tintColour`, chosen because an
        // overlay costs nothing while a mask forces an offscreen pass. That
        // reasoning held only while the thing underneath was a single colour a
        // vertical gradient could reproduce. The mesh behind it varies
        // horizontally as well, and no vertical gradient can match it — an
        // overlay would paint a uniform band across a field that is not
        // uniform, and put back a visible edge on the other side of the seam.
        //
        // The cost is real and accepted: one offscreen pass over the artwork
        // per frame during the drag. It buys the only thing that removes the
        // crease. If it ever measures badly, the answer is to stop compositing
        // this per frame — not to go back to painting over it.
        //
        // Every stop collapses to location 1 at progress 0, making the whole
        // mask opaque white — so the collapsed pill's thumbnail is untouched,
        // with no view inserted or removed mid-morph to pop.
        .mask(
            LinearGradient(
                stops: Self.dissolveStops(progress: progress),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Interpolates to a square corner as it opens: the expanded artwork is
        // full-bleed, and a rounded corner floating against the screen's own
        // rounded corner reads as a mistake. The card's `clipShape` supplies
        // the top corners at that point.
        .clipShape(RoundedRectangle(cornerRadius: width * 0.12 * (1 - progress)))
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

    /// The finger's speed at release, in the units
    /// `BottomBarStyle.settle(initialVelocity:)` wants.
    ///
    /// Three conversions, and each one is a place this could be silently wrong:
    ///
    ///   1. **Sign.** `value.velocity.height` is positive downward, while
    ///      `progress` grows as the card is dragged *up*. Miss the negation and
    ///      every flick hands the spring a velocity pointing away from where the
    ///      card is going, which reads as the card being knocked backwards
    ///      before it recovers.
    ///   2. **Points to progress.** Dividing by `travel` turns points per second
    ///      into progress per second, the same conversion `onChanged` makes for
    ///      the position.
    ///   3. **Progress to remaining.** SwiftUI wants the velocity relative to
    ///      the distance the animation still has to cover, not to the whole
    ///      range — so it is divided again by what is left.
    ///
    /// Zero when there is nothing left to travel: dividing by that remainder is
    /// undefined, and a spring with no distance to cover has no use for a speed.
    ///
    /// Takes the bare number rather than the `DragGesture.Value` it comes from.
    /// That type has no public initialiser, so a function that took one could
    /// not be tested at all — and the three conversions below are exactly the
    /// kind that stay silently wrong.
    ///
    /// - Parameter verticalVelocity: points per second, positive downward, as
    ///   `DragGesture.Value.velocity.height` reports it.
    static func settleVelocity(
        verticalVelocity: CGFloat,
        travel: CGFloat,
        from current: Double,
        to target: Double
    ) -> Double {
        let remaining = target - current
        guard abs(remaining) > 0.0001, travel > 0 else { return 0 }
        let progressPerSecond = Double(-verticalVelocity / travel)
        let relative = progressPerSecond / remaining
        return min(max(relative, -BottomBarStyle.maxSettleVelocity), BottomBarStyle.maxSettleVelocity)
    }

    /// How far the finger must move before the card starts following it.
    ///
    /// **Near zero once the card is open, because there is nothing left to
    /// disambiguate.** A threshold exists to stop a tap being read as a drag,
    /// and the tap it protects — `onTapGesture`, which expands — is guarded on
    /// `progress < 0.5` and does nothing at all while the card is open. Paying
    /// for that protection when it cannot fire is what put a dead zone at the
    /// start of every downward swipe.
    ///
    /// Not literally zero: at zero this gesture recognises on touch-down and
    /// competes with the controls inside the expanded card for the same touch.
    /// Two points is below the threshold of a deliberate movement and above the
    /// jitter of a stationary finger.
    static func dragThreshold(progress: Double) -> CGFloat {
        progress > 0.5 ? 2 : 10
    }

    /// The finger's travel with the recognition threshold taken back out.
    ///
    /// `DragGesture.Value.translation` is measured from **touch-down**, not from
    /// the moment the gesture recognised — so the very first `onChanged` already
    /// carries the whole threshold, and assigning it straight across makes the
    /// card jump that far in a single frame. Ten points of jump after ten points
    /// of nothing is the stutter at the start of a swipe: the dead zone and the
    /// catch-up are one defect with two halves.
    ///
    /// Subtracting leaves the card trailing the finger by the threshold forever
    /// after, which at two points is not visible and is the right trade: a
    /// constant offset nobody can see, against a discontinuity everybody can.
    ///
    /// Clamped to the movement's own magnitude rather than subtracted blindly.
    /// `minimumDistance` measures distance in two dimensions, so a finger that
    /// moved mostly sideways can recognise with a vertical component smaller
    /// than the threshold — and a blind subtraction would flip its sign and send
    /// the card the wrong way.
    static func dragOffset(translationHeight: CGFloat, threshold: CGFloat) -> CGFloat {
        if translationHeight > 0 { return max(0, translationHeight - threshold) }
        if translationHeight < 0 { return min(0, translationHeight + threshold) }
        return 0
    }

    private func drag(travel: CGFloat, threshold: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: threshold)
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
                dragDelta = -Self.dragOffset(
                    translationHeight: value.translation.height,
                    threshold: threshold
                ) / travel
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
                // Compensated the same way as the live position above, so the
                // decision is taken in the same coordinates the card was moving
                // in rather than ones a threshold apart.
                let predicted = settled - Self.dragOffset(
                    translationHeight: value.predictedEndTranslation.height,
                    threshold: threshold
                ) / travel
                let target: Double = predicted > 0.5 ? 1 : 0
                withAnimation(
                    BottomBarStyle.settle(
                        initialVelocity: Self.settleVelocity(
                            verticalVelocity: value.velocity.height,
                            travel: travel,
                            from: progress,
                            to: target
                        )
                    )
                ) {
                    settled = target
                    dragDelta = 0
                    expansion.progress = target
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
        let artworkHeight = Self.artworkHeight(fullSize: fullSize)

        let path = playback.currentTrack?.artworkRelativePath
        async let image = ArtworkStore.image(
            for: path,
            maxPixel: max(fullSize.width, artworkHeight) * UIScreen.main.scale
        )
        async let colour = ArtworkStore.dominantColor(for: path)
        // Concurrently with the other two, not after them: all three read the
        // same cached decode chain, and the palette is the cheapest of the
        // three by a wide margin — a 48px decode and a nine-pixel draw.
        async let palette = ArtworkStore.meshPalette(for: path)
        let (loadedImage, loadedColour, loadedPalette) = await (image, colour, palette)

        guard playback.currentTrack?.artworkRelativePath == path else { return }
        artwork = loadedImage
        tint = loadedColour
        meshColours = loadedPalette
    }
}
