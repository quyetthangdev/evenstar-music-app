# Endless Playback and a Simpler Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an honest "keep playing" (∞) mode that extends the queue from the user's own library instead of Apple Music-style Autoplay, and ship five small interface fixes — a press-only queue capsule, aligned queue-list padding, a queue list that reaches closer to the scrubber without swallowing its drag strip, a volume slider that answers touch like the scrubber, and a white accent colour with the three controls it would otherwise make invisible.

**Architecture:** Part 1 is service-layer work in `PlaybackService`/`PlaybackState` (a two-rung fallback ladder run from `handleFinish()`, gated on `repeatMode == .off`) plus one `QueuePanel` pill that surfaces it. Part 2 is five independent, mostly cosmetic changes to existing SwiftUI views and one color asset — none of them touch playback logic, and none of them depend on Part 1 or on each other.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest. iOS 18.0 deployment target.

**Spec:** docs/superpowers/specs/2026-08-11-endless-and-simple-design.md

## Global Constraints
- NEVER edit `Evenstar/Evenstar.xcodeproj/project.pbxproj` or any `.xcscheme`. New Swift files are picked up automatically — Xcode 16 synced folders.
- Every `xcodebuild` invocation passes `-configuration Debug` explicitly.
- Build tests with `clean build-for-testing`, never plain `build` — a plain `build` strips the test PlugIn and the next `test-without-building` fails with "Failed to create a bundle instance … EvenstarTests.xctest".
- Simulator destination: `platform=iOS Simulator,name=iPhone 17`.
- No third-party libraries. SwiftUI only. No `try!`. No silently swallowed `catch {}`.
- Never modify a pre-existing test to make new code pass.
- New `PlaybackState` properties must carry a literal default value, or SwiftData cannot open a store written by an earlier build and the app fails to launch for every existing user.
- `PlayerCard.contentBudget` must not be raised.
- The scrubber and transport row must not move between queue modes.
- Every new user-visible string needs both `vi` and `en` in `Evenstar/Evenstar/Localizable.xcstrings`. Vietnamese is the source language. Preserve key order and Xcode's `" : "` separators — a re-serialisation turns a small change into a 1300-line diff.
- Suite is at **415 tests** before this plan starts.

---

### Task 1: ∞ — the fallback ladder in `PlaybackService`

