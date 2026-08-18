# Repeat — Design

**Date:** 2026-08-04
**Status:** approved
**Feature:** three-state repeat (off / all / one) for playback

## Goal

Give the player the three repeat modes every music app has — off, repeat the
whole queue, repeat the current track — on one button that cycles between them.

## Scope

**In:** the three modes, their effect on automatic advance and on the Previous
and Next buttons, persistence across launches, one button in the full-screen
player.

**Out, deliberately:** shuffle (a separate axis, its own đợt), A–B section
looping (a different feature that needs scrubber markers), and repeat from the
lock screen or Control Center (`MPRemoteCommandCenter.changeRepeatModeCommand`).
The lock screen keeps exactly the commands Phase 1 gave it.

## The central decision: automatic advance is not the Next button

`handleFinish()` currently delegates to `next()`:

```swift
private func handleFinish() {
    if queueIndex + 1 < queue.count {
        next()
    } else {
        stopPlayback()
    }
}
```

That delegation must end. Repeat-one applies when a track runs out by itself
and does **not** apply when the user presses Next — pressing Next under
repeat-one moves to the next track, as it does in Apple Music. Left as it is,
turning on repeat-one would make the Next button replay the current track and
look broken.

So `handleFinish()` gets its own branch on the mode, and `next()` keeps meaning
"the user asked to move on".

## Behaviour table

This table is the specification. Every cell is a test.

| Situation | Off | All | One |
|---|---|---|---|
| Track ends by itself, not the last track | advance | advance | **replay it** |
| Track ends by itself, last track | stop | **wrap to index 0** | **replay it** |
| Next pressed, not the last track | advance | advance | advance |
| Next pressed, last track | stop | wrap to index 0 | wrap to index 0 |
| Previous pressed, `position <= 3`, index 0 | restart | **wrap to last** | wrap to last |
| Previous pressed, `position <= 3`, index > 0 | step back | step back | step back |
| Previous pressed, `position > 3` | restart | restart | restart |

Two things the table settles:

- **`restartThreshold` (3s) outranks the repeat mode.** Past three seconds,
  Previous always means "restart this track", exactly as it does today.
- **Next at the last track wraps whenever the mode is not off**, including
  under repeat-one. Repeat-one does not mean the queue has an end; it means an
  unattended track repeats.

Replaying a track under repeat-one resets `playCountedForCurrent` to `false`,
so each pass counts as a play once it crosses 30 seconds. A track left on
repeat overnight is genuinely being played repeatedly, and the play count
should say so.

## State

```swift
enum RepeatMode: String {
    case off, all, one
}
```

Not `CaseIterable`. The cycle order is behaviour and belongs in an explicit
`switch`, not in the order the cases happen to be declared — reordering the
declaration for readability would silently reorder what the button does.

Stored on `PlaybackState` (SwiftData) beside `queueTrackIDs` and `queueIndex`,
as a `String` with the default `"off"`. An added property with a default is a
lightweight migration; SwiftData handles it without a migration plan.

Considered and rejected: `@AppStorage` / `UserDefaults`. The repeat mode is
part of the playback state, and putting it in a second store would split one
concept across two — restoring a session after relaunch would have to read from
both.

`PlaybackService` exposes:

```swift
private(set) var repeatMode: RepeatMode
func cycleRepeatMode()   // off → all → one → off
```

`cycleRepeatMode()` persists through `deferPersist()`, matching every other
mutation on a tap path — a SwiftData write between the tap and the next render
is felt as button latency.

## The cross-file consistency point

`NowPlayingContent` and `MiniPlayerChrome` each compute the same rule
independently today:

```swift
.disabled(playback.queueIndex >= playback.queue.count - 1)
```

With repeat on, the last track is no longer the end, so Next must stop being
disabled there. Two files deriving one rule is the shape of the defect that
shipped in Đợt A, where two screens belonged to no task. The rule moves onto
the service:

```swift
var canGoNext: Bool {
    !queue.isEmpty && (queueIndex + 1 < queue.count || repeatMode != .off)
}
```

Both call sites use it. Neither recomputes it.

## UI

A row below the transport row in `NowPlayingContent`, so the three transport
buttons keep their size and spacing and there is room for shuffle later.

- `repeat` for off and all; `repeat.1` for one, swapped with
  `.contentTransition(.symbolEffect(.replace))` the way play/pause swaps.
- Off renders `.secondary`; all and one render in the accent colour, which is
  what distinguishes an armed mode from a resting one. The glyph alone cannot:
  `repeat` and `repeat.1` differ, but off and all share a glyph.
- The button takes `.transportToggle(trigger:)` — the same squeeze, rebound
  spring, halo and haptic as play/pause, so it answers a press in the language
  the other buttons already speak, without a new animation.

The mini player is unchanged. It has an artwork tile, a title and two buttons in
54pt; a third would squeeze the title, and repeat is set once and forgotten
rather than pressed often.

**To verify by screenshot, not by build:** `TransportButtonStyle` applies
`foregroundStyle(.primary)` to the label from outside, and the accent tint is
applied inside the label. The inner one should win, but that is a rendering
claim, and a clean build proves nothing about it.

## Testing

The logic is nearly pure and the harness exists: `MockAudioPlayer`,
`simulateFinish()`, `tickForTesting()`, `InMemoryLibrary`.

One test per row-and-column of the behaviour table, plus:

- repeat-one replays and increments the play count a second time past 30s
- `cycleRepeatMode()` runs off → all → one → off
- the mode survives `restoreFromPersistedState()`
- `canGoNext` is false only at the last track with the mode off

Note for whoever writes these: `simulateFinish()` hops through
`Task { @MainActor in ... }`, so a test that drives it must be `async` and
yield before asserting.
