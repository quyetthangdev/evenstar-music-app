# Evenstar concurrency + persistence audit (phase-2a, read-only)

Scope read: `Services/PlaybackService.swift` (full, 1216 lines), `Services/LibraryService.swift`,
`Services/ImportService.swift`, `Services/DriveLibraryService.swift`, `Services/JamendoLibraryService.swift`,
`Services/StreamingAudioPlayer.swift`, `Services/RoutingAudioPlayer.swift`, `Services/AudioPlayerProtocol.swift`,
`Services/JamendoPreviewPlayer.swift`, `Services/NowPlayingService.swift`, `Services/RemoteCommandsBridge.swift`,
`Utilities/ArtworkStore.swift`, all `@Model` types (`Track`, `DriveTrack`, `JamendoTrack`, `PlaybackState`,
`DriveFolder`), `App/EvenstarApp.swift`, `App/RootView.swift`, plus git history for every model file and
`Features/Account/AccountView.swift` for its `@concurrent` usage. `MockAudioPlayer.swift` and
`JamendoPreviewPlayerTests.swift` read to check whether test doubles could violate the isolation
`JamendoPreviewPlayer` assumes.

This codebase is unusually well self-documented: most of the classic bugs an audit like this looks for
(retain cycles on `Timer`/KVO/NotificationCenter, stale async callbacks racing a superseded load, id churn
on a `.unique` collision, double-save races) are already identified, fixed, and explained in doc comments
with a named commit (`3d255f5`, `1902bbe`, etc.). The findings below are what is left after verifying those
claims rather than trusting them.

---

## Findings, ranked by likelihood × severity

### 1. `ImportService` performs an O(library size) full-table fetch per imported file — main-thread UI freeze during bulk import, quadratic in library size

- `Services/ImportService.swift:130-134` calls `library.findExistingTrack(title:artist:duration:)` once per
  file in the batch, inside the `for url in urls` loop in `importFiles(at:)` (`ImportService.swift:77-101`).
- `Services/LibraryService.swift:196-209` — `findExistingTrack` builds `FetchDescriptor<Track>()` with **no
  predicate and no fetch limit**, fetches and materializes *every* `Track` row in the library into memory,
  then does the actual dedup comparison (`title`/`artist`/`duration`) in a linear Swift scan.
- Both `ImportService` and `LibraryService` are `@MainActor`, so this fetch runs synchronously on the main
  thread, once per file. Importing N files into a library of M existing tracks is O(N×M) SwiftData fetches
  and O(N×M) full-row materializations, all on the main actor.
- **What the user experiences:** the import progress UI stalls/hangs, worse as the library grows — the
  100th file in a batch re-fetches and re-scans all of the tracks that came before it *and* the whole
  pre-existing library, every time. On a library of a few thousand tracks (the scale Phase 2's local library
  explicitly targets) this is a visible freeze, not a theoretical one, and it degrades further every time the
  library grows. No crash, but the worst "likelihood × severity" combination in this audit: it fires on the
  ordinary, common-case path (any multi-file import) and gets worse over time rather than staying constant.
- Fix direction: predicate-filter the fetch (e.g. narrow by rounded duration via `#Predicate` before the
  Swift-side title/artist comparison, or maintain a single in-memory index for the duration of one
  `importFiles` batch instead of re-querying per file).

### 2. `JamendoPreviewPlayer`'s `MainActor.assumeIsolated` is safe only by an unenforced contract with `StreamingAudioPlayer`'s threading — a future `AudioPlayerProtocol` conformer or a threading change crashes it, not a compile error

- `Services/JamendoPreviewPlayer.swift:62-71`:
  ```swift
  self.player.didFinishCallback = { [weak self] in
      MainActor.assumeIsolated { self?.stop() }
  }
  self.player.didFailCallback = { [weak self] error, url in
      MainActor.assumeIsolated { ... }
  }
  ```
- `AudioPlayerProtocol.didFinishCallback`/`didFailCallback` (`Services/AudioPlayerProtocol.swift:8-25`) are
  plain `(() -> Void)?` / `((Error, URL) -> Void)?` closures with **no isolation annotation in the protocol
  itself** — nothing in the type system requires a conformer to invoke them on the main thread.
