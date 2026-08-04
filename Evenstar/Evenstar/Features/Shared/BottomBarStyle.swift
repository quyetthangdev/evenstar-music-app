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

    /// Content inside a surface as that surface changes shape: icons and labels
    /// shrinking and fading as the pill closes over them.
    ///
    /// Quicker and calmer than `morph` on purpose. The surface closing around
    /// them is the gesture; the glyphs should feel carried by it rather than
    /// staging a second performance inside it.
    static let content = Animation.spring(duration: 0.34, bounce: 0.20)

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
