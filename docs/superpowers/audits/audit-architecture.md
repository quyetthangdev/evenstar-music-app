# Evenstar — architecture, structure and maintainability audit

Branch `phase-2a`. 118 Swift files (72 source, 46 test), 419 tests.
Read-only audit; nothing was built, run, or modified.

---

## 0. Summary

This is a well-above-average codebase for a first iOS project, and the gap
between it and a typical solo SwiftUI app is not in the UI — it is in the
service layer. The composition root is clean and singleton-free, every service
takes its dependencies as arguments, the audio-failure handling is better than
most shipping music apps, and the habit of lifting a rule out of a view so it
can be pinned by a test (`PlayerSubtitle`, `LibraryGrouping`, `artworkGeometry`,
`settleVelocity`) is applied consistently. The test suite is behavioural, not
implementation-shaped, and has essentially no assertion-free tests.

The structural problems cluster in three places:

1. **`Playable` is shaped for SwiftData rows.** Apple Music cannot conform to
   it. The abstraction that made Drive and Jamendo nearly free will not make
   Apple Music free, and discovering that mid-integration means forking the most
   valuable file in the project.
2. **Several multi-file contracts are enforced by prose rather than by
   construction** — the 440pt content budget, the `queue`/`unshuffledQueue`
   permutation invariant, the `expansion.progress` mirror, and "tell playback
   before you delete". Each has already failed at least once, and each is
   documented at length in the comment where it failed.
3. **The comments have begun to rot at their cross-references.** Four backticked
   symbol names in load-bearing docs point at symbols that no longer exist.

Rankings are by expected pain over the next six months given the stated roadmap:
endless playback, then Apple Music.

---

## 1. Findings, ranked

### F1 — `Playable` cannot describe an Apple Music track. (highest)

**What is wrong.** `Services/Playable.swift:12`:

```
protocol Playable: AnyObject {
    var id: UUID { get }
    …
    var playCount: Int { get set }
    var lastPlayedAt: Date? { get set }
    func playbackURL() -> URL
}
```

Four requirements each break for MusicKit:

- `AnyObject` — MusicKit's `Song` is a value type. It cannot conform.
- `id: UUID` — a catalogue identifier is a `MusicItemID`, i.e. a `String`. This
  is not hypothetical: it has *already* excluded a type. `JamendoCatalogueTrack`
  (`Services/JamendoClient.swift:5`) is a struct with a `String` id and cannot
  conform, which is the entire reason `JamendoPreviewPlayer` exists as a second
  audio path (see F5).
- `playCount`/`lastPlayedAt` as `{ get set }` — these are settable because
  `PlaybackService.tickPosition()` mutates the SwiftData row in place
  (`PlaybackService.swift:1009-1013`). Apple Music owns its own play history;
  there is no writable row.
- `playbackURL() -> URL` — Apple Music plays through
  `ApplicationMusicPlayer`/`MusicItemID`, never a URL handed to AVFoundation.
  `RoutingAudioPlayer` selects an engine *by inspecting the URL*; a catalogue ID
  has no URL to inspect. The protocol's non-throwing signature has already
  forced one force-unwrap — `JamendoTrack.playbackURL()` is
  `URL(string: audioURLString)!` (`Playable.swift:66`), held up only by an
  invariant maintained in a different file.

The persistence side has the matching defect, and it is worse than it looks.
`Models/PlaybackState.swift:6-8` stores `queueTrackIDs: [UUID]` with no source
tag and no relationship, so `PlaybackService.resolveTrack(byID:)`
(`PlaybackService.swift:691`) linear-probes three tables in turn. Both
`Models/DriveTrack.swift:10-23` and `Models/JamendoTrack.swift:14-24` carry
~15-line comments describing the *same* latent bug this causes: an
`@Attribute(.unique)` upsert on collision can re-mint `id`, silently orphaning
the persisted queue. Two long doc comments describing one structural defect is
the clearest available signal that the abstraction is incomplete.

**Cost of leaving it.** The Apple Music integration cannot reuse queue, repeat,
shuffle, restore, play-counting or the lock-screen push — precisely the code
`Playable` exists to share, and precisely the code the 419 tests cover. Both
escapes are bad: mint a shadow local `@Model` row for every Apple Music track (a
permanent two-way sync problem), or fork `PlaybackService`.

**Smallest fix**, before Apple Music work starts, in three independent steps,
none of which changes behaviour today:

1. Drop `AnyObject` and the two settable properties. Move play counting behind a
   collaborator — `PlaybackService` calls `history.recordPlay(of: track.id)`
   instead of mutating a row — so a source with no writable row simply no-ops.
   `Playable` becomes a read-only identity protocol a struct can satisfy, which
   also lets `JamendoCatalogueTrack` conform and collapses F5.
2. Replace `func playbackURL() -> URL` with `var source: PlaybackSource { get }`,
   `enum PlaybackSource { case localFile(URL), stream(URL), catalogue(String) }`.
   `RoutingAudioPlayer` switches on the case instead of sniffing a URL — which is
   strictly more honest than what it does now — and gains a third case cleanly.
