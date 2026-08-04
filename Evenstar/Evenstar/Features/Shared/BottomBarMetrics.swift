import CoreGraphics

/// Every measurement in the floating bottom stack, in one place.
///
/// This exists because one specific defect has now recurred twice: `PlayerCard`
/// positions its collapsed pill with a bottom padding, and converts finger
/// movement to progress with a separate `dragTravel` divisor. Those two must
/// describe the same distance. When they drifted the card lagged the finger —
/// first by `insets.bottom`, then again by the pill's own gap. The pill sits a
/// full `playerBottomOffset` up, so a third drift would put the card most of
/// that distance behind the finger.
///
/// Both formulas must read these values. Never restate the arithmetic.
///
/// **The stack is anchored to the screen, not to the safe area.** Everything
/// below is measured from the physical bottom edge of the display, the way
/// Apple's own iOS 26 floating tab bar is: 21pt in from the bottom on every
/// device, home indicator or not. It deliberately intrudes into the bottom
/// safe-area inset — the home indicator is a thin line about 8pt from the edge,
/// not 34pt of obstruction, and a bar bottom at 21 still clears it by roughly
/// 8pt. Only the *horizontal* margin is still applied inside the safe area, so
/// landscape clears the notch.
///
/// The one consequence to keep in mind: a list's clearance is therefore **not**
/// a constant, because `.safeAreaInset(edge: .bottom)` measures from the safe
/// area while the bar is measured from the screen. See
/// `clearanceTabBarOnly(bottomSafeAreaInset:)`.
enum BottomBarMetrics {
    /// How far the bar is inset from each side. Applied inside the safe area,
    /// unlike the vertical measurements below — in landscape on a notched
    /// device the sides of the *screen* are under the notch and the rounded
    /// corners, so a screen-relative side margin would put the bar under them.
    static let sideMargin: CGFloat = 21
    static let tabBarHeight: CGFloat = 54
    /// Between the tab bar's bottom edge and the **physical bottom of the
    /// screen** — not the safe area, which is what this used to measure from
    /// and what made it mean something different on every device: 8 above a
    /// home indicator was 42 from the physical edge, twice Apple's 21, while on
    /// a device without one it was 8 from the edge and nothing else separated
    /// the bar from it. Measured from the screen it is 21 everywhere, and the
    /// device-dependence moves to the one place that genuinely needs it — the
    /// list clearance below.
    ///
    /// **30, not the 21 two write-ups give for iOS 26.** Set at 21 it looked
    /// too close to the edge beside the real Apple Music on the same phone,
    /// which is better evidence than a figure from a blog — and that figure is
    /// suspect: it quotes one number for "left, right, and bottom", and the
    /// bottom is the one edge where a home indicator changes the picture. At 30
    /// the bar's bottom sits 4pt inside a 34pt bottom inset, still intruding on
    /// it but only just, and clears the home indicator line by about 17pt.
    static let screenBottomInset: CGFloat = 30
    /// Between the tab bar's top edge and the collapsed player's bottom edge.
    static let playerTabGap: CGFloat = 8
    /// Between the tab pill and the detached circular search button.
    static let tabBarSearchGap: CGFloat = 8
    /// The bar's height while searching — a little shorter, since a single
    /// text field needs less room than an icon stacked over a label.
    ///
    /// The lists' clearance deliberately does **not** follow this. It stays
    /// keyed to `tabBarHeight`, so entering search leaves a few extra points of
    /// space rather than reflowing every list underneath. Reflowing content the
    /// user is not looking at, to reclaim 8pt, is not a trade worth making.
    static let searchBarHeight: CGFloat = 48

    /// Screen bottom up to the collapsed player pill's bottom edge.
    static let playerBottomOffset = screenBottomInset + tabBarHeight + playerTabGap

    /// Screen bottom up to the floating tab bar's **top** edge — the height a
    /// list has to keep clear, before converting to the safe-area coordinates
    /// `.safeAreaInset` works in.
    static let tabBarTopOffset = screenBottomInset + tabBarHeight

    /// What a list must leave clear with no track — the pill is hidden.
    ///
    /// **Not a constant, and it cannot go back to being one.** A list applies
    /// this through `.safeAreaInset(edge: .bottom)`, which measures from the
    /// safe area, while the bar above is anchored to the screen. The distance
    /// between the two is exactly `bottomSafeAreaInset`: 34 on a phone with a
    /// home indicator, 0 on an iPhone SE. So the same bar needs 37pt of
    /// clearance on one and 71 on the other.
    ///
    /// Clamped at 0 for a hypothetical device whose bottom inset exceeds the
    /// whole bar: the safe area alone would already clear it, and a negative
    /// inset would pull content down under the home indicator.
    ///
    /// No screen computes this itself — they all apply `View.clearsBottomBar()`,
    /// which reads the measured inset out of the environment. See
    /// `BottomBarClearance.swift`.
    static func clearanceTabBarOnly(bottomSafeAreaInset: CGFloat) -> CGFloat {
        max(0, tabBarTopOffset - bottomSafeAreaInset)
    }

    /// What a list must leave clear with a track loaded: the tab bar's own
    /// clearance plus the pill and the gap above the bar it floats on.
    static func clearanceWithPlayer(bottomSafeAreaInset: CGFloat) -> CGFloat {
        clearanceTabBarOnly(bottomSafeAreaInset: bottomSafeAreaInset)
            + playerTabGap
            + PlayerCard.collapsedHeight
    }

    /// Horizontal inset of the collapsed player once it has joined the tab row:
    /// past the leading circle and its gap. The player slots exactly between
    /// the two circles.
    static let minimisedPlayerInset = sideMargin + tabBarHeight + tabBarSearchGap
}
