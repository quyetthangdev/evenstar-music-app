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
    /// Positive slides right, negative slides left.
    let direction: CGFloat
    /// How far the glyph travels before wrapping, in points. See the note on
    /// the extension below for how to derive it — it is a property of the
    /// frame and glyph at each call site, not a constant that can be shared.
    let travel: CGFloat

    private struct Pulse {
        var offset: CGFloat = 0
        var haloOpacity: Double = 0
        var haloScale: Double = 0.5
    }

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
                    CubicKeyframe(direction * travel, duration: 0.13)
                    // The wrap: same distance, opposite side, no interpolation.
                    MoveKeyframe(-direction * travel)
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
    ///
    /// `travel` must put the glyph **entirely outside the clip** before
    /// `MoveKeyframe` fires, or the wrap — the whole point of the effect —
    /// shows as a sliver blinking between the two edges instead of the glyph
    /// leaving one side and re-entering the other. For a glyph centred in a
    /// square frame:
    ///
    ///     travel > frameWidth / 2 + glyphWidth / 2
    ///
    /// Measure `glyphWidth` rather than eyeballing it. `forward.fill` renders
    /// 25.0pt wide at `.body` and 32.3pt at `.title2` (measured via
    /// `UIImage(systemName:withConfiguration:)`), both noticeably wider than
    /// they look. Hence:
    ///
    /// - collapsed (32pt frame, `.body`): 16 + 12.5 = 28.5, so 30.
    /// - expanded (44pt frame, `.title2`): 22 + 16.2 = 38.2, so 40.
    ///
    /// This is a required parameter and deliberately has no default. It was
    /// once a single shared constant of 18 — below the collapsed threshold, so
    /// roughly 8pt of the glyph never left the clip — and no one number can
    /// serve both call sites: 30 leaves the expanded glyph half inside, while
    /// 40 in the collapsed frame parks it out of sight for a third of the
    /// animation, which reads as a blink rather than a wrap. A default would
    /// let the next call site inherit whichever of those was wrong for it,
    /// silently.
    func transportTapEffect(trigger: Int, direction: CGFloat, travel: CGFloat) -> some View {
        modifier(TransportTapEffect(trigger: trigger, direction: direction, travel: travel))
    }
}
