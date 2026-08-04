import SwiftUI

/// The circular bloom under a transport button when it is pressed.
///
/// Split out from the arrow's slide because not every transport control has a
/// direction: play/pause toggles in place, so it takes the halo and nothing
/// else, while Previous and Next take both.
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
                LinearKeyframe(1, duration: 0.06)
                LinearKeyframe(1, duration: 0.10)
                LinearKeyframe(0, duration: 0.22)
            }
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.0, duration: 0.16, spring: .bouncy)
                LinearKeyframe(1.0, duration: 0.22)
            }
        }
    }
}

extension View {
    /// Acknowledges a press with a bloom, for a control that does not travel.
    func tapHalo(trigger: Int) -> some View {
        modifier(TapHalo(trigger: trigger))
    }
}

/// A transport arrow that hands over to a fresh copy of itself when tapped.
///
/// Two glyphs, not one. A fresh copy arrives from the side the arrow points at,
/// fading up and springing into place, while the copy it replaces is pushed off
/// the far side, fading out.
///
/// This replaced a single glyph that slid out and wrapped around via a
/// `MoveKeyframe`. A wrap has to teleport — keyframes interpolate, so the jump
/// from one edge to the other cannot be animated — and a teleport is visible if
/// the glyph has not fully cleared the clip by the time it happens. Two copies
/// have no discontinuity to hide: at every instant both are simply somewhere,
/// and the handover reads as one arrow replacing another rather than one arrow
/// jumping.
///
/// It also removes the constraint that made the old version fragile. The wrap
/// needed `travel` large enough to put the glyph *entirely* outside the clip
/// before the jump — measured per call site, and wrong by 8pt on the first
/// attempt. Here the outgoing copy is already transparent by the time it would
/// matter, so `travel` only has to be far enough to read as movement.
struct TransportArrow: View {
    let systemName: String
    let font: Font
    /// The square frame the glyph sits in — also the halo's size and the bounds
    /// the slide is clipped to.
    let side: CGFloat
    let trigger: Int
    /// `1` for a control that moves forward, `-1` for one that moves back.
    ///
    /// This is the side the *replacement* arrives from, not the side the old
    /// glyph leaves towards. Tapping Next brings the new glyph in from the
    /// right and pushes the old one off to the left, the way the next item in a
    /// list arrives; Previous mirrors it.
    let direction: CGFloat
    let travel: CGFloat

    /// Both copies move on this, so their acceleration matches rather than one
    /// easing while the other springs. The bounce is what the incoming copy
    /// arrives on; the outgoing one is transparent long before its own
    /// overshoot would show.
    private static let slide = Spring(duration: 0.30, bounce: 0.22)

    private struct Leg {
        var offset: CGFloat
        var opacity: Double
    }

    var body: some View {
        // Each copy animates on its own `keyframeAnimator` applied to a real
        // `Image`, rather than one animator building both inside its closure.
        //
        // The one-animator version compiled, reserved its layout space, and
        // drew nothing: its base view was an `EmptyView`, chosen because
        // applying the modifier to `self` inside `body` would have made `body`
        // depend on itself. A modifier over `EmptyView` contributes no content
        // no matter what its closure returns. Caught by screenshot, not by the
        // compiler — the build was clean and the tests were green.
        //
        // Sharing `trigger` and `Self.slide` is what keeps the two in step, so
        // splitting them costs nothing: both start on the same press and move
        // on the same curve.
        ZStack {
            // At rest this is the copy you see: offset 0, fully opaque.
            glyph.keyframeAnimator(
                initialValue: Leg(offset: 0, opacity: 1),
                trigger: trigger
            ) { view, leg in
                view.offset(x: leg.offset).opacity(leg.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    // Away from the side the replacement comes from.
                    SpringKeyframe(-direction * travel, duration: 0.30, spring: Self.slide)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.16)
                }
            }

            // At rest this one is invisible, and it ends each run holding the
            // visible position — offset 0, opacity 1. That is what lets the
            // animator snap back to `initialValue` afterwards without anything
            // being seen: the two copies simply trade which is showing, and
            // they are the same glyph.
            glyph.keyframeAnimator(
                initialValue: Leg(offset: 0, opacity: 0),
                trigger: trigger
            ) { view, leg in
                view.offset(x: leg.offset).opacity(leg.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.offset) {
                    // Jumps to the side it is arriving from — the direction the
                    // arrow points — while still transparent, so the jump is
                    // unseen.
                    MoveKeyframe(direction * travel)
                    SpringKeyframe(0, duration: 0.30, spring: Self.slide)
                }
                KeyframeTrack(\.opacity) {
                    // Held down at first so the two are never both solid: this
                    // copy only starts to read once the other is nearly gone.
                    LinearKeyframe(0, duration: 0.09)
                    LinearKeyframe(1, duration: 0.17)
                }
            }
        }
        .frame(width: side, height: side)
        // So a glyph on its way out disappears at the frame's edge instead of
        // sliding over the control beside it.
        .clipped()
        .tapHalo(trigger: trigger)
    }

    private var glyph: some View {
        Image(systemName: systemName).font(font)
    }
}
