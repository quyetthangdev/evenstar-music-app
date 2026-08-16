import SwiftUI

/// The bloom under a transport button when it is pressed.
///
/// Separate from `TransportButtonStyle`, its only caller, because the style has
/// to apply it *outside* its own squash and stretch. Inside, the deformation
/// would scale the disc unevenly and draw it as an ellipse, and the kick would
/// drag it off the point that was actually pressed.
private struct TapHalo: ViewModifier {
    /// Changing this fires it. A counter rather than a `Bool` so a second press
    /// during the first retriggers instead of being swallowed.
    let trigger: Int

    /// Hình của vệt sáng, và nó phải là hình của **chính cái nút**.
    ///
    /// Mặc định là hình tròn, đúng cho các nút transport vốn là glyph trong
    /// khung vuông. Nhưng viên thuốc shuffle/repeat rộng gấp đôi chiều cao của
    /// nó: một vệt tròn nở ra trong đó hoặc thò ra hai đầu, hoặc không chạm
    /// tới hai đầu — cả hai đều đọc ra như vệt sáng thuộc về một nút khác.
    let shape: AnyShape

    private struct Pulse {
        var opacity: Double = 0
        var scale: Double = 0.5
    }

    /// **Off entirely when Reduce Motion is on, and this is the one place in
    /// the bottom-bar work allowed to remove feedback rather than restate it.**
    ///
    /// A disc growing from half size to full and fading out is displacement and
    /// scale together, with nothing underneath it: it carries no information at
    /// all. Every caller already answers the same touch two other ways —
    /// `TransportButtonStyle` and `QueueToggleStyle` each fire
    /// `.sensoryFeedback(.impact)` off the identical `presses` counter, and each
    /// dims its label to `BottomBarStyle.pressedOpacity` on contact. Those are
    /// the only two callers there are (`grep tapHalo`), so switching this off
    /// leaves both a haptic and a visible change behind. That is what makes
    /// deleting it the right answer here and the wrong answer for the tab wash.
    ///
    /// `content` on its own rather than a `keyframeAnimator` whose keyframes are
    /// all zero: the animator would still be built, still be driven by `trigger`
    /// and still composite a fully transparent background on every press. There
    /// is nothing here that a flat branch should keep the shape of.
    @ViewBuilder
    func body(content: Content) -> some View {
        if BottomBarStyle.reduceMotion {
            content
        } else {
            haloed(content)
        }
    }

    private func haloed(_ content: Content) -> some View {
        content.keyframeAnimator(initialValue: Pulse(), trigger: trigger) { view, pulse in
            view.background {
                shape
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
            // Eased open, not sprung. A spring makes the shape overshoot its
            // size and rebound, which on a plain fill reads as a wobble rather
            // than as elasticity — there is no edge for the eye to read the
            // bounce against. It just grows and fades.
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.0, duration: 0.22)
                LinearKeyframe(1.0, duration: 0.30)
            }
        }
    }
}

extension View {
    /// Acknowledges a press with a bloom, in the shape of the control itself.
    func tapHalo(trigger: Int, in shape: AnyShape = AnyShape(Circle())) -> some View {
        modifier(TapHalo(trigger: trigger, shape: shape))
    }
}