- Today this is safe only because the concrete conformer actually used here, `StreamingAudioPlayer`, always
  routes both callbacks through its private `onMain(_:)` helper before invoking them
  (`StreamingAudioPlayer.swift:194-207`, `223-226`, `263-269`), and `onMain` dispatches to
  `DispatchQueue.main` when not already on the main thread — which does correspond to `MainActor`'s
  executor in this app (no custom executor is installed).
- Contrast with `PlaybackService`'s own use of the *same* protocol, which wraps identically-shaped callbacks
  in `Task { @MainActor in ... }` (`PlaybackService.swift:189-194`) — a safe hop under any calling thread,
  not an assumption about one.
- **Failure mode if the contract is ever broken** (a new `AudioPlayerProtocol` conformer used for previews,
  or a refactor of `StreamingAudioPlayer` that fires a callback before/without the `onMain` hop — e.g.
  directly from a KVO or notification thread): `MainActor.assumeIsolated` traps with a fatal runtime
  precondition failure. That is a hard crash, indistinguishable in symptom from a random background crash,
  and the compiler will not catch it because the whole point of `assumeIsolated` is to assert past what the
  compiler can verify.
- Currently **not reachable** with the code as it stands (only `StreamingAudioPlayer` is ever handed to
  `JamendoPreviewPlayer`, and its test double `MockAudioPlayer` fires callbacks synchronously from
  `@MainActor` test methods — see `EvenstarTests/MockAudioPlayer.swift:49-52,65-72` and
  `EvenstarTests/JamendoPreviewPlayerTests.swift`, all `@MainActor`). This is a latent landmine, not an
  active bug — ranked here because the failure mode (hard crash) is severe even though present-day
  likelihood is low. Recommend replacing with the same `Task { @MainActor in ... }` pattern
  `PlaybackService` uses, which is equally cheap here (nothing time-critical depends on synchronous
  delivery) and removes the crash risk entirely.

### 3. `DriveLibraryService.scan()` fetches every `DriveTrack` row in the entire library on every single folder scan

- `Services/DriveLibraryService.swift:167`: `let existingAnywhere = try library.context.fetch(FetchDescriptor<DriveTrack>())`
  — unfiltered, fetches every `DriveTrack` row across *all* linked folders, not just the folder being
  scanned, into memory as an array, then rebuilt into a `[String: DriveTrack]` dictionary
  (`DriveLibraryService.swift:168`).
