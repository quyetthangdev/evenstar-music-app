# Endless playback, and a simpler palette — Design

**Date:** 2026-08-11
**Status:** approved (both parts)

Two decisions taken together. They share no code; they are one document because
they were agreed in one conversation.

---

# Part 1 — The ∞ button

## What Apple Music's Autoplay actually is

With ∞ on, the queue never ends: when the last track finishes, Apple Music
appends songs *similar* to what you have been playing, drawn from its
catalogue. The word doing the work is **similar** — it needs a recommendation
engine over listening behaviour at enormous scale.

**Evenstar has no similarity data and no source that could supply it.** This
đợt was ruled out twice before on exactly that ground. What follows is not
Autoplay; it is the honest thing this app can do instead, and it is named
accordingly.

## What ∞ does here

When the queue runs out, keep playing from **the user's own library**.

The ladder has two rungs, not three:

1. tracks by the same artist as the one that just finished, not already queued
2. the rest of the library

An earlier draft said "same artist → same genre → anything". `Track` has no
genre field — title, artist, album, disc, track number, duration, path, format
and nothing else. The middle rung does not exist, and saying it did was a claim
made without reading the model.

**Appended in batches, not one at a time.** A queue that grows by one track
shows a single row in the queue panel and reads as about to end. A batch gives
the panel something to be.

## It cannot collide with repeat

`.all` and `.one` both mean the queue has no end, so ∞ never gets a turn. It
only ever acts when `repeatMode` is `.off`. No precedence rule is needed, and
none should be invented.

## The place this will break

**Appending to `queue` while shuffle is on must append to `unshuffledQueue`
too.**

The invariant the last several đợt rest on is that the two arrays hold the same
*set*. Six mutation sites already respect it. This is the seventh, and the first
that **adds** elements rather than permuting or removing them — every previous
site either left the set alone or changed both arrays in the same breath.

The whole-branch review of the shuffle đợt named this risk in the abstract:
"two parallel arrays held equal by convention." This is the convention being
tested in a way it has not been before.

## Naming

**Not "Autoplay".** It recommends nothing. The label is **"Phát tiếp"** /
*Keep playing*, with a footer saying where the music comes from.

The `infinity` glyph stays, because it describes the behaviour honestly: there
is no end.

## Persistence

One `PlaybackState` property, **with a literal default** — the same requirement
`repeatModeRaw` and the two shuffle properties carry, and for the same reason:
without one, SwiftData cannot open a store written by an earlier build, and the
app fails to launch for every existing user.

## Testing

- ∞ off: the queue still ends and playback still stops
- ∞ on: the queue grows and playback continues
- same artist comes first
- a track already in the queue is never appended
- **appending while shuffled grows both arrays** — the invariant above
- **a library containing only what is already queued stops**, rather than
  recursing forever looking for something to add
- `repeat .all` is on: ∞ never runs

The second-to-last is the one to write first. An endless feature whose
exhaustion case is untested is an endless loop waiting for a small library.

---

# Part 2 — Five interface changes

## 1. The queue capsule appears on press, not while active

Today the glass capsule is shown whenever `showingQueue` is true. It should
appear only while the finger is down — driven by `configuration.isPressed`
inside `QueueToggleStyle`, not by the toggle's state.

**This costs the only strong "the queue is open" signal.** What remains is the
glyph's own colour. That is a deliberate trade, recorded here so it is not
rediscovered as a bug: the button is not the indicator, the panel filling the
screen is.

## 2. The list's side padding matches the content above it

Both are already 24pt — `expandedContent` and `QueuePanel` use the same figure.
The visible mismatch is the `List`'s own per-row inset, which indents rows
relative to the header above them. `listRowInsets` is the fix, not the padding.

## 3. The list extends down toward the scrubber

It stops at `contentOffset` today, and **that cap is not arbitrary — it is the
fix for a Critical**: `QueuePanel`'s `List` is a `UIScrollView`, and its pan
recogniser swallowed `ScrubberBar`'s 28pt drag strip, making seeking impossible
while the queue was open.

The room to reclaim is the title block's, which is invisible in queue mode but
still occupies its space. The list may grow into that, and **must still stop
above the scrubber's touch strip.** Close to the scrubber is the requirement;
touching it is the defect coming back.

## 4. The volume slider answers a touch like the scrubber

`SystemVolumeSlider` gains what `ScrubberBar` has: a haptic on contact, and the
track growing under the finger. Self-contained — it touches no other view.

## 5. The accent colour becomes white, app-wide

The current accent is `rgb(0.776, 0.294, 0.820)` — the purple-pink. It changes
at the asset, once, so every user changes together: the Jamendo genre chips and
save button, `ProminentActionButton`, `DriveFoldersView`, the queue pills, the
queue button.

**White is invisible on light backgrounds, and three of those places sit on
one.** The asset change alone is therefore not the whole job:

- `ProminentActionButton` fills a capsule with the accent and draws its label on
  top — white on white, and a button nobody can see
- `JamendoDiscoveryView`'s genre chips use the accent as the selected fill,
  against `tertiarySystemFill` unselected. This is the exact pair that already
  shipped invisible once, at 0.12 opacity, and white would be worse
- `JamendoResultRow`'s save button tints its `plus.circle` with the accent

Those three need their own treatment — a dark fill with a light label, or the
label carrying the state instead of the fill. **Changing the asset without
touching them ships three invisible controls**, and that is the failure this
section exists to prevent.

In the player, white is correct and needs nothing: it sits over artwork that the
darkening overlay already keeps dark.
