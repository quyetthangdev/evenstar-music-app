# Scroll-Minimising Bottom Bar Implementation Plan (Đợt B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scrolling down collapses the bottom into one row — tab pill to a circle, collapsed player sliding down between that circle and the search button. Scrolling up reverses it.

**Architecture:** One new `Bool` in `RootView` drives everything. `FloatingTabBar` gains a minimised mode reusing its search-morph mechanism; `PlayerCard` gains a `minimised` input that all three of its inset, bottom offset and drag divisor read. Scroll direction comes from `onScrollGeometryChange` behind one shared `View` extension.

**Tech Stack:** SwiftUI, SwiftData, iOS 18.6.

**Design spec:** `docs/superpowers/specs/2026-08-03-scroll-minimise-design.md` — read it before Task 1.

## Global Constraints

- **Never edit `Evenstar/Evenstar.xcodeproj/project.pbxproj` or `Evenstar.xcscheme`.** Xcode is open and rewrites the pbxproj cosmetically — stage specific paths; never revert it. New Swift files under `Evenstar/Evenstar/` are picked up automatically.
- Never change build settings. `SWIFT_DEFAULT_ACTOR_ISOLATION` stays `nonisolated`.
- Do not modify `PlaybackService`, `ImportService`, `LibraryService`, `NowPlayingService`, `Models/`, or `LibraryGrouping.swift`. No schema change.
- SwiftUI only. No third-party libraries. No `try!`. No silent `catch { }`.
- Clean build must produce **zero Swift warnings**.
- **74 tests** must keep passing. Confirm with `xcrun xcresulttool`, never `grep "^Test case"` — unreliable in this project, has reported a wrong count.
- Phase 1 capability must survive: background audio, lock-screen Now Playing, remote commands.
- SourceKit reports spurious "cannot find type in scope" errors throughout. Trust `xcodebuild`.
- Never synthesize a placeholder artifact. Do not commit while the build is broken, a test is failing, or a warning remains.

**Verification commands:**

```bash
cd /Users/phanquyetthang/evenstar && xcodebuild clean build \
  -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \
  | grep -E "warning:|error:|BUILD" | grep -v AppIntents | sort -u

xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -destination 'platform=iOS Simulator,name=iPhone 17'
R=$(ls -td ~/Library/Developer/Xcode/DerivedData/Evenstar-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results summary --path "$R"
```

**Screenshotting** (the simulator has no imported tracks, so the player pill never appears there — say so rather than implying otherwise):

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; sleep 10
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Evenstar-*/Build/Products/Debug-iphonesimulator/Evenstar.app
xcrun simctl launch booted com.evenstar.app
```

## File Structure

| File | Responsibility |
|---|---|
| `Features/Shared/BottomBarMetrics.swift` | modified — one new constant |
| `Features/Shared/FloatingTabBar.swift` | modified — minimised mode |
| `Features/Shared/ScrollMinimise.swift` | **new** — the `View` extension and its threshold logic |
| `Features/Player/PlayerCard.swift` | modified — `minimised` input; inset, bottom offset, drag divisor, hit region |
| `App/RootView.swift` | modified — owns the flag, wires everything |
| seven screen files | modified — one modifier each |

---

### Task 1: Metrics and the minimised tab bar

**Files:**
- Modify: `Evenstar/Evenstar/Features/Shared/BottomBarMetrics.swift`
- Modify: `Evenstar/Evenstar/Features/Shared/FloatingTabBar.swift`

**Interfaces:**
- Produces: `BottomBarMetrics.minimisedPlayerInset`; `FloatingTabBar` gaining `isMinimised: Binding<Bool>` and an `onRestore: () -> Void` closure. Tasks 2–4 consume both.

- [ ] **Step 1: Add the metric**

```swift
/// Horizontal inset of the collapsed player once it has joined the tab row:
/// past the leading circle and its gap. The player slots exactly between the
/// two circles.
static let minimisedPlayerInset = sideMargin + tabBarHeight + tabBarSearchGap
```

- [ ] **Step 2: Give `FloatingTabBar` a minimised mode**

Add `@Binding var isMinimised: Bool` and `let onRestore: () -> Void`.

The leading capsule already collapses to a circle for search — reuse that path rather than writing a second one. Introduce a single derived value for "the capsule is a circle":

```swift
private var isCollapsed: Bool { isSearching || isMinimised }
```

and use it wherever the capsule's width, the tab reveal, and the row's hit-testing currently test `isSearching`. **Do not** change what `isSearching` alone drives: the search field's width, the trailing button's glyph, and the bar's height all stay keyed to search only. Minimising does not shorten the bar and does not turn the search button into an X.

The circle's content differs by mode:

- searching → the existing home glyph, which closes search to Bài hát
- minimised → **the currently selected tab's** icon, and tapping calls `onRestore()`

Read the design spec's "FloatingTabBar" section for why the minimised circle shows the current tab and restores rather than navigating. Give the minimised button its own accessibility label saying what it does — a bare tab icon announces the destination, not the action.

- [ ] **Step 3: Make the two modes mutually exclusive**

Opening search while minimised must restore first, so the bar never has both flags true. Enforce it where the flags are set, not by hoping callers behave: in `onOpenSearch`'s path, clear `isMinimised`.

State in your report which line makes this impossible rather than merely unlikely.

- [ ] **Step 4: Update the preview**

`FloatingTabBarPreview` needs the new binding and closure. Add a control to it — a plain `Button("Minimise")` overlay is enough — so the mode can actually be seen in the canvas.

- [ ] **Step 5: Build, test, screenshot**

Clean build, zero warnings. 74 tests. Screenshot the app and Read the PNG; the bar renders in its normal state, which is what you can verify without driving a scroll.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Features/Shared/BottomBarMetrics.swift Evenstar/Evenstar/Features/Shared/FloatingTabBar.swift
git commit -m "feat: add a minimised mode to the floating tab bar"
```

