import SwiftUI

/// Acknowledges a transport tap: the glyph travels the way its arrow points,
/// wraps around, and springs back into place, over a halo that blooms and
/// fades under it.
///
/// The wrap is the point. A glyph that slides out and slides *back* reads as
/// undo — it went somewhere and returned. Sliding out one side and re-entering
/// from the other reads as advancing, which is what the button did.
///
/// The two halves are one keyframe track with a `MoveKeyframe` between them.
/// Keyframes interpolate, so the jump from one edge to the other cannot be a
/// keyframe of its own — `MoveKeyframe` sets the value without animating
/// through it, which is exactly the discontinuity a wrap needs and the reason
/// this is not simply two springs in sequence.
struct TransportTapEffect: ViewModifier {
    /// Changing this fires the effect. A counter rather than a `Bool` so
    /// repeated taps each retrigger it instead of the second one being a
    /// no-op because the value did not change.
    let trigger: Int
    /// Positive slides right, negative slides left. Sized to the glyph, not to
    /// the button, so the travel reads the same on symbols of different widths.
    let direction: CGFloat

    private struct Pulse {
        var offset: CGFloat = 0
        var haloOpacity: Double = 0
        var haloScale: Double = 0.5
    }

    /// How far the glyph travels before wrapping. Roughly a glyph's width —
    /// far enough to clearly leave, close enough that the whole thing is over
    /// before the finger lifts.
    private static let travel: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Pulse(), trigger: trigger) { view, pulse in
                view
                    .offset(x: pulse.offset)
                    // Clipped to the button's own bounds, so the glyph
                    // disappears at the edge instead of sliding over whatever
                    // sits beside it — the title on one side, another control
                    // on the other.
                    .clipped()
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.12))
                            .scaleEffect(pulse.haloScale)
                            .opacity(pulse.haloOpacity)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    // Out, the way the arrow points.
                    CubicKeyframe(direction * Self.travel, duration: 0.13)
                    // The wrap: same distance, opposite side, no interpolation.
                    MoveKeyframe(-direction * Self.travel)
                    // Back to centre with the bounce.
                    SpringKeyframe(0, duration: 0.30, spring: .bouncy)
                }

                KeyframeTrack(\.haloOpacity) {
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.10)
                    LinearKeyframe(0, duration: 0.22)
                }

                KeyframeTrack(\.haloScale) {
                    SpringKeyframe(1.0, duration: 0.16, spring: .bouncy)
                    LinearKeyframe(1.0, duration: 0.22)
                }
            }
    }
}

extension View {
    /// Acknowledges a transport tap. `direction` is `1` for a control that
    /// moves forward and `-1` for one that moves back, so the glyph travels
    /// the way its own arrow points.
    func transportTapEffect(trigger: Int, direction: CGFloat) -> some View {
        modifier(TransportTapEffect(trigger: trigger, direction: direction))
    }
}
