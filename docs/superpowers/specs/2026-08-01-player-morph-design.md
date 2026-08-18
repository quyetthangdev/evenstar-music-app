# Evenstar — Interactive player morph

**Date:** 2026-08-01
**Author/Owner:** gihubtbe1@gmail.com
**Predecessor:** `docs/superpowers/specs/2026-08-01-bottom-sheets-design.md`
**Branch:** `phase-2a`

---

## 1. Problem

Two things, found by running the app on a physical iPhone for the first time.

**The player does not morph.** Tapping the mini player slides a separate sheet up over the library. Apple Music instead grows the mini player itself into the full screen: the 40 pt artwork expands continuously into the hero, the bar becomes the card, and dragging tracks your finger in both directions. The previous spec deferred this deliberately, choosing a standard `.sheet` for drag-to-dismiss. Having now used it, the gap is the thing that reads as unfinished.

**The play/pause icon snaps.** Both buttons are written `Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")`. SwiftUI treats that as replacing one view with another, so there is nothing to animate between — the icon jumps.

## 2. Goal

The mini player and the full player become one card whose shape is driven by a single `progress` value, dragged interactively in both directions, over a background tinted from the artwork. The play/pause icons morph rather than snap.

## 3. Why this supersedes the sheet

`matchedGeometryEffect` does not work across `.sheet` or `.fullScreenCover` boundaries — they are separate presentation hosts. More to the point, `matchedGeometryEffect` interpolates between two *discrete* states when a view appears or disappears; it does not track a finger. A gesture that follows the hand continuously cannot be built on it.

So this replaces the Now Playing `.sheet` entirely. **The import sheet's changes from the previous spec stay exactly as they are** — its detents, its conditional drag indicator, its `ScrollView`. Only the Now Playing presentation is rebuilt.

Rejected alternatives:

- **`matchedGeometryEffect` + overlay.** Less code, and the artwork expands nicely on *tap*. But during a drag the card does not follow the finger, so it needs manual offsets bolted alongside — the result lands in "almost right", and the wrongness lives inside SwiftUI's implicit behaviour where it is hard to debug.
- **A UIKit custom presentation controller wrapped in `UIViewControllerRepresentable`.** This is what Apple actually does. It breaks the parent spec's "SwiftUI only" constraint and would leave the hardest-to-maintain code in the app to a first-time iOS developer.

## 4. Architecture

### 4.1 The central idea

Mini player and Now Playing stop being two views. They are one card whose every visual property is a function of `progress: Double`, where `0` is the collapsed bar and `1` is the full screen.

### 4.2 Components

**`ArtworkStore`** — new, `Evenstar/Evenstar/Utilities/ArtworkStore.swift`

A shared, cached, downsampling image loader, replacing per-view decoding.

```swift
static func image(for relativePath: String?, maxPixel: CGFloat) async -> UIImage?
static func dominantColor(for relativePath: String?) async -> Color?
```

- `NSCache<NSString, UIImage>` with a ~50 MB total cost limit, exactly as the parent spec §10 always required and no implementation ever provided. Keyed by `"<path>@<maxPixel>"`.
- Downsampling through `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`. Embedded cover art is routinely 1000×1000 to 3000×3000; decoding a 3000×3000 JPEG to draw a 44 pt thumbnail allocates roughly 36 MB. Downsampling decodes at the size actually needed.
- Dominant colour by downsampling to about 10×10 and averaging, cached separately from the image.
- All work off the main thread. Nothing throws; failures return `nil`.

This closes three items already recorded as deferred: the Phase 2a final review's Important #3 (uncached full-resolution decode inside `body`), the QA guide's item 3.2 (list-scroll jank at 300+ tracks), and the parent spec's unimplemented `NSCache` requirement.

**`PlayerCard`** — new, `Evenstar/Evenstar/Features/Player/PlayerCard.swift`

Owns `progress` and the gesture. Responsible for three things only: the card container (height, corner radius, background), the artwork as a single continuous view whose frame interpolates 40 pt → 280 pt, and cross-fading the two chrome sets beneath it.

**`MiniPlayerChrome`** — renamed from `MiniPlayerBar`

Keeps the title, artist and transport row. **Loses the artwork and the background**, which move up to `PlayerCard` because they must be continuous across the morph.

**`NowPlayingContent`** — renamed from `NowPlayingView`

Keeps the title block, scrubber and transport row. **Loses the artwork and the background**, for the same reason. Its `@State artworkImage` and `loadArtwork()` go with them.

**`ArtworkThumbnail`** — modified

Switches from its own `Data(contentsOf:)` + `UIImage(data:)` to `ArtworkStore`. Its call site in `SongRow` is unchanged.

### 4.3 Placement in `LibraryView`

The `.safeAreaInset` carrying `MiniPlayerBar` and the `.sheet` carrying `NowPlayingView` are both replaced by a `ZStack`:

```swift
ZStack(alignment: .bottom) {
    NavigationStack { … }
    PlayerCard(playback: playback, progress: $playerProgress)
}
```

The `.safeAreaInset` stays but carries `Color.clear` at the collapsed bar's height, so the list still scrolls clear of the card.