**Files:**
- Modify: `Evenstar/Evenstar/Models/PlaybackState.swift`
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift`
- Create: `Evenstar/EvenstarTests/PlaybackServiceKeepPlayingTests.swift`

**Interfaces:**
- Consumes: `LibraryService.fetchAllTracks(sortedByTitle:) throws -> [Track]` (existing), `PlaybackService.queue: [any Playable]`, `.unshuffledQueue: [any Playable]`, `.isShuffled: Bool`, `.repeatMode: RepeatMode`, `.currentTrack: (any Playable)?` (all existing).
- Produces (for Task 2): `PlaybackState.isKeepPlayingEnabled: Bool` (default `false`), `PlaybackService.isKeepPlayingEnabled: Bool { get }`, `PlaybackService.toggleKeepPlaying() -> Void`.

Local `Track` only — Drive and Jamendo tracks are excluded from the ladder. The design's own case for this đợt is that Evenstar has no similarity data; extending that reach into every library source is a bigger claim than "the user's own local library," which is what `fetchAllTracks()` already returns.

- [ ] **Step 1: Write the exhaustion test first**

The design calls this out explicitly: "An endless feature whose exhaustion case is untested is an endless loop waiting for a small library." Create `Evenstar/EvenstarTests/PlaybackServiceKeepPlayingTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// ∞ ("Phát tiếp"): once the queue runs out under `repeatMode == .off`, keep
/// playing from the user's own library instead of stopping.
@MainActor
final class PlaybackServiceKeepPlayingTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, library)
    }

    @discardableResult
    private func makeTrack(title: String, artist: String, library: LibraryService) throws -> Track {
        let track = Track(
            title: title,
            artistName: artist,
            albumTitle: "Album",
            durationSeconds: 100,
            relativePath: "Music/\(UUID().uuidString).mp3",
            format: "mp3"
        )
        try library.insert(track)
        return track
    }

    // MARK: - The exhaustion case, written first — see the design's own note
    // that an untested exhaustion path is an endless loop waiting for a
    // small library.

    func testALibraryContainingOnlyWhatIsAlreadyQueuedStops() async throws {
        let (service, player, library) = try makeStack()
        let list = [
            try makeTrack(title: "A", artist: "Artist", library: library),
            try makeTrack(title: "B", artist: "Artist", library: library)
        ]
        service.play(list[0], in: list)
        service.toggleKeepPlaying()
        service.next() // now playing "B", the last queued track — and the whole library

        player.simulateFinish()
        await Task.yield()

        XCTAssertFalse(service.isPlaying, "nothing left in the library to add, so it must stop")
        XCTAssertTrue(service.queue.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails to compile**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: **compile failure** — `value of type 'PlaybackService' has no member 'toggleKeepPlaying'`.

- [ ] **Step 3: Add the persisted flag**

In `Evenstar/Evenstar/Models/PlaybackState.swift`, add beside `unshuffledQueueTrackIDs`:

```swift
    /// Whether the queue keeps extending itself from the library once it
    /// runs out, instead of stopping — the "Phát tiếp" (Keep playing) pill.
    ///
    /// A literal default, for the same reason `repeatModeRaw` and
    /// `isShuffled` carry one: without it SwiftData cannot open a store
    /// written by an earlier build, and the app fails to launch for every
    /// existing user.
    var isKeepPlayingEnabled: Bool = false
```

Add it to the memberwise `init`, both as a parameter with the same default and as an assignment:

```swift
    init(currentTrackID: UUID? = nil,
         positionSeconds: Double = 0,
         queueTrackIDs: [UUID] = [],
         queueIndex: Int = 0,
         repeatModeRaw: String = "off",
         isShuffled: Bool = false,
         unshuffledQueueTrackIDs: [UUID] = [],
         isKeepPlayingEnabled: Bool = false) {
        self.currentTrackID = currentTrackID
        self.positionSeconds = positionSeconds
        self.queueTrackIDs = queueTrackIDs
        self.queueIndex = queueIndex
        self.repeatModeRaw = repeatModeRaw
        self.isShuffled = isShuffled
        self.unshuffledQueueTrackIDs = unshuffledQueueTrackIDs
        self.isKeepPlayingEnabled = isKeepPlayingEnabled
    }
```

- [ ] **Step 4: Add the service-side flag, toggle, and the ladder**

In `Evenstar/Evenstar/Services/PlaybackService.swift`, add a stored property right after `unshuffledQueue` (around line 33):

```swift
    /// Whether the queue keeps extending itself from the user's own library
    /// once it runs out, rather than stopping — the "Phát tiếp" (Keep
    /// playing) pill in `QueuePanel`.
    ///
    /// Only ever consulted from `handleFinish()`'s `.off` branch: `.all` and
    /// `.one` already mean the queue has no end, so this never gets a turn
    /// while either is armed.
    private(set) var isKeepPlayingEnabled: Bool = false
```

Add the toggle right after `toggleShuffle()`'s closing brace (around line 316):

```swift
    /// Flips ∞ ("Phát tiếp") on or off.
    ///
    /// Nothing else happens here: the ladder only ever runs from
    /// `handleFinish()`, at the moment the queue actually reaches its end
    /// under `repeatMode == .off`. Turning this on mid-queue does not
    /// retroactively extend anything.
    func toggleKeepPlaying() {
        isKeepPlayingEnabled.toggle()
        persistImmediately()
    }
```

Add the batch size and the ladder itself right before `private func handleFinish()` (around line 873):

```swift
    /// How many tracks ∞ appends at once when the queue runs out.
    ///
    /// Batched rather than one at a time: a queue that grows by a single
    /// track shows one row in the queue panel and reads as about to end —
    /// see the design's "Appended in batches" note.
    static let keepPlayingBatchSize = 10

    /// Extends the queue from the user's own library when it has run out and
    /// ∞ is on. Returns `false` — a no-op — when ∞ is off, or when nothing
    /// in the library is left to add: a library containing only what is
    /// already queued must stop, not recurse looking for something that
    /// isn't there.
    ///
    /// Two rungs, not three — `Track` has no genre field to make a middle
    /// rung out of:
    ///   1. tracks by the same artist as `finishedTrack`, not already queued
    ///   2. the rest of the library, not already queued
    ///
    /// Only called from `handleFinish()`'s `.off` case: `.all` and `.one`
    /// already mean the queue has no end, so this never gets a turn while
    /// either is armed.
    ///
    /// **Appending to `queue` while shuffled also appends to
    /// `unshuffledQueue`** — the seventh site that has to keep the two
    /// arrays holding the same set, and the first that adds elements rather
    /// than permuting or removing them.
    private func extendQueueForKeepPlaying(after finishedTrack: any Playable) -> Bool {
        guard isKeepPlayingEnabled else { return false }
        let queuedIDs = Set(queue.map(\.id))
        let allTracks = (try? library.fetchAllTracks()) ?? []
        let notQueued = allTracks.filter { !queuedIDs.contains($0.id) }
        guard !notQueued.isEmpty else { return false }
        let sameArtist = notQueued.filter { $0.artistName == finishedTrack.artistName }
        let candidates = sameArtist.isEmpty ? notQueued : sameArtist
        let batch: [any Playable] = Array(candidates.prefix(Self.keepPlayingBatchSize))
            .map { $0 as any Playable }
        queue.append(contentsOf: batch)
        if isShuffled {
            unshuffledQueue.append(contentsOf: batch)
        }
        return true
    }

```

Now change `handleFinish()`'s `.off` case (leave `.one` and `.all` untouched):

```swift
        case .off:
            if queueIndex + 1 < queue.count {
                advance(to: queueIndex + 1)
            } else if let finished = currentTrack, extendQueueForKeepPlaying(after: finished) {
                advance(to: queueIndex + 1)
            } else {
                stopPlayback()
            }
```

Add the flag to `persistImmediately()`, right after the `unshuffledQueueTrackIDs` line:

```swift
        state.isKeepPlayingEnabled = isKeepPlayingEnabled
```

Add the restore, right after `isShuffled = state.isShuffled` in `restoreFromPersistedState()` — above the empty-queue guard, for the same reason `repeatMode` and `isShuffled` are: it is a setting, not part of the queue, so a launch with nothing to restore must still bring it back:

```swift
        isKeepPlayingEnabled = state.isKeepPlayingEnabled
```

- [ ] **Step 5: Run the exhaustion test to verify it passes**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EvenstarTests/PlaybackServiceKeepPlayingTests 2>&1 \
  | grep -E "Test case .*(passed|failed)" | sed 's/ on .*//'
```

Expected: 1 passed, 0 failed.

- [ ] **Step 6: Write the remaining tests**

Append to `Evenstar/EvenstarTests/PlaybackServiceKeepPlayingTests.swift`, inside the class, after the exhaustion test:

```swift

    // MARK: - Off

    func testKeepPlayingOffQueueStillEndsAndStops() async throws {
        let (service, player, library) = try makeStack()
        let list = [
            try makeTrack(title: "A", artist: "Artist", library: library),
            try makeTrack(title: "B", artist: "Artist", library: library)
        ]
        try makeTrack(title: "C", artist: "Artist", library: library) // more library, but ∞ is off
        service.play(list[0], in: list)
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertFalse(service.isPlaying)
        XCTAssertTrue(service.queue.isEmpty)
    }

    // MARK: - On

    func testKeepPlayingOnQueueGrowsAndContinues() async throws {
        let (service, player, library) = try makeStack()
        let queued = [
            try makeTrack(title: "A", artist: "Artist", library: library),
            try makeTrack(title: "B", artist: "Artist", library: library)
        ]
        let extra = try makeTrack(title: "C", artist: "Other", library: library)
        service.play(queued[0], in: queued)
        service.toggleKeepPlaying()
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertTrue(service.isPlaying, "the queue grew, so playback should continue")
        XCTAssertEqual(service.currentTrack?.id, extra.id)
        XCTAssertEqual(service.queue.count, 3)
    }

    func testKeepPlayingNeverAppendsATrackAlreadyInTheQueue() async throws {
        let (service, player, library) = try makeStack()
        let queued = [
            try makeTrack(title: "A", artist: "Artist", library: library),
            try makeTrack(title: "B", artist: "Artist", library: library)
        ]
        let fresh = try makeTrack(title: "C", artist: "Artist", library: library)
        service.play(queued[0], in: queued)
        service.toggleKeepPlaying()
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(
            service.queue.map(\.id),
            [queued[0].id, queued[1].id, fresh.id],
            "A and B are already queued and must not be appended again"
        )
    }

    func testKeepPlayingPrefersSameArtist() async throws {
        let (service, player, library) = try makeStack()
        let queued = [try makeTrack(title: "A", artist: "Wanted", library: library)]
        let other = try makeTrack(title: "Other Artist Track", artist: "Someone Else", library: library)
        let sameArtist = try makeTrack(title: "Same Artist Track", artist: "Wanted", library: library)
        service.play(queued[0], in: queued)
        service.toggleKeepPlaying()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.currentTrack?.id, sameArtist.id,
                       "a same-artist candidate exists, so it wins over the rest of the library")
        XCTAssertFalse(service.queue.contains { $0.id == other.id })
    }

    // MARK: - The seventh site: appending while shuffled

    func testKeepPlayingAppendingWhileShuffledGrowsBothArrays() async throws {
        let (service, player, library) = try makeStack()
        let queued = [
            try makeTrack(title: "A", artist: "Artist", library: library),
            try makeTrack(title: "B", artist: "Artist", library: library)
        ]
        let fresh = try makeTrack(title: "C", artist: "Artist", library: library)
        service.play(queued[0], in: queued)
        service.toggleShuffle()
        service.toggleKeepPlaying()
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(
            Set(service.queue.map(\.id)),
            Set(service.unshuffledQueue.map(\.id)),
            "queue and unshuffledQueue must hold the same set after an append"
        )
        XCTAssertTrue(
            service.unshuffledQueue.contains { $0.id == fresh.id },
            "the appended track must land in unshuffledQueue too, or turning shuffle off later would drop it"
        )
    }

    // MARK: - Repeat outranks ∞

    func testKeepPlayingNeverRunsWithRepeatAllArmed() async throws {
        let (service, player, library) = try makeStack()
        let queued = [
            try makeTrack(title: "A", artist: "Artist", library: library),
            try makeTrack(title: "B", artist: "Artist", library: library)
        ]
        try makeTrack(title: "C", artist: "Artist", library: library)
        service.play(queued[0], in: queued)
        service.toggleKeepPlaying()
        service.cycleRepeatMode() // .all
        service.next()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(service.queue.count, 2, "repeat-all wraps; ∞ must never get a turn")
        XCTAssertEqual(service.currentTrack?.id, queued[0].id)
    }

    // MARK: - Batching

    func testKeepPlayingAppendsAtMostOneBatchAtATime() async throws {
        let (service, player, library) = try makeStack()
        let queued = [try makeTrack(title: "A", artist: "Artist", library: library)]
        for i in 0..<(PlaybackService.keepPlayingBatchSize + 1) {
            try makeTrack(title: "Extra \(i)", artist: "Other", library: library)
        }
        service.play(queued[0], in: queued)
        service.toggleKeepPlaying()

        player.simulateFinish()
        await Task.yield()

        XCTAssertEqual(
            service.queue.count, 1 + PlaybackService.keepPlayingBatchSize,
            "one batch, not the whole remaining library"
        )
    }

    // MARK: - Persistence

    func testFreshPlaybackStateDefaultsToKeepPlayingDisabled() {
        XCTAssertFalse(PlaybackState().isKeepPlayingEnabled)
    }

    func testTogglingKeepPlayingPersists() throws {
        let (service, _, library) = try makeStack()
        let list = [try makeTrack(title: "A", artist: "Artist", library: library)]
        service.play(list[0], in: list)

        service.toggleKeepPlaying()

        XCTAssertTrue(library.playbackState.isKeepPlayingEnabled)
    }

    func testKeepPlayingSurvivesRestore() async throws {
        let (service, _, library) = try makeStack()
        let list = [try makeTrack(title: "A", artist: "Artist", library: library)]
        service.play(list[0], in: list)
        service.toggleKeepPlaying()

        let relaunched = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await relaunched.restoreFromPersistedState()

        XCTAssertTrue(relaunched.isKeepPlayingEnabled)
    }
```

- [ ] **Step 7: Run the whole file, then the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EvenstarTests/PlaybackServiceKeepPlayingTests 2>&1 \
  | grep -E "Test case .*(passed|failed)" | sed 's/ on .*//'
```

Expected: 11 passed, 0 failed.

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/keepplaying1.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/keepplaying1.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 426 423 0 3` — the 415 already there plus these 11, with the pre-existing 3 `SystemVolumeSliderTests` simulator skips unchanged. Zero failures. If any pre-existing test fails, **stop and report it**; do not modify it.

- [ ] **Step 8: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Models/PlaybackState.swift \
  Evenstar/Evenstar/Services/PlaybackService.swift \
  Evenstar/EvenstarTests/PlaybackServiceKeepPlayingTests.swift
git commit -m "feat: add ∞ (keep playing) fallback ladder to PlaybackService"
```

---

### Task 2: The ∞ pill in `QueuePanel`

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/QueuePanel.swift`
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes (from Task 1): `PlaybackService.isKeepPlayingEnabled: Bool`, `.toggleKeepPlaying() -> Void`.
- Produces: nothing for later tasks — this is a UI leaf.

No dedicated XCTest: the pill reuses `QueuePanel`'s existing `pill(systemImage:isOn:label:trigger:action:)` helper, which the shuffle and repeat pills already use with no test of their own (view styling, not extractable logic). Verified by the full-suite regression run in Step 3 and by manual QA against the design.

- [ ] **Step 1: Add the pill and the footer**

In `Evenstar/Evenstar/Features/Player/QueuePanel.swift`, add a new `@State` beside `shuffleTaps`/`repeatTaps` (around line 21):

```swift
    @State private var keepPlayingTaps = 0
```

Change `body` (around line 55) to show a footer only while ∞ is on:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pillRow
                .offset(y: Self.riseDistance * (1 - factor))
                .opacity(factor)
            if playback.isKeepPlayingEnabled {
                keepPlayingFooter
                    .offset(y: Self.riseDistance * (1 - factor))
                    .opacity(factor)
            }
            upcomingList
                .offset(y: Self.riseDistance * (1 - factor))
                .opacity(factor)
        }
    }
```

Add the footer view, right after `pillRow`'s closing brace (around line 128):

```swift

    /// Says where ∞'s extra tracks come from — the honesty the design
    /// insists on in place of a claim of similarity Evenstar cannot make.
    private var keepPlayingFooter: some View {
        Text("Nhạc tiếp theo lấy từ thư viện của bạn.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
```

Add the third pill to `pillRow`, inside the `HStack`, right after the repeat pill's closing brace:

```swift

            pill(
                systemImage: "infinity",
                isOn: playback.isKeepPlayingEnabled,
                label: String(localized: "Phát tiếp",
                              bundle: AppLanguage.resolvedBundle,
                              locale: AppLanguage.resolvedLocale),
                trigger: keepPlayingTaps
            ) {
                keepPlayingTaps += 1
                playback.toggleKeepPlaying()
            }
```

- [ ] **Step 2: Add the two new strings to the String Catalog**

In `Evenstar/Evenstar/Localizable.xcstrings`, the `"strings"` dictionary currently ends with the `"Cổ điển"` entry, immediately before the closing `},` of `"strings"`. Change:

```json
        "vi" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cổ điển"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

to:

```json
        "vi" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cổ điển"
          }
        }
      }
    },
    "Phát tiếp" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Keep playing"
          }
        },
        "vi" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Phát tiếp"
          }
        }
      }
    },
    "Nhạc tiếp theo lấy từ thư viện của bạn." : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Next tracks come from your library."
          }
        },
        "vi" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nhạc tiếp theo lấy từ thư viện của bạn."
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 3: Build and run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/keepplaying2.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/keepplaying2.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 426 423 0 3` — unchanged from Task 1's end; no tests were added or broken by a pure-UI change.

- [ ] **Step 4: Manual QA**

Run the app (simulator or device), play a local track, open the queue, and confirm: the ∞ pill sits after Shuffle and Repeat; tapping it fills with the accent colour and shows the footer sentence; playing to the end of a short queue with ∞ on continues from the library instead of stopping.

- [ ] **Step 5: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/QueuePanel.swift \
  Evenstar/Evenstar/Localizable.xcstrings
git commit -m "feat: surface ∞ (keep playing) as a pill in QueuePanel"
```

