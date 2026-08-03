import CoreGraphics

/// Every measurement in the floating bottom stack, in one place.
///
/// This exists because one specific defect has now recurred twice: `PlayerCard`
/// positions its collapsed pill with a bottom padding, and converts finger
/// movement to progress with a separate `dragTravel` divisor. Those two must
/// describe the same distance. When they drifted the card lagged the finger —
/// first by `insets.bottom`, then again by the pill's 12pt gap. The pill now
/// sits a further `playerBottomOffset` up, so a third drift would put the card
/// 76pt behind the finger.
///
/// Both formulas must read these values. Never restate the arithmetic.
enum BottomBarMetrics {
    static let sideMargin: CGFloat = 12
    static let tabBarHeight: CGFloat = 56
    static let tabBarBottomGap: CGFloat = 12
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

    /// Safe-area bottom up to the collapsed player pill's bottom edge.
    static let playerBottomOffset = tabBarBottomGap + tabBarHeight + playerTabGap

    /// What a list must leave clear with a track loaded.
    static let clearanceWithPlayer = playerBottomOffset + PlayerCard.collapsedHeight

    /// What a list must leave clear with no track — the pill is hidden.
    static let clearanceTabBarOnly = tabBarBottomGap + tabBarHeight
}
