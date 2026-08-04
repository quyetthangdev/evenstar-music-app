import SwiftUI

/// The circular bloom under a transport button when it is pressed.
///
/// Split out from the arrow's slide because not every transport control has a
/// direction: play/pause toggles in place, so it takes the halo and nothing
/// else, while Previous and Next take both.
private struct TapHalo: ViewModifier {
    /// Changing this fires it. A counter rather than a `Bool` so a second press
    /// during the first retriggers instead of being swallowed.
    let trigger: Int

    private struct Pulse {
        var opacity: Double = 0
        var scale: Double = 0.5
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Pulse(), trigger: trigger) { view, pulse in
            view.background {
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .scaleEffect(pulse.scale)
                    .opacity(pulse.opacity)
            }
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.08)
                LinearKeyframe(1, duration: 0.14)
                LinearKeyframe(0, duration: 0.30)
            }
            // Eased open, not sprung. A spring makes the circle overshoot its
            // size and rebound, which on a plain disc reads as a wobble rather
            // than as elasticity — there is no shape for the eye to read the
            // bounce against. It just grows and fades.
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.0, duration: 0.22)
                LinearKeyframe(1.0, duration: 0.30)
            }
        }
    }
}

extension View {
    /// Acknowledges a press with a bloom, for a control that does not travel.
    func tapHalo(trigger: Int) -> some View {
        modifier(TapHalo(trigger: trigger))
    }
}

/// A transport arrow that hands over to a fresh copy of itself when tapped.
///
/// Deliberately no halo of its own: `TransportButtonStyle` adds one outside its
/// own squash-and-stretch, where it stays a circle. Applied here it would sit
/// inside that transform and be drawn as an ellipse.
///
/// Two glyphs, not one, and they take turns rather than crossing. The copy you
/// pressed leaves first — travelling the way its own arrow points and fading —
/// and only once it is nearly gone does a fresh copy set off from the far edge,
/// fading up and springing into place.
///
/// This replaced a single glyph that slid out and wrapped around via a
/// `MoveKeyframe`. A wrap has to teleport — keyframes interpolate, so the jump
/// from one edge to the other cannot be animated — and a teleport is visible if
/// the glyph has not fully cleared the clip by the time it happens. Two copies
/// have no discontinuity to hide: at every instant both are simply somewhere,
/// and the handover reads as one arrow replacing another rather than one arrow
/// jumping.
///
/// It also removes the constraint that made the old version fragile. The wrap
/// needed `travel` large enough to put the glyph *entirely* outside the clip
/// before the jump — measured per call site, and wrong by 8pt on the first
/// attempt. Here the outgoing copy is already transparent by the time it would
/// matter, so `travel` only has to be far enough to read as movement.
struct TransportArrow: View {
    let systemName: String
    let font: Font
    /// The square frame the glyph sits in — also the halo's size and the bounds
    /// the slide is clipped to.
    let side: CGFloat
    let trigger: Int
    /// `1` for a control that moves forward, `-1` for one that moves back, so
    /// the pressed glyph travels the way its own arrow points. Its replacement
    /// then comes in from the opposite edge.
    let direction: CGFloat
    let travel: CGFloat

    /// Both copies move on this, so they accelerate alike rather than one
    /// easing while the other springs. The bounce is what the incoming copy
    /// arrives on; the outgoing one is transparent long before its own
    /// overshoot would show.
    private static let slide = Spring(duration: 0.44, bounce: 0.12)

    /// How long the replacement waits at the edge before setting off.
    ///
    /// Without it the two legs are simultaneous and only opacity separates
    /// them — which does not read as an arrow arriving, because by the time the
    /// incoming copy fades up it has already travelled most of the way and
    /// appears near the middle. Holding it still at the edge is what makes the
    /// eye see it come in from the side.
    private static let handoverDelay = 0.14

    private struct Leg {
        var offset: CGFloat
        var opacity: Double
    }

    var body: some View {
        // Each copy animates on its own `keyframeAnimator` applied to a real
        // `Image`, rather than one animator building both inside its closure.
        //
        // The one-animator version compiled, reserved its layout space, and
        // drew nothing: its base view was an `EmptyView`, chosen because
        // applying the modifier to `self` inside `body` would have made `body`
        // depend on itself. A modifier over `EmptyView` contributes no content
        // no matter what its closure returns. Caught by screenshot, not by the
        // compiler — the build was clean and the tests were green.
        //
        // Sharing `trigger` and `Self.slide` is what keeps the two in step, so
        // splitting them costs nothing: both start on the same press and move
        // on the same curve.
        ZStack {
            // At rest this is the copy you see: offset 0, fully opaque.
            glyph.keyframeAnimator(
                initialValue: Leg(offset: 0, opacity: 1),
                trigger: trigger
            ) { view, leg in
                view.offset(x: leg.offset).opacity(leg.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    SpringKeyframe(direction * travel, duration: 0.44, spring: Self.slide)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.22)
                }
            }

            // At rest this one is invisible, and it ends each run holding the
            // visible position — offset 0, opacity 1. That is what lets the
            // animator snap back to `initialValue` afterwards without anything
            // being seen: the two copies simply trade which is showing, and
            // they are the same glyph.
            glyph.keyframeAnimator(
                initialValue: Leg(offset: 0, opacity: 0),
                trigger: trigger
            ) { view, leg in
                view.offset(x: leg.offset).opacity(leg.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    // Jumps to the far edge while still transparent, so the
                    // jump is unseen, and waits there.
                    MoveKeyframe(-direction * travel)
                    LinearKeyframe(-direction * travel, duration: Self.handoverDelay)
                    SpringKeyframe(0, duration: 0.44, spring: Self.slide)
                }
                KeyframeTrack(\.opacity) {
                    // Stays hidden for exactly as long as it stays still, so it
                    // becomes visible at the edge in the act of setting off
                    // rather than materialising part-way across.
                    LinearKeyframe(0, duration: Self.handoverDelay)
                    LinearKeyframe(1, duration: 0.22)
                }
            }
        }
        .frame(width: side, height: side)
        // So a glyph on its way out disappears at the frame's edge instead of
        // sliding over the control beside it.
        .clipped()
    }

    private var glyph: some View {
        Image(systemName: systemName).font(font)
    }
}
