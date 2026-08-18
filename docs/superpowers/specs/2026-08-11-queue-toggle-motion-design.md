# The queue toggle's motion — Design

**Date:** 2026-08-11
**Status:** approved

## Goal

Make opening the queue feel like one deliberate gesture: the button answers the
finger, a capsule lights up behind it, the cover shrinks into the header, and
the list rises into the space the cover left.

## What already exists

Three of the requested pieces shipped in earlier đợt and need no work:

- **Light-impact haptic**, fired at *touch-down* rather than release —
  `TransportButtonStyle`'s `.sensoryFeedback(.impact(weight: .light), trigger:)`
- **The shared-element artwork transition** — `PlayerCard.artworkGeometry`,
  interpolating on two axes toward the header slot
- **A toggling implementation** — `showingQueue` plus the animated
  `queueFactor` that mirrors it

This design adds four things to those.

## The button stops being a transport button

`scale 0.9` on press cannot be layered onto the current style. `transportToggle`
already pops the glyph to 1.08 at touch-down, and the two scales multiply:

```
0.9 × 1.08 = 0.97
```

The pop inverts into a shrink. That is not a near-miss — it is the same
arithmetic that already cost this project one defect, when a held-press squeeze
of 0.92 cancelled the kick it was meant to precede.

So the queue button gets its own `ButtonStyle`, and the split is honest rather
than convenient: **every other button that style serves moves the queue; this
one changes what you are looking at.** The transport buttons throw themselves in
the direction their arrow points because their action goes somewhere. This one
does not go anywhere.

The new style keeps what the old one got right — the halo and the haptic, both
at touch-down — and replaces the kick with `scaleEffect(0.9)` driven by
`configuration.isPressed`. Because `TouchDownButton` already runs the action on
contact, the shrink and the queue opening happen in the same instant rather than
one announcing the other.

**The shrink is not on the layout spring.** It uses `BottomBarStyle.press` —
the 0.09s ease-out a tab already uses to answer a finger — because a press has
no known duration and a spring that overshoots on the way *in* reads as the
button wobbling under a finger that is still holding it. The spring below is for
the layout change the press causes, which is a different event with a different
job.

## The capsule

An `.ultraThinMaterial` `Capsule` behind the glyph, present only while
`showingQueue`: `opacity` 0→1 and `scaleEffect` 0.6→1, scaled about its own
centre.

**Risk, with the symptom named.** The expanded card already draws a frosted
layer in its own background. Material over material does not compose the way two
translucencies suggest — it can read as a flat grey smear rather than glass. The
tell is specific: if the capsule looks like a painted swatch rather than
something the background shows through, the fix is `.regularMaterial`, or a
solid tint at low opacity, not more blur.

## The list rises, the header does not

`offset(y: 50 → 0)` alongside the existing fade.

Applied to **`pillRow` and `upcomingList` only — never `header`.** The header is
where the artwork is flying to. A destination that moves while something is
travelling toward it makes two animations chase each other, and the artwork
would land on a slot that has since gone somewhere else.

That constraint is not decoration: `queueThumbCentre` computes the landing point
from static constants precisely so it does not depend on a layout that has not
settled. Sliding the header would reintroduce, in motion, the same class of
disagreement that a 12pt constant mismatch produced in stillness.

## The spring

`Spring(mass: 1, stiffness: 180, damping: 22)` — damping ratio 0.82, settling in
roughly 0.36s. Named in `BottomBarStyle` beside the four springs already there.

**It drives three things and only three:** the capsule's fade-and-grow, the
list's rise, and `queueFactor` — which is to say the artwork's shrink, since
that is the value the shrink interpolates on. Those are the parts of one gesture
and they must share a clock or they will visibly disagree. Everything else in
`PlayerCard` keeps the animation it has; this design does not retune the
expand/collapse morph, and touching `BottomBarStyle.settle` would do exactly
that from a distance.

**Risk, with the symptom named.** The whole-branch review established that a
drag-collapse begun while the queue is open already runs two independent clocks:
`progress` tracks the finger directly, while `queueFactor` runs its own spring.
Introducing a third timing character makes that harder to read, not easier.

The tell: if a slow collapse-drag with the queue open looks like two objects
moving separately rather than one thing folding away, the answer is to give both
the same spring. This design ships the requested numbers and records the exit.

## The header slot grows to 54pt

One constant, `QueuePanel.headerArtwork`. The artwork's landing point follows
automatically — it reads that constant, and a fix landed today collapsed the two
places that used to derive it into one.

**A conscious deviation, recorded as one.** Every other artwork thumbnail in
this app is 44pt: `SongRow`, `QueueRow`, `JamendoResultRow`. 54 makes this the
only one that differs. That was chosen deliberately for prominence at the top of
the panel, and this paragraph exists so a later reader finds a decision rather
than an inconsistency.

## What was asked for and is not being built

**"Player controls translate down slightly."** Dropped. Two turns before this
request, the same controls were reported as wrongly moving and a fix shipped to
hold them still; re-checking the Apple Music screenshot that started all of
this, its scrubber and transport row sit at exactly the same height in both
modes. Reintroducing motion there would undo a fix that was asked for, to match
a reference that does not do it.

## Testing

The button style, the capsule and the slide are view modifiers, and this
codebase does not unit-test SwiftUI views. What can be tested is already tested:
`artworkGeometry` and `queueThumbCentre` carry the arithmetic, and the 54pt
change flows through both.

The observations that replace tests, for the device pass:

- pressing the button shrinks it to 0.9 while held, and the queue begins opening
  on contact rather than on release
- the capsule fades and grows from its centre — not from an edge, and not by
  sliding
- the capsule reads as glass over the card's gradient, not as a grey swatch
- the list rises from below as it fades, while the header stays put and the
  cover lands cleanly on it
- the scrubber and transport row do not move at all between modes
- a slow drag-collapse with the queue open still reads as one object