---

### Task 3: The queue capsule appears on press, not while active

**Files:**
- Modify: `Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new for later tasks.

No dedicated XCTest: this moves a `configuration.isPressed`-driven capsule from one view to a `ButtonStyle`, with no extractable pure function — the same class of change as the rest of `QueueToggleStyle`/`TransportButtonStyle`, neither of which carries tests today. Verified by the full-suite regression run and by manual QA.

- [ ] **Step 1: Move the capsule into `QueueToggleStyle`, keyed on `isPressed`**

In `Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift`, change `Interaction.body`:

```swift
        var body: some View {
            configuration.label
                // Moved here from `NowPlayingContent`'s queue button, and
                // re-keyed on `configuration.isPressed` rather than
                // `showingQueue` — see the design's "queue capsule appears on
                // press" note. This costs the only strong "the queue is
                // open" signal; what remains is the glyph's own colour,
                // which `NowPlayingContent` still drives from `showingQueue`.
                // That is a deliberate trade, not a bug to rediscover.
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(configuration.isPressed ? 1 : 0)
                        .scaleEffect(configuration.isPressed ? 1 : 0.6)
                }
                .scaleEffect(configuration.isPressed ? QueueToggleStyle.pressedScale : 1)
                .animation(BottomBarStyle.press, value: configuration.isPressed)
                .tapHalo(trigger: presses)
                .sensoryFeedback(.impact(weight: .light), trigger: presses)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { presses += 1 }
                }
        }
