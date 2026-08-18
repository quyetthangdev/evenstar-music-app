# Evenstar — Bottom sheets to iOS standard

**Date:** 2026-08-01
**Author/Owner:** gihubtbe1@gmail.com
**Predecessor:** Phase 2a (Foundation), branch `phase-2a`, 47 tests green
**Scope:** Presentation only. No playback, queue, persistence or import logic changes.

---

## 1. Problem

Evenstar presents exactly two surfaces, and neither behaves the way iOS users expect.

**`NowPlayingView`** is presented with `.fullScreenCover`. It slides up as a separate full screen with square corners, unrelated to the mini player it came from, and **cannot be dismissed by dragging**. The only way out is a small `chevron.down` button in the top-left corner. Every music app on iOS — Apple Music included — lets you swipe down to return.

**`ImportProgressSheet`** is a `.sheet` pinned to `.presentationDetents([.medium])` with no drag indicator. It gives no visual affordance that it is draggable, and its fixed height is too small for its own content: the failure-reason list can overflow and clip, because `ImportError.fileNotAccessible` embeds the filename in its message, so N inaccessible files produce N distinct un-deduplicable reasons. That overflow was found during the Phase 2a final review and parked as item **P2**.

## 2. Goal

Both surfaces behave like standard iOS sheets: rounded corners, a grabber, and drag-to-dismiss — using the system's own presentation mechanics rather than hand-rolled gestures.

## 3. Non-goals

- **The Apple Music matched-geometry morph.** Tapping the mini player in Apple Music grows the 40 pt artwork continuously into the full-size hero, the bar itself becoming the card. `matchedGeometryEffect` does not work across `.sheet` or `.fullScreenCover` boundaries — they are separate presentation hosts — so that effect requires abandoning system presentation for a hand-built `ZStack` overlay with its own drag gesture, rubber-banding and safe-area handling. Explicitly deferred; recorded here so the decision is not re-litigated by accident.
- Blurred artwork-tinted background behind `NowPlayingView`.
- Hiding the mini player while `NowPlayingView` is open.
- Any change to playback, queue, persistence, or import behaviour.

## 4. Design

### 4.1 `LibraryView.swift`

`NowPlayingView`'s presentation changes from `.fullScreenCover` to `.sheet`, carrying:

- `.presentationDetents([.large])` — full height only, matching Apple Music's Now Playing, which has no half-height state
- `.presentationDragIndicator(.visible)`

The import sheet gains:

- `.presentationDetents([.medium, .large])` — replacing the fixed `.medium`, so the user can drag up when the summary is long
- `.presentationDragIndicator(...)` — see §4.3 for why it is conditional

Everything else in the file is untouched, including the `.onChange(of: playback.currentTrack?.id)` that sets `showNowPlaying = false` when playback ends. That continues to work with a sheet.

### 4.2 `NowPlayingView.swift`

- Delete the `handle` computed property (the `chevron.down` button) and its use in `body`. The system grabber replaces it.
- Delete `@Environment(\.dismiss) private var dismiss` — the chevron was its only consumer.
- Increase `.padding(.top, 8)` to `.padding(.top, 24)`. Removing `handle` takes a row out of the `VStack`, and the system grabber occupies roughly 20 pt at the top of the sheet; without the extra padding the artwork would sit under it. The exact value is a judgement call to confirm visually on device — 24 pt is the starting point, not a measured constant.

### 4.3 `ImportProgressSheet.swift`

- **The grabber must be hidden while importing.** `.interactiveDismissDisabled(importer.isImporting)` already blocks dismissal during an import; showing a grabber the user cannot act on is a false affordance. Bind the indicator to the same condition: `.presentationDragIndicator(importer.isImporting ? .hidden : .visible)`.
- **Wrap the summary branch in a `ScrollView`** so the failure-reason list can never clip, whatever detent the sheet is at. This closes parked item P2. Only the `else if let summary` branch is wrapped — the in-progress branch keeps its current centred layout, since a progress bar and one line of text never overflow and centring them inside a `ScrollView` would require extra work for no gain.

The existing 4-reason cap and its `+N more` line stay. The cap keeps the common case tidy; the `ScrollView` and the `.large` detent handle the uncommon one.

## 5. Verification

This is UI work, and per the parent spec's testing strategy SwiftUI views get no unit tests. Verification is:

- Clean build with **zero Swift warnings** (a bar held since Task 7 of Phase 2a)
- **47 tests still passing** — this change must not alter the count in either direction
- Simulator screenshot of the empty library state, unchanged

**Neither sheet can be exercised on the simulator.** `NowPlayingView` requires a track to be playing; `ImportProgressSheet` requires driving the Files-app picker by hand. Both are confirmed only during manual QA on a physical iPhone.

## 6. Known risk

With a sheet, a vertical drag on non-scrollable content dismisses it. `NowPlayingView`'s scrubber sits mid-screen. A horizontal drag scrubs correctly, but a drag that starts with vertical drift may dismiss the sheet instead of seeking.

Apple Music has the same characteristic, so this may be acceptable. It cannot be assessed without a physical device, so it is **not** pre-emptively mitigated. It goes on the QA list as a specific question: *does scrubbing feel reliable, or does the sheet close when you try to seek?* If it does prove annoying, the fix is to constrain the slider's gesture — but that is a change to make with evidence, not in anticipation.

## 7. Files changed

| File | Change |
|---|---|
| `Features/Library/LibraryView.swift` | Two presentation modifiers |
| `Features/Player/NowPlayingView.swift` | Remove chevron handle, `dismiss`, adjust top padding |
| `Features/Import/ImportProgressSheet.swift` | Conditional drag indicator, `ScrollView` wrapper |
| `docs/superpowers/plans/2026-08-01-phase2a-qa-guide.md` | Add the scrubber-versus-sheet-drag question |
