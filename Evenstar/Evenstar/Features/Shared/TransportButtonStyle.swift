import SwiftUI

/// Press-and-release physics for a transport button: squeeze while held, then
/// on release deform, kick, and spring back.
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
/// release the squeeze is relaxing back to 1 while the kick is deforming away
/// from it, so the button leaves the compressed state and grows into the
/// stretch with no step between them.
///
/// Prefer the two named forms — `.transportSkip` and `.transportToggle` — over
/// building one by hand. They are the difference between a button that goes
/// somewhere and one that does not, and that difference is not just a zero
/// distance: see `transportToggle`.
struct TransportButtonStyle: ButtonStyle {
    /// Incremented by the button's action, so the kick fires on release rather
    /// than on touch-down, and a second press during the first retriggers it.
    let trigger: Int
    /// `1` kicks right, `-1` left, `0` not at all.
    let direction: CGFloat
    /// How far the kick throws the button, in points.
    let translate: CGFloat
    /// Deformation at the peak of the kick. Unequal for a button that travels
    /// and equal for one that does not — see `transportToggle`.
    let stretchX: CGFloat
    let stretchY: CGFloat

    /// The rebound.
    ///
    /// Given as mass/stiffness/damping rather than SwiftUI's usual
    /// duration/bounce because those are the terms the behaviour was specified
    /// in, and `Spring` accepts them directly — no conversion to get wrong.
    ///
    /// Slackened from an earlier 0.8 / 200 / 12, which settled in about half a
    /// second with a rebound sharp enough to read as a snap rather than as
    /// weight. Loosening the spring is what slows the motion without making the
    /// button feel late, because the press itself still answers immediately.
    fileprivate static let rebound = Spring(mass: 1.0, stiffness: 140, damping: 13)

    /// Fast enough to feel like it answers the finger, and used on the way out
    /// as well as in: relaxing instantly instead would put a visible step
    /// between the squeeze and the stretch. Deliberately not slowed along with
    /// the rest — it is the part that has to be immediate.
    fileprivate static let squeeze = Animation.easeOut(duration: 0.09)

    fileprivate static let pressedScale: CGFloat = 0.92

    /// How long the kick takes to reach full deformation before the spring
    /// takes over. Short — it is the snap of the release, not a movement in
    /// itself.
    fileprivate static let kickDuration = 0.14
    /// Long enough for `rebound` to actually settle: with these constants the
    /// natural frequency is `sqrt(140)` ≈ 11.8 rad/s and the damping ratio
    /// `13 / (2 * sqrt(140))` ≈ 0.55, which puts settling at roughly
    /// `4 / (0.55 * 11.8)` ≈ 0.62s. Cutting it short would clip the overshoot
    /// the spring was chosen for.
    fileprivate static let reboundDuration = 0.62

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
        // every transport button is disabled with no track loaded, so without
        // this they look tappable when they are not.
        Interaction(
            configuration: configuration,
            trigger: trigger,
            direction: direction,
            translate: translate,
            stretchX: stretchX,
            stretchY: stretchY
        )
    }

    /// Named for what it does, not `Body` — that collides with `ButtonStyle`'s
    /// own `Body` associated type and makes the conformance fail to resolve.
    private struct Interaction: View {
        @Environment(\.isEnabled) private var isEnabled
        /// Counts touch-*downs*, where `trigger` counts completed taps.
        ///
        /// A `Button`'s action runs on touch-**up**, so everything keyed on
        /// `trigger` — the kick, the halo, the haptic — used to arrive only when
        /// the finger left. On a quick tap that is nearly the same instant; on a
        /// press held even briefly it is not, and the button read as answering
        /// late. The squeeze was the only thing that ever met the finger, and a
        /// 0.92 scale on a glyph is not much of an answer.
        @State private var presses = 0
        let configuration: Configuration
        let trigger: Int
        let direction: CGFloat
        let translate: CGFloat
        let stretchX: CGFloat
        let stretchY: CGFloat

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
                    KeyframeTrack(\.scaleX) {
                        CubicKeyframe(stretchX, duration: TransportButtonStyle.kickDuration)
                        SpringKeyframe(1, duration: TransportButtonStyle.reboundDuration, spring: TransportButtonStyle.rebound)
                    }
                    KeyframeTrack(\.scaleY) {
                        CubicKeyframe(stretchY, duration: TransportButtonStyle.kickDuration)
                        SpringKeyframe(1, duration: TransportButtonStyle.reboundDuration, spring: TransportButtonStyle.rebound)
                    }
                }
                // Outside the kick, deliberately. Inside it, the deformation
                // would scale the disc unevenly and draw it as an ellipse, and
                // the throw would drag it off the point that was actually
                // pressed. Out here it stays a circle, centred where the finger
                // was.
                //
                // Keyed on touch-down, not on the completed tap: the halo is the
                // acknowledgement, and an acknowledgement that waits for the
                // finger to leave is not one.
                .tapHalo(trigger: presses)
                // Same counter as the halo, so the tap lands in the hand at the
                // same moment it lands in the eye — which is now the moment of
                // contact rather than the moment of release. `.sensoryFeedback`
                // rather than a `UIImpactFeedbackGenerator`: SwiftUI owns the
                // generator's lifetime, and it respects the system's haptics
                // settings.
                //
                // A press dragged off the button still gets both, and that is
                // right: the phone was touched, the command was not sent, and
                // the two are separate facts. The kick — the throw that goes
                // with the command — stays on `trigger` and correctly does not
                // fire.
                .sensoryFeedback(.impact(weight: .light), trigger: presses)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { presses += 1 }
                }
        }
    }
}

extension ButtonStyle where Self == TransportButtonStyle {
    /// For a button that moves the queue: Previous and Next.
    ///
    /// It throws itself the way its own arrow points, and stretches along that
    /// travel while squashing across it — roughly conserving the area it
    /// covered, which is what reads as one object being flung rather than two
    /// unrelated scalings.
    ///
    /// - Parameter translate: shorten it where the button is tight against its
    ///   neighbours; the mini player's 32pt Next has less room than the
    ///   expanded player's 44pt one.
    static func transportSkip(
        trigger: Int,
        direction: CGFloat,
        translate: CGFloat = 7
    ) -> Self {
        TransportButtonStyle(
            trigger: trigger,
            direction: direction,
            translate: translate,
            stretchX: 1.12,
            stretchY: 0.92
        )
    }

    /// For a button that acts in place: play/pause.
    ///
    /// Not simply the skip form with the distance set to zero. Squash and
    /// stretch is the deformation of something being *thrown* — it reads as
    /// wind resistance, and it needs a direction of travel to be read against.
    /// On a button that stays put it has none, and an unequal scaling with
    /// nowhere to go just looks like the glyph is being wrung.
    ///
    /// So the deformation here is equal on both axes: a pop rather than a
    /// stretch. It carries the same squeeze, the same rebound spring, and the
    /// same halo and haptic as its neighbours, so the three buttons answer a
    /// press in one language — only the part that describes travel is dropped,
    /// because this one does not travel.
    static func transportToggle(trigger: Int) -> Self {
        TransportButtonStyle(
            trigger: trigger,
            direction: 0,
            translate: 0,
            stretchX: 1.08,
            stretchY: 1.08
        )
    }
}