3. Persist `(sourceKind, idString)` pairs in `PlaybackState` rather than bare
   `UUID`s, and turn `resolveTrack(byID:)` into a resolver registry keyed by
   source kind. The three-probe chain disappears, the fourth source becomes a
   registration rather than an edit, and the `@Attribute(.unique)` re-mint hazard
   documented in two models stops being able to orphan a queue.

Each is roughly an afternoon now. Together they are the difference between Apple
Music being a new `Playable` conformer and Apple Music being a second playback
subsystem with its own queue.

---

### F2 — `queue`, `unshuffledQueue` and `queueIndex` are three variables with an unenforced invariant.

**What is wrong.** `PlaybackService` states in at least five comments that
`unshuffledQueue` must always be a permutation of `queue`. Five methods maintain
that by hand — `play(_:in:)` (`:207`), `toggleShuffle()` (`:270`),
`moveUpcoming(from:to:)` (`:358`), `handleTrackDeleted(_:)` (`:529`),
`stopPlayback()` (`:837`) — plus `restoreFromPersistedState()`, which rebuilds
both from two separate `compactMap`s. `queueIndex` is separately bounds-clamped
in six places.

The clearest evidence this is load-bearing rather than incidental is the 20-line
comment at `:284-306`, which exists solely to explain that a defensive `else`
branch is unreachable *because* the invariant holds — and which then honestly
concedes that this could only be verified by instrumenting the branch by hand.

**Cost of leaving it.** Endless playback means appending to the queue *while it
plays*. Every append must touch both arrays, must not move `queueIndex`, and must
be correct when the tail is already shuffled. That is a sixth hand-maintained
site for an invariant no type enforces, in the code path most likely to run
unattended overnight with repeat-all armed. This is the finding the next feature
on the roadmap walks straight into.

**Smallest fix.** Extract a value type. The tests already contain a file named
`PlayableQueueTests.swift`, but no such type exists:

```
struct PlayableQueue {
    private(set) var items: [any Playable]
    private(set) var index: Int
    private(set) var unshuffled: [any Playable]
    private(set) var isShuffled: Bool
    mutating func shuffleTail(using: ([any Playable]) -> [any Playable])
    mutating func unshuffle()
    mutating func move(from: IndexSet, to: Int)
    mutating func remove(id: UUID) -> Removal   // .absent / .shiftedIndex / .wasCurrent
    mutating func append(contentsOf: [any Playable])
}
```

`PlaybackService` holds one. The invariant becomes structural, the six clamps
become one, ~150 lines leave `PlaybackService`, and
`PlaybackServiceQueueTests`/`ShuffleTests`/`UpcomingTests` can target pure value
semantics instead of standing up `MockAudioPlayer` + `InMemoryLibrary`. This is
also the split `PlaybackService` actually wants — see F6.

---

### F3 — `contentBudget = 440` is a contract between four files, held together by a comment.

**What is wrong.** `PlayerCard.contentBudget` (`PlayerCard.swift:404`) is
`private` and must be ≥ the summed height of five elements defined in three other
files: `NowPlayingContent.titleBlock`, `ScrubberBar.touchHeight`,
`NowPlayingContent.transport`, `NowPlayingContent.volume`,
`NowPlayingContent.queueToggleRow`, plus four 24pt `VStack` gaps.

Nothing checks this. Its own 60-line doc records that it has been wrong three
times (350 → 380 → 440), each time clipping a control off the bottom of a 4.7"
screen or of every iPhone in landscape, and that the remaining slack is "~16pt,
not 20" — already less than one Dynamic Type step, as the same comment says.
`QueuePanel.pillHeight`, `PlayerSubtitle`'s header doc and
`NowPlayingContent.jamendoCredit`'s 30-line doc all reason about this budget from
memory, because they cannot read it.

**Cost of leaving it.** Both roadmap features want an element in that stack — an
endless-playback toggle belongs next to the queue toggle, an Apple Music source
badge belongs in the title block. Adding either reopens a defect that has shipped
three times, on the devices least likely to be checked. The comment correctly
identifies the durable fix and then does not take it.

**Smallest fix.** Take the fix the comment names: measure instead of allow for.
`NowPlayingContent` reports its own height
(`.onGeometryChange(for: CGFloat.self) { $0.size.height }`), `PlayerCard` stores
it, and `contentOffset(fullSize:)` becomes `fullSize.height - measuredHeight`.
The constant survives only as a first-frame fallback.

If that is too much for one release: promote each element height to an
`internal static let`, make `contentBudget` internal, and add one test asserting
`sum + 4*24 <= contentBudget - contentInset`. That converts a silent visual
regression on an SE into a red test on every machine.

---

### F4 — Local deletion's queue safety lives in a view; Drive's and Jamendo's live in their services.