```

- [ ] **Step 2: Remove the old `showingQueue`-driven capsule**

In `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, change `queueToggleRow`'s `Image`:

```swift
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        playback.currentTrack == nil ? AnyShapeStyle(.tertiary)
                            : showingQueue ? AnyShapeStyle(Color.accentColor)
                                           : AnyShapeStyle(.secondary)
                    )
                    .frame(width: Self.queueGlyphFrame, height: Self.queueGlyphFrame)
                    .contentShape(Rectangle())
```

(This removes the `.background { Capsule()... }` block that used to sit between `.frame` and `.contentShape` — that capsule now lives in `QueueToggleStyle`.)

- [ ] **Step 3: Build and run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/presscapsule.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/presscapsule.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 426 423 0 3` — unchanged.

- [ ] **Step 4: Manual QA**

Open the expanded player. Confirm the queue glyph's capsule backdrop is visible only while a finger is down on it (press and hold), not for the whole time the queue panel is open. Confirm the glyph itself still turns accent-coloured while the queue is open (that signal is unchanged).

- [ ] **Step 5: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift \
  Evenstar/Evenstar/Features/Player/NowPlayingContent.swift
git commit -m "fix: queue capsule appears on press, not while queue is open"
```

---

### Task 4: The queue list's side padding matches the content above it

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/QueuePanel.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new for later tasks.

No dedicated XCTest: `listRowInsets` is a layout-only fix with no pure function to pin, matching the rest of `QueuePanel`'s (untested) row styling. Verified by the full-suite regression run and by manual QA/screenshot.

- [ ] **Step 1: Zero the list's own horizontal row inset**

In `Evenstar/Evenstar/Features/Player/QueuePanel.swift`, add a constant beside `pillHitPad` (around line 53):

```swift
    /// The `List`'s own per-row inset, replaced entirely rather than
    /// adjusted. The panel's outer 24pt padding (`PlayerCard
    /// .queuePanelSideMargin`, applied where this panel is placed) already
    /// supplies the horizontal margin that lines rows up with `header` and
    /// `pillRow` above them; `List`'s default row inset then indents on top
    /// of that, which is the visible mismatch this fixes. Vertical padding
    /// is kept close to the list's previous row height so nothing else about
    /// row size changes.
    private static let rowVerticalInset: CGFloat = 8
```

In `upcomingList`, add `.listRowInsets(...)` to the `QueueRow`'s modifier chain, right after `.listRowBackground(Color.clear)`:

```swift
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(
                            top: Self.rowVerticalInset,
                            leading: 0,
                            bottom: Self.rowVerticalInset,
                            trailing: 0
                        ))
```

- [ ] **Step 2: Build and run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/rowinsets.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/rowinsets.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 426 423 0 3` — unchanged.

- [ ] **Step 3: Manual QA / screenshot**

Open the queue with at least two upcoming tracks. Confirm each row's artwork and title start at the same leading x-coordinate as the header artwork and the "Tiếp theo" label above them — no extra indent.

