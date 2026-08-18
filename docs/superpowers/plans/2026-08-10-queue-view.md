# Queue View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A queue panel in the expanded player — opened by one icon, showing what plays next, reorderable by drag, and holding the shuffle and repeat pills.

**Architecture:** `PlaybackService` gains two methods that work in *tail offsets* — the view never does arithmetic against `queueIndex`. A new `QueuePanel` view holds the header, the pills (moved out of `NowPlayingContent`) and the list. `PlayerCard` owns a `showingQueue` flag and swaps the artwork for the panel; everything from the scrubber down is untouched by the switch.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest. iOS 18.0 deployment target.

**Spec:** `docs/superpowers/specs/2026-08-10-queue-view-design.md`

## Global Constraints

- **NEVER edit `Evenstar/Evenstar.xcodeproj/project.pbxproj` or any `.xcscheme`.** New Swift files are picked up automatically — Xcode 16 synced folders.
- Every `xcodebuild` invocation passes `-configuration Debug` explicitly. The scheme's TestAction is set to Release and must not be relied on.
- Build tests with `clean build-for-testing`, never plain `build`. A plain `build` overwrites the app bundle without the test PlugIn, and the next `test-without-building` fails with "Failed to create a bundle instance … EvenstarTests.xctest".
- Simulator destination: `platform=iOS Simulator,name=iPhone 17`.
- No third-party libraries. SwiftUI only; `UIViewRepresentable` permitted, `UIViewControllerRepresentable` not. No `try!`. No silently swallowed `catch {}`.
- Never modify a pre-existing test to make new code pass. If one fails, stop and report it.
- Every new user-visible string goes in `Evenstar/Evenstar/Localizable.xcstrings` with **both** `vi` and `en`. Vietnamese is the source language. Edit with 2-space indent and `" : "` separators, preserving existing key order — a re-serialisation turns a small change into a 1300-line diff.
- `PlayerCard.contentBudget` must not be raised. Read its doc comment: ~380pt of stack against ~400pt available, and it records the same overrun shipping twice.
- Suite is at **387 tests** before this plan starts.

---

### Task 1: `upcoming`, `moveUpcoming`, `playUpcoming`

Pure queue arithmetic. No view.

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift`
- Test: `Evenstar/EvenstarTests/PlaybackServiceUpcomingTests.swift` (create)

**Interfaces:**
- Consumes: `queue: [any Playable]`, `queueIndex: Int`, `currentTrack`, `isShuffled`, `unshuffledQueue`, `persistImmediately()`, and the private `advance(to:)`, `failureSkipRun`, `explicitSelections` — all already present.
- Produces, for Tasks 2 and 3:
  - `PlaybackService.upcoming: [any Playable]` — the tracks after the playing one
  - `PlaybackService.moveUpcoming(from: IndexSet, to: Int)` — offsets into `upcoming`
  - `PlaybackService.playUpcoming(at: Int)` — offset into `upcoming`

- [ ] **Step 1: Write the failing tests**

Create `Evenstar/EvenstarTests/PlaybackServiceUpcomingTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// The queue view's three service entry points.
///
/// All offsets in `moveUpcoming` and `playUpcoming` are into `upcoming` — the
/// tail — not into `queue`. Every test here asserts against that, because a
/// method that quietly took queue indices would still pass a test that only
/// ever moved the first element.
@MainActor
final class PlaybackServiceUpcomingTests: XCTestCase {