- This is deliberate and well-reasoned in the surrounding comment (`fileID` is `.unique` store-wide because
  Drive files can have multiple parents, so a folder-scoped existence check would miss a fileID already
  known under a different folder and mint a duplicate row with a fresh `id`, silently orphaning
  `PlaybackState`'s persisted queue references — see finding 5). The design intent is sound; the cost is
  still O(total Drive library size) on every scan, run on `@MainActor`.
- **What the user experiences:** for a user with several large linked Drive folders, every rescan (manual
  pull-to-refresh, or any re-link flow) does a full-table materialization of every `DriveTrack` on the main
  actor in addition to the already-inherent network listing cost. Less severe than finding 1 because Drive
  scanning is already network-bound (the `await client.listAudioFiles` call dwarfs this in practice for any
  real folder), but it is still avoidable main-actor O(n) work on a path a user can trigger repeatedly.

### 4. Persist-on-tick does synchronous `ModelContext.save()` (disk I/O) on the main actor on a 0.5s timer for the entire duration of playback

- `PlaybackService.swift:1003-1040` (`tickPosition()`) runs on a `Timer` firing every 0.5s
  (`PlaybackService.swift:1042-1050`, `startPositionUpdates()`), hops through `Task { @MainActor in
  self.tickPosition() }`, and calls `persistThrottled()` → `persistImmediately()` → `try? library.save()`
  (`PlaybackService.swift:1057-1074`) at most once per `persistInterval` (default 5s), plus unconditionally
  on every `pause()`, `resume()`, `seek()`, track advance, failure, and the 30-second play-count write
  inside `tickPosition()` itself (`PlaybackService.swift:1009-1014`, also a synchronous `library.save()`).
- All of this is synchronous SwiftData `ModelContext.save()` — real disk I/O — invoked directly on the main
  actor, inside a timer callback, for the whole time a track is playing.
- **What the user experiences:** in the common case (a small, low-write-count `PlaybackState`/`Track` diff)
  this is fast enough not to be felt — SwiftData single/few-row saves are typically sub-millisecond to a
  few milliseconds. It is flagged here because it is squarely the "file I/O that should be off the main
  actor" pattern the review is looking for, and its cost is not bounded by anything in this file: a large
  pending change set in the shared `ModelContext` at the moment a tick fires (e.g. a big import or Drive
  scan racing against playback) would be persisted synchronously on the main thread on this same call,
  which could turn a routine tick into a visible stutter. Lower severity than findings 1–3 because it is
  the existing, working design for a feature (position/play-count persistence) that has clearly been
  tuned for correctness already (see `persistImmediately()`'s extensive doc comment on why captures are
  forbidden) — flagging as worth watching if `ModelContext` write volume grows, not as a live incident.

### 5. `DriveTrack`/`JamendoTrack` `.unique`-collision `id` churn silently orphaning `PlaybackState`'s persisted queue — verified as *already mitigated*, not live

- Both models document (`DriveTrack.swift:11-23`, `JamendoTrack.swift:12-24`) that on a `.unique`-attribute
  collision (same `fileID`/`jamendoID` inserted twice), SwiftData's upsert keeps *a* row but not necessarily
  either caller's original `id`, and since `PlaybackState` persists queue membership as bare `UUID`s with no
  relationship back to these tables, an `id` that moves underneath a queued reference silently drops that
  track from any future restore.
- I checked whether the mitigations claimed actually hold:
  - `DriveLibraryService.scan()` (`DriveLibraryService.swift:181`) only inserts a fresh `DriveTrack` for a
    `fileID` **not already known anywhere** (`existingByFileIDAnywhere[file.id] == nil`) — it never
    reconstructs-and-inserts for a known `fileID`, so the collision path this guards against cannot be hit
    from a scan. Confirmed correct.
  - `JamendoLibraryService.save()` (`JamendoLibraryService.swift:94-130`) coalesces concurrent saves for the
    same `jamendoID` through `inFlightSaves`, checked and populated with no `await` in between
    (`JamendoLibraryService.swift:99-124`), so two overlapping `save()` calls for the same id cannot both
    fall through and both insert. Confirmed correct — this is the fix from commit `1902bbe`.
- **Verdict:** this is a real historical class of bug (per the commit messages, it was live before `1902bbe`)
  that is now closed at both call sites that could trigger it. No further finding here beyond noting it was
  verified rather than assumed.

### 6. `queue`/`unshuffledQueue` "same-set" invariant — verified to hold at all seven mutation sites; one site is fragile-but-currently-safe

The task's premise asked me to check this rather than trust the doc comments. I traced every assignment site:

| Site | What it does | Holds? |
|---|---|---|
| `play(_:in:)` (`:199-217`) | `queue = queueTracks`; if shuffled, `unshuffledQueue = queueTracks` before reshuffling `queue`'s tail | Yes — both set from the same source array |
| `toggleShuffle()` off-branch (`:270-309`) | `queue = unshuffledQueue` (permutation search for playing id, with a documented, tested fallback if not found) | Yes |
| `toggleShuffle()` on-branch (`:310-315`) | `unshuffledQueue = queue` before reshuffling `queue`'s tail | Yes |
| `moveUpcoming(from:to:)` (`:358-368`) | Permutes `queue`'s tail only, `unshuffledQueue` untouched | Yes — a permutation cannot change set membership |
| `playUpcoming(at:)` (`:383-394`) | Only moves `queueIndex`, no array mutation | N/A |
| `handleTrackDeleted(_:)` (`:520-569`) | `queue.remove(at:)` + `unshuffledQueue.removeAll { id match }` | Yes — guarded on the track already being in `queue`; `unshuffledQueue` is either a permutation of `queue` (shuffled) or empty (not shuffled), so the `removeAll` is a no-op or removes exactly one matching element either way |
| `restoreFromPersistedState()` (`:589-682`) | `unshuffledQueue` and `queue` are resolved via **two separate** `state...TrackIDs.compactMap { resolveTrack(byID:) }` calls | Yes, but conditionally |
| `stopPlayback()` (`:809-845`) | Both cleared to `[]` | Yes |

The one site worth flagging on its own, because it is the only one that does not derive one array from the
other in the same expression: **`restoreFromPersistedState()`** resolves `unshuffledQueue` and `queue`
independently from two persisted `[UUID]` lists (`PlaybackState.swift:8,35`). This is safe **only because**:
(a) the two persisted ID lists are themselves permutations of the same set — true only if every write path
that populates `PlaybackState.unshuffledQueueTrackIDs`/`queueTrackIDs` (i.e. `persistImmediately()`,
`PlaybackService.swift:1063-1074`) is itself invariant-preserving, which the table above confirms; and (b)
`resolveTrack(byID:)` is called for both lists with **no `await` between the two `compactMap` calls**
(`PlaybackService.swift:600,602`), so nothing else can mutate the library's `Track`/`DriveTrack`/`JamendoTrack`
rows between the two resolutions within this single synchronous stretch of a `@MainActor` method. If a future
change introduced an `await` between those two lines (e.g. batching the id resolution through an async
fetch), a delete racing the restore could resolve the two lists against different library states and break
set-equality — currently that cannot happen. **No live bug; flagging the exact place a future edit would
have to preserve this property.**

---

## Schema migration safety

Checked every `@Model` type's stored properties against "does an existing user's on-disk store, written
before this property existed, still open" — i.e. every non-`Optional` property needs a **property-level**
literal default (`var x: T = value` on the declaration itself), not merely a default parameter on the
memberwise `init`, which SwiftData's lightweight migration does not consult.

- **`Track`** (`Models/Track.swift`) — one commit ever (`53cca5c`), never modified since. Every property
  existed from the schema's introduction; no property was added to an already-shipped shape. Optional
  properties (`trackNumber`, `discNumber`, `sampleRate`, `bitDepth`, `lastPlayedAt`) are migration-safe by
  construction regardless. Non-optional properties (`title`, `artistName`, `albumTitle`, `durationSeconds`,
  `relativePath`, `format`, `dateAdded`, `playCount`) have **no property-level default** — currently safe
  only because nothing has ever been added after the fact, **not** because the declarations themselves would
  protect a future addition.
- **`DriveTrack`** (`Models/DriveTrack.swift`) — two commits; the second (`3d255f5`) is documentation-only
  (verified via `git show`), no property added. Same non-optional-without-inline-default shape as `Track`.
- **`JamendoTrack`** (`Models/JamendoTrack.swift`) — two commits; the second (`1902bbe`) is also
  documentation-only (verified via `git show`), no property added. Same shape.
- **`DriveFolder`** (`Models/DriveFolder.swift`) — one commit, never modified.
- **`PlaybackState`** (`Models/PlaybackState.swift`) — three commits, and this is the one model that *has*
  had properties added after its initial shape: `repeatModeRaw` (added in `70e9983`) and `isShuffled` /
  `unshuffledQueueTrackIDs` (added in `6a0752d`) each correctly received a property-level literal default
  (`= "off"`, `= false`, `= []` at `PlaybackState.swift:19,27,35`) exactly where migration safety requires
  it, with doc comments explicitly naming *why*. This is the correct pattern, applied correctly, every time
  it has actually been needed so far.

**Verdict:** every property in every `@Model` type is migration-safe as of this snapshot — but only because
`Track`, `DriveTrack`, `DriveFolder`, and `JamendoTrack` have never had a property added post-launch, not
because their declarations would survive one. `PlaybackState` is the only model that has been through this
before, and it was done correctly both times. **The load-bearing rule for the next schema change is: any new
non-optional property on any `@Model` must carry its default on the property declaration itself
(`var x: T = ...`), not only in the initializer** — the discipline exists and has a track record, it is just
not yet enforced by anything other than habit for three of the five models.