That height must be a single named constant — `PlayerCard.collapsedHeight` — read by both the inset and the card itself. Today the bar's height is implicit, emerging from a 40 pt artwork plus 8 pt vertical padding plus a divider, roughly 64 pt. Leaving it implicit in two places is how the list ends up scrolling under the card by a few points. Pin it at **64** and have both sides read it.

The existing `.onChange(of: playback.currentTrack?.id)` keeps its job: when the track goes `nil`, it drives `progress` back to `0` instead of setting a sheet binding false.

### 4.4 What `progress` drives

| Property | `p = 0` | `p = 1` |
|---|---|---|
| Card height | collapsed bar height | full screen |
| Artwork | 40 pt, leading, centred in the bar | 280 pt, horizontally centred, near the top |
| Corner radius | square, flush to the bottom edge | 38 pt on the top corners only |
| Background | `.thinMaterial` | gradient from the artwork's dominant colour |
| `MiniPlayerChrome` | opaque | faded out by `p ≈ 0.33` |
| `NowPlayingContent` | hidden | fading in from `p ≈ 0.5` |

The two chrome sets deliberately do not cross-fade through each other; the gap between 0.33 and 0.5 keeps the transition from looking muddy.

There is no public API for a device's physical corner radius, so 38 pt is a chosen constant that reads correctly on the iPhone 12 this is being developed against, not a measured one. Only the top corners round; the bottom edge stays flush.

Exact easing curves are visual judgement to tune on device. The table fixes the structure and the two constants that must not drift (`collapsedHeight` 64, top corner radius 38); everything else about the feel is settled by sitting with the device.

### 4.5 The gesture

**Collapsed** — a tap, or a drag upward, animates `progress` to `1` with a spring.

**Expanded** — a `DragGesture` on the card:
- While dragging: `progress = 1 − (translation.height / expandedHeight)`, clamped to `0…1`. Past the top, the excess is damped to 20% so the card feels tethered rather than rigid.
- On release: the decision uses `predictedEndTranslation`, not the current offset. A quick flick collapses the card even though the finger barely moved. Comparing raw distance instead is what makes hand-rolled sheets feel heavy.

**A gesture conflict that may resolve itself.** With `.sheet`, the system's pan recogniser competes with the scrubber's `Slider`, and a vertical drift while seeking can dismiss instead of seek — a real risk recorded in the previous spec and left for device QA. In SwiftUI a child view's gesture takes priority over a parent's `.gesture()`, so once the card owns the drag rather than the system, the `Slider` should keep its own touches. This needs confirming on device, but the direction of the change is favourable, not merely cosmetic.

### 4.6 The symbol animation

`.contentTransition(.symbolEffect(.replace))` on the play/pause `Image` in both chrome sets. Available since iOS 17; the deployment floor is 17.6, so no availability check is needed.

## 5. Error handling

Missing artwork renders the existing `music.note` placeholder inside the same interpolated frame. A failed colour extraction falls back to the system background. `ArtworkStore` never throws — every failure path returns `nil`, so no corrupt or missing image file can crash playback or the library list.

## 6. Testing

**`ArtworkStore` gets real unit tests.** It is not a view; it is a utility with genuine logic, and it is the riskiest non-visual part of this work. Roughly five tests:

- A cached image is returned without re-decoding
- A downsampled image is no larger than the requested `maxPixel`
- A missing file returns `nil`
- Undecodable data returns `nil`
- A solid-colour image yields approximately that colour as its dominant colour

**The card, the gesture and the interpolation get no unit tests**, per the parent spec's standing rule that SwiftUI views are verified manually. No test substitutes for how a drag feels.

The existing 47 tests must stay green, bringing the suite to roughly 52.

**This is the first work in the project where the developer can verify on device before merge.** The iPhone is connected and the app runs on it. Every prior phase was handed over unverified.

## 7. Risks

1. **The drag has to be tuned by hand.** Thresholds, spring response, the damping factor past the top — no value is right first time. The implementation sets sensible starting points; the feel is settled by sitting with the device.
2. **Safe areas and the Dynamic Island.** `.sheet` handled this. An overlay does not: the background must bleed to the edges while content insets away from them, and getting it wrong is immediately visible.
3. **Landscape.** The app is phone-first portrait. This will not be optimised for landscape, but it must not break in it.
4. **This becomes the most intricate code in the app.** Everything so far leaned on system mechanics. This does not, so it is also the most likely place for future regressions — which is part of why `ArtworkStore`, the one testable piece, is tested properly.

## 8. Files changed

| File | Change |
|---|---|
| `Utilities/ArtworkStore.swift` | NEW — cached downsampling loader + dominant colour |
| `Features/Player/PlayerCard.swift` | NEW — progress, gesture, artwork, container |
| `Features/Player/MiniPlayerBar.swift` | RENAMED to `MiniPlayerChrome.swift`, loses artwork + background |
| `Features/Player/NowPlayingView.swift` | RENAMED to `NowPlayingContent.swift`, loses artwork + background |
| `Features/Library/ArtworkThumbnail.swift` | MODIFIED — loads via `ArtworkStore` |
| `Features/Library/LibraryView.swift` | MODIFIED — `ZStack` replaces the Now Playing `.sheet`; import sheet untouched |
| `EvenstarTests/ArtworkStoreTests.swift` | NEW — about 5 tests |