    private func makeStack(
        shuffleTail: @escaping ([any Playable]) -> [any Playable] = { $0.reversed() }
    ) throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player,
            nowPlaying: MockNowPlayingPublisher(),
            library: library,
            shuffleTail: shuffleTail
        )
        return (service, player, library)
    }

    private func tracks(_ count: Int, library: LibraryService) throws -> [Track] {
        var out: [Track] = []
        for i in 0..<count {
            let t = Track(
                title: "Track \(i)",
                artistName: "Artist",
                albumTitle: "Album",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3",
                format: "mp3"
            )
            try library.insert(t)
            out.append(t)
        }
        return out
    }

    private func titles(_ tracks: [any Playable]) -> [String] { tracks.map(\.title) }

    // MARK: - upcoming

    func testUpcomingIsEverythingAfterThePlayingTrack() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()

        XCTAssertEqual(titles(service.upcoming), ["Track 2", "Track 3", "Track 4"])
    }

    func testUpcomingIsEmptyOnTheLastTrack() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[2], in: all)

        XCTAssertTrue(service.upcoming.isEmpty)
    }

    func testUpcomingIsEmptyWithNoQueue() throws {
        let (service, _, _) = try makeStack()

        XCTAssertTrue(service.upcoming.isEmpty)
    }

    // MARK: - moveUpcoming

    /// The offsets are into `upcoming`. Moving *its* first element must move
    /// `queue[queueIndex + 1]` — a method that took queue indices instead would
    /// move the playing track here and this assertion is what catches it.
    func testMoveUpcomingOffsetsAreIntoTheTailNotTheQueue() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()
        // queue: [0, 1, |2, 3, 4], playing index 1, upcoming [2, 3, 4]

        service.moveUpcoming(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(titles(service.queue), ["Track 0", "Track 1", "Track 3", "Track 4", "Track 2"])
    }

    func testMoveUpcomingLeavesThePlayingTrackAndIndexAlone() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.next()
        service.next()
        XCTAssertEqual(service.currentTrack?.title, "Track 2", "precondition")

        service.moveUpcoming(from: IndexSet(integer: 1), to: 0)

        XCTAssertEqual(service.queueIndex, 2)
        XCTAssertEqual(service.currentTrack?.title, "Track 2")
        XCTAssertEqual(Array(titles(service.queue).prefix(3)), ["Track 0", "Track 1", "Track 2"])
    }

    func testMoveUpcomingKeepsEveryTrack() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)

        service.moveUpcoming(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(Set(service.queue.map(\.id)), Set(all.map(\.id)))
        XCTAssertEqual(service.queue.count, 5)
    }

    func testMoveUpcomingOnAnEmptyTailDoesNothing() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[2], in: all)

        service.moveUpcoming(from: IndexSet(integer: 0), to: 1)

        XCTAssertEqual(titles(service.queue), ["Track 0", "Track 1", "Track 2"])
        XCTAssertEqual(service.queueIndex, 2)
    }

    /// The spec's ruling: a drag edits the shuffled arrangement, so turning
    /// shuffle off discards it and restores what was there before the shuffle.
    func testTurningShuffleOffAfterAReorderStillRestoresTheOriginalOrder() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        service.moveUpcoming(from: IndexSet(integer: 0), to: 3)

        service.toggleShuffle()

        XCTAssertEqual(titles(service.queue), ["Track 0", "Track 1", "Track 2", "Track 3", "Track 4"])
    }

    /// A reorder is a queue change like any other, so it has to reach the
    /// store. `moveUpcoming` calls `persistImmediately()` for that reason;
    /// without it the order would survive until the app was killed and no
    /// longer.
    func testAReorderSurvivesASaveAndRestore() async throws {
        let library = try InMemoryLibrary.make()
        let first = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        let all = try tracks(4, library: library)
        first.play(all[0], in: all)
        first.moveUpcoming(from: IndexSet(integer: 0), to: 3)
        let reordered = first.queue.map(\.id)

        let second = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        await second.restoreFromPersistedState()

        XCTAssertEqual(second.queue.map(\.id), reordered)
    }

    // MARK: - playUpcoming

    func testPlayUpcomingPlaysTheTrackAtThatTailOffset() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        // upcoming: [1, 2, 3, 4]; offset 2 is "Track 3"

        service.playUpcoming(at: 2)

        XCTAssertEqual(service.currentTrack?.title, "Track 3")
        XCTAssertEqual(service.queueIndex, 3)
    }

    /// `play(_:in:)` would rebuild the queue and, with shuffle armed, reshuffle
    /// the tail and reset `unshuffledQueue` — so tapping row three would
    /// silently reorder everything below it. This is why `playUpcoming` exists.
    func testPlayUpcomingDoesNotReshuffleOrResetTheUnshuffledOrder() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(5, library: library)
        service.play(all[0], in: all)
        service.toggleShuffle()
        let orderBefore = service.queue.map(\.id)
        let unshuffledBefore = service.unshuffledQueue.map(\.id)

        service.playUpcoming(at: 1)

        XCTAssertEqual(service.queue.map(\.id), orderBefore, "the queue was reordered")
        XCTAssertEqual(service.unshuffledQueue.map(\.id), unshuffledBefore, "the restore order was reset")
        XCTAssertTrue(service.isShuffled)
    }

    func testPlayUpcomingPastTheEndDoesNothing() throws {
        let (service, _, library) = try makeStack()
        let all = try tracks(3, library: library)
        service.play(all[0], in: all)

        service.playUpcoming(at: 99)

        XCTAssertEqual(service.queueIndex, 0)
        XCTAssertEqual(service.currentTrack?.title, "Track 0")
    }

    func testPlayUpcomingWithNoQueueDoesNothing() throws {
        let (service, _, _) = try makeStack()

        service.playUpcoming(at: 0)

        XCTAssertNil(service.currentTrack)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep error: | head -3
```

Expected: `value of type 'PlaybackService' has no member 'upcoming'`.

- [ ] **Step 3: Add the three members**

In `Evenstar/Evenstar/Services/PlaybackService.swift`, add to the `// MARK: - Public` section, immediately after `func toggleShuffle()`:

```swift
    /// The tracks after the playing one — what the queue panel lists.
    ///
    /// Computed rather than stored: `queue` and `queueIndex` are the truth, and
    /// a stored copy would be one more thing to keep in step with them. Empty
    /// when nothing is playing, and when the playing track is the last.
    var upcoming: [any Playable] {
        guard queue.indices.contains(queueIndex) else { return [] }
        let start = queueIndex + 1
        guard start < queue.count else { return [] }
        return Array(queue[start...])
    }

    /// Reorders the upcoming tracks.
    ///
    /// **`source` and `destination` are offsets into `upcoming`, not into
    /// `queue`.** The view hands over exactly what `.onMove` gave it and never
    /// does arithmetic against `queueIndex`; the conversion happens here, once,
    /// where it can be tested.
    ///
    /// `queueIndex` cannot move, because every index this touches is strictly
    /// greater than it — the same property that lets `applyShuffleToTail` leave
    /// the index alone.
    ///
    /// **`unshuffledQueue` is deliberately untouched.** Turning shuffle off
    /// restores the order that existed before the shuffle, and a drag is an
    /// edit to the shuffled arrangement, so it goes when that arrangement does.
    /// That ruling is also what keeps the two arrays consistent for free: they
    /// must hold the same *set*, and a permutation cannot change a set. Without
    /// it this method would have to define where a track dragged in the
    /// shuffled order belongs in the original one, which has no non-arbitrary
    /// answer.
    func moveUpcoming(from source: IndexSet, to destination: Int) {
        guard queue.indices.contains(queueIndex) else { return }
        let start = queueIndex + 1
        guard start < queue.count else { return }
        var tail = Array(queue[start...])
        tail.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange(start..<queue.count, with: tail)
        persistImmediately()
    }

    /// Jumps to an upcoming track, leaving the queue's order as it stands.
    ///
    /// `offset` is into `upcoming`, as above.
    ///
    /// **Not `play(_:in:)`.** That method rebuilds the queue from its argument
    /// and, with shuffle armed, reshuffles the tail and resets
    /// `unshuffledQueue` — so tapping the third row would silently reorder
    /// everything below it and throw away the order shuffle restores to.
    func playUpcoming(at offset: Int) {
        guard queue.indices.contains(queueIndex) else { return }
        let target = queueIndex + 1 + offset
        guard queue.indices.contains(target) else { return }
        // The two counters `play(_:in:)` resets for a deliberate tap. This is
        // one: whatever the last run skipped past has nothing to do with the
        // row the user just chose.
        failureSkipRun = 0
        explicitSelections += 1
        advance(to: target)
    }
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EvenstarTests/PlaybackServiceUpcomingTests 2>&1 \
  | grep -E "Test case .*(passed|failed)" | sed 's/ on .*//'
```

Expected: 13 passed, 0 failed. Then the whole suite:

```bash
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/queue1.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/queue1.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['failedTests'])"
```

Expected: `Passed 400 0`. If a pre-existing test fails, **stop and report it**.

- [ ] **Step 5: Mutation check — prove the offsets are really tail-relative**

Temporarily change `moveUpcoming` to treat the offsets as queue indices:

```swift
        queue.move(fromOffsets: source, toOffset: destination)
```

(dropping the tail slicing). Re-run `-only-testing:EvenstarTests/PlaybackServiceUpcomingTests`.

Expected: `testMoveUpcomingOffsetsAreIntoTheTailNotTheQueue` and
`testMoveUpcomingLeavesThePlayingTrackAndIndexAlone` **fail**. Restore the
correct body and confirm they pass again. Report both outcomes.

- [ ] **Step 6: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Services/PlaybackService.swift \
        Evenstar/EvenstarTests/PlaybackServiceUpcomingTests.swift
git commit -m "feat: upcoming, moveUpcoming và playUpcoming cho màn hàng đợi

Cả hai hàm nhận offset trong phần đuôi chứ không phải chỉ số trong
queue, nên view không phải làm số học với queueIndex và không thể làm
sai. Chuyển đổi nằm ở một chỗ, có test.

Kéo sắp xếp không chạm unshuffledQueue: tắt shuffle trả về thứ tự
trước khi xáo, còn thao tác kéo là chỉnh sửa trên bản đã xáo."
```

---

### Task 2: `QueuePanel`

The panel itself: header, pills, list. Not yet reachable from the app.

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/QueuePanel.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift` (move the pills out)
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes from Task 1: `playback.upcoming`, `playback.moveUpcoming(from:to:)`, `playback.playUpcoming(at:)`.
- Produces, for Task 3: `QueuePanel(playback:)` — a view filling whatever region it is given.

- [ ] **Step 1: Add the two strings**

```bash
cd /Users/phanquyetthang/evenstar
python3 - <<'PY'
import json, collections
p='Evenstar/Evenstar/Localizable.xcstrings'
d=json.load(open(p), object_pairs_hook=collections.OrderedDict)
for k, en in [('Tiếp theo', 'Up Next'), ('Không còn bài nào tiếp theo', 'Nothing up next')]:
    if k in d['strings']:
        print('already present:', k); continue
    d['strings'][k] = {'localizations': {
        'en': {'stringUnit': {'state': 'translated', 'value': en}},
        'vi': {'stringUnit': {'state': 'translated', 'value': k}},
    }}
    print('added:', k)
open(p,'w').write(json.dumps(d, ensure_ascii=False, indent=2, separators=(',',' : '))+'\n')
PY
git diff --stat -- Evenstar/Evenstar/Localizable.xcstrings
```

Expected: roughly 32 insertions. **If the diff exceeds 100 lines, the file was re-serialised — revert and retry.**

- [ ] **Step 2: Move the pill row out of `NowPlayingContent`**

Cut these from `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift` — they move verbatim into `QueuePanel` in Step 3, so paste them there before deleting:

- `@State private var repeatTaps = 0` and `@State private var shuffleTaps = 0`
- `pillHeight`, `pillHorizontalPadding`, `pillHitPad`
- `shuffleRepeatRow`
- `pill(systemImage:isOn:label:trigger:action:)`

Then remove `shuffleRepeatRow` from the body's `VStack`, leaving:

```swift
    var body: some View {
        VStack(spacing: 24) {
            titleBlock
            scrubber
            transport
            volume
        }
    }
```

The toggle icon that takes its place in the stack is Task 3's job. After this
step the expanded player has no shuffle or repeat control at all — that is
expected and temporary.

- [ ] **Step 3: Create the panel**

Create `Evenstar/Evenstar/Features/Player/QueuePanel.swift`:

```swift
import SwiftUI

/// What plays next, with the controls that shape it.
///
/// Occupies the region the artwork otherwise fills — see `PlayerCard`. That is
/// the whole reason this exists as a panel rather than a sheet: the spec's
/// point is that Apple Music *replaces* the artwork rather than stacking a
/// queue below it, and stacking is what this screen has no room for.
struct QueuePanel: View {
    let playback: PlaybackService

    @State private var shuffleTaps = 0
    @State private var repeatTaps = 0

    /// Matches `SongRow`'s thumbnail, so a queue row and a library row are the
    /// same size object.
    private static let rowArtwork: CGFloat = 44
    private static let headerArtwork: CGFloat = 44

    /// Pill geometry, moved here with the pills.
    ///
    /// **36pt tall, and that is not negotiable.** `PlayerCard.contentBudget`
    /// allows about 20pt of slack across the whole stack and its doc comment
    /// records the same overrun shipping twice. The pills grow sideways; they
    /// never grow down.
    private static let pillHeight: CGFloat = 36
    private static let pillHorizontalPadding: CGFloat = 22

    /// Half of what a 36pt pill is short of HIG's 44pt hit region. Spent on the
    /// *hit shape* rather than the frame, by the padding → `contentShape` →
    /// negative-padding trick `NowPlayingContent.jamendoCredit` uses for the
    /// identical collision.
    private static let pillHitPad: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pillRow
            upcomingList
        }
    }

    /// The artwork and title, one line tall.
    ///
    /// `NowPlayingContent` hides its own title block while this is on screen —
    /// see Task 3 — so these two strings appear once, not twice.
    private var header: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(
                relativePath: playback.currentTrack?.artworkRelativePath,
                size: Self.headerArtwork
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.currentTrack?.title ?? "—")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(playback.currentTrack?.artistName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var pillRow: some View {
        HStack(spacing: 12) {
            pill(
                systemImage: "shuffle",
                isOn: playback.isShuffled,
                label: String(localized: "Phát ngẫu nhiên",
                              bundle: AppLanguage.resolvedBundle,
                              locale: AppLanguage.resolvedLocale),
                trigger: shuffleTaps
            ) {
                shuffleTaps += 1
                playback.toggleShuffle()
            }

            pill(
                systemImage: playback.repeatMode == .one ? "repeat.1" : "repeat",
                isOn: playback.repeatMode != .off,
                label: String(localized: "Lặp lại",
                              bundle: AppLanguage.resolvedBundle,
                              locale: AppLanguage.resolvedLocale),
                trigger: repeatTaps
            ) {
                repeatTaps += 1
                playback.cycleRepeatMode()
            }
        }
    }

    @ViewBuilder
    private var upcomingList: some View {
        let upcoming = playback.upcoming
        if upcoming.isEmpty {
            Text("Không còn bài nào tiếp theo")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer(minLength: 0)
        } else {
            Text("Tiếp theo")
                .font(.headline)
            // `.active` edit mode is what puts the drag handles on screen and
            // makes the rows draggable at all: a `List` outside edit mode
            // ignores `.onMove` entirely. There is no `.onDelete` here, so the
            // red delete affordance edit mode would otherwise add never
            // appears — removing a track from the queue is out of scope, and
            // deliberately so: it would have to touch `unshuffledQueue` too,
            // which is exactly what this design avoids.
            List {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, track in
                    QueueRow(track: track, size: Self.rowArtwork)
                        .contentShape(Rectangle())
                        .onTapGesture { playback.playUpcoming(at: offset) }
                }
                .onMove { source, destination in
                    playback.moveUpcoming(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
        }
    }

    /// One capsule control.
    ///
    /// The **fill** says on or off, not the glyph's colour: `shuffle` and
    /// `repeat` render identically armed or not, so a tint alone would leave
    /// shuffle with no readable state. `JamendoDiscoveryView`'s genre chips
    /// shipped that mistake with a 0.12-opacity fill against
    /// `tertiarySystemFill` and it was invisible.
    @ViewBuilder
    private func pill(
        systemImage: String,
        isOn: Bool,
        label: String,
        trigger: Int,
        action: @escaping () -> Void
    ) -> some View {
        let enabled = playback.currentTrack != nil
        TouchDownButton(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                // Three branches, and set *inside* the label on purpose:
                // `TransportButtonStyle` dims a disabled label from outside,
                // but the innermost `foregroundStyle` wins, so its dimming
                // would never land.
                .foregroundStyle(
                    !enabled ? AnyShapeStyle(.tertiary)
                             : isOn ? AnyShapeStyle(Color.white)
                                    : AnyShapeStyle(.secondary)
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(height: Self.pillHeight)
                .padding(.horizontal, Self.pillHorizontalPadding)
                .background(
                    isOn && enabled ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule()
                )
                .padding(.vertical, Self.pillHitPad)
                .contentShape(Rectangle())
                .padding(.vertical, -Self.pillHitPad)
        }
        .buttonStyle(.transportToggle(trigger: trigger))
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn && enabled ? [.isButton, .isSelected] : .isButton)
    }
}

/// One row of the queue.
///
/// Not `SongRow`: that one is greedy and carries its own vertical padding sized
/// for a full-width library list, and these rows sit in a panel that is fighting
/// for every point of height. Same 44pt thumbnail so the two read as the same
/// kind of object.
private struct QueueRow: View {
    let track: any Playable
    let size: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(relativePath: track.artworkRelativePath, size: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild build -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD" | tail -6
```

Expected: `** BUILD SUCCEEDED **`, no errors, no warnings. If the compiler
reports `pillHeight` or `shuffleRepeatRow` still referenced in
`NowPlayingContent.swift`, Step 2 left something behind — finish removing it
rather than re-adding the constant.

- [ ] **Step 5: Run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -2
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/queue2.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/queue2.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['failedTests'])"
```

Expected: `Passed 400 0` — this task adds no tests, and must break none.

- [ ] **Step 6: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/QueuePanel.swift \
        Evenstar/Evenstar/Features/Player/NowPlayingContent.swift \
        Evenstar/Evenstar/Localizable.xcstrings
git commit -m "feat: QueuePanel — dòng đầu, hàng pill, danh sách sắp tới

Hàng pill chuyển nguyên vẹn từ NowPlayingContent sang đây: shuffle và
repeat sống trong hàng đợi chứ không đứng thường trực trong player.

Danh sách dùng editMode .active vì List ngoài chế độ sửa bỏ qua
onMove hoàn toàn. Không có onDelete nên nút xoá đỏ không xuất hiện."
```

