# Evenstar — Now Playing controls to Apple Music's shape

**Date:** 2026-08-02
**Author/Owner:** gihubtbe1@gmail.com
**Predecessor:** `docs/superpowers/specs/2026-08-01-player-morph-design.md`
**Branch:** `phase-2a`

---

## 1. Problem

Two gaps against Apple Music's Now Playing, both noticed by comparing the two screens directly.

**There is no volume control.** Apple Music puts one below the transport row. Evenstar has none, so changing volume means the hardware buttons or leaving the app.

**The scrubber has a round thumb.** Evenstar uses SwiftUI's `Slider`, which always draws a circular knob. Apple Music's scrubber is a thin capsule with no knob at rest that swells when touched. The knob is the single most obvious thing that reads as "not Apple Music" on that screen.

## 2. Goal

A volume slider below the transport row, and a scrubber that is a knobless capsule which expands under the finger.

## 3. Constraint that shapes the whole design

**iOS does not let an app set system volume from SwiftUI.** `AVAudioSession.outputVolume` is read-only; the only sanctioned way to change it is `MPVolumeView`, a UIKit view.

This does not break the project's "SwiftUI only" rule — the parent design spec already anticipated exactly this, listing an AirPlay button "wrapped via `UIViewRepresentable`" for this screen. `UIViewRepresentable` is in scope; `UIViewControllerRepresentable` and UIKit presentation controllers remain out.

**`MPVolumeView` renders nothing in the simulator.** It works only on a device. So no screenshot can verify this control — not even that it appears at all.

## 4. Decisions

### 4.1 Volume: use Apple's control, hide its knob

`MPVolumeView` is used directly, with `showsRouteButton = false` and its thumb hidden via `setVolumeThumbImage(_:for:)`. It stays in sync with the hardware buttons and with AirPlay routing for free, because it *is* the system control.

**Rejected:** a custom capsule matching the scrubber exactly, driven by a hidden `MPVolumeView`. That is what full fidelity would require, and it is what several shipping apps do — but setting the volume then depends on reaching into `MPVolumeView`'s undocumented subview hierarchy to find its `UISlider`. Any iOS release can change that, and the failure is silent: the slider simply stops changing the volume. For an app intended for the App Store, that is the wrong thing to build a real function on.

The visible cost is narrow: Apple Music's volume slider at rest is also a thin knobless line. The only difference is that it swells on touch, and that gesture matters far less on volume than on the scrubber.

The developer may revisit this after comparing the two side by side on their own phone; the layout will already be in place, so only the control's source would change.

### 4.2 Scrubber: build it

There is no way to remove `Slider`'s thumb. The scrubber becomes a custom view.

That is a gain beyond appearance. An open risk has been carried since the player moved to a sheet and then to a hand-built card: a vertical drift while dragging the scrubber might collapse the player instead of seeking, because two gestures compete and the winner is decided by SwiftUI's implicit child-over-parent rule. Owning the scrubber means declaring the winner explicitly with `.highPriorityGesture`.

## 5. Components

**`ScrubberBar`** — new, `Evenstar/Evenstar/Features/Player/ScrubberBar.swift`

A capsule track with the played portion filled and no knob. 7 pt tall at rest, 12 pt while dragging, animated between. The elapsed and remaining labels sit below and grow more prominent during a drag.

```swift
ScrubberBar(position: TimeInterval, duration: TimeInterval, onSeek: (TimeInterval) -> Void)
```

It owns the `draggingPosition` state that currently lives in `NowPlayingContent`, and the `formatTime` helper, so the whole scrubbing concern lives in one file.

**`onSeek` fires once, on release** — not continuously during the drag. The bar follows the finger locally the whole time, but the player is only told where to go when the finger lifts. This matches what the `Slider`'s `onEditingChanged` did before, and it matters: seeking an `AVAudioPlayer` on every drag frame would thrash it.

