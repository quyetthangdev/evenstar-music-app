import SwiftUI

/// The blurred band that separates scrolling content from the floating bottom
/// bar — iOS 26 calls this a **scroll edge effect**, and this is a hand-rolled
/// one.
///
/// Hand-rolled rather than `scrollEdgeEffectStyle(_:for:)`, and **not** because
/// of the deployment target. The API is iOS 26 only, but the app builds against
/// the iOS 26 SDK, so a `#available` branch could call it. It was tried on the
/// iOS 26 simulator, both as the documented default ("a scroll view renders an
/// automatic edge effect") and forced to `.soft`: the screenshots were
/// identical to having no modifier at all — list separators ran sharp straight
/// under the bar and out the other side.
///
/// The reason is that a scroll edge effect anchors to a **system** bar, and
/// every screen here hides that bar with `.toolbar(.hidden, for: .tabBar)` and
/// draws its own. The clear `safeAreaInset` those screens add is spacing, not a
/// bar, so there is nothing for the system to draw an effect against. The HIG
/// says as much directly, on Scroll views: *"If you use custom bars, you might
/// want to add this effect manually."*
///
/// So this is not a fallback for old systems. It is the only version, on every
/// system, and raising the deployment target would not remove the need for it —
/// only replacing the custom bar with the system one would.
///
/// **What it must be, per the HIG:** *"Scroll edge effects further enhance
/// legibility by blurring and reducing the opacity of background content"*, and
/// *"They don't block or darken like overlays."* That rules out the obvious
/// implementation — a dark gradient laid over the bottom of the screen. So the
/// band is a material and the gradient is a **mask** on it rather than a fill.
///
/// **A material is not free of that objection either, which measurement showed
/// and this comment used to deny.** It claimed a material "blurs and
/// de-emphasises what is behind it without adding a colour of its own". It
/// does add one: sampled against a plain region of the list, the band at full
/// strength darkened it by 10/255 on every channel. Worse, that is *all* it
/// did there — blurring a uniform area changes nothing, so on the plain
/// stretches of a list the effect was pure darkening. Hence `peak`.
enum ScrollEdgeEffect {

    /// How far above the chrome the blur ramps in.
    ///
    /// **Proportional to what it runs out from, not a constant.** It was 28,
    /// then 56, then a flat 120pt — and 120 was measurably right above the bar
    /// while being wrong to look at with nothing playing. That is not a
    /// contradiction: with a track loaded the chrome is a pill above a bar and
    /// the run-out was half the band; with nothing playing the chrome is just
    /// the bar, the same 120pt became **68%** of the band, and a band that is
    /// two-thirds ramp reads as a haze over the bottom of the screen rather than
    /// as an edge effect.
    ///
    /// Equal to `solidHeight` makes the band exactly twice the chrome's midline
    /// in both cases, so it stays in proportion to the thing it is protecting
    /// instead of being a number that happens to suit one of them:
    ///
    ///     nothing playing   57 + 57  = 114pt   (was 177)
    ///     a track loaded   119 + 119 = 238pt   (was 239 — unchanged)
    ///
    /// Which is what was asked for: the case that looked too tall shrinks by a
    /// third, and the case that did not is left alone.
    static func fade(hasTrack: Bool) -> CGFloat { solidHeight(hasTrack: hasTrack) }

    /// The strongest the material is ever allowed to be, as a fraction.
    ///
    /// **Not 1, and the reason is measurable.** Sampling a plain region of the
    /// list with and without the band put the difference at exactly −10/255 on
    /// each channel — a neutral 4% darkening, no hue shift.
    ///
    /// That number is entirely tint. `.ultraThinMaterial` is a blur *and* a
    /// translucent wash, and over a uniform area the blur contributes nothing
    /// at all: blurring white gives white. So across the large plain stretches
    /// of a list the band was doing no work and only darkening — which is the
    /// one thing the HIG rules out for this effect: "they don't block or darken
    /// like overlays".
    ///
    /// Capping it trades blur strength for invisibility. **0.55 traded away too
    /// much** — with the midline anchor it left the band taking 2% of edge
    /// sharpness above the bar, which is nothing, while still tinting. A knob
    /// set where the effect does no work but still costs something is set
    /// wrong.
    ///
    /// 0.75 with a 120pt run-out is the measured compromise: worst-case tint
    /// −8/255 instead of −10, reached over twice the distance, and the blur
    /// above the bar back to taking out 12% of edge sharpness instead of 2%.
    ///
    /// A tint-free progressive backdrop blur would be better than any value of
    /// this. SwiftUI has no such primitive: every material and every
    /// `UIBlurEffect` style carries a wash, and the alternative — rendering the
    /// list a second time through `.blur` and masking that — doubles the row
    /// rendering and the SwiftData observation for one visual effect.
    static let peak: CGFloat = 0.75