---

### Task 3: The toggle, and the mode switch

Wire the panel in. This is the task that ships the feature.

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`
- Modify: `Evenstar/Evenstar/Localizable.xcstrings`

**Interfaces:**
- Consumes from Task 2: `QueuePanel(playback:)`.
- Produces: nothing downstream. This is the last task.

- [ ] **Step 1: Add the string**

```bash
cd /Users/phanquyetthang/evenstar
python3 - <<'PY'
import json, collections
p='Evenstar/Evenstar/Localizable.xcstrings'
d=json.load(open(p), object_pairs_hook=collections.OrderedDict)
k, en = 'Hàng đợi', 'Queue'
if k in d['strings']:
    print('already present:', k)
else:
    d['strings'][k] = {'localizations': {
        'en': {'stringUnit': {'state': 'translated', 'value': en}},
        'vi': {'stringUnit': {'state': 'translated', 'value': k}},
    }}
    print('added:', k)
open(p,'w').write(json.dumps(d, ensure_ascii=False, indent=2, separators=(',',' : '))+'\n')
PY
git diff --stat -- Evenstar/Evenstar/Localizable.xcstrings
```

Expected: about 16 insertions. Over 100 means re-serialisation — revert and retry.

- [ ] **Step 2: Give `NowPlayingContent` the binding and the icon**

In `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, add beside `let playback`:

```swift
    /// Owned by `PlayerCard`, which swaps the artwork for `QueuePanel` when it
    /// is true. A `Binding` rather than local state because two views have to
    /// agree about it: the icon that flips it lives here, and the region that
    /// changes lives there.
    @Binding var showingQueue: Bool

    @State private var queueTaps = 0
```

Replace the body:

```swift
    var body: some View {
        VStack(spacing: 24) {
            // Hidden in queue mode: `QueuePanel`'s header already carries the
            // title and artist, and showing both prints the same two strings
            // twice on one screen. It is also the only element this stack drops
            // in queue mode, which is what buys the list its room.
            if !showingQueue {
                titleBlock
            }
            scrubber
            transport
            volume
            queueToggleRow
        }
    }
```

Add the row, in place of where `shuffleRepeatRow` used to sit:

```swift
    /// The glyph frame. 44pt, so the hit region needs no tricks — unlike the
    /// pills, this row replaces nothing and can afford its own height.
    private static let queueGlyphFrame: CGFloat = 44

    /// One icon, trailing. Apple Music puts three here — lyrics, AirPlay and
    /// the queue — and this app has nothing to put behind the other two.
    private var queueToggleRow: some View {
        HStack {
            Spacer()
            TouchDownButton {
                queueTaps += 1
                withAnimation(BottomBarStyle.settle) {
                    showingQueue.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        playback.currentTrack == nil ? AnyShapeStyle(.tertiary)
                            : showingQueue ? AnyShapeStyle(Color.accentColor)
                                           : AnyShapeStyle(.secondary)
                    )
                    .frame(width: Self.queueGlyphFrame, height: Self.queueGlyphFrame)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.transportToggle(trigger: queueTaps))
            .disabled(playback.currentTrack == nil)
            .accessibilityLabel(String(
                localized: "Hàng đợi",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            ))
            .accessibilityAddTraits(showingQueue ? [.isButton, .isSelected] : .isButton)
        }
    }
```