---

### Task 2: PlayerCard joins the row

This task carries the arithmetic that has already broken twice, and this time the value is continuous rather than constant. Work slowly.

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`

**Interfaces:**
- Consumes: `BottomBarMetrics.minimisedPlayerInset` (Task 1).
- Produces: `PlayerCard(playback:minimised:)` — Task 4 passes it.

- [ ] **Step 1: Add the input**

```swift
/// 0 collapsed on its own row, 1 slotted into the tab row. Interpolated, not
/// a Bool, so the card can be animated between the two.
let minimised: Double
```

- [ ] **Step 2: Interpolate the horizontal inset**

The card currently insets by `pillSideMargin * (1 - progress)` each side. It must now interpolate that toward `BottomBarMetrics.minimisedPlayerInset` as `minimised` goes to 1, still scaled by `(1 - progress)` so an expanded card is unaffected.

- [ ] **Step 3: Interpolate the bottom offset — and the drag divisor with it**

The bottom offset is currently `BottomBarMetrics.playerBottomOffset` (76). It must interpolate to `BottomBarMetrics.tabBarBottomGap` (12) as `minimised` goes to 1.

**Both the `.padding(.bottom, …)` and `dragTravel` must read one shared expression.** Write it once as a computed value and use it in both places.

Then derive the card's top-edge position yourself and check it against `dragTravel` term for term, at **both** `minimised == 0` and `minimised == 1`:

```
top(p) = fullHeight − (insets.bottom + bottomOffset)(1−p) − collapsedHeight − (fullHeight − collapsedHeight)p
top(0) = fullHeight − collapsedHeight − insets.bottom − bottomOffset
top(1) = 0
```

Visible travel is `top(0) − top(1)` and must equal `dragTravel`. Put both derivations in your report with real numbers for an iPhone 17 (`fullHeight` 874, `insets.bottom` 34, `collapsedHeight` 56). If they disagree at either end, stop and say so rather than committing.

- [ ] **Step 4: Narrow the hit region**

`BottomHitRegion`'s `horizontalInset` currently passes `Self.pillSideMargin` when at collapsed rest. It must use the same interpolated inset as the card.

Left at 12, a minimised player hit-tests the whole width of the row and swallows the leading circle and the search button — the Critical defect from Đợt A, one layer down.

Read the long comment at that `.contentShape` call site before touching it. The rule it records still holds: **the region's size keys on whether a drag is in flight, never on `progress` alone.** Minimisation changes the region's *horizontal* extent at rest; it must not change the gate that keeps the region full-screen during a drag.

- [ ] **Step 5: Update the preview if there is one, build, test**

Clean build, zero warnings, 74 tests.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Features/Player/PlayerCard.swift
git commit -m "fix: let the collapsed player slot into the tab row"
```

---

### Task 3: Scroll detection

**Files:**
- Create: `Evenstar/Evenstar/Features/Shared/ScrollMinimise.swift`

**Interfaces:**
- Produces: `View.minimisesBottomBar(_ isMinimised: Binding<Bool>)` — Task 4 applies it to seven screens.

- [ ] **Step 1: Write the modifier**

A `ViewModifier` using `onScrollGeometryChange(for: CGFloat.self)` reading `contentOffset.y`, holding its own accumulator in `@State`.

Rules, in this order:

1. **At or above the top of the content, always restore**, whatever the direction. Without this, a short scroll down followed by a shorter scroll up strands the bar minimised at the very top of a list, with nothing left to scroll up to fix it.
2. Otherwise accumulate travel in the current direction, resetting the accumulator when the direction reverses.
3. Threshold crossed downward → minimise; upward → restore.

The threshold is why a few pixels of finger jitter cannot flip the bar. Start at 50pt and name it as a constant with that reasoning attached.

Wrap the state change in `withAnimation(FloatingTabBar.searchSpring)` so the bar moves on the same curve as the search morph. A second spring for a second bottom-bar transition would read as two unrelated systems.