Its drag is attached with `.highPriorityGesture` so it takes precedence over `PlayerCard`'s card drag.

**`SystemVolumeSlider`** — new, `Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift`

A `UIViewRepresentable` wrapping `MPVolumeView`, with the route button off and the thumb hidden.

Its two track colours are set to match `ScrubberBar` exactly, so the two read as one family: the played/filled portion uses `.primary`, and the remaining portion `.primary` at 25% opacity. `MPVolumeView` takes `UIColor`, so these are `UIColor.label` and `UIColor.label.withAlphaComponent(0.25)` — the `UIKit` equivalents of what the scrubber uses. Overall height is fixed at 44 pt so it does not shift the layout as the volume changes.

**`NowPlayingContent`** — modified

The `Slider` block is replaced by `ScrubberBar`; `SystemVolumeSlider` is added below the transport row; `draggingPosition` and `formatTime` move out with the scrubber.

## 6. The knock-on nobody should miss

`PlayerCard` derives the expanded artwork size as:

```swift
min(expandedArtwork, fullSize.height - insets.top - expandedArtworkTopGap - 300, fullSize.width - 48)
```

That `300` is the allowance for everything below the artwork. Adding a volume slider adds roughly 44 pt to that stack.

**If the allowance is not raised at the same time, this reintroduces the exact defect fixed one round ago:** content overflowing the card and being clipped away, removing controls entirely in landscape and amputating the play button on an iPhone SE at default type. The allowance goes to **350**, and the change lands in the same commit as the volume slider — not as a follow-up.

## 7. Error handling

A zero or non-finite duration makes `ScrubberBar` render an empty track and ignore drags, rather than dividing by zero. Seeks are clamped to `0...duration`. `MPVolumeView` failing to render — which is exactly what happens on the simulator — leaves an empty space; nothing crashes and nothing else is affected.

## 8. Testing

**`ScrubberBar`'s seek arithmetic gets real unit tests.** Mapping a touch x-coordinate to a time, and a time to a fill fraction, is pure logic with edge cases — zero duration, a touch outside the bar's bounds, a non-finite duration. It is extracted as static functions and tested, the same way `ArtworkStore` was.

About four tests:
- x at the left edge maps to 0, at the right edge to the full duration
- an x beyond either end clamps rather than overshooting
- a zero duration yields a zero fraction and does not divide by zero
- a mid-bar x maps to the proportional time

**The rendering, the swell, the drag feel and the volume slider get no unit tests**, per the standing rule that SwiftUI views are verified manually — and in the volume slider's case, no automated verification is possible at all.

The suite goes from 54 to roughly 58.

## 9. Risks

1. **The volume slider cannot be verified before the developer runs it.** `MPVolumeView` is invisible in the simulator, so a screenshot cannot even confirm the control exists. This is the first change in the project where a whole component is beyond automated reach.
2. **Hiding the thumb may not take with an empty `UIImage()`.** Some iOS versions need a genuinely 1×1 transparent image. If the knob is still visible on device, that is the cause.
3. **`.highPriorityGesture` is a deliberate override.** It should stop the card collapsing during a seek, but it also means the scrubber wins any drag that starts on it — including a large vertical one that the user intended for the card. That is the correct trade for a control this small, but it is a trade.
4. **The artwork allowance.** See §6. This is the one that has already gone wrong once.

## 10. Files changed

| File | Change |
|---|---|
| `Features/Player/ScrubberBar.swift` | NEW — knobless capsule, swell on touch, seek arithmetic |
| `Features/Player/SystemVolumeSlider.swift` | NEW — `MPVolumeView` wrapper |
| `Features/Player/NowPlayingContent.swift` | MODIFIED — swap the scrubber, add the volume slider |
| `Features/Player/PlayerCard.swift` | MODIFIED — artwork allowance 300 → 350 |
| `EvenstarTests/ScrubberBarTests.swift` | NEW — about 4 tests |
