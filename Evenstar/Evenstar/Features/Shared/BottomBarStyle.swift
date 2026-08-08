import SwiftUI

/// How the floating bottom surfaces look and move.
///
/// The counterpart to `BottomBarMetrics`, which owns *where* they are. Between
/// them: Metrics answers "how big and how far in", Style answers "what it looks
/// like and how it gets there".
///
/// It exists because the pieces down there are separate views that must read as
/// one system. The collapsed player and the tab bar sit on the same screen and,
/// while minimised, on the same row — a shadow on one and none on the other is
/// visible immediately, and two morphs on different springs read as two
/// unrelated things happening at once.
///
/// It also fixes a dependency that pointed the wrong way. The springs used to
/// live on `FloatingTabBar`, so `ScrollMinimise` and `RootView` reached into a
/// *view* to find out how fast to animate. Anything new down here should take
/// its motion from this type, not from whichever view happens to define it.
enum BottomBarStyle {

    // MARK: - Motion

    /// A surface changing shape: the tab pill collapsing to a circle, the
    /// search field growing, the collapsed player sliding into the row.
    ///
    /// Written as `duration`/`bounce` rather than `response`/`dampingFraction`.
    /// The two describe the same family of springs, but this pair names what it
    /// does — `bounce` 0 stops on arrival, higher springs past and returns —
    /// where the older pair inverts that axis, since higher damping means less
    /// bounce.
    ///
    /// The two are not independent: `bounce` is a *proportion* of the duration,
    /// so shortening the spring flattens the same bounce value. Past about 0.4
    /// it wobbles rather than settles, and well before that it starts arriving
    /// hard — a high bounce over a short duration snaps back from its overshoot
    /// instead of easing into place.
    static let morph = Animation.spring(duration: 0.36, bounce: 0.24)

    /// The selected tab's wash travelling to the tab just tapped.
    ///
    /// Deliberately bouncier than `morph`. That one is scenery rearranging
    /// itself and should get out of the way; this is direct feedback for a tap
    /// the user just made, and can afford to be more alive. The extra bounce is
    /// what makes it read as liquid — arriving past the new tab and settling
    /// back — where a calmer curve reads as merely sliding.
    static let selection = Animation.spring(duration: 0.38, bounce: 0.34)

    /// How a tab answers the finger, before anything has moved.
    ///
    /// The same 0.09s ease-out `TransportButtonStyle.squeeze` uses, and for the
    /// reason written there: it is the part that has to be immediate. A tab
    /// carried no press feedback at all — `.buttonStyle(.plain)` draws none —
    /// so the first thing that happened after a tap happened on touch-*up*,
    /// once the wash began to slide. Everything before that was the app
    /// appearing not to have noticed.
    static let press = Animation.easeOut(duration: 0.09)

    /// What a pressed tab shrinks to. Shallower than the transport buttons'
    /// 0.92: those are 44pt circles the thumb lands on squarely, while a tab is
    /// a whole quarter of the bar, and the same ratio on something that wide
    /// reads as the bar itself flinching.
    static let pressedScale: CGFloat = 0.96

    /// Content inside a surface as that surface changes shape: icons and labels
    /// shrinking and fading as the pill closes over them.
    ///
    /// Quicker and calmer than `morph` on purpose. The surface closing around
    /// them is the gesture; the glyphs should feel carried by it rather than
    /// staging a second performance inside it.
    static let content = Animation.spring(duration: 0.34, bounce: 0.20)

    /// A surface settling after the user let go of it, or moving to an end
    /// state they asked for: the player card released mid-drag, collapsing when
    /// the queue empties, expanding on a tap.
    ///
    /// Longer and much calmer than `morph`. That one is a surface rearranging
    /// itself while the user watches; this one finishes a gesture the user was
    /// steering, and overshoot there fights the hand that just let go rather
    /// than decorating it.
    ///
    /// This replaced two springs that claimed to be different and were not:
    /// `response: 0.42, dampingFraction: 0.86` for the settle and
    /// `response: 0.45, dampingFraction: 0.85` for the expand — 0.42/0.14 and
    /// 0.45/0.15 in these units, a difference of three hundredths of a second
    /// and one hundredth of bounce. A comment described the second as
    /// "snappier"; it was in fact the slower of the two.
    static let settle = Animation.spring(duration: 0.42, bounce: 0.14)

    private static let settleDuration: Double = 0.42
    private static let settleBounce: Double = 0.14

