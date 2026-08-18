import SwiftUI

/// Minimises the floating tab bar while a screen's content scrolls down, and
/// restores it only at the top of the content. Applied to all six scrollable
/// screens via `View.minimisesBottomBar(_:)` below, so the threshold and
/// direction logic exists exactly once rather than once per screen.
/// `SearchView` is deliberately not one of them — see the comment on its
/// results list.
///
/// The asymmetry is the design: a light scroll down folds the bar away, and
/// getting it back is a deliberate act — the restore button on the pill, or
/// returning to the top. See the branch below for why scrolling up no longer
/// counts.
private struct ScrollMinimiseModifier: ViewModifier {
    @Binding var isMinimised: Bool

    /// Travel accumulated in the current scroll direction since it last
    /// reversed. `@State` because it must persist across the many
    /// `onScrollGeometryChange` callbacks a single scroll gesture produces,
    /// but it is scoped to this one modifier instance: SwiftUI keys `@State`
    /// to a view's position in the hierarchy, so each of the six screens
    /// that apply this modifier gets its own accumulator, entirely
    /// independent of the others and of the single `isMinimised` binding
    /// they all share.
    @State private var accumulatedTravel: CGFloat = 0

    /// Same-direction travel required before the bar reacts.
    ///
    /// This is the **only** thing between the user's finger and the bar
    /// moving: the springs start the instant it is crossed, so whatever this
    /// costs is felt directly as lag. It started at 50, which was safe and
    /// noticeably late — a scroll had visibly begun before anything happened.
    ///
    /// 12 is chosen against finger jitter, which is a couple of points, not
    /// against scroll distance. It survives jitter because the accumulator
    /// **resets on any direction change**: a wobble of down-3, up-2, down-4
    /// never accumulates toward anything, whatever this number is. The
    /// threshold only has to outrun noise within a single unbroken direction,
    /// and 12 does that with room to spare while reading as immediate.
    ///
    /// Lower it further and the reset is still the real protection — but a
    /// deliberate slow scroll starts flipping the bar on the first frame,
    /// which is a different kind of wrong.
    private static let directionThreshold: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldOffset, newOffset in
                // "At the top" is `<= 0`, not `== 0`. Two things push
                // `contentOffset.y` away from a clean zero at rest:
                // rubber-band overscroll drives it negative past the top,
                // and a list sitting under a safe-area inset (a nav bar,
                // `safeAreaInset`) can settle with its resting offset itself
                // negative — the inset region is "above" content offset 0,
                // not the origin. Either way, negative means the user has
                // not yet scrolled into real content, so treating `<= 0` as
                // "at or above the top" covers both without assuming the
                // rest position is exactly zero. Whatever the direction,
                // being there always restores the bar: skipping this rule
                // lets a short scroll down followed by a shorter scroll up
                // strand the bar minimised with nothing left above to
                // scroll into to fix it.
                if newOffset <= 0 {
                    accumulatedTravel = 0
                    setMinimised(false)
                    return
                }

                let delta = newOffset - oldOffset
                guard delta != 0 else { return }

                let scrollingDown = delta > 0
                let sameDirectionAsBefore = (accumulatedTravel >= 0) == scrollingDown
                accumulatedTravel = sameDirectionAsBefore ? accumulatedTravel + delta : delta

                // Down minimises. Up does **not** restore.
                //
                // Scrolling up used to restore the bar the same way scrolling
                // down minimised it, symmetrically. That symmetry is what made
                // the bar feel unsettled: reading a list is not one long
                // downward sweep, it is down-down-up-down, and every one of
                // those small upward corrections unfolded the bar again. The
                // bar spent the whole scroll flapping.
                //
                // So restoring now has exactly two triggers, both deliberate:
                // the round button on the pill's leading edge, and arriving
                // back at the top of the content (the `newOffset <= 0` branch
                // above). Both are things a person does on purpose, which is
                // the property scrolling up lacks.
                if scrollingDown, accumulatedTravel >= Self.directionThreshold {
                    setMinimised(true)
                }
            }
            // Resets the accumulator whenever `isMinimised` changes from
            // outside this modifier — `onRestore`, most importantly. Without
            // this, tapping the restore circle after scrolling 400pt down
            // left `accumulatedTravel` still holding +400: the very next
            // same-direction pixel — one point of finger jitter, or the tail
            // of a list still decelerating under the tap — crossed the 50pt
            // threshold instantly and re-minimised the bar before the restore
            // had a chance to be seen. This also fires for the modifier's own
            // writes above (`setMinimised`), which is harmless: a direction
            // reversal already resets the accumulator to just that delta at
            // `accumulatedTravel = sameDirectionAsBefore ? … : delta` above,
            // so zeroing it a moment earlier, right as the bar itself flips,
            // changes nothing about when the next crossing fires.
            .onChange(of: isMinimised) { _, _ in
                accumulatedTravel = 0
            }
    }

    /// Guards every write. `onScrollGeometryChange`'s `action` fires on
    /// nearly every frame while a scroll is in flight, but `isMinimised` is
    /// meaningful only at the moment it actually changes — writing it to the
    /// value it already holds still invalidates the view hierarchy for
    /// nothing, and repeating that write mid-animation can fight the spring
    /// that is already carrying it toward its target. Comparing before the
    /// write, rather than relying on SwiftUI to no-op an unchanged
    /// `Binding` assignment, keeps both the invalidation and the animation
    /// restart from happening at all.
    private func setMinimised(_ value: Bool) {
        guard isMinimised != value else { return }
        withAnimation(BottomBarStyle.morph) {
            isMinimised = value
        }
    }
}

extension View {
    /// Minimises the floating tab bar as this view's scrollable content
    /// moves down past `ScrollMinimiseModifier.directionThreshold`, and
    /// restores it scrolling back up or returning to the top. See that
    /// type for the accumulation and top-of-content rules.
    func minimisesBottomBar(_ isMinimised: Binding<Bool>) -> some View {
        modifier(ScrollMinimiseModifier(isMinimised: isMinimised))
    }
}
