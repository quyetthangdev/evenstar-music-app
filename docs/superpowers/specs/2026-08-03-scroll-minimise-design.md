# Scroll-Minimising Bottom Bar — Design (Đợt B)

**Status:** design, approved
**Date:** 2026-08-03

## Goal

Scrolling a list down collapses the bottom of the screen into a single row: the
tab pill folds into a circle, the collapsed player slides down into the space
between that circle and the search button, and the search button stays put.
Scrolling back up reverses it. Everything moves on the same bouncy spring the
search morph already uses.

Đợt A (four tabs behind a floating pill bar) is complete. Đợt C (Liquid Glass)
and the localization đợt remain untouched by this.

## The three states

The minimised state deliberately reuses the geometry the search morph already
established, so the bar has one three-slot layout rather than two:

```
Normal      [ pill, four tabs ─────────── ] [🔍]     player pill on the row above
Minimised   [○] [ player ─────────────── ] [🔍]     one row
Searching   [○] [ search field ────────── ] [✕]     one row (Đợt A)
```

`PlayerCard.collapsedHeight` is 56 and `BottomBarMetrics.tabBarHeight` is 56.
The minimised player pill is therefore exactly as tall as the row it joins, and
minimising changes only horizontal insets and the distance from the safe-area
bottom. One fewer dimension in flight than it first appears.

## Geometry

Measured up from the safe-area bottom edge, as in Đợt A:

| | Normal | Minimised |
|---|---|---|
| Tab row | 12 → 68 | 12 → 68 (unchanged) |
| Player pill, vertical | 76 → 132 | 12 → 68 |
| Player pill, horizontal inset | 12 each side | 76 each side |

76 = `sideMargin + tabBarHeight + tabBarSearchGap` — the leading circle plus its
gap. The player slots exactly into the space between the two circles.

`BottomBarMetrics` gains:

```swift
/// Horizontal inset of the collapsed player once it has joined the tab row:
/// past the leading circle and its gap.
static let minimisedPlayerInset = sideMargin + tabBarHeight + tabBarSearchGap  // 76
```

**List clearance does not follow minimisation.** It stays keyed to the
un-minimised layout. Shrinking a list's bottom inset while the user is actively
scrolling it reflows the content under their finger, which is a worse problem
than a few points of unused space.

## PlayerCard

Gains one input, `minimised: Double` in 0...1, driven from `RootView`. Three
things read it, and **all three must**:

1. **Horizontal inset**, interpolating `sideMargin` → `minimisedPlayerInset`.
2. **Bottom offset**, interpolating `playerBottomOffset` (76) → `tabBarBottomGap` (12).
3. **`dragTravel`**, which must use the *current* bottom offset, not the constant.

Point 3 is the defect that has already recurred twice in this file, and this
change makes it worse than before: the bottom offset is no longer a constant
that someone forgot to update, it is a value that **changes continuously while
the user scrolls**. Left as the literal `playerBottomOffset`, the card lags the
finger by 64pt whenever the bar is minimised, and by some fraction of that
mid-transition. Both the padding and the divisor must read one expression.

As with the existing `(1 - progress)` factors, minimisation only applies while
the card is collapsed — at `progress == 1` the card is full screen and neither
inset nor offset applies.

**The hit region must narrow too.** `BottomHitRegion`'s horizontal inset
currently uses `pillSideMargin`; it must follow the same interpolation. Left at
12, a minimised player hit-tests the full width of the row and swallows both
the leading circle and the search button — the Critical defect from Đợt A, one
layer down.

Tapping the minimised pill expands straight to full Now Playing. That is
already the behaviour (`onTapGesture` when `progress < 0.5`) and needs no
change.

## FloatingTabBar

Gains a minimised mode alongside its existing search mode. The four-tab pill
collapses to a circle exactly as it does for search, so the mechanism is the
one already built: the row is pinned to its expanded width and the capsule
clips it, with each tab scaling in place as the edge passes.

Two things differ from search mode:

- **The circle shows the currently selected tab's icon**, not a fixed home
  glyph. It says where you are, which a fixed icon cannot.
- **Tapping it restores the full bar** rather than navigating. Nothing else on
  screen offers a way back other than scrolling up, and a circle that looks
  tappable and only navigates would be a trap.

The search button on the right is unchanged in this state.

Minimised and searching are mutually exclusive: opening search from the
minimised state restores the bar first, so the two morphs never run at once.

## Scroll detection

`onScrollGeometryChange` — iOS 18, which is why the deployment target was
raised. Wrapped in one `View` extension so six screens share one
implementation rather than six copies of the same threshold logic:

```swift
extension View {
    func minimisesBottomBar(_ isMinimised: Binding<Bool>) -> some View
}
```

Rules, in order:

1. **At or above the top of the content, always restore.** Without this, a
   short scroll down followed by a shorter scroll up leaves the bar minimised
   at the very top of a list, with nothing to scroll further up to fix it.
2. Otherwise accumulate travel in the current direction, resetting the
   accumulator whenever the direction reverses.
3. Cross the threshold downward → minimise. Upward → restore.

The threshold exists so a few pixels of finger jitter cannot flip the bar. 50pt
is the starting value.

Applied to all six scrollable screens: `SongsView`, `AlbumsView`,
`ArtistsView`, `AccountView`, `AlbumDetailView`, `ArtistDetailView`. Đợt A's
Critical defect was a treatment applied to the four tab roots and missed on
the two pushed detail screens — the same trap is present here, and the two
detail screens are named explicitly for that reason.

`SearchView` is deliberately excluded, the way `ImportProgressSheet` already
is. Its results list is on screen only while the bar is already collapsed
into its three-slot search form — there is no four-tab pill left to fold, so
minimising has no meaning there. An earlier pass applied the modifier to it
anyway: scrolling the results then set `isMinimised` true behind
`isSearching`, which the leading capsule and the collapsed player both read
independently, and both rendered as if the user had scrolled a library list
while still searching. See the whole-plan review's Finding 1 (2026-08-03).

## Animation

`FloatingTabBar.searchSpring` — `.spring(duration: 0.45, bounce: 0.32)` — is
reused rather than a second curve introduced. Two bottom-bar transitions on
visibly different springs would read as two unrelated systems.

## Risks

1. **The drag divisor.** Third occurrence of a defect class that has cost this
   project four diagnostic rounds once already, and the first time the value is
   continuous rather than constant. Any task touching it must derive the card's
   top-edge position and match it term for term against `dragTravel`.
2. **Hit-testing across the minimised row.** Three tappable things now share
   one row, with the player's frame between two circles it must not cover.
3. **Missing a screen.** Six screens need the scroll modifier; Đợt A shipped
   a Critical defect by treating four when six needed it.
4. **State collision.** Minimised and searching both drive the leading capsule.
   If both can be true, the bar has an undefined fourth state.