- [ ] **Step 3: Give `PlayerCard` the flag and the swap**

In `Evenstar/Evenstar/Features/Player/PlayerCard.swift`, add beside the other `@State`:

```swift
    /// Whether the artwork region is showing `QueuePanel` instead of the
    /// artwork.
    ///
    /// Reset when the card collapses, in the `progress` observer below: the
    /// queue is something you open while looking at the player, and reopening
    /// the player later should show the artwork rather than whatever was on
    /// screen last time.
    @State private var showingQueue = false
```

Pass the binding where `NowPlayingContent` is built (in `expandedContent`):

```swift
        NowPlayingContent(playback: playback, showingQueue: $showingQueue)
```

Then in `artworkView(size:artworkHeight:)`, wrap the artwork so the panel can
take its place. Add, as the last modifiers on the view that function returns:

```swift
            // The panel occupies the artwork's frame rather than being pushed
            // below it — the artwork is the only region on this screen with
            // room, and `contentBudget` documents that there is none to spare
            // anywhere else.
            //
            // `opacity` on both rather than an `if`: the artwork participates
            // in the collapse morph, and removing it from the hierarchy
            // mid-morph would take its `matchedGeometry`-driven frame with it.
            .opacity(showingQueue ? 0 : 1)
            .overlay {
                if showingQueue {
                    QueuePanel(playback: playback)
                        .padding(.horizontal, 24)
                        .opacity(progress)
                        .allowsHitTesting(progress > 0.9)
                }
            }
```