- [ ] **Step 2: Build and test**

Nothing consumes it yet. Clean build, zero warnings, 74 tests unchanged.

- [ ] **Step 3: Commit**

```bash
git add Evenstar/Evenstar/Features/Shared/ScrollMinimise.swift
git commit -m "feat: add a shared scroll-direction modifier for the bottom bar"
```

---

### Task 4: Wire it up

**Files:**
- Modify: `Evenstar/Evenstar/App/RootView.swift`
- Modify: `SongsView.swift`, `AlbumsView.swift`, `ArtistsView.swift`, `SearchView.swift`, `AccountView.swift`, `AlbumDetailView.swift`, `ArtistDetailView.swift`

**Interfaces:**
- Consumes everything from Tasks 1–3.

- [ ] **Step 1: `RootView` owns the flag**

Add `@State private var isMinimised = false`. Pass it to `FloatingTabBar`, and pass `minimised: isMinimised ? 1 : 0` to `PlayerCard`.

`onRestore` sets it false inside `withAnimation(FloatingTabBar.searchSpring)`. `onOpenSearch` must clear it too — see Task 1 Step 3.

- [ ] **Step 1b: Remove the temporary defaults — required, not optional**

Tasks 1 and 2 each added a default so `RootView` kept compiling while it was off-limits to them: `FloatingTabBar.init` defaults `isMinimised` to `.constant(false)` and `onRestore` to `{}`; `PlayerCard.init` defaults `minimised` to `0`.

Delete all three now that the real call site passes them.

They are not harmless leftovers. A default that silently disables a feature means the next view to construct either type — a new screen, a second root, a preview — gets a bar that never minimises and a player that never moves, with **no compiler error, no test failure, and no visible signal at all**. The whole reason the defaults were acceptable was that they were temporary. Removing them turns a silent misconfiguration into a build error.

If either `init` becomes trivial once its default is gone, delete the explicit `init` and let the memberwise one do the work.

- [ ] **Step 2: Apply the modifier to all seven screens**

`.minimisesBottomBar($isMinimised)` on each screen's scrollable content. The flag lives in `RootView`, so the screens need it passed in — add a `@Binding var isMinimised: Bool` to each rather than reaching for a singleton or an environment object.

**All seven.** `AlbumDetailView` and `ArtistDetailView` are pushed destinations, not tab roots, and Đợt A shipped a Critical defect precisely by treating the four tab roots and missing those two. Grep for scrollable containers when you think you are finished and check the list against what you changed.

- [ ] **Step 3: Build, test, screenshot**

Clean build, zero warnings, 74 tests. Launch, screenshot, Read the PNG.

Then **verify the minimised layout by temporarily defaulting `isMinimised` to `true`**, rebuilding, screenshotting, reading it, and restoring the default. The simulator cannot synthesize the scroll that would trigger it otherwise. Restore the file and confirm with `git diff` that nothing of that hack survives — say in your report that you checked.

State plainly what remains unverifiable: with no imported tracks the player pill never appears, so the minimised player's position, its hit region against the two circles, and the drag are all the developer's to confirm on device.

- [ ] **Step 4: Commit**

```bash
git add Evenstar/Evenstar/App/RootView.swift Evenstar/Evenstar/Features/
git commit -m "feat: minimise the bottom bar as lists scroll"
```

---

## Device QA (developer, after Task 4)

Nothing below is checkable in the simulator — it has no imported tracks, and no way to synthesize a scroll.

1. Scrolling a list down collapses the tab pill to a circle and slides the player into the row; scrolling up restores both.
2. A few pixels of jitter does not flip the bar back and forth.
3. Returning to the top of a list always restores the bar.
4. While minimised, the leading circle and the search button are both still tappable — the player must not swallow them.
5. Tapping the leading circle restores the bar.
6. Tapping the minimised player opens Now Playing.
7. **Dragging the minimised player up still tracks the finger exactly.** This is the twice-broken behaviour, now with a moving target.

   **One known exception, so it is not misread as a fourth recurrence:** if the bar minimises or restores *while a player drag is already in flight* — a decelerating list still firing scroll events after the finger has moved to the pill — the card moves about 8% less than the finger for the length of one spring, then re-syncs. The padding animates; the divisor jumps on the next body evaluation. It is transient and self-correcting. Suppressing it would mean exposing `PlayerCard`'s private drag state so scroll handling could stand down, which was judged more machinery than a rare half-second warrants. If it turns out to be common in practice, that is the fix.

8. **Landscape.** Rotate and repeat checks 1, 4 and 7. The player measures its horizontal inset from a different edge than the tab bar does — that mismatch is what made the minimised pill overhang and swallow both circles in landscape while portrait looked perfect.
8. Opening search from the minimised state does not produce a half-minimised, half-searching bar.
9. It happens on all seven screens, including inside an album and inside an artist.