**What is wrong.** `DriveLibraryService.swift:46` and
`JamendoLibraryService.swift:74` each declare
`var onTrackWillBeDeleted: (@MainActor (any Playable) -> Void)?`, wired to
`PlaybackService.handleTrackDeleted` in `EvenstarApp.init` (`:48`, `:56`) —
precisely so no caller can forget. `LibraryService.delete(_:)` has **no such
hook**. The only thing keeping a deleted local `Track` out of the playing queue is
`SongsView.deleteTrack` (`Features/Library/SongsView.swift:347`) calling
`playback.handleTrackDeleted(track)` by hand, first, in the right order — and
that method's own comment concedes the ordering is fragile.

The failure mode is documented at `PlaybackService.handleTrackDeleted`
(`:503-511`): the queue retains a deleted-and-saved `PersistentModel`, and
reading any property off it raises `NSObjectInaccessibleException` — an
Objective-C exception, uncatchable in Swift, unhelped by `try?`, and
*intermittent*, because a row whose attributes are still materialised answers
silently for a while.

**Cost of leaving it.** The second caller of `library.delete(_:)` crashes the app
non-deterministically, with no compiler warning and no failing test. A batch
delete, a "remove all local files" in Settings, or an import that reconciles
duplicates all reach it. This is the highest severity-per-line-of-fix item in the
audit.

**Smallest fix.** Give `LibraryService` the identical hook, call it at the top of
`delete(_:)`, wire it in `EvenstarApp` beside the other two, delete the manual
call from `SongsView.deleteTrack`. Three lines added, one removed, and the rule
stops depending on a future author reading a comment.

---

### F5 — `JamendoPreviewPlayer` is a second audio engine, owned by a view, arbitrating the audio session through `onAppear`.

**What is wrong.** `Features/Jamendo/JamendoDiscoveryView.swift:18` constructs
`@State private var preview = JamendoPreviewPlayer()`, which default-constructs
its own `StreamingAudioPlayer` (`JamendoPreviewPlayer.swift:60`) — a third audio
engine, outside the composition root. The same view also owns a network client
(`:69`, `private let client = JamendoClient()`).

Arbitration between the preview engine and the real player is done by assigning
closures inside a view lifecycle callback:

```
:204  preview.suspendMainPlayback = { … playback.pause() … }
:209  preview.resumeMainPlayback  = { playback.resume() }
:214  .onDisappear { preview.stop() }
```

So "which engine owns the shared `AVAudioSession`" is a property of whether a
particular SwiftUI view is currently mounted.

The root cause is F1: `JamendoCatalogueTrack` is a struct with a `String` id and
cannot be `Playable`, and `JamendoPreviewPlayer`'s own doc (`:7-14`) says this is
exactly why it exists.

There is a related unwritten coupling: `JamendoPreviewPlayer.swift:63` and `:66`
use `MainActor.assumeIsolated`, an *unchecked* assertion that traps if the
callback ever arrives off-main. It holds today only because
`StreamingAudioPlayer`'s private `onMain` helper (`:263`) makes it hold. That is a
cross-file dependency between an unchecked assumption in one file and a private
implementation detail in another.

**Cost of leaving it.** Apple Music adds a *fourth* engine with its own session
requirements. The current pattern — each new source brings its own player,
constructed wherever it is used, arbitrated by view lifecycle — does not scale to
that, and the failure mode (two engines both think they own the session; music
resumes when it should not, or does not when it should) is intermittent and
device-only.

**Smallest fix.** After F1 step 1, `JamendoCatalogueTrack` can conform to
`Playable` and preview becomes `playback.play(catalogueTrack, in: [catalogueTrack])`
— the second engine disappears entirely. Short of that: move `JamendoPreviewPlayer`
and `JamendoClient` into `EvenstarApp`'s composition root and inject them, so at
minimum the session arbitration is wired in one place rather than in `onAppear`.

---

### F6 — The big files: what the sizes actually are, and where the real seams are.

Measured (total / comment / blank / **code**):

| file | total | comment | blank | **code** | comment:code |
|---|---|---|---|---|---|
| `PlayerCard.swift` | 1855 | 1319 | 68 | **468** | 2.81 |
| `PlaybackService.swift` | 1216 | 655 | 52 | **509** | 1.28 |
| `FloatingTabBar.swift` | 926 | 524 | 47 | **355** | 1.47 |
| `RootView.swift` | 315 | 227 | 9 | **79** | 2.87 |

**`PlayerCard` is a 468-line view, not a 1700-line one.** Splitting it on the
strength of its line count would relocate comments and fix nothing. Two seams
inside it are nonetheless real:

**(a) Artwork resolution — extract it.** `ArtworkIdentity` (`:486`),
`ArtworkSource` (`:496`), `source(hasArtwork:loaded:)` (`:534`), `preferredCover`
(`:579`), `displayedArtwork` (`:564`), `loadArtwork` (`:1824`) and three `@State`
values (`artwork`, `artworkOwner`, `tint`) form a self-contained state machine:
decide the *structure* from the model synchronously, fill the *content*
asynchronously, prefer the certainly-current image, guard the late decode against
a track change. `PlaybackService.loadArtworkIntoNowPlaying` (`:1171`) runs a
second, differently-guarded copy of the same machine for the lock screen. Move it
to an `@Observable final class PlayerArtwork` both use. `PlayerCard` loses ~120
code lines and one class of "which picture is current" bug loses its second home.

