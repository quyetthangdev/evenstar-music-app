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

    /// Safe-area bottom up to the collapsed player pill's bottom edge.
    static let playerBottomOffset = tabBarBottomGap + tabBarHeight + playerTabGap

    /// What a list must leave clear with a track loaded.
    static let clearanceWithPlayer = playerBottomOffset + PlayerCard.collapsedHeight

    /// What a list must leave clear with no track — the pill is hidden.
    static let clearanceTabBarOnly = tabBarBottomGap + tabBarHeight
}