And reset the flag as the card collapses — add to `PlayerCard`'s body, on the
same view that already carries `.animation(BottomBarStyle.settle, value:)`:

```swift
        .onChange(of: progress) { _, newValue in
            // Collapsed, or nearly. Not `== 0`: a drag that ends just short of
            // closed still means the player is gone from the user's view, and
            // reopening it should start from the artwork.
            if newValue < 0.05, showingQueue {
                showingQueue = false
            }
        }
```

- [ ] **Step 4: Build**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild build -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD" | tail -6
```

Expected: `** BUILD SUCCEEDED **`, no errors, no warnings.

- [ ] **Step 5: Run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -2
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/queue3.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/queue3.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['failedTests'])"
```

Expected: `Passed 400 0`. `NowPlayingContentCreditTests` and
`PlayerSubtitleTests` both exercise `NowPlayingContent.swift` and must still
pass.

- [ ] **Step 6: Account for the height**

The `contentBudget` constraint fails silently, so state the arithmetic in your
report rather than assuming it.

The permanent stack was `titleBlock(81) + scrubber(53) + transport(82) +
volume(28) + pillRow(40)` with four 24pt gaps = **380**. It is now
`titleBlock(81) + scrubber(53) + transport(82) + volume(28) +
queueToggleRow(44)` with the same four gaps = **384**, against a region of
~400pt. In queue mode the title block is hidden, which returns 81 + 24 = 105pt
to the panel.