**(b) Layout metrics — extract them.** Every `static let`/`static func` from
`collapsedHeight` (`:32`) to `queueThumbCentre` (`:1742`) is pure arithmetic with
no view in it, and `ArtworkGeometryTests`, `DragOffsetTests` and
`SettleVelocityTests` already reach into a `View` type to call them. Move to
`enum PlayerCardMetrics`. This is F3's prerequisite: it is what lets
`NowPlayingContent` and `QueuePanel` *read* `contentBudget` rather than describe
it from memory.

**Do not** split `background`, `artworkView`, `expandedContent` or `miniChrome`
out. Each reads five or six `@State`/derived values; as separate views their
parameter lists would exceed their bodies, and `artworkView`'s modifier *order*
is itself load-bearing (documented at `:817-841` and `:1425-1433`).

**`PlaybackService` at 509 code lines is one cohesive job and should not be split
beyond F2's queue extraction.** Every method touches the same four state
variables; there is no second responsibility hiding in it. After `PlayableQueue`
comes out it is ~360 lines, which is right for what it does. Its size is an
honest reflection of the job.

**`FloatingTabBar` at 355 code lines** was not in scope but is worth a note: five
`@Binding`s, two `@Namespace`s, and a nine-way morph. It is the file most likely
to become the next `PlayerCard`. Watch it; do not act yet.

---

### F7 — `expansion.progress` is a hand-maintained mirror of `PlayerCard.progress`.

**What is wrong.** `PlayerCard.progress` is derived
(`min(max(settled + dragDelta, 0), 1)`, `:215`). `PlayerExpansion.progress` is
*assigned* from four places — `drag.onChanged` (`:1758`), `drag.onEnded`
(`:1800`), `expand()` (`:1809`), `collapse()` (`:1817`). `PlayerExpansion.swift`
documents at length why it cannot be driven from an `onChange` (two update passes
per dragged frame, which is what made the recede stutter). That reasoning is
correct. The consequence is that two values which must always be equal are kept
equal by four remembered writes. Three things read the mirror: the recede
transform, `prefersDarkChrome`, and through it the whole window's colour scheme.

**Cost of leaving it.** A fifth way to move the card — a "now playing" deep link,
a return from the lock screen, an Apple Music handoff — silently desyncs the
background scale and the status-bar colour from the card.

**Smallest fix.** Move `settled` and `dragDelta` onto `PlayerExpansion` and let it
compute `progress`. `PlayerCard` reads `expansion.progress` rather than computing
it; the four assignments become writes to `settled`/`dragDelta`. One owner, no
mirror. The performance property that justified the class survives untouched,
because `PlayerCard`'s body reads `progress` anyway.

For contrast, the same file gets this exactly right elsewhere:
`PlaybackService.stalledPlaybackError` (`:76`) is *derived*
(`hasLoaded ? nil : lastPlaybackError`) rather than stored, so the two error
notions cannot disagree. That is the discipline F2, F3 and F7 are missing, applied
correctly two files away.

---

### F8 — The comments: mostly institutional knowledge, but the cross-references have rotted.

**Carrying real knowledge — keep, and keep writing these:**

- `PlaybackService.interruptedTrackID` (`:116-131`): why a three-second network
  blip must not cost forty minutes of listening. Non-obvious, expensive to
  rediscover.
- `PlaybackService.failureSkipRun` (`:150-168`): why the skip loop needs a bound,
  and — the good part — why "a track started" is *not* evidence the run is over
  on the streaming path.
- `PlaybackService.deferPersist` (`:1090-1103`): "Nothing may be captured here",
  with the reason. The single most valuable comment in the project.
- `RoutingAudioPlayer`'s header: why routing is not a branch inside
  `PlaybackService`.
- `PlayerCard`'s `.contentShape` note (`:894-957`): a defect that shipped in
  *both* directions, with both fixes and why neither alone was right.
- `PlayerCard.queueFactor` (`:166-202`): records what was measured, then
  explicitly separates it from what the measurement establishes — "Treat
  'smoother' as established and 'why' as open." Unusually good practice; make it
  the house standard.

**Rotted, and load-bearing:**

- `` `PlayerCard.artworkSide` `` is cited by name in `PlayerSubtitle.swift:17` and
  `NowPlayingContent.swift:108`. **The symbol does not exist.** It is
  `contentBudget`.
- `` `NowPlayingContent.metadataSubtitle` `` is cited in `Playable.swift:42` as
  the reason `DriveTrack.albumTitle` must use exactly `MetadataPlaceholder.album`.
  **The symbol does not exist.** The rule is now `PlayerSubtitle.metadataText`. A
  future author following that pointer to justify changing the placeholder finds
  nothing and concludes the constraint is stale.