- [ ] **Step 4: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/QueuePanel.swift
git commit -m "fix: queue list rows align with the header and pills above them"
```

---

### Task 5: The queue list extends toward the scrubber, without touching it

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new for later tasks.

**This cap is the fix for a Critical**, and the plan must not soften it: `QueuePanel`'s `List` is a `UIScrollView`, and its pan recogniser previously swallowed `ScrubberBar`'s **28pt** drag strip, making seeking impossible while the queue was open. The reclaimed space below comes only from the title block's own footprint — never past where `ScrubberBar`'s 28pt touch strip begins.

No dedicated XCTest: `contentOffset(fullSize:)` is `private` and already untested (no existing test references it or `contentBudget`), and the new constant follows the same pattern. Verified by the full-suite regression run and by manual QA on both a short queue and a long one, in portrait and landscape.

- [ ] **Step 1: Add the reclaimed-height constant**

In `Evenstar/Evenstar/Features/Player/PlayerCard.swift`, add it right after `contentOffset(fullSize:)`'s closing brace (around line 455):

```swift

    /// How far the queue list may grow past `contentOffset`, into the space
    /// `NowPlayingContent`'s title block reserves but leaves invisible in
    /// queue mode (`titleBlock` stays in the layout at `opacity(0)` rather
    /// than being removed — see its own doc comment for why).
    ///
    /// 81 (the title block's own measured height, per `contentBudget`'s doc)
    /// plus 24 (the `VStack(spacing: 24)` gap before the scrubber) lands the
    /// cap exactly on `ScrubberBar`'s own top edge — the top of its **28pt**
    /// touch strip — never past it. That strip is what a Critical was fixed
    /// over once already: `QueuePanel`'s `List` is a `UIScrollView`, and its
    /// pan recogniser swallowed it, making seeking impossible while the
    /// queue was open. This constant is the boundary that keeps this change
    /// from reopening that defect — close to the scrubber is the
    /// requirement, touching it is the regression.
    private static let queueListReclaimedHeight: CGFloat = 81 + 24
```

- [ ] **Step 2: Raise the queue list's cap by that amount**

In the same file, change the `QueuePanel`'s `.frame(maxHeight:...)` call inside `artworkView`'s `.overlay(alignment: .top)` (around line 1493):

```swift
                    .frame(
                        maxHeight: max(0, Self.contentOffset(fullSize: size) + Self.queueListReclaimedHeight),
                        alignment: .top
                    )
```

Leave `.clipped()` immediately below it untouched — it is what keeps anything that still overflows (a long queue on a short landscape card) from painting past this new, still-bounded cap.

- [ ] **Step 3: Build and run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/listextend.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/listextend.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 426 423 0 3` — unchanged.

- [ ] **Step 4: Manual QA — the regression this must not reopen**

With a queue of at least 6 upcoming tracks open, drag a finger across `ScrubberBar` (the thin bar just below the (invisible) title area) and confirm the track seeks — it must not instead scroll the queue list. Repeat in landscape on an iPhone 17 simulator, where the card is shortest. Confirm the list now reaches visibly closer to the scrubber than before this task, without any row's content painting into or past the scrubber's 28pt strip.

- [ ] **Step 5: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/PlayerCard.swift
git commit -m "fix: queue list reclaims the invisible title block's space, capped above the scrubber"
```

---

### Task 6: The volume slider answers a touch like the scrubber

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/ScrubberBar.swift`
- Modify: `Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`
- Modify: `Evenstar/EvenstarTests/SystemVolumeSliderTests.swift`

**Interfaces:**
- Consumes: `ScrubberBar.restingHeight: CGFloat` (existing, internal), `ScrubberBar.activeHeight: CGFloat` (this task removes `private` so `SystemVolumeSlider` can reuse it, exactly as `restingHeight` already is).
- Produces: `SystemVolumeSlider.init(onTouchDown: () -> Void = {})`, `SystemVolumeSlider.trackImage(color:height:) -> UIImage` (new `height` parameter, defaulted so the two pre-existing call sites in `SystemVolumeSliderTests` keep compiling unchanged).

Self-contained, per the design: it touches no other view besides the one row that hosts it.

- [ ] **Step 1: Write the failing tests**

Append to `Evenstar/EvenstarTests/SystemVolumeSliderTests.swift`, inside the class, after `testTrackImageColourReachesTheBitmap`:

```swift

    // MARK: - Touch response (design Part 2 item 4)

    func testTrackImageAcceptsACustomHeight() {
        let image = SystemVolumeSlider.trackImage(color: .label, height: 12)

        XCTAssertEqual(image.size.height, 12, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.left, 6, accuracy: 0.01)
        XCTAssertEqual(image.capInsets.right, 6, accuracy: 0.01)
    }

    func testTouchDownSwellsTheTrackToTheActiveHeight() throws {
        let (_, slider) = try requireSlider()

        slider.sendActions(for: .touchDown)

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage)
        XCTAssertEqual(minimum.size.height, ScrubberBar.activeHeight, accuracy: 0.01)
    }

    func testReleasingRestoresTheRestingHeight() throws {
        let (_, slider) = try requireSlider()
        slider.sendActions(for: .touchDown)

        slider.sendActions(for: .touchUpInside)

        let minimum = try XCTUnwrap(slider.currentMinimumTrackImage)
        XCTAssertEqual(minimum.size.height, ScrubberBar.restingHeight, accuracy: 0.01)
    }

    func testTouchDownFiresTheCallbackExactlyOnce() throws {
        let view = TintedVolumeView(
            frame: CGRect(x: 0, y: 0, width: 300, height: ScrubberBar.touchHeight)
        )
        var fireCount = 0
        view.onTouchDown = { fireCount += 1 }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.addSubview(view)
        window.isHidden = false
        view.setNeedsLayout()
        view.layoutIfNeeded()
        guard let slider = Self.findSlider(in: view) else {
            throw XCTSkip("MPVolumeView builds no UISlider without audio hardware; run on a device")
        }

        slider.sendActions(for: .touchDown)
        slider.sendActions(for: .touchDown) // a second down without a release in between

        XCTAssertEqual(fireCount, 1, "one press must fire the callback once, not once per event")
    }
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: **compile failure** — `value of type 'TintedVolumeView' has no member 'onTouchDown'` and `extra argument 'height' in call`.

- [ ] **Step 3: Un-privatize `ScrubberBar.activeHeight`**

In `Evenstar/Evenstar/Features/Player/ScrubberBar.swift`, change:

```swift
    private static let activeHeight: CGFloat = 12
