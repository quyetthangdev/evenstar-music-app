# The queue view — Design

**Date:** 2026-08-10
**Status:** approved
**Supersedes part of:** `2026-08-09-shuffle-design.md`

## Goal

Show what is playing next, let it be reordered, and give shuffle and repeat the
home Apple Music gives them — inside the queue, not permanently parked in the
player.

## Where this came from, and what it corrects

The shuffle đợt shipped shuffle and repeat as a pill row sitting under the
volume slider, visible at all times. Shown the Apple Music screenshot again, the
user pointed out what it actually contains: **one icon** below the volume
slider; tapping it collapses the artwork into a header line and reveals the
options and the queue beneath it. The options are not permanent furniture.

The previous spec had already written the principle down — *"the queue replaces
the artwork rather than stacking below it; imitating it properly means imitating
that decision too"* — and then scoped the queue out and put the pills in the
nearest free space. This design puts them where they belong.

**The pill row moves. It is not rebuilt.** `NowPlayingContent.pill(...)` and its
two callers survive intact; only their container changes.

## What the user sees

A `list.bullet` glyph below the volume slider, trailing-aligned. Tapping it
switches the player into **queue mode**:

| | Normal | Queue mode |
|---|---|---|
| Artwork region | full-bleed artwork | header line: 44pt artwork, title, artist |
| Below it | title block | the pill row, then **Tiếp theo** |
| Bottom | scrubber · transport · volume · icon | unchanged, identical position |

Everything from the scrubber down holds still across the switch. Only the region
above it changes, which is what makes the transition read as one panel swapping
rather than the screen rearranging.

**The title block is hidden in queue mode**, not merely pushed around: the
header line already carries the title and artist, and showing both would print
the same two strings twice on one screen. It is the only element of the
permanent stack that queue mode removes, which is also what buys the list its
room.

Tapping a row jumps to that track. Dragging a row reorders what is coming.

## The list shows only what is coming

**Tiếp theo** holds the tracks *after* the playing one — Apple's "Continue
Playing", and the same slice `applyShuffleToTail` already operates on.

That choice pays twice. It matches the screenshot, and it means every drag lands
inside the tail, so **`queueIndex` never has to be recomputed**. The playing
track cannot move, because it is not in the list.

An empty tail — nothing queued, or the last track playing — shows a single line
saying so rather than an empty region.

## Reordering, and why it costs nothing structurally

**Turning shuffle off restores the original order and discards a manual
reorder.** A drag edits the shuffled arrangement; it goes when that arrangement
goes.

This is the decision that keeps the design cheap. The whole-branch review of the
shuffle đợt warned that `queue` and `unshuffledQueue` are two parallel arrays
held equal only by every mutation site remembering to touch both, and named
queue reordering as the thing to fix before. Under this ruling, **a reorder
touches `queue` alone**. The invariant that matters is that the two hold the
same *set*, not the same order, and a permutation cannot change a set. The
warned-about risk does not arrive.

The rejected alternative — a manual order that survives the shuffle toggle —
would have required defining where a track dragged in the shuffled order lands
in the original one. The two lists have different orders and no correspondence
between positions, so there is no answer that is not arbitrary.

**Turning shuffle *on* after a reorder needs no special case, and this is worth
stating because it looks like it should.** `toggleShuffle()` captures whatever
`queue` currently holds as the order to restore to, so a manual arrangement made
while unshuffled becomes the thing shuffle undoes back to. That falls out of the
existing code rather than being added to it: the "original order" was never
defined as the album's, only as whatever was there before the shuffle.

## Two new methods on `PlaybackService`

```swift
/// Reorders the upcoming tracks. Offsets are into the tail, not the queue.
func moveUpcoming(from source: IndexSet, to destination: Int)

/// Jumps to an upcoming track, keeping the queue as it stands.
func playUpcoming(at offset: Int)
```

Both take offsets **into the tail**, so the view never does index arithmetic
against `queueIndex` and cannot get it wrong. The service converts.

`playUpcoming` exists rather than reusing `play(_:in:)` because that method
rebuilds the queue from its argument and, when shuffle is on, reshuffles the
tail and resets `unshuffledQueue`. Tapping row three would silently reshuffle
everything below it.

## Where the mode lives

`PlayerCard` owns a `showingQueue` flag beside `progress`. It resets when the
card collapses: the queue is a thing you open while looking at the player, and
reopening the player later should show the artwork, not whatever was on screen
last time.

## Out of scope

Swipe-to-remove from the queue — removing a track from the queue without
deleting it from the library is a new operation, and it would touch both arrays,
which is exactly what this design avoids. Apple's other two icons, lyrics and
AirPlay: the app has nothing to put behind either.

**Autoplay (∞) remains out**, for the reason the shuffle spec gave: it appends
tracks *similar* to what played, and no source this app has exposes similarity.

## Testing

The two new service methods are pure queue arithmetic and test without a view:

- a drag leaves the playing track and `queueIndex` untouched
- a drag preserves the set of queued tracks — same multiset, new order
- offsets are interpreted against the tail, not the whole queue: a drag of the
  first upcoming track must move the track at `queueIndex + 1`
- tapping the third upcoming row plays that track and **does not** reshuffle or
  reset `unshuffledQueue`
- turning shuffle off after a reorder still restores the original order
- a reordered queue survives a save/restore round trip
- an empty tail: both methods are no-ops rather than crashes

## Risks

**Two panels sharing one region will fight over height.** The header, pills and
list must fit where the artwork was, and `PlayerCard.contentBudget` documents
that this screen has about 20pt of slack and has been overrun twice. The list
scrolls, so it absorbs the difference — but the header and pill row above it do
not, and they are what to measure on a 4.7" screen at a large Dynamic Type size.

**The mode switch is a new animation on a screen whose morph is already
delicate.** `PlayerCard` interpolates every collapsed dimension from `progress`
and drives the expand with its own springs. A second, independent transition
inside that region is a new opportunity for the two to interfere — worth
watching on device rather than only in the simulator.