- `` `backgroundTintHold` `` at `PlayerCard.swift:1363`. **Does not exist.**
- Four comments call the queue header slot **44pt** (`:1398`, `:1442`, `:1669`,
  and inside `ArtworkGeometryTests`' own doc) when `QueuePanel.headerArtwork` is
  **54**. One comment (`:1334`) has it right.

**Substituting for clearer code, in two places:**

- `contentBudget`'s doc is 60 lines narrating three corrections and contains two
  different derivations of the same stack (`~380pt` at `:329`, `~384pt` at
  `:366`) that were appended rather than reconciled. The reader who most needs it
  — the person adding a sixth element — must read all three histories to extract
  a rule that is one sentence: *"raise this by the new element's height plus
  24."* F3's measurement fix makes most of that prose unnecessary; short of that,
  rewrite it once rather than appending a fourth time.
- `PlayerCard.swift:1353-1390` argues for three paragraphs that a `.mask` should
  be an `.overlay`, then three more that it must be a mask. Both arguments are
  preserved; only the second is current. A reader cannot tell which paragraph
  describes the code without reading the code.

**Smallest fix.** Nothing structural. A convention — when a symbol is renamed,
grep the prose for the old name — and, if you want it enforced, a CI grep that
fails when a backticked identifier in a doc comment matches no declaration in the
project. That would have caught all four dangling references.

---

### F9 — Testability: excellent where dependencies are injected, absent where they are not.

The dividing line between tested and untestable is exactly the
dependency-injection line. Nothing here is an accident.

**Tested well, and behaviourally.** No `func test…` body in the suite lacks an
assertion. `PlaybackService` is covered deeply (repeat 604 lines, shuffle
324+172, queue 290, upcoming 260, restore 235, streaming failure 560), and the
injection of `shuffleTail` is what makes shuffle assertions exact rather than
seed-dependent. `MockNowPlayingPublisher` (`MockAudioPlayer.swift:75-112`) is the
best-designed double: it records `hasArtwork`/`artworkSize` because its earlier
version discarded the argument, which is how the restore path once shipped
pushing `artwork: nil` with all 74 tests green — and the comment says so.
`ScrubberBarTests.swift:41-45` deliberately adds a second width so an
implementation that hardcoded 200 would fail; that is mutation-aware test design.
`ScrubberBarTests.swift:22-29` documents that one of its own assertions *cannot*
discriminate the guard it appears to test, and points at the test that can.

**Assertions that establish nothing.** Only one is genuinely tautological:
`ArtworkGeometryTests.swift:124-136` asserts
`centre.y == panelTop + QueuePanel.headerArtwork / 2`, which is a
character-for-character restatement of `PlayerCard.queueThumbCentre`
(`:1742-1747`). It cannot fail for any input, and it is currently the only thing
standing between the project and the 12pt landing-mismatch regression it claims
to guard. Delete it or make the two sides independent. Lower-grade restatement:
`AppThemeTests.swift:22-24` (`.light.colorScheme == .light`),
`AppThemeTests.swift:50-52` and `AppLanguageTests.swift:61-63` (`allCases` equals
declaration order), `JamendoTrackTests.swift:39-43` and `:49-54` (pass a value in,
assert it comes back out).

**Structurally untestable today, in priority order:**

1. **The 0.5s position `Timer`** (`PlaybackService.swift:1042-1055`). Every test
   calls `tickForTesting()` instead, so the timer's creation, its
   `RunLoop.main.add(…, forMode: .common)` mode, its invalidation on stop, and its
   `[weak self]` behaviour are all unverified. A regression where the timer is
   never started, or never invalidated (battery drain), passes the full suite.
   *Fix:* inject a `Ticker` protocol; `tickForTesting()` then disappears.
2. **The audio session.** `activateSessionIfNeeded()` (`:1205`) touches
   `AVAudioSession.sharedInstance()` directly and swallows failures into a
   `print`. Interruptions are *simulated* by hand-setting `player.isPlaying = false`
   (`PlaybackServiceTests.swift:83-95`); the real notification path is untouched.
   *Fix:* a two-method `AudioSessionControlling` protocol.
3. **The artwork path**, in both `PlaybackService` and `PlayerCard`, because
   `ArtworkStore` is a global `enum` with three `static let NSCache`s. *Fix:* an
   `ArtworkProviding` protocol with the static enum as default conformer.
4. **`RemoteCommandsBridge`** — zero tests, and it is the only entirely untested
   *service* with real branching (including a `.commandFailed` return at `:43`).
   Lock screen, CarPlay and headphone buttons all run through it.

**Test-only API shipping in production**, unguarded by `#if DEBUG`:
`PlaybackService.tickForTesting()` (`:492`),
`StreamingAudioPlayer.observedItemForTesting` (`:192`), `markReadyForTesting()`
(`:252`), `pendingSeekForTesting` (`:255`),
`RoutingAudioPlayer.isStreamingActiveForTesting` (`:155`). The comments
cross-reference each other, so this is a deliberate convention rather than drift —
but the last two expose internal state purely so tests can assert on it
(`StreamingFailureTests.swift:262-264`, `:283`, `:328`, `:342-348`), which is
implementation-detail coupling. Items 1 and 2 above remove the need for three of
the five.

**Isolation hazards that will produce a flake eventually:**

- `LibraryServiceTests.swift:94-95` — a `defer` that removes the shared `Music/`
  and `Artwork/` **parent directories** in the app's real Documents sandbox. If
  another test is mid-import, that is cross-test destruction. `ImportService`
  already accepts an injected `fileManager` (used at `ImportServiceTests.swift:193`);
  `LibraryService` accepts one too. Use it rather than the real sandbox.
- `ArtworkStore`'s three static `NSCache`s are never cleared by any test.
  `ArtworkStoreTests.swift:66-76` asserts `first === second` (a cache hit);
  `NSCache` evicts under memory pressure with no warning, so this can fail
  nondeterministically on a loaded machine. Add a reset hook called from `setUp`.
- `StubURLProtocol`'s state is all `nonisolated(unsafe) static` with a manual
  `reset()`, and responses come off a positional FIFO. Any test that forgets
  `reset()` inherits the previous test's queue, and the file cannot run in
  parallel.
- `SystemVolumeSliderTests` — six of eight tests `throw XCTSkip` on the simulator
  (`:36-42`, `:148-150`), so touch-swell, release-restore, centring and the
  one-fire-per-press callback are unverified in any CI run. The comment is honest
  about it, but the skip count reads as coverage. Either split the four
  hardware-independent tests into a file that always runs, or mark the file
  device-only in the scheme.
- Async work deferred with bare `Task { @MainActor in … }`
  (`PlaybackService.swift:1082-1106`) is drained in tests by a single
  `await Task.yield()`. This works for one hop, but adding a second `await` inside
  `deferSideEffects` would silently break every such test, and a test that forgets
  the yield gets a green pass on a stale value.

**Behavioural gaps worth closing, highest value first:** `ImportService`
cancellation mid-batch (leaves orphaned files on disk, no test); intermediate
import progress (`ImportServiceTests.swift:213-241` only observes the final
state, so a bug that jumps straight to complete passes);
`LibraryService.metadataRevision` incrementing on `updateMetadata`;
`moveUpcoming` interacting with an already-shuffled tail; `FormatSupport`
case-handling (`.FLAC`, `.mp3.bak`, extensionless).

---

### F10 — The service layer depends upward on `Features/`.

Twenty-four `String(localized:…)` call sites across `LibraryService.swift`,
`ImportService.swift`, `JamendoError.swift` and `DriveClient.swift` reach
`AppLanguage.resolvedBundle` / `AppLanguage.resolvedLocale`, which live in
`Features/Shared/AppLanguage.swift:41-74`. The dependency arrow points
Services → Features, and all the copy is hardcoded Vietnamese inside the service
layer.

Related, smaller: `Services/JamendoLibraryService.swift:3` imports SwiftUI and
uses nothing from it; `Services/PlaybackService.swift:5` likewise (its `UIKit`
import at `:4` *is* used, for `UIImage`). `Utilities/ArtworkStore.swift:224`
returns a SwiftUI `Color` from `dominantColor(for:)`.
`Services/NowPlayingService.swift:13` declares a seven-positional-parameter
protocol method while `struct TrackMetadata` — holding five of those seven fields
— is declared directly above it at `:5` and unused by the protocol.

**Cost.** Low today; it bites when you want to unit-test an error message, extract
the services into a Swift package, or add English copy that is not a translation
of the Vietnamese. Also, every service that formats an error transitively depends
on `UserDefaults` through `AppLanguage`.

**Smallest fix.** Move `AppLanguage` (or just `resolvedBundle`/`resolvedLocale`)
out of `Features/Shared` into a `Localization` utility below Services. Delete the
two unused imports. Longer term the better shape is errors carrying codes and
views rendering them, but the move alone fixes the arrow.

---

### F11 — Duplication, judged case by case.

**Deliberate and correct; leave alone:**

- `restoreFromPersistedState()`'s skip loop (`:617-680`) duplicating
  `loadCurrentAndPlay()`'s (`:720-807`). The stated reason — restore must never
  autoplay — is sound, and merging would thread a flag through a loop whose exit
  conditions genuinely differ.
- `JamendoSongsList.deleteJamendoTrack` calling `handleTrackDeleted` when
  `JamendoLibraryService.unsave` already does. Idempotent, keeps the two delete
  paths the same shape, and the comment says exactly this.
- `PlayerSubtitle.line` vs `collapsedLine`. The album rule genuinely differs
  between a 54pt pill and a full screen; the *failure* rule is shared, which is
  the half that mattered.
- `Track` / `DriveTrack` / `JamendoTrack` being separate `@Model`s.
  `DriveTrack.swift:6-9` explains that sharing one model would force every
  existing `@Query` to grow a filter. Correct for query isolation.

**Not deliberate; worth collapsing:**

- `String(localized:bundle:locale:)` appears **51 times** with the same two
  trailing arguments across 13 files. A three-line helper
  (`func L(_ key: String.LocalizationValue) -> String`) makes the correct form the
  short form — and the verbosity is why, by `NowPlayingContent.creditLine`'s own
  admission, the project "has shipped exactly that bug twice already" (an
  interpolated plain `String` that does not localise).
- **Find-by-id, four times.** `LibraryService.findTrack` (`:172`),
  `findDriveTrack` (`:181`), `findJamendoTrack` (`:191`) and
  `JamendoLibraryService.existingRow(jamendoID:)` (`:181`) are four copies of one
  `FetchDescriptor + fetchLimit = 1`. The doc at `LibraryService.swift:164-171`
  records that one of the three was *missing* `fetchLimit = 1` — exactly the drift
  a generic would have prevented. F1 step 3 replaces these with a registry anyway.
- **`onTrackWillBeDeleted` declared verbatim twice** with ~20 lines of
  near-identical doc each (`DriveLibraryService.swift:20-46`,
  `JamendoLibraryService.swift:54-74`) — and absent from the third service, which
  is F4.
- **Delete-plus-best-effort-artwork-cleanup twice**: `LibraryService.delete`
  (`:41-56`) and `JamendoLibraryService.unsave` (`:142-151`), same routine, same
  `try?` rationale spelled out in both.
- **`FileManager` injection is inconsistent.** `LibraryService` and
  `ImportService` take an injected `fileManager`; `JamendoLibraryService`
  hardcodes `FileManager.default` at `:145`, `:201`, `:204`. The Jamendo artwork
  path is therefore not testable against a fake filesystem while the local one is.
- **`SongsView.localContent`, `DriveSongsList.list` and `JamendoSongsList`** each
  independently build `List { SongRow … .onTapGesture { playback.play(track, in: list) } }`
  with a per-source swipe action, and they have already diverged: `DriveSongsList`
  has **no** swipe-to-delete where the other two do. Worth one
  `SourceSongList<T: Playable>` once a fourth source arrives — which it will.
- **The preview object graph is rebuilt inline in seven files** (`AlbumsView:175`,
  `ArtistsView:112`, `AlbumDetailView:67`, `ArtistDetailView:55`,
  `SearchView:97`, `AccountView:160`, `DriveFoldersView:366`). One
  `PreviewEnvironment` helper.

---

### F12 — Albums, Artists and Search are structurally local-only.

`LibraryGrouping.albums/artists/search` are concretely `[Track] -> …`, and
`AlbumsView`, `ArtistsView` and `SearchView` each `@Query` `[Track]`. Drive and
Jamendo tracks appear only behind the Songs tab's source chip; they are invisible
to the other three library screens. Apple Music makes this worse — a user with a
large Apple Music library will search and find nothing.

**Smallest fix now:** make `LibraryGrouping` generic over `Playable`
(`static func artists<T: Playable>(from tracks: [T]) -> [ArtistGroup]`) and make
`AlbumGroup.tracks`/`ArtistGroup.tracks` hold `[any Playable]`. The views keep
passing `[Track]` today. Note `sortedAlbumTracks` needs `discNumber`/`trackNumber`,
which are on `Track` and not on `Playable` — that is the one real piece of work
here, and it argues for a small `Orderable` refinement rather than putting track
numbers on every `Playable`.

---

### F13 — Smaller notes

- **API keys are handled correctly, and the mechanism is fragile.** Verified:
  `DriveAPIKey.swift` and `JamendoAPIKey.swift` are committed with
  `static let value = ""`, and both are flagged `skip-worktree` in the index
  (`git ls-files -v` shows `S`), so the real keys exist only in the local working
  tree. The doc comments are accurate and no credential is in history. But
  `skip-worktree` is a *local index flag*: a fresh clone, a second machine, or CI
  does not have it, and a `git add -f` or certain rebases silently un-hide the
  file. Consider moving the values to an untracked `.xcconfig` or the keychain so
  the safety does not depend on a flag that travels with nothing.
- **`AlbumsView` caches its grouping in `@State`** and refreshes it from two
  `onChange` triggers (`tracks` and `library.metadataRevision`). The motivation is
  documented and correct, but it is a third instance of the F7 shape: derived
  state stored, kept fresh by remembering to add a trigger. Any *future* screen
  deriving from `[Track]` must remember both, not one.
- **`LibraryService.context` is `let`, not `private let`** (`:25`), and both other
  services reach straight through it to the `ModelContext` (ten call sites in
  `DriveLibraryService`, five in `JamendoLibraryService`). So `LibraryService` is
  not really an abstraction over SwiftData — it is a context holder plus a bag of
  `Track` methods. That is a defensible position, but it should be a stated one:
  either make it a real gateway or rename it to reflect what it is.
- **Concurrency: no actors, one `Sendable` conformance** (`MetadataReading`). The
  three audio classes (`StreamingAudioPlayer`, `RoutingAudioPlayer`,
  `AVAudioPlayerWrapper`), `NowPlayingService` and `RemoteCommandsBridge` are all
  un-isolated and hold mutable state written from KVO and `NotificationCenter`
  callbacks. Correctness rests on a hand-rolled funnel
  (`StreamingAudioPlayer.onMain`, `:263`) rather than on the compiler. This is
  *documented* and currently correct; it is the area most likely to break under a
  future Swift concurrency-checking upgrade, and `MainActor.assumeIsolated`
  (`JamendoPreviewPlayer.swift:63`, `:66`) traps rather than warns when it does.
- **`Playable.artworkRelativePath` is a member one conformer structurally cannot
  satisfy** — `DriveTrack` hardcodes `nil` (`Playable.swift:49`). Minor today; it
  is the shape F1 step 1 should clean up in passing.
- **`AudioPlayerProtocol` has two members that exist for one conformer each**, and
  both say so: `isDurationKnown` (only streaming ever answers `false`) and
  `didFailCallback` (`AVAudioPlayerWrapper` declares it and never calls it —
  local failures come through `throws`). Two error channels for one operation,
  split by conformer. Acceptable, but worth knowing before adding a third engine.

---

## 2. What is genuinely strong

Stated plainly, because a problems-only list would misrepresent this codebase.

1. **The composition root.** `App/EvenstarApp.swift:19-64` constructs every
   service explicitly, injects every dependency, wires the delete hooks by closure
   (with the retain-cycle reasoning written down), and publishes everything via
   `.environment`. There are **no singletons among the app's own services** and no
   `@EnvironmentObject`/`@StateObject` anywhere — it is all modern Observation.
   This is better than most professional SwiftUI codebases and is the single
   reason 419 tests run with no simulator, no network and no clock.
2. **`Playable` earned its keep.** Adding Jamendo as a third source required
   *zero* changes to queue, repeat, shuffle, restore, play-counting or the lock
   screen. The dividend is real and the code's claim about it is accurate. F1 is
   about its limits, not its value.
3. **`RoutingAudioPlayer`.** Refusing to put a source check inside
   `PlaybackService` was the right call for the right stated reason, and the
   callback gating — both engines alive, only one live, each callback gated on
   which, `[weak self]` plus a value-typed `Engine` so neither can retain the
   other — is subtle, correct, and correctly explained.
4. **Failure handling is better than most shipping music apps.** Bounded skip
   loops with the bound justified; position preserved across a stall so a network
   blip does not cost the user their place; staleness guards on asynchronous
   callbacks that carry no inherent claim on the present; and a deliberate
   distinction between "the last thing that went wrong" and "what you are stuck on
   now".
5. **"Lift the rule out of the view so it can be pinned."** `PlayerSubtitle`,
   `LibraryGrouping`, `artworkGeometry`, `settleVelocity`, `dragOffset`,
   `LicenceName`, `NowPlayingContent.creditLine`. I verified every one of these is
   actually called from production code — none was extracted merely so a test
   could exist. That is genuine functional-core extraction, not test theatre, and
   it is the habit that makes everything else possible.
6. **A coherent, measured performance discipline.** `deferPersist`,
   `deferSideEffects`, `acknowledge`, `PlayerExpansion` as a reference type,
   dropping the material layer past `materialCutoff`, constant rather than
   interpolated shadows, `ArtworkStore`'s downsample-and-cache — with the one
   exception (play/pause runs inline) reasoned rather than forgotten, and several
   decisions citing Instruments numbers.
7. **`JamendoLibraryService.inFlightSaves`** — the check→`await`→insert TOCTOU is
   identified and closed, and `Task<Void, Error>` is chosen over
   `Task<JamendoTrack, Error>` explicitly because `@Model` is not `Sendable`. That
   is a level of concurrency care well above the rest of the project.
8. **The `@AppStorage` + `resolvedLocale` + `.id(language)` language switch**
   solves a genuinely tricky problem correctly, including naming explicitly what
   the environment locale does *not* cover.

---

## 3. Recommended order of work

1. **F4** — the delete hook on `LibraryService`. Three lines; removes an
   uncatchable crash. Do it this week.
2. **F9's item 1** — inject a `Ticker` and delete `tickForTesting()`. Small, and
   it closes the largest untested subsystem in the most-tested file.
3. **F1 steps 1–3** — reshape `Playable` and `PlaybackState` for source-agnostic
   identity and playback. Before Apple Music work starts. **Highest long-term
   payoff in this report**, and it collapses F5 as a side effect.
4. **F2** — extract `PlayableQueue`. Before endless playback, because endless
   playback is what stresses the invariant.
5. **F3** — measure the content stack instead of budgeting for it (after F6(b)).
6. **F6(b)** then **F6(a)** — `PlayerCardMetrics` first (it unblocks F3), then
   `PlayerArtwork`.
7. **F8** — fix the four dangling symbol references and the 44/54 drift; adopt
   the grep-on-rename convention. Delete `ArtworkGeometryTests:124-136`.
8. **F7, F10, F11, F12** — as the surrounding code is next touched, not as a
   campaign.
