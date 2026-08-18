import SwiftUI

/// A `Button` whose action runs the instant a finger lands, not when it lifts.
///
/// The same departure `FloatingTabBar` already makes for tab selection, and for
/// the same reason: on a real device, waiting for touch-up reads as the control
/// having hesitated. `TransportButtonStyle` already moves at touch-down —
/// `configuration.isPressed` flips there — so a transport button used to shrink
/// under the finger and then do nothing until it lifted, which is worse than
/// either extreme on its own. This closes that gap.
///
/// **What it gives up: there is no cancelling by sliding off.** That is
/// inherent, not an oversight — an action that has already run cannot be taken
/// back by lifting somewhere else. It is an acceptable trade for transport
/// controls, whose worst case is a track skipped or a pause the user undoes
/// with a second tap, and it would not be for anything destructive. Do not
/// reach for this for a delete.
///
/// Not written as a `View` extension because it has to own the `Button` itself:
/// the action must live in exactly one place, and leaving it on the `Button`
/// while also firing at touch-down runs it twice per tap.
struct TouchDownButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    /// Latches the gesture to one call per touch.
    ///
    /// `DragGesture.onChanged` reports every movement, not just the landing, so
    /// without this a finger that shifts one point while pressed calls the
    /// action again — and again — for as long as it moves. On play/pause that
    /// is a control that toggles as fast as the finger trembles.
    @State private var fired = false

    /// `.disabled` is applied by callers from *outside* this view and reaches
    /// the `Button` through the environment — but a `.simultaneousGesture` is
    /// not a control, and relying on `disabled` to suppress it would be relying
    /// on an implementation detail. Read the flag and check it: a disabled
    /// Next that still skipped on touch is exactly the bug this would be.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // An empty action, deliberately. The gesture below is what runs the
        // work; a `Button` that also ran it would run it twice on every tap
        // that ends where it began. The `Button` is still here because it is
        // what draws the press physics (`ButtonStyle` reaches it through the
        // environment, so callers keep applying `.buttonStyle` and `.disabled`
        // exactly as before) and what carries the button trait to VoiceOver.
        Button {} label: { label() }
            // VoiceOver's activation never produces a touch sequence, so the
            // gesture below cannot serve it. This is the path it takes, and
            // without it the control would be inert to anyone using it.
            .accessibilityAction { action() }
            // `minimumDistance: 0` is what makes a `DragGesture` report the
            // landing rather than waiting for travel, and `.simultaneousGesture`
            // leaves the `Button` intact underneath — `isPressed`, the traits
            // and the accessibility action all keep working.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !fired else { return }
                        fired = true
                        action()
                    }
                    .onEnded { _ in fired = false }
            )
    }
}