```

to:

```swift
    /// Also read by `SystemVolumeSlider`, so the two bars swell to the same
    /// thickness under a touch by construction rather than by two people
    /// picking 12.
    static let activeHeight: CGFloat = 12
```

- [ ] **Step 4: Parameterize `trackImage` by height, and add the touch-down callback**

In `Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift`, change `trackImage(color:)`'s signature and body:

```swift
    static func trackImage(color: UIColor, height: CGFloat = ScrubberBar.restingHeight) -> UIImage {
        let size = CGSize(width: height, height: height)
        let capsule = UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: height / 2
            ).fill()
        }
        return capsule.resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2),
            resizingMode: .stretch
        )
    }
```

Add a stored property to `SystemVolumeSlider` and wire it through `makeUIView`/`updateUIView`:

```swift
struct SystemVolumeSlider: UIViewRepresentable {

    /// Called once per touch-down on the slider, so a caller wanting a
    /// haptic can drive its own `.sensoryFeedback` from it — the same
    /// contract `TransportButtonStyle`/`QueueToggleStyle` use, and for the
    /// same reason given there: SwiftUI owns the generator's lifetime and
    /// respects the system's haptics settings, where a raw
    /// `UIImpactFeedbackGenerator` inside this representable would not.
    var onTouchDown: () -> Void = {}

    @available(iOS, deprecated: 13.0, message: "showsRouteButton is the only way to hide MPVolumeView's route button; AVRoutePickerView is a separate control, not a switch for this one.")
    func makeUIView(context: Context) -> MPVolumeView {
        let view = TintedVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.setVolumeThumbImage(Self.invisibleThumb, for: .normal)
        view.setVolumeThumbImage(Self.invisibleThumb, for: .highlighted)
        view.tintColor = .label
        view.onTouchDown = onTouchDown
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        (uiView as? TintedVolumeView)?.onTouchDown = onTouchDown
    }
```

- [ ] **Step 5: Track press state in `TintedVolumeView` and rebuild the track images**

In the same file, change `TintedVolumeView`:

```swift
final class TintedVolumeView: MPVolumeView {
    /// The appearance the current track images were drawn for, so they are
    /// rebuilt when it changes and not on every layout pass.
    private var renderedStyle: UIUserInterfaceStyle?
    /// Whether the images last drawn were the pressed (swelled) ones — kept
    /// separately from `isPressed` so a press/release toggle also triggers a
    /// rebuild even when the appearance has not changed.
    private var renderedPressed = false
    /// True while a finger is down on the slider — mirrors
    /// `ScrubberBar.isDragging` and drives the same swell, from
    /// `restingHeight` to `ScrubberBar.activeHeight`.
    private var isPressed = false
    private var isObservingSliderTouches = false

    /// Fired once per touch-down — see its doc comment on `SystemVolumeSlider`.
    var onTouchDown: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let slider = Self.findSlider(in: self) else { return }

        if !isObservingSliderTouches {
            isObservingSliderTouches = true
            slider.addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
            slider.addTarget(self, action: #selector(handleTouchUp),
                              for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }

        // On the slider itself, not through
        // `MPVolumeView.setMinimum/MaximumVolumeSliderImage`. Those were tried
        // first and had no visible effect on device — which the simulator
        // could not have shown either way, since `MPVolumeView` draws nothing
        // there. `UISlider`'s own setters do land.
        if renderedStyle != traitCollection.userInterfaceStyle || renderedPressed != isPressed {
            renderedStyle = traitCollection.userInterfaceStyle
            renderedPressed = isPressed
            let filled = UIColor.label.resolvedColor(with: traitCollection)
            let height = isPressed ? ScrubberBar.activeHeight : ScrubberBar.restingHeight
            slider.setMinimumTrackImage(
                SystemVolumeSlider.trackImage(color: filled, height: height),
                for: .normal
            )
            slider.setMaximumTrackImage(
                SystemVolumeSlider.trackImage(color: filled.withAlphaComponent(0.25), height: height),
                for: .normal
            )
        }

        // Centred by hand. `MPVolumeView` lays its slider out against its own
        // idea of the row, which is not the 28pt this view reports, so the bar
        // sat a few points above the speaker glyphs either side of it.
        let centred = (bounds.height - slider.frame.height) / 2
        if abs(slider.frame.minY - centred) > 0.5 {
            slider.frame.origin.y = centred
        }
    }

    @objc private func handleTouchDown() {
        guard !isPressed else { return }
        isPressed = true
        onTouchDown?()
        setNeedsLayout()
    }

    @objc private func handleTouchUp() {
        guard isPressed else { return }
        isPressed = false
        setNeedsLayout()
    }

    /// Searches the whole subtree, not just the direct children.
    ///
    /// The direct-children version silently found nothing. It was written when
    /// only the tint went through here, and the tint appeared to work anyway —
    /// `tintColor` on the outer view reaches the slider on its own, so the walk
    /// contributed nothing and no one noticed it was dead. The track image has
    /// no such fallback, which is what finally exposed it.
    ///
    /// A dump of `subviews` in a unit test shows `[UILabel, MPButton]` in the
    /// simulator, where there is no audio hardware and so no slider at all.
    /// Where a slider does exist, nothing documents how deep it sits, so this
    /// does not assume.
    private static func findSlider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let found = findSlider(in: subview) { return found }
        }
        return nil
    }
}
```

- [ ] **Step 6: Drive a real `.sensoryFeedback` from the call site**

In `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, add a tap counter beside `playPauseTaps` (around line 23):

```swift
    @State private var volumeTaps = 0
```

Change `volume`:

```swift
    private var volume: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .frame(height: ScrubberBar.touchHeight)
            SystemVolumeSlider(onTouchDown: { volumeTaps += 1 })
            Image(systemName: "speaker.wave.3.fill")
                .frame(height: ScrubberBar.touchHeight)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .sensoryFeedback(.impact(weight: .light), trigger: volumeTaps)
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EvenstarTests/SystemVolumeSliderTests 2>&1 \
  | grep -E "Test case .*(passed|failed)" | sed 's/ on .*//'
```

The grep pattern above only matches lines containing "passed" or "failed" — a skipped test's log line contains neither, so a skip will not appear in this output at all, only in the suite-summary check in Step 8. In the iPhone 17 simulator (no audio hardware), `testTrackImagesAreAsThickAsTheScrubber`, `testTheTwoEndsOfTheTrackAreDrawnDifferently`, `testTheSliderIsCentredInTheRow`, `testTouchDownSwellsTheTrackToTheActiveHeight`, `testReleasingRestoresTheRestingHeight` and `testTouchDownFiresTheCallbackExactlyOnce` all throw `XCTSkip` via `requireSlider()` (or, for the last one, its own inline guard).

