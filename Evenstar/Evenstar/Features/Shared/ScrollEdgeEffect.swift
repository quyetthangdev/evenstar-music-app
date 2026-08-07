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
/// implementation — a dark gradient laid over the bottom of the screen. A
/// material is what blurs and de-emphasises what is behind it without adding a
/// colour of its own, so the band is a material, and the gradient is a **mask**
/// on it rather than a fill.
enum ScrollEdgeEffect {

    /// How far above the bar the blur ramps in, in points.
    ///
    /// The band below this is at full strength; this is only the run-out. Too
    /// short and the top of the effect is a visible horizontal line across the
    /// screen; too long and half the list is permanently hazy.
    ///
    /// **56, up from 28.** At 28 the blur reached full strength on the bar's
    /// own top edge and fell to nothing 28pt later — measured by differencing
    /// two screenshots, the whole visible transition happened between 84 and
    /// 110pt above the screen bottom. That is a quarter of the band doing all
    /// the work, and it read as an edge rather than as a fade. Doubling it
    /// spreads the same change over twice the distance, so at any given height
    /// the effect is weaker and the eye has nothing to catch on.
    ///
    /// It stays a run-out rather than taking over: the full-strength region
    /// below is 84pt, still taller than this.
    static let fade: CGFloat = 56

    /// Total height of the band, measured from the **physical bottom of the
    /// screen** — the same origin `BottomBarMetrics` measures the bar from,
    /// which is why the view below has to ignore the bottom safe area.
    ///
    /// It covers whatever the user must be able to read past: the bar always,
    /// and the collapsed player above it whenever a track is loaded. Deriving
    /// it from the same constants as the list clearance is the point — a bar
    /// that grows and a band that does not would leave the pill sitting on
    /// sharp content again.
    static func height(hasTrack: Bool) -> CGFloat {
        let covered = hasTrack
            ? BottomBarMetrics.tabBarTopOffset
                + BottomBarMetrics.playerTabGap
                + PlayerCard.collapsedHeight
            : BottomBarMetrics.tabBarTopOffset
        return covered + fade
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
            return Gradient.Stop(color: .black.opacity(smooth), location: t * span)
        }
        // The remainder of the band is solid. Without this the mask would stop
        // at `span` and everything below it would be undefined by the stop
        // list; SwiftUI extends the last stop, but stating it keeps the mask
        // readable and makes `span == 1` behave the same as any other value.
        stops.append(Gradient.Stop(color: .black, location: 1))
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
                        fadeFraction: ScrollEdgeEffect.fade / height
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
