import SwiftUI

/// Press physics for a button that changes what you are looking at.
///
/// **Deliberately not `TransportButtonStyle`.** That style throws its glyph in
/// the direction the button's action goes — right for Next, wrong for a control
/// that goes nowhere. It also pops the glyph to 1.08 at touch-down, and a press
/// scale of 0.9 layered on top multiplies to `0.9 × 1.08 = 0.97`: the pop
/// inverts into a shrink. That is the same arithmetic that already cost this
/// project one defect, when a 0.92 held-press squeeze cancelled the kick it was
/// meant to precede.
///
/// What survives from that style is what it got right — the halo and the
/// haptic, both fired at touch-**down** — because `TouchDownButton` runs the
/// action there too, so the shrink, the feedback and the queue opening are one
/// instant rather than three.
///
/// No `trigger` parameter, unlike `.transportSkip`/`.transportToggle`: those
/// need an external counter to retrigger a kick. This style's only counter is
/// internal, and an unused parameter is an invitation to pass something into it.
struct QueueToggleStyle: ButtonStyle {

    /// Deeper than `BottomBarStyle.pressedScale` (0.96, for a tab that is a
    /// whole quarter of the bar). This is a 44pt glyph the thumb lands on
    /// squarely, and the same ratio on something that small reads as barely
    /// moving.
    fileprivate static let pressedScale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        // A nested view, not the style itself: a `ButtonStyle` is not a `View`
        // and cannot read `@Environment`, and this needs `isPressed` observed
        // through `onChange`.
        Interaction(configuration: configuration)
    }

    /// Named for what it does, not `Body` — that collides with `ButtonStyle`'s
    /// own `Body` associated type and makes the conformance fail to resolve.
    private struct Interaction: View {
        /// Counts touch-*downs*. The halo and the haptic key off this rather
        /// than off a completed tap, because an acknowledgement that waits for
        /// the finger to leave is not one.
        @State private var presses = 0
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? QueueToggleStyle.pressedScale : 1)
                // `press`, not the layout spring. A press has no known
                // duration, and a spring that overshoots on the way *in* reads
                // as the button wobbling under a finger that is still holding
                // it. The spring belongs to the layout change the press causes,
                // which is a different event with a different job.
                .animation(BottomBarStyle.press, value: configuration.isPressed)
                .tapHalo(trigger: presses)
                .sensoryFeedback(.impact(weight: .light), trigger: presses)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { presses += 1 }
                }
        }
    }
}

extension ButtonStyle where Self == QueueToggleStyle {
    /// For the control that opens the queue. See the type's doc comment for why
    /// it is not one of the transport styles.
    static var queueToggle: Self { QueueToggleStyle() }
}