Expected: **3 lines, all "passed"** — `testTrackImageStretchesFromItsMiddle`, `testTrackImageColourReachesTheBitmap`, `testTrackImageAcceptsACustomHeight`. 0 "failed" lines. Re-run on a physical device to see all 9 pass.

- [ ] **Step 8: Run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/volumeslider.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/volumeslider.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 430 424 0 6` — the 426 already there plus these 4, with 3 more simulator skips (6 total). Zero failures. If any pre-existing test fails, **stop and report it**; do not modify it.

- [ ] **Step 9: Manual QA on a physical device**

`MPVolumeView` draws nothing in the simulator. On a device, touch and hold the volume slider: confirm a light haptic fires once on contact (not continuously while dragging) and the track visibly thickens for the duration of the touch, returning to its resting thickness on release.

- [ ] **Step 10: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/ScrubberBar.swift \
  Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift \
  Evenstar/Evenstar/Features/Player/NowPlayingContent.swift \
  Evenstar/EvenstarTests/SystemVolumeSliderTests.swift
git commit -m "feat: volume slider answers touch with a haptic and a swelling track"
```

---

### Task 7: The accent colour becomes white, app-wide

**Files:**
- Modify: `Evenstar/Evenstar/Assets.xcassets/AccentColor.colorset/Contents.json`
- Modify: `Evenstar/Evenstar/Features/Shared/ProminentActionButton.swift`
- Modify: `Evenstar/Evenstar/Features/Jamendo/JamendoDiscoveryView.swift`
- Modify: `Evenstar/Evenstar/Features/Jamendo/JamendoResultRow.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new for later tasks.

**Do not combine this task with anything else.** Six files in the codebase reference `Color.accentColor`/`accentColor`: these four, plus `Evenstar/Evenstar/Features/Player/QueuePanel.swift`, `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, and `Evenstar/Evenstar/Features/Drive/DriveFoldersView.swift`. Those last three are deliberately **left untouched** by this task:
- `QueuePanel`'s shuffle/repeat/∞ pills and `NowPlayingContent`'s queue-open glyph use the accent only while sitting over the player's own artwork, which the darkening overlay already keeps dark — the design states plainly that white there "is correct and needs nothing."
- `DriveFoldersView`'s "Quét lại" swipe action `.tint(.accentColor)` is not one of the three the design names as sitting on a light background needing its own fix, and the design's own accounting of what breaks names exactly three controls, not this one. Do not soften that list by adding a fourth without a design decision — flag it for a follow-up đợt instead if it is found to need one.

**Three controls sit on light backgrounds and go invisible if only the asset changes; fixing them is this task's whole reason to exist, in the same commit as the asset:**
1. `ProminentActionButtonStyle` fills a capsule with the accent and draws a **black** label on top (a mitigation for the *old* purple accent's contrast — see its current doc comment's WCAG table). Once the accent is white, the *fill itself* — a white capsule — is invisible against this app's light backgrounds (`.systemGroupedBackground` lists, `ContentUnavailableView` actions), whatever colour the label is. Fixed by decoupling the fill from the accent entirely: `Color.primary` fill, `Color(.systemBackground)` label — the inverse of the page behind it, in both appearances, so the button can never colour-match its own background again.
2. `JamendoDiscoveryView`'s `GenreChip` fills the **selected** state with the accent and draws its label in literal `.white` — "the exact pair that already shipped invisible once, at 0.12 opacity, and white would be worse" per the design. Fixed with the same technique as (1): `Color.primary` fill, `Color(.systemBackground)` label.
3. `JamendoResultRow`'s save button tints its `plus.circle` glyph directly with the accent, with no fill behind it at all — an accent turned white makes it disappear outright rather than merely lose contrast. Fixed per the design's second strategy — "the label carrying the state instead of the fill": the glyph's own shape (`plus.circle` vs. `checkmark.circle.fill`) and weight (`.primary` vs. `.secondary`) already say saved/unsaved: it never needed the accent color to say it a second time. Tinted `.primary` instead.

No dedicated XCTest: none of the three fixes exposes a pure function, and no existing test in the suite pins an accent RGB value or either affected view's colours (`grep`-confirmed against `EvenstarTests` before writing this task). Verified by the full-suite regression run and by manual QA/screenshot against all three controls, in both light and dark mode.

- [ ] **Step 1: Change the asset**

Replace the full contents of `Evenstar/Evenstar/Assets.xcassets/AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "1.000",
          "green" : "1.000",
          "red" : "1.000"
        }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "1.000",
          "green" : "1.000",
          "red" : "1.000"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 2: Fix `ProminentActionButtonStyle`**

Replace the full contents of `Evenstar/Evenstar/Features/Shared/ProminentActionButton.swift`:

```swift
import SwiftUI

