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

    /// The collapsed bar's own height. `LibraryView` no longer reads this
    /// directly — it reads `collapsedClearance`, which adds the gap below the
    /// floating pill. Do not duplicate this as a literal.
    static let collapsedHeight: CGFloat = 64

    /// How far the collapsed pill is inset from each screen edge.
    private static let pillSideMargin: CGFloat = 12
    /// The gap between the collapsed pill's bottom edge and the safe area.
    private static let collapsedBottomGap: CGFloat = 12
    /// A true pill: half the collapsed height, so the caps are semicircles.
    private static let collapsedCornerRadius: CGFloat = collapsedHeight / 2
    /// What the library must leave clear: the bar plus the gap beneath it.
    static let collapsedClearance: CGFloat = collapsedHeight + collapsedBottomGap

    private static let collapsedArtwork: CGFloat = 40
    /// How far the collapsed artwork sits in from the pill's leading edge.
    ///
    /// Larger than it looks like it needs to be, because the pill's leading
    /// cap is a semicircle and the visible gap is therefore not uniform: at
    /// mid-height the pill's edge is at x = 0, but level with the artwork's
    /// top and bottom edges (y = 12 and y = 52) the curve has already come in
    /// to x ≈ 7. At a 12pt inset that left only ~5pt of daylight at the
    /// artwork's corners while the middle showed a full 12pt, and the eye
    /// judges the tightest point. 20pt puts the tightest point at ~13pt.
    ///
    /// The artwork still clears the cap comfortably: its corner sits 23.3pt
    /// from the cap's centre against a 32pt radius. Room remains to go
    /// further, but not indefinitely — the corner only starts touching the
    /// curve at an inset around 24pt, and past that the artwork clips.
    private static let collapsedArtworkInset: CGFloat = 20
    /// Between the collapsed artwork's trailing edge and the title.
    private static let collapsedArtworkGap: CGFloat = 12
    private static let expandedArtwork: CGFloat = 280
    private static let expandedCornerRadius: CGFloat = 38
    /// Gap between the top safe area and the expanded artwork.
    private static let expandedArtworkTopGap: CGFloat = 72

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

    /// Spring shared by drag release and `collapse()`, including the fade
    /// that now accompanies `collapse()` when the queue ends (F7) so the
    /// card disappears on the same curve it moves on. `expand()` keeps its
    /// own slightly snappier spring.
    private static let settleSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)

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
    /// `380` is a rough allowance for the title, scrubber, transport row and
    /// volume slider below the artwork — a starting point, like the other
    /// constants here, not a measured minimum. It was raised from 350 once
    /// before, when the volume slider was added, but only by the slider's own
    /// 44pt height — the extra `VStack(spacing: 24)` gap that came with a
    /// fourth stack element (+24pt) was forgotten, leaving the allowance 18pt
    /// short and clipping the slider on a two-line title on a 4.7" device.
    /// Adding anything else to that stack means raising this by the new
    /// element's height *plus* the `VStack` spacing, not just the element's
    /// height — that omission is exactly the mistake being corrected here.
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
            fullSize.height - insets.top - Self.expandedArtworkTopGap - 380,
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
        .animation(Self.settleSpring, value: playback.currentTrack == nil)
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
        // The collapsed card is a floating pill inset from both screen edges;
        // the expanded card still spans the display. `sideMargin` is 12 at
        // progress 0 and exactly 0 at progress 1, so `cardWidth == fullWidth`
        // when expanded and every layout inside the card is unchanged there.
        let sideMargin = Self.pillSideMargin * (1 - progress)
        let cardWidth = fullWidth - sideMargin * 2
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
        // `insets.bottom` (F3's safe-area inset) *plus* `collapsedBottomGap`
        // (the floating pill's gap) — so using `travel` there made the card
        // trail the finger by the sum of the two. Both terms must appear
        // here and in that padding, or they drift apart again. See R2.
        let dragTravel = max(
            fullHeight - Self.collapsedHeight - insets.bottom - Self.collapsedBottomGap,
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
        // Lifts the collapsed pill off the list behind it. Colour, radius and
        // offset are deliberately CONSTANT and must not be interpolated with
        // `progress`: this view moves every frame during a drag, and animating
        // a shadow on it forces a fresh offscreen pass per frame. This shadow
        // is the first thing to remove if drag performance regresses. It also
        // needs no fade-out — when expanded the card fills the screen, so the
        // shadow is occluded anyway.
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        // The card is laid out bottom-aligned in a full-screen frame, and
        // hit-testing binds to *that* frame rather than to the card, so the
        // region's size is ours to choose instead of being whatever the card
        // currently measures.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
        // `pillSideMargin` so the 12pt strips beside the pill fall through to
        // the library — without it, tapping near a screen edge expands the
        // player. But the inset must come from this same drag-state gate, NOT
        // from the interpolated `sideMargin`: derived from `progress` it would
        // narrow the region mid-drag and drop the finger sideways, exactly the
        // failure described above in the vertical direction.
        .contentShape(
            BottomHitRegion(
                height: isDragging || progress > 0 ? fullHeight : Self.collapsedHeight,
                horizontalInset: isDragging || progress > 0 ? 0 : Self.pillSideMargin
            )
        )
        .gesture(drag(travel: dragTravel))
        .onTapGesture { if progress < 0.5 { expand() } }
        // At progress 0 this holds the card's bottom at the real safe-area
        // inset plus `collapsedBottomGap`, so the pill floats clear of the
        // safe area and matches where LibraryView's `collapsedClearance`
        // spacer stops the list; at progress 1 it goes to 0 so the expanded
        // card reaches the physical bottom edge. See F3. `dragTravel` above
        // must subtract exactly the same two terms — see the note there.
        //
        // It must stay *outside* the frame and the hit region above. Applied
        // here it shortens the height proposed to that frame, so the frame's
        // bottom edge lands exactly where the card's bottom edge is, and
        // `BottomHitRegion` — which measures up from `rect.maxY` — lines up
        // with the collapsed bar. Moved inside (padding the card itself), the
        // frame would still span the full screen and the collapsed region
        // would sit `insets.bottom` too low, missing the top of the bar.
        .padding(.bottom, (insets.bottom + Self.collapsedBottomGap) * (1 - progress))
    }

    /// The bottom `height` points of whatever it is applied to, inset by
    /// `horizontalInset` on each side.
    ///
    /// Used instead of `Rectangle()` so the hit region's size can be chosen
    /// by state rather than inherited from the card's current size. See the
    /// note at the `.contentShape` call site.
    private struct BottomHitRegion: Shape {
        var height: CGFloat
        var horizontalInset: CGFloat

        func path(in rect: CGRect) -> Path {
            Path(
                CGRect(
                    x: rect.minX + horizontalInset,
                    y: rect.maxY - height,
                    width: rect.width - horizontalInset * 2,
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
            Rectangle()
                .fill(.thinMaterial)
                .opacity(1 - progress)
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
        .shadow(radius: 10 * progress, y: 4 * progress)
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
                withAnimation(Self.settleSpring) {
                    settled = predicted > 0.5 ? 1 : 0
                    dragDelta = 0
                }
            }
    }

    private func expand() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            settled = 1
            dragDelta = 0
        }
    }

    private func collapse() {
        withAnimation(Self.settleSpring) {
            settled = 0
            dragDelta = 0
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
