import SwiftUI

/// Press-and-release physics for a transport button: squeeze while held, then
/// kick in the button's own direction with a squash-and-stretch and spring
/// back.
///
/// A `ButtonStyle` rather than a modifier on the label, because only a button
/// style is handed `configuration.isPressed` — the touch-down and touch-up
/// edges. A `DragGesture(minimumDistance: 0)` can fake them, but it competes
/// with the button's own gesture and swallows the tap on the second press.
///
/// Two motions with different natures, so they are driven differently:
///
/// - The **squeeze** lasts as long as the finger is down, which has no known
///   duration, so it is state — `isPressed` with a fast animation.
/// - The **kick** is a fixed timeline fired at the moment of release, so it is
///   keyframes on the same tap counter the glyph handover already uses.
///
/// They compose by multiplication, which is what makes the seam invisible: at
/// release the squeeze is relaxing 0.88 → 1 while the kick stretches 1 → 1.2,
/// so the product leaves the compressed state and grows into the stretch with
/// no jump between them.
struct TransportButtonStyle: ButtonStyle {
    /// Incremented by the button's action, so the kick fires on release rather
    /// than on touch-down, and a second press during the first retriggers it.
    let trigger: Int
    /// `1` kicks right, `-1` left, `0` not at all — the squeeze and the spring
    /// still apply, which is what a play/pause button wants.
    let direction: CGFloat
    /// How far the kick throws the button, in points.
    var translate: CGFloat = 10

    /// The rebound. Given as mass/stiffness/damping rather than SwiftUI's usual
    /// duration/bounce because those are the terms the behaviour was specified
    /// in, and `Spring` accepts them directly — no conversion to get wrong.
    ///
    /// The damping ratio this works out to is
    /// `12 / (2 * sqrt(200 * 0.8))` ≈ 0.47, comfortably under 1, so it really
    /// does overshoot and settle rather than easing flat into place.
    fileprivate static let rebound = Spring(mass: 0.8, stiffness: 200, damping: 12)

    /// Fast enough to feel like it answers the finger, and used on the way out
    /// as well as in: relaxing instantly instead would put a visible step
    /// between the squeeze and the stretch.
    fileprivate static let squeeze = Animation.easeOut(duration: 0.07)

    fileprivate static let pressedScale: CGFloat = 0.88

    /// How long the kick takes to reach full stretch before the spring takes
    /// over. Short — it is the snap of the release, not a movement in itself.
    fileprivate static let kickDuration = 0.10
    /// Long enough for `rebound` to actually settle: with these constants the
    /// natural frequency is `sqrt(200 / 0.8)` ≈ 15.8 rad/s, which puts settling
    /// at roughly `4 / (0.47 * 15.8)` ≈ 0.54s. Cutting it short would clip the
    /// overshoot the spring was chosen for.
    fileprivate static let reboundDuration = 0.52

    fileprivate struct Kick {
        var offset: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
    }

    func makeBody(configuration: Configuration) -> some View {
        // A nested view, not the style itself, because a `ButtonStyle` is not a
        // `View` and cannot read `@Environment`. It needs to: replacing
        // `.plain` with a custom style silently takes the disabled appearance
        // with it — `.plain` greys a disabled label, a custom style renders it
        // exactly like an enabled one. Next is disabled on the last track and
        // both arrows are disabled with no track loaded, so without this the
        // buttons look tappable when they are not.
        Interaction(
            configuration: configuration,
            trigger: trigger,
            direction: direction,
            translate: translate
        )
    }

    /// Named for what it does, not `Body` — that collides with `ButtonStyle`'s
    /// own `Body` associated type and makes the conformance fail to resolve.
    private struct Interaction: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let trigger: Int
        let direction: CGFloat
        let translate: CGFloat

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .scaleEffect(configuration.isPressed ? TransportButtonStyle.pressedScale : 1)
                .animation(TransportButtonStyle.squeeze, value: configuration.isPressed)
                .keyframeAnimator(initialValue: Kick(), trigger: trigger) { view, kick in
                    view
                        .scaleEffect(x: kick.scaleX, y: kick.scaleY)
                        .offset(x: kick.offset)
                } keyframes: { _ in
                    KeyframeTrack(\.offset) {
                        CubicKeyframe(direction * translate, duration: TransportButtonStyle.kickDuration)
                        SpringKeyframe(0, duration: TransportButtonStyle.reboundDuration, spring: TransportButtonStyle.rebound)
                    }
                    // Stretch along the travel and squash across it, conserving
                    // roughly the area the glyph occupied, which is what reads
                    // as one object being flung rather than two unrelated
                    // scalings.
                    KeyframeTrack(\.scaleX) {
                        CubicKeyframe(1.2, duration: TransportButtonStyle.kickDuration)
                        SpringKeyframe(1, duration: TransportButtonStyle.reboundDuration, spring: TransportButtonStyle.rebound)
                    }
                    KeyframeTrack(\.scaleY) {
                        CubicKeyframe(0.85, duration: TransportButtonStyle.kickDuration)
                        SpringKeyframe(1, duration: TransportButtonStyle.reboundDuration, spring: TransportButtonStyle.rebound)
                    }
                }
                // Fires on the same counter, so the tap lands in the hand at
                // the same moment it lands in the eye. `.sensoryFeedback`
                // rather than a `UIImpactFeedbackGenerator`: SwiftUI owns the
                // generator's lifetime, and it respects the system's haptics
                // settings.
                .sensoryFeedback(.impact(weight: .light), trigger: trigger)
        }
    }
}