Report: the old total, the new total, and that the new one still fits 400.

- [ ] **Step 7: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/NowPlayingContent.swift \
        Evenstar/Evenstar/Features/Player/PlayerCard.swift \
        Evenstar/Evenstar/Localizable.xcstrings
git commit -m "feat: icon mở hàng đợi, ảnh bìa nhường chỗ cho QueuePanel

Một icon canh phải dưới thanh âm lượng, thay chỗ hàng pill cũ trong
stack thường trực — chênh 4pt nên contentBudget không phải động.

Panel chiếm đúng khung của ảnh bìa thay vì xếp bên dưới: đây là vùng
duy nhất còn chỗ. Dùng opacity chứ không phải if, vì ảnh bìa tham gia
morph thu gọn và gỡ nó khỏi cây giữa chừng sẽ mất luôn khung của nó.

Khối tiêu đề ẩn ở chế độ hàng đợi vì dòng đầu của panel đã mang tên
bài và nghệ sĩ."
```

---

## Manual QA (needs the phone)

The panel is layout and animation; none of this is automatable.

1. Play an album. Open the player, tap the queue icon. The artwork gives way to the header, pills and list; **the scrubber, transport and volume do not move**.
2. Tap it again. The artwork comes back.
3. Drag a row. The order changes, the song keeps playing, and skipping forward follows the new order.
4. Tap the third row. That track plays. Reopen the queue: the order below it is unchanged — no silent reshuffle.
5. With shuffle on, drag a row, then turn shuffle off. Album order returns and the drag is discarded — this is the design's ruling, not a bug.
6. Play the last track of a queue. The panel says "Không còn bài nào tiếp theo" rather than showing an empty box.
7. Collapse the player while the queue is open, then reopen it. It shows the artwork, not the queue.
8. **On a 4.7" device (or the smallest simulator available), portrait and landscape:** the volume slider is fully visible and draggable in both modes. This is what `contentBudget` protects and it fails silently.
9. At a large Dynamic Type size, the header and pill row still fit above the list.
10. VoiceOver: the queue icon announces "Hàng đợi" and reports selected when open; the pills announce their own state.
11. Switch to English: "Up Next", "Nothing up next", "Queue", "Shuffle", "Repeat".
12. Watch the transition between modes for interference with the player's own expand/collapse springs — the spec flags this as the likeliest place for the two to fight.
