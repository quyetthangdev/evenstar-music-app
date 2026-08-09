# Shuffle, and a pill row to hold it — Design

**Date:** 2026-08-09
**Status:** approved

## Goal

Play a queue in a random order. The app has had `RepeatMode` since Phase 2 and
a button to cycle it; it has never had shuffle at all — not a line of it
anywhere in the codebase.

## Where this came from

An Apple Music screenshot of the expanded player's queue view: a compact
header, a row of four capsule buttons (shuffle, repeat, autoplay, and a
fourth), and a reorderable **Continue Playing** list.

That picture is three separable systems: shuffle in the playback service, a
queue screen that displaces the artwork, and a queue-mutation API for
reordering. **This đợt is the first only**, plus the control row that shuffle
needs somewhere to live. The queue screen is a later đợt and this design is
written to make it cheaper, not to pre-empt it.

**Autoplay — the ∞ pill — is out, and not for scheduling reasons.** It appends
tracks *similar* to what just played, which requires similarity data. Evenstar
has local files, Google Drive and Jamendo, and none of them expose anything of
the kind. "Keep playing random tracks from the library" is a different feature
wearing that icon, and shipping it as autoplay would misdescribe what the app
does.

## What the user sees

The lone repeat button becomes **two capsule pills, centred**: shuffle, then
repeat.

- Off: muted fill, secondary glyph
- On: accent fill, white glyph
- Repeat still cycles `off → all → one`; only its shell changes

Apple's row runs four pills to the full width. Two icon-only buttons stretched
across half a screen each read as empty, so these keep their natural width and
centre instead. The capsule itself is the part being copied, and it is the part
that matters: it is what says on or off. `JamendoDiscoveryView`'s genre chips
shipped that distinction as a 0.12-opacity fill against `tertiarySystemFill`
and it was invisible — the same mistake is available here and is avoided the
same way, with an accent fill.

## The shuffle model

**Shuffle the tail** — the tracks after the currently playing one — not the
whole array.

```
before:  [played] [PLAYING] [a] [b] [c] [d]
after:   [played] [PLAYING] [c] [a] [d] [b]
                            └── only this ──┘
```

Three reasons, and each is load-bearing:

1. It is what the screenshot actually shows. The list that reorders is
   **Continue Playing**, which is precisely the tail.
2. `queueIndex` does not move, so the whole class of off-by-one reindexing
   bugs never arises.
3. `previous()` keeps its meaning. The history in front of the index is
   untouched.

Turning shuffle **off** restores the original order, then finds the playing
track in it to reset `queueIndex` — by then the track has drifted, because
playback continued through the shuffled tail. A track that is no longer in the
restored order at all (deleted while playing) clamps the index to a valid
position rather than trapping the queue.

**Starting a new queue while shuffle is on shuffles its tail too.** Tapping one
track of an album and having the rest follow at random is the behaviour being
copied; without this, shuffle would silently switch itself off every time the
user picked a song.

## Persistence

Two new properties on `PlaybackState`:

```swift
var isShuffled: Bool = false
var unshuffledQueueTrackIDs: [UUID] = []
```

**Both carry literal defaults, and that is a requirement rather than a
convenience.** `PlaybackState.repeatModeRaw` documents why in that same file: a
default is what lets SwiftData migrate rows written before the property existed
without a migration plan. A property added without one is an app that will not
launch for anyone who has used it before — the failure `I9` exists to catch.

The shuffled order needs no new storage: it *is* `queue`, and `queueTrackIDs`
already persists that. What must be stored is the **original** order, or
turning shuffle off after a relaunch would have nothing to restore.

## Two constraints this design is shaped around

**The expanded player has no vertical room.** `PlayerCard.contentBudget`
documents ~380pt of stack against ~400pt available — about 20pt, which one step
of Dynamic Type already exceeds. Its own comment records the same mistake being
made twice: raising it for a new element's height and forgetting the 24pt
`VStack` gap that comes with it.

So the pill row **replaces** the repeat row at the same height: 36pt frame plus
4pt top padding, exactly what is there now. The pills grow sideways, never
down. `contentBudget` is not touched, and this design does not get to plead
that it only needed a few points.

**36pt is below HIG's 44pt hit region** — a violation the current repeat button
already ships. The fix is the one `NowPlayingContent.jamendoCredit` already
uses for the same collision: padding, `contentShape`, then negative padding, so
the hit rectangle reaches 44pt while the frame reported to the layout stays 36.
Nothing about the budget changes, and the buttons stop being under-sized.

## Testing

`Array.shuffled()` draws from the system generator, which cannot produce a
deterministic test. `PlaybackService` takes an injected `RandomNumberGenerator`
defaulting to the system one: tests seed it, production is unchanged.

- the playing track does not move, and the head of the queue is byte-identical
- the tail is a permutation of what it was — same multiset, different order
- turning shuffle off restores the original order **and** points `queueIndex`
  at the track that is playing
- a track deleted mid-shuffle leaves a valid index rather than a trap
- a new queue started while shuffle is on comes out shuffled
- state survives a save/restore round trip, including the unshuffled order
- an empty queue and a one-track queue are no-ops, not crashes
- `repeatMode` still cycles `off → all → one` through the new shell

## Risks

**Shuffling the tail is not what everyone means by shuffle.** Someone who
expects the whole queue reordered, history included, will find the first few
entries stubbornly in album order. That is the trade for keeping `previous()`
honest, and it matches the screenshot; it is written here so a later reader
knows it was chosen rather than overlooked.

**Interaction with `RepeatMode.all` is not special-cased.** Wrapping past the
end of a shuffled queue replays the same shuffled order rather than reshuffling.
Apple reshuffles on wrap. Doing the same means a queue that mutates itself
during playback, which is worth its own decision with the queue screen in front
of us rather than guessed at now.