    /// `settle`, but starting at the speed the finger was already moving.
    ///
    /// **This is the difference between a surface that was let go of and one
    /// that was told where to be.** A plain spring always starts from rest, so a
    /// violent flick and a gentle release produce animations identical to the
    /// pixel — they differ in where they end up, never in how they get there,
    /// and the moment of release has a visible discontinuity in speed. Handing
    /// the gesture's own velocity to the spring removes that seam, and it is
    /// what every system sheet does.
    ///
    /// `interpolatingSpring` rather than `spring`: only that family accepts an
    /// initial velocity, and it is also velocity-preserving if it is retargeted
    /// mid-flight, which is the right behaviour for a surface the user may grab
    /// again before it has settled.
    ///
    /// - Parameter initialVelocity: in units of the *remaining* distance per
    ///   second — 1 means "would arrive in one second at this speed". The caller
    ///   converts, because only it knows the travel and how far is left.
    static func settle(initialVelocity: Double) -> Animation {
        .interpolatingSpring(
            duration: settleDuration,
            bounce: settleBounce,
            initialVelocity: initialVelocity
        )
    }

    /// The largest initial velocity worth handing to `settle(initialVelocity:)`.
    ///
    /// A hard flick released a few points from its destination divides a large
    /// speed by a nearly-zero remaining distance, and the result is a spring
    /// that shoots far past its target and swings back. The clamp is not a
    /// fudge for that arithmetic — it is the same limit a real sheet has, which
    /// is that past a certain speed the surface simply arrives.
    static let maxSettleVelocity: Double = 18

    /// The collapsed player opening to full screen, and closing again.
    ///
    /// Separate from `settle`, and this distinction is real where the one it
    /// replaced was not. `settle` finishes a drag the user was steering: it
    /// covers whatever is left of the travel, often a fraction of the screen.
    /// This one covers the whole height in a single move — around 750pt on a
    /// phone — and a spring tuned for the short case reads as abrupt over that
    /// distance, arriving before the eye has followed it.
    ///
    /// Longer and calmer accordingly. Not bounce-free: a little overshoot is
    /// what keeps a large move from feeling mechanical, but far less than a
    /// short one can carry.
    static let expand = Animation.spring(duration: 0.52, bounce: 0.12)

    /// How the content behind the player recedes as it opens, the way a sheet
    /// pushes its presenting screen back.
    ///
    /// The scale is small on purpose. iOS's own card presentation moves the
    /// screen behind it by only a few percent; more than that stops reading as
    /// depth and starts reading as the app shrinking.
    static let recedeScale: CGFloat = 0.92
    // A `recedeCornerRadius` stood here, rounding the receding content the way
    // a sheet's backdrop is rounded. It was removed rather than tuned: applying
    // it meant clipping the whole screen to a shape on every frame of a drag,
    // which is a mask and an offscreen pass, and the recede was visibly rough
    // because of it. `recedeScale` above is a transform and costs nothing by
    // comparison.
    //
    // If the corners are wanted back, round a static backdrop behind the
    // content instead of masking the content itself.

    /// A control inside one of these surfaces reacting to touch — the
    /// scrubber swelling under a finger.
    ///
    /// A curve, not a spring: it is a state change on a small element, not a
    /// mass arriving somewhere, and a bounce on a 5pt height change is noise.
    static let control = Animation.easeOut(duration: 0.15)

    // MARK: - Surface

    /// What lifts a floating surface off the content behind it.
    ///
    /// Constant — never interpolated with any progress value. A shadow forces
    /// an offscreen pass, and one whose radius changes per frame forces a fresh
    /// one every frame on a view that is already moving. **If the bar or the
    /// player ever drops frames while animating, this is the first thing to
    /// remove**; nothing else down here draws offscreen.
    ///
    /// The expanded player needs no exception: at full screen it covers
    /// everything, so its shadow is occluded rather than wasted.
    private static let shadowColor = Color.black.opacity(0.15)
    private static let shadowRadius: CGFloat = 10
    private static let shadowOffsetY: CGFloat = 4

    /// Applies the shared shadow. Use this rather than restating the numbers,
    /// so a surface added later cannot land with a slightly different lift.
    static func floatingShadow<V: View>(_ view: V) -> some View {
        view.shadow(color: shadowColor, radius: shadowRadius, y: shadowOffsetY)
    }
}

extension View {
    /// The shadow every floating bottom surface shares. See
    /// `BottomBarStyle.floatingShadow`.
    func floatingBarShadow() -> some View {
        BottomBarStyle.floatingShadow(self)
    }
}