    /// Where the run-out begins, measured from the **physical bottom of the
    /// screen** — the same origin `BottomBarMetrics` measures the bar from,
    /// which is why the view below has to correct for the safe area.
    ///
    /// **The midline of the topmost thing the bar draws, not its top edge.**
    ///
    /// Anchored at the top edge, the material was still at full strength on the
    /// exact line where the bar ends, so the step from "blurred" to "not" was
    /// the first thing visible above the bar and no amount of lengthening the
    /// run-out moved it. Starting the ramp halfway up the bar puts most of it
    /// *behind* the bar, which is opaque enough to hide it: by the time the
    /// band emerges past the top edge it is already about halfway down, and
    /// what is left is the gentlest part of the curve.
    ///
    /// With a track loaded the topmost element is the collapsed pill rather
    /// than the bar, so the same rule points at the pill's midline.
    static func solidHeight(hasTrack: Bool) -> CGFloat {
        hasTrack
            ? BottomBarMetrics.tabBarTopOffset
                + BottomBarMetrics.playerTabGap
                + PlayerCard.collapsedHeight / 2
            : BottomBarMetrics.screenBottomInset
                + BottomBarMetrics.tabBarHeight / 2
    }

    /// Total height of the band: everything at full strength, plus the run-out
    /// above it.
    ///
    /// Deriving it from the same constants as the list clearance is the point —
    /// a bar that grows and a band that does not would leave the pill sitting
    /// on sharp content again.
    static func height(hasTrack: Bool) -> CGFloat {
        solidHeight(hasTrack: hasTrack) + fade(hasTrack: hasTrack)
    }

    /// The mask's stops, from the top of the band downward: transparent at the
    /// very top, opaque from the end of the fade to the bottom.
    ///
    /// **Smootherstep, not a straight ramp and not smoothstep.** A linear
    /// gradient reaches full opacity with its slope unchanged, and a
    /// discontinuity in the *first derivative* of a gradient reads as a line
    /// even when the two sides match exactly — the same Mach band that had to
    /// be designed out of the expanded player's artwork fade.
    ///
    /// Smoothstep (`3t² − 2t³`) flattens the first derivative at both ends and
    /// was the first version here. It still read as slightly abrupt, because it
    /// leaves the *second* derivative jumping at each end — the rate of change
    /// changes suddenly even though the value does not. `6t⁵ − 15t⁴ + 10t³`
    /// zeroes both, so the ramp leaves nothing and arrives at nothing with no
    /// corner in between.
    ///
    /// - Parameter fadeFraction: how much of the band's height the run-out
    ///   occupies. Clamped to 0...1: a band shorter than the fade would
    ///   otherwise produce locations past the end of the gradient.
    /// - Parameter samples: how many stops approximate the curve. SwiftUI
    ///   interpolates *linearly* between stops, so too few turns the curve back
    ///   into the straight segments it exists to avoid. 12 over a 56pt run-out
    ///   is a stop every few points, well under what the eye resolves.
    static func maskStops(fadeFraction: CGFloat, samples: Int = 12) -> [Gradient.Stop] {
        let span = min(max(fadeFraction, 0), 1)
        var stops = (0...samples).map { index -> Gradient.Stop in
            let t = CGFloat(index) / CGFloat(samples)
            let smooth = t * t * t * (t * (t * 6 - 15) + 10)
            return Gradient.Stop(color: .black.opacity(smooth * peak), location: t * span)
        }
        // The remainder of the band holds whatever the ramp reached. Without
        // this the mask would stop at `span` and everything below it would be
        // undefined by the stop list; SwiftUI extends the last stop, but
        // stating it keeps the mask readable and makes `span == 1` behave the
        // same as any other value.
        //
        // `peak`, not `.black` — this stop is the one that covers the strip
        // beside and below the bar, which is exactly where a full-strength
        // wash was visible as a grey patch against the list.
        stops.append(Gradient.Stop(color: .black.opacity(peak), location: 1))
        return stops
    }
}

/// The band itself.
///
/// `allowsHitTesting(false)` is load-bearing, not caution: this sits over the
/// bottom of every scrolling screen, and the tab bar directly beneath it has
/// only just had its dead zones removed. A band that swallowed taps would
/// reintroduce the same bug one layer up and look nothing like its cause.
struct ScrollEdgeEffectBand: View {
    let hasTrack: Bool

    /// How far the host's bottom edge sits above the physical bottom of the
    /// screen — 34 on a phone with a home indicator, 0 without.
    ///
    /// Needed because `height(hasTrack:)` is measured from the screen while
    /// this band is bottom-aligned inside a list whose own bottom stops at the
    /// safe area. Without correcting for it the whole band rides that much too
    /// high and the strip under the bar stays sharp.
    let bottomSafeAreaInset: CGFloat

    var body: some View {
        let height = ScrollEdgeEffect.height(hasTrack: hasTrack)
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: ScrollEdgeEffect.maskStops(
                        fadeFraction: ScrollEdgeEffect.fade(hasTrack: hasTrack) / height
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: height)
            .allowsHitTesting(false)
            // Negative padding, not `.ignoresSafeArea(edges: .bottom)`.
            //
            // That was the first attempt and it did nothing measurable: this is
            // a leaf inside the list's own overlay, and ignoring a safe area
            // governs how a view insets its *content*, not whether it may draw
            // outside the frame its parent gave it. Differencing two
            // screenshots — one with the band, one without — put the change at
            // exactly zero for the bottom 30pt and non-zero above it, which is
            // the safe area to the point.
            //
            // Negative padding shortens the layout box while letting the view
            // overhang it, so the band's bottom lands on the physical screen
            // edge and its top stays `height` above that — which is where
            // `BottomBarMetrics` measures the bar from in the first place.
            .padding(.bottom, -bottomSafeAreaInset)
    }
}
