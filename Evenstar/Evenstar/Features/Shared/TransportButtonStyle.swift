import SwiftUI

/// Touch-down physics for a transport button: deform, kick, and spring back,
/// starting the instant the finger lands.
///
/// A `ButtonStyle` rather than a modifier on the label, because only a button
/// style is handed `configuration.isPressed` — which is still what drives the
/// halo and the haptic, even though the motion no longer reads it.
///
/// **One motion, not two.** It used to be a squeeze held for the length of the
/// press and then a kick at release, composing by multiplication. That shape
/// belonged to a button whose command ran on touch-up. These buttons are
/// `TouchDownButton`s now: command, kick, halo and haptic all land together on
/// contact, and the squeeze survived only to cancel the kick out — see the note
/// where it used to be declared for the arithmetic.
///
/// Prefer the two named forms — `.transportSkip` and `.transportToggle` — over
/// building one by hand. They are the difference between a button that goes
/// somewhere and one that does not, and that difference is not just a zero
/// distance: see `transportToggle`.
struct TransportButtonStyle: ButtonStyle {
    /// Incremented by the button's action — which, for every caller, now runs
    /// at touch-down. A second press during the first retriggers the kick.
    let trigger: Int
    /// `1` kicks right, `-1` left, `0` not at all.
    let direction: CGFloat
    /// How far the kick throws the button, in points.
    let translate: CGFloat
    /// Deformation at the peak of the kick. Unequal for a button that travels
    /// and equal for one that does not — see `transportToggle`.
    let stretchX: CGFloat
    let stretchY: CGFloat
    /// Hình của vệt sáng khi chạm — xem `TapHalo.shape`.
    var haloShape: AnyShape = AnyShape(Circle())

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

    /// **The held-press squeeze is gone, and its removal is the point.**
    ///
    /// It existed to acknowledge a press whose command had not run yet: the
    /// action was on touch-*up*, so between contact and release the squeeze was
    /// the only thing answering the finger. Every one of these buttons is now a
    /// `TouchDownButton`, so the command — and the kick that announces it — fire
    /// on contact. The squeeze had nothing left to cover.
    ///
    /// Worse, it cancelled the thing that replaced it. The two scales multiply,
    /// and firing together instead of in sequence left the kick almost
    /// invisible:
    ///
    ///     X: 0.92 × 1.12 = 1.03      (intended: 1.12)
    ///     Y: 0.92 × 0.92 = 0.85
    ///
    /// A 3% stretch is not a response. The button was running its action the
    /// instant it was touched and still reading as slow, because nothing on
    /// screen said so.

    /// How long the kick takes to reach full deformation before the spring
    /// takes over.
    ///
    /// Shortened from 0.14 now that this is the *whole* response rather than
    /// the snap at the end of one. 0.14s is roughly eight frames to peak, which
    /// was fine as a punctuation mark after a press had already been
    /// acknowledged and reads as a ramp when it is the acknowledgement itself.
    /// 0.09 is about five, close enough to the ~0.1s where a response stops
    /// being perceived as a separate event from the touch.
    fileprivate static let kickDuration = 0.09
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
            stretchY: stretchY,
            haloShape: haloShape
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
        let haloShape: AnyShape

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
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
                .tapHalo(trigger: presses, in: haloShape)
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
    /// stretch. It carries the same rebound spring and the same halo and haptic
    /// as its neighbours, so the three buttons answer a press in one language —
    /// only the part that describes travel is dropped, because this one does
    /// not travel.
    /// Cho một viên thuốc: shuffle và repeat trong hàng đợi.
    ///
    /// Giống `transportToggle` về chuyển động, khác đúng một điểm: vệt sáng khi
    /// chạm là **capsule**, không phải hình tròn. Vệt sáng là lời đáp cho cú
    /// chạm, và một lời đáp có hình khác hẳn cái nút vừa bị chạm thì đọc ra
    /// như đang đáp cho thứ khác.
    static func transportPill(trigger: Int) -> Self {
        var style = Self.transportToggle(trigger: trigger)
        style.haloShape = AnyShape(Capsule())
        return style
    }

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
