import SwiftUI

/// The circular bloom under a transport button when it is pressed.
///
/// Separate from `TransportButtonStyle`, its only caller, because the style has
/// to apply it *outside* its own squash and stretch. Inside, the deformation
/// would scale the disc unevenly and draw it as an ellipse, and the kick would
/// drag it off the point that was actually pressed.
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
    /// Acknowledges a press with a bloom.
    func tapHalo(trigger: Int) -> some View {
        modifier(TapHalo(trigger: trigger))
    }
}
