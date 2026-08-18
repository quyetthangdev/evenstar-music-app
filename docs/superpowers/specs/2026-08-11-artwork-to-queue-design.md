# The artwork shrinks into the queue header — Design

**Date:** 2026-08-11
**Status:** approved

## Goal

Opening the queue should look like the cover shrinking into the header line, not
like one picture fading out while a different one fades in.

## Why the obvious fixes do not work

`artworkView` is not an image. It is five terms, all interpolated from
`progress`:

```swift
.frame(width: width, height: height)
.mask(LinearGradient(stops: dissolveStops(progress: progress)))
.clipShape(RoundedRectangle(cornerRadius: width * 0.12 * (1 - progress)))
.shadow(color: .black.opacity(0.18), radius: 6, y: 3)
.position(centre)
```

Shrink the frame alone and the result is a 44pt square with **sharp corners**
— `1 - progress` is 0 while the player is open — carrying a **dissolve
gradient** computed for a full-bleed cover. Wrong, in the middle of the app's
signature animation.

`matchedGeometryEffect` does not help either. It overrides the frame and leaves
the mask and the corner radius still reading `progress`, which is the actual
problem. It would also introduce a second geometry language into a file that
interpolates everything by hand.

## The observation this design rests on

`dissolveStops` computes `span = artworkFadeFraction * progress`. At
`progress == 0` the span is zero: **no dissolve, fully opaque, fully rounded.**

That is exactly what a 44pt thumbnail needs. The queue header's thumbnail is
the same kind of object as the collapsed pill's thumbnail, and the existing
expressions already know how to draw it. Nothing new has to be invented — only
a second input.

## Two groups, not five terms

**Shape — the mask and the corner radius.** These only need to know whether the
artwork currently looks like a thumbnail or like a full-bleed cover. One factor
feeds both:

```swift
let shapeProgress = progress * (1 - queueFactor)
```

| State | `progress` | `queueFactor` | `shapeProgress` | Result |
|---|---|---|---|---|
| collapsed pill | 0 | 0 | 0 | rounded, no dissolve |
| player open | 1 | 0 | 1 | square, dissolving |
| queue open | 1 | 1 | **0** | rounded, no dissolve |

Both existing expressions keep their shape; only their input changes. No new
formula is written, which is the point — the tuned behaviour at the two
existing ends is untouched by construction.

**Position — width, height, centre.** These interpolate on toward the 44pt slot
in the panel's header, exactly as they already interpolate from the pill to
full-bleed. The slot's rect is not measured at runtime: it is derived from
constants `PlayerCard` is given — the panel's horizontal padding, its top
inset, and `QueuePanel`'s own header artwork size — for the same reason the
collapsed centre is derived rather than measured. A measured anchor would make
the artwork's position depend on a layout pass that has not happened yet on the
first frame of the transition.

**The shadow is left exactly as it is.** An earlier draft of this design said to
scale it with `shapeProgress`, which was wrong twice over: at `shapeProgress ==
0` that removes the shadow, and `shapeProgress` is 0 for the *collapsed pill*
too — so it would have silently changed how the pill thumbnail has looked since
Phase 2. The pill already carries `radius: 6` at 36pt and looks right; 44pt is
not a size at which that stops being true.

## The panel reserves the slot

`QueuePanel` keeps its `ArtworkThumbnail` but draws it invisibly. It holds its
place in the `HStack` so the title and artist do not slide; the real artwork
flies down and lands on it.

`PlayerCard` therefore needs to know where that slot is. There is precedent in
the same file: it already passes `artworkCentreInset` down to
`MiniPlayerChrome` because one view needed an anchor point owned by the other.

## The risk, and how to tell it has bitten

`queueFactor` must be an interpolating `Double`. `showingQueue` is a `Bool`.

SwiftUI animates `.frame` when a value changes inside `withAnimation`, so the
size and position will move smoothly whether or not the factor is stored. **The
mask is the uncertain one:** `Gradient.Stop` is not reliably animatable, so the
dissolve may snap between its two states while the frame glides.

The symptom is specific and easy to name: the cover changes size smoothly, and
the fade at its bottom edge disappears in one frame rather than with it.

If that happens, the fix is a `@State private var queueFactor: Double` driven
by the same `withAnimation` that flips `showingQueue`, so the mask has a real
number to interpolate. The implementation should start with the simpler derived
form and switch only on evidence — the plan carries both, and this paragraph is
the test for which one is needed.

## Out of scope

The reverse direction gets the same treatment for free: closing the queue runs
the same interpolation backwards. Nothing else about the morph changes, and
`PlayerCard.contentBudget` is untouched — this design changes how the artwork is
drawn, never how much room anything gets.

## Testing

There is nothing here a unit test can hold. The geometry is a view modifier
chain, the codebase does not unit-test SwiftUI views, and the failure modes are
all visual.

What replaces tests is a named observation list for the device pass:

- opening the queue: the cover shrinks into the header slot, corners rounding as
  it goes, with no jump in either size or the bottom fade
- closing it: the same in reverse, landing back at full bleed
- collapsing the player while the queue is open: the artwork ends at the pill,
  not at the header
- a track with no artwork: the placeholder does the same thing, since it goes
  through the same view
- the pill thumbnail and the full-bleed cover are unchanged from today — this
  design must be invisible at both ends