/// The app's prominent action button: a solid capsule with a label drawn in
/// the inverse of it.
///
/// **No longer tied to the accent colour.** It used to fill with
/// `Color.accentColor` and rely on a hardcoded `.black` label to stay
/// readable against the old purple-pink accent. The accent is white now
/// (design Part 2 item 5), and a white-filled capsule is invisible against
/// the light backgrounds this button actually sits on — `ContentUnavailableView`
/// actions, `.systemGroupedBackground` lists — whatever colour its label is.
///
/// `Color.primary`/`Color(.systemBackground)` sidesteps the whole class of
/// bug: the fill is always the *opposite* of the page behind it, in both
/// appearances, so the button can never colour-match its background by
/// construction — accent or no accent, light mode or dark.
struct ProminentActionButtonStyle: ButtonStyle {
    /// These give a 33pt-tall button against the 28pt `.borderedProminent`
    /// measured before it was replaced, so the three buttons using it grew
    /// slightly. Left that way deliberately: 28pt was already well under
    /// Apple's 44pt minimum touch target, and nothing around these buttons is
    /// tight enough for 5pt to matter.
    private static let verticalPadding: CGFloat = 5
    private static let horizontalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(Capsule().fill(Color.primary))
            // The system style dims on press; without this the button would be
            // the one control in the app that does not answer a finger.
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProminentActionButtonStyle {
    static var prominentAction: Self { ProminentActionButtonStyle() }
}
```

- [ ] **Step 3: Fix `GenreChip`'s selected fill and label**

In `Evenstar/Evenstar/Features/Jamendo/JamendoDiscoveryView.swift`, change `GenreChip.body`'s `Text`:

```swift
            Text(genre.label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                // `Color(.systemBackground)`, not `.white`: the fill below is
                // `Color.primary` now, not the accent, and a literal white
                // label would go invisible against a light-mode fill — the
                // same pair that already shipped invisible once before, at
                // 0.12 opacity. See the fill's own comment.
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                // `Color.primary`, not the accent colour. The accent is white
                // now (design Part 2 item 5), and a white fill is invisible
                // against this screen's light backgrounds regardless of what
                // colour the label is — the same failure `ProminentActionButtonStyle`
                // was rewritten to avoid. `Color.primary` inverts with the page
                // in both appearances instead, so the selected chip stays
                // visible independent of the accent.
                .background(isSelected ? Color.primary : Color(.tertiarySystemFill),
                            in: Capsule())
                .contentShape(Capsule())
```

- [ ] **Step 4: Fix the Jamendo save button's tint**

In `Evenstar/Evenstar/Features/Jamendo/JamendoResultRow.swift`, change the save `Button`'s `Image`:

```swift
            Button(action: onSave) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    // `.primary`, not the accent colour. This glyph has no
                    // fill of its own to sit on — it tints directly against
                    // the row's own background — so an accent turned white
                    // (design Part 2 item 5) makes it disappear outright
                    // rather than merely lose contrast. The glyph's own shape
                    // (plus vs. filled checkmark) and weight (`.primary` vs.
                    // `.secondary`) already carry the saved/unsaved state; the
                    // accent was never required to say it a second time.
                    .foregroundStyle(isSaved ? AnyShapeStyle(.secondary)
                                             : AnyShapeStyle(Color.primary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
```

- [ ] **Step 5: Build and run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/accent.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/accent.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['passedTests'], d['failedTests'], d['skippedTests'])"
```

Expected: `Passed 430 424 0 6` — unchanged from Task 6's end.

- [ ] **Step 6: Manual QA/screenshot — all three, both appearances**

In light mode: confirm the "Thử lại" retry button (`JamendoDiscoveryView.statusRow`, reached by forcing a load error) is a dark, clearly visible capsule with a light label; confirm a tapped genre chip is a dark, clearly visible pill with a light label distinguishable from the unselected `.tertiarySystemFill` chips beside it; confirm an unsaved Jamendo result's `+` glyph is clearly visible against the row. Repeat all three in dark mode. Separately, open the expanded player and confirm the shuffle/repeat/∞ pills and the queue-open glyph are still white and legible over the artwork — those three were deliberately left unchanged.

- [ ] **Step 7: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Assets.xcassets/AccentColor.colorset/Contents.json \
  Evenstar/Evenstar/Features/Shared/ProminentActionButton.swift \
  Evenstar/Evenstar/Features/Jamendo/JamendoDiscoveryView.swift \
  Evenstar/Evenstar/Features/Jamendo/JamendoResultRow.swift
git commit -m "feat: accent colour becomes white app-wide, with the three controls it would otherwise hide"
```

---

## Self-Review

**Spec coverage:**
- Part 1, "What ∞ does here" (two-rung ladder, `Track` has no genre field) → Task 1, `extendQueueForKeepPlaying`.
- Part 1, "Appended in batches" → Task 1, `keepPlayingBatchSize`, pinned by `testKeepPlayingAppendsAtMostOneBatchAtATime`.
- Part 1, "It cannot collide with repeat" → Task 1, `handleFinish()`'s `.off`-only branch, pinned by `testKeepPlayingNeverRunsWithRepeatAllArmed`.
- Part 1, "The place this will break" (shuffle invariant, the seventh site) → Task 1, `extendQueueForKeepPlaying`'s `if isShuffled { unshuffledQueue.append(...) }`, pinned by `testKeepPlayingAppendingWhileShuffledGrowsBothArrays`.
- Part 1, "Naming" (Phát tiếp / Keep playing, footer, ∞ glyph) → Task 2.
- Part 1, "Persistence" (literal default) → Task 1, `PlaybackState.isKeepPlayingEnabled = false`, pinned by `testFreshPlaybackStateDefaultsToKeepPlayingDisabled`.
- Part 1, "Testing" bullet list (7 items) → all 7 covered by name in Task 1's tests; the exhaustion test is written and run first, per its own instruction.
- Part 2 item 1 (press-only capsule) → Task 3.
- Part 2 item 2 (list padding) → Task 4.
- Part 2 item 3 (list extends toward scrubber, capped above the 28pt strip) → Task 5.
- Part 2 item 4 (volume slider haptic + swell) → Task 6.
- Part 2 item 5 (white accent + the three fixes) → Task 7.

**Placeholder scan:** no "TBD"/"add appropriate"/"similar to Task N" found; every code step carries real code, every test step carries a real assertion, every `xcodebuild` step carries the exact command and an expected number.

**Type/name consistency checked across tasks:**
- `PlaybackState.isKeepPlayingEnabled` (Task 1) matches `PlaybackService.isKeepPlayingEnabled`/`toggleKeepPlaying()` (Task 1) matches the read/call sites in `QueuePanel` (Task 2).
- `ScrubberBar.activeHeight` un-privatized in Task 6, Step 3, before Task 6, Step 4/5 read it from `SystemVolumeSlider.swift`/`TintedVolumeView` — ordered correctly within the task.
- `SystemVolumeSlider.trackImage(color:height:)`'s new `height` parameter carries a default equal to the old fixed value (`ScrubberBar.restingHeight`), so the two pre-existing call sites in `SystemVolumeSliderTests` (`trackImage(color: .label)`, `trackImage(color: UIColor.black)`) keep compiling without being touched — satisfies "never modify a pre-existing test."
- Running total of tests (415 baseline) is threaded through every task's "run the whole suite" step in the order the tasks are listed: 426 after Task 1, unchanged through Tasks 2–5, 430 after Task 6, unchanged through Task 7 — each number double-checked against the cumulative count of new tests added by that point (11, then +4).
- Task 7's file list and its explicit "left untouched" paragraph were added after checking `grep -rln "accentColor" Evenstar/Evenstar/**/*.swift`, which returns exactly six files; three of them are fixed here and three are named and deliberately left alone, so a reviewer checking "did this really touch every accent site" finds an answer for all six rather than three fixed and three silently unmentioned.
