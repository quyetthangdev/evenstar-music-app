# Now Playing Controls — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Now Playing a knobless capsule scrubber that swells under the finger, and a volume slider below the transport row — matching Apple Music's shape.

**Architecture:** The scrubber becomes a custom view, because SwiftUI's `Slider` cannot lose its thumb; owning it also lets the gesture priority against the player card be declared rather than inferred. Volume uses `MPVolumeView` wrapped in `UIViewRepresentable`, because iOS grants no other way to set system volume.

**Tech Stack:** Swift 5, SwiftUI, `MediaPlayer` (`MPVolumeView`), iOS 17.6 deployment target, Xcode 26. No third-party dependencies.

**Reference spec:** `docs/superpowers/specs/2026-08-02-now-playing-controls-design.md`

## Global Constraints

- **Min iOS deployment target:** 17.6.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION` must stay `nonisolated`** on both targets. Xcode 26's template sets it to `MainActor`, which gives every MainActor-isolated class an isolated `deinit`; below iOS 26 that routes through a back-deployed shim aborting with a libmalloc double-free on **every** dealloc.
- **Never edit `Evenstar/Evenstar.xcodeproj/project.pbxproj`.** Both targets use Xcode synced folders. Xcode is open and periodically rewrites that file cosmetically — if it shows as modified and you did not touch it, exclude it by staging specific paths and say so; do not revert it.
- **SwiftUI only, with one sanctioned exception:** `UIViewRepresentable` is permitted — the parent design spec already anticipated it for this screen. `UIViewControllerRepresentable` and UIKit presentation controllers remain out.
- **No third-party libraries.** No `try!`. No silent `catch { }`.
- **A clean build must produce zero Swift warnings.** That bar has held since Phase 2a.
- **`PlaybackService` must not be modified.** This plan touches presentation only.
- **Phase 1 capability — background audio, lock-screen Now Playing, remote commands — must be preserved.**
- **`onSeek` fires once, on release** — never continuously during a drag. Seeking an `AVAudioPlayer` every frame thrashes it.

---

## Commands

**Clean build — zero Swift warnings required:**
```bash
cd /Users/phanquyetthang/evenstar && xcodebuild clean build -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "warning:|error:|BUILD" | grep -v AppIntents | sort -u
```
Expect exactly `** BUILD SUCCEEDED **`. Allow a 600000 ms timeout.

**Full test suite:**
```bash
cd /Users/phanquyetthang/evenstar && xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "^Test case|TEST SUCCEEDED|TEST FAILED|error:"
```
54 pass today. Scope with `-only-testing:EvenstarTests/ScrubberBarTests` while iterating.

**Reading a test failure.** `xcodebuild` prints no message when a test fails by *throwing* rather than by a failed assertion. A bare `TEST FAILED` with no detail is **not** an environmental problem:
```bash
R=$(ls -td ~/Library/Developer/Xcode/DerivedData/Evenstar-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results tests --path "$R"
```

**Launch and screenshot:**
```bash
xcrun simctl boot "iPhone 17" 2>/dev/null
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Evenstar-*/Build/Products/Debug-iphonesimulator/Evenstar.app
xcrun simctl terminate booted com.evenstar.app 2>/dev/null
xcrun simctl launch booted com.evenstar.app
sleep 4
xcrun simctl io booted screenshot /tmp/claude-501/-Users-phanquyetthang-evenstar/0e6e70ca-2ba8-4e82-b804-3618ac2f7281/scratchpad/<name>.png
```
Then **Read the PNG**. **If any command fails or times out, say so and report DONE_WITH_CONCERNS — never synthesize a placeholder file in place of a real artifact.** A fabricated verification result is worse than an admitted gap; that has happened once in this project.

## What cannot be verified here

**No audio file has ever been imported into this app on the simulator**, and importing needs the Files-app picker driven by hand. Now Playing only appears when a track is playing, so **neither the scrubber nor the volume slider can be seen by a subagent.** The screenshot proves only that the empty library still renders and launch did not crash.

Worse for Task 2: **`MPVolumeView` renders nothing at all in the simulator.** Even with a track playing it would show empty space. No automated check can confirm the volume slider exists, let alone that it works. That component is entirely the developer's to verify on a device.

Say all of this plainly in reports. Do not imply either control was observed.

## File structure

```
Evenstar/Evenstar/Features/Player/
├── ScrubberBar.swift          # NEW — knobless capsule, swell on touch, seek arithmetic
├── SystemVolumeSlider.swift   # NEW — MPVolumeView wrapper
├── NowPlayingContent.swift    # MODIFIED — swap the scrubber, add the volume slider
└── PlayerCard.swift           # MODIFIED — artwork allowance 300 -> 350 (Task 2 only)

Evenstar/EvenstarTests/
└── ScrubberBarTests.swift     # NEW — 5 tests
```

---

## Task 1: `ScrubberBar` — a knobless capsule that swells under the finger

**Goal:** Replace SwiftUI's `Slider` with a custom scrubber: a capsule track with the played portion filled and no thumb, 7 pt at rest and 12 pt while dragging, with the time labels growing more prominent during a drag.

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/ScrubberBar.swift`
- Create: `Evenstar/EvenstarTests/ScrubberBarTests.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`

**Interfaces (produced):**
- `struct ScrubberBar: View` with `init(position: TimeInterval, duration: TimeInterval, onSeek: @escaping (TimeInterval) -> Void)`
- `static func fillFraction(position: TimeInterval, duration: TimeInterval) -> Double`
- `static func time(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval`

**Why this also closes an open risk.** Since the player moved to a sheet and then to a hand-built card, an unresolved question has been carried: does a vertical drift while dragging the scrubber collapse the player instead of seeking? Two gestures compete and SwiftUI's implicit child-over-parent rule decides. Owning the scrubber lets `.highPriorityGesture` declare the winner outright.

### Steps

- [ ] **Step 1.1: Write the failing tests**

Create `Evenstar/EvenstarTests/ScrubberBarTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Evenstar

final class ScrubberBarTests: XCTestCase {

    // MARK: - fillFraction

    func testFillFractionIsProportional() {
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: 120), 0.25, accuracy: 0.0001)
    }

    func testFillFractionClampsOutOfRangePositions() {
        XCTAssertEqual(ScrubberBar.fillFraction(position: -5, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.fillFraction(position: 500, duration: 120), 1, accuracy: 0.0001)
    }

    func testFillFractionIsZeroForUnusableDuration() {
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: .infinity), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.fillFraction(position: .nan, duration: 120), 0, accuracy: 0.0001)
    }

    // MARK: - time(forX:width:duration:)

    func testTimeAtEdgesMapsToStartAndEnd() {
        XCTAssertEqual(ScrubberBar.time(forX: 0, width: 200, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 200, width: 200, duration: 120), 120, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: 120), 60, accuracy: 0.0001)
    }

    func testTimeClampsBeyondEitherEndAndSurvivesZeroWidthOrDuration() {
        XCTAssertEqual(ScrubberBar.time(forX: -40, width: 200, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 900, width: 200, duration: 120), 120, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 0, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: 0), 0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 1.2: Run the tests — they must fail to compile**

Run the scoped test command with `-only-testing:EvenstarTests/ScrubberBarTests`.
Expected: `Cannot find 'ScrubberBar' in scope`.

- [ ] **Step 1.3: Implement `ScrubberBar`**

Create `Evenstar/Evenstar/Features/Player/ScrubberBar.swift`:

```swift
import SwiftUI

/// The playback scrubber: a capsule track with the played portion filled and
/// no thumb, which swells while a finger is on it.
///
/// SwiftUI's `Slider` always draws a circular knob, which is the single most
/// obvious difference from Apple Music on this screen — hence a custom view.
/// Owning the gesture also lets the priority against `PlayerCard`'s drag be
/// declared with `.highPriorityGesture` rather than left to SwiftUI's implicit
/// child-over-parent rule.
struct ScrubberBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    /// Where the finger currently is. Nil when nobody is dragging, in which
    /// case the bar follows `position` from the player.
    @State private var draggingPosition: TimeInterval?

    private static let restingHeight: CGFloat = 7
    private static let activeHeight: CGFloat = 12
    /// The bar is thin; the touch target is not. This is the full height the
    /// row reserves, so the swell does not shift anything below it.
    private static let touchHeight: CGFloat = 28

    private var displayedPosition: TimeInterval { draggingPosition ?? position }
    private var isDragging: Bool { draggingPosition != nil }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.25))
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: geo.size.width * Self.fillFraction(
                            position: displayedPosition,
                            duration: duration
                        ))
                }
                .frame(height: isDragging ? Self.activeHeight : Self.restingHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(drag(width: geo.size.width))
                .animation(.easeOut(duration: 0.15), value: isDragging)
            }
            .frame(height: Self.touchHeight)

            labels
        }
    }

    private var labels: some View {
        HStack {
            Text(Self.formatTime(displayedPosition))
            Spacer()
            Text("-" + Self.formatTime(max(0, duration - displayedPosition)))
        }
        .font(.caption)
        .foregroundStyle(isDragging ? Color.primary : Color.secondary)
        .monospacedDigit()
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    /// `minimumDistance: 0` so a tap seeks, as Apple Music does. Combined with
    /// `.highPriorityGesture` this means any touch starting on the bar belongs
    /// to the scrubber and never to the card behind it — which is the point.
    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                draggingPosition = Self.time(
                    forX: value.location.x, width: width, duration: duration
                )
            }
            .onEnded { value in
                // Seek once, on release. Seeking every frame would thrash
                // AVAudioPlayer.
                onSeek(Self.time(forX: value.location.x, width: width, duration: duration))
                draggingPosition = nil
            }
    }

    // MARK: - Arithmetic (pure, and unit-tested)

    /// How much of the track is filled, 0...1. Returns 0 for any duration or
    /// position that cannot produce a meaningful fraction.
    static func fillFraction(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// The time a touch at `x` across a bar of `width` corresponds to, clamped
    /// to `0...duration`.
    static func time(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration.isFinite, duration > 0 else { return 0 }
        let fraction = min(max(Double(x / width), 0), 1)
        return fraction * duration
    }

    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 1.4: Run the tests — they must pass**

Run the scoped test command. Expected: **5 `ScrubberBarTests` pass**.

- [ ] **Step 1.5: Swap the scrubber into `NowPlayingContent`**

Read `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift` first. Three changes, and nothing else:

1. Delete the `@State private var draggingPosition: TimeInterval?` property — it now lives in `ScrubberBar`.
2. Replace the whole `scrubber` computed property with:

```swift
    private var scrubber: some View {
        ScrubberBar(
            position: playback.position,
            duration: playback.duration,
            onSeek: { playback.seek(to: $0) }
        )
    }
```

3. Delete the `formatTime(_:)` method — it moved to `ScrubberBar` as a static.

Leave `titleBlock`, `metadataSubtitle`, `transport` and the `body` untouched.

- [ ] **Step 1.6: Clean build**

Run the clean-build command. Expect exactly `** BUILD SUCCEEDED **`. If the compiler reports `formatTime` or `draggingPosition` still in use, you missed a deletion in Step 1.5.

- [ ] **Step 1.7: Run the full suite**

**Expect 59 passing** (54 existing + 5 new), 0 failures.

- [ ] **Step 1.8: Launch and screenshot**

Run the launch-and-screenshot commands, writing to `…/scratchpad/controls-task1.png`, then **Read the PNG**. Expect the unchanged empty-library state with a clean bottom edge.

The scrubber cannot be seen — nothing is playing and nothing can be imported here. State that.

- [ ] **Step 1.9: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features Evenstar/EvenstarTests
git commit -F - <<'MSG'
feat: replace the scrubber with a knobless capsule that swells under the finger

SwiftUI's Slider always draws a circular thumb, which was the most obvious
difference from Apple Music on this screen. ScrubberBar is a capsule track with
the played portion filled, 7pt at rest and 12pt while dragging, with the time
labels growing more prominent during a drag.

Owning the gesture also settles a question carried since the player became a
hand-built card: .highPriorityGesture declares that a touch starting on the bar
belongs to the scrubber, rather than leaving it to SwiftUI's implicit
child-over-parent rule.

Seeking still happens once on release, not per frame.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Task 2: `SystemVolumeSlider` — a volume control below the transport

**Goal:** A volume slider under the transport row, using the system control so it stays in sync with the hardware buttons and AirPlay routing.

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `struct SystemVolumeSlider: UIViewRepresentable`.

**Why `MPVolumeView` and not something nicer.** `AVAudioSession.outputVolume` is read-only. `MPVolumeView` is the only sanctioned way to change system volume. Making it look exactly like `ScrubberBar` would mean reaching into its undocumented subview hierarchy to find its `UISlider` and set `.value` — and when a future iOS changes that hierarchy, the failure is silent: the slider simply stops changing the volume. Putting a real function on that assumption is the wrong trade for an app headed to the App Store. Apple Music's volume slider at rest is also a thin knobless line; the difference is that it swells on touch, which matters far less here than on the scrubber.

**The knock-on that must not be forgotten.** `PlayerCard` sizes the expanded artwork as `min(expandedArtwork, fullSize.height - insets.top - expandedArtworkTopGap - 300, fullSize.width - 48)`. That `300` is the allowance for everything below the artwork. A volume slider adds about 44 pt. **If the allowance is not raised in the same commit, this reintroduces the exact defect fixed one round ago** — content overflowing the card and being clipped, which removed every control in landscape and amputated the play button on an iPhone SE at default type.

### Steps

- [ ] **Step 2.1: Write `SystemVolumeSlider`**

Create `Evenstar/Evenstar/Features/Player/SystemVolumeSlider.swift`:

```swift
import MediaPlayer
import SwiftUI
import UIKit

/// The system volume control.
///
/// iOS gives no way to set system volume from SwiftUI —
/// `AVAudioSession.outputVolume` is read-only, and `MPVolumeView` is the only
/// sanctioned route. Using Apple's own control means it stays in sync with the
/// hardware buttons and with AirPlay routing for free.
///
/// Note: `MPVolumeView` renders **nothing in the simulator**. Empty space there
/// is expected, not a bug.
struct SystemVolumeSlider: UIViewRepresentable {

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.setVolumeThumbImage(Self.invisibleThumb, for: .normal)
        view.setVolumeThumbImage(Self.invisibleThumb, for: .highlighted)
        view.tintColor = .label
        Self.matchTrackColours(in: view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}

    /// A genuinely 1x1 transparent image. An empty `UIImage()` is not reliably
    /// honoured by `setVolumeThumbImage` across iOS versions — if a knob is
    /// still visible on device, this is the first thing to check.
    private static let invisibleThumb: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }()

    /// Tints the track to match `ScrubberBar`.
    ///
    /// This walks `MPVolumeView`'s subviews, which is undocumented — but only
    /// for colour. If Apple changes the hierarchy the slider keeps working and
    /// simply falls back to the system tint. That is deliberately different
    /// from driving the volume itself through the same traversal, which would
    /// fail silently and is why this design does not do it.
    private static func matchTrackColours(in view: MPVolumeView) {
        for subview in view.subviews {
            guard let slider = subview as? UISlider else { continue }
            slider.minimumTrackTintColor = .label
            slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.25)
        }
    }
}
```

- [ ] **Step 2.2: Add it to `NowPlayingContent`**

Read the file, then add the volume slider below the transport row in `body`. The `VStack` becomes:

```swift
        VStack(spacing: 24) {
            titleBlock
            scrubber
            transport
            SystemVolumeSlider()
                .frame(height: 44)
        }
```

A fixed 44 pt height keeps the layout from shifting as the volume changes. Change nothing else in the file.

- [ ] **Step 2.3: Raise the artwork allowance in `PlayerCard`**

In `Evenstar/Evenstar/Features/Player/PlayerCard.swift`, find `artworkSide(fullSize:insets:)` and change the content allowance from `300` to `350`, updating the comment beside it to say what the allowance now covers:

```swift
    /// The artwork shrinks when there is not enough room below it for the
    /// title, scrubber, transport row and volume slider. 350 is a rough
    /// allowance for that stack — a starting point like the other constants
    /// here, not a measured value.
    private static func artworkSide(fullSize: CGSize, insets: EdgeInsets) -> CGFloat {
        min(
            Self.expandedArtwork,
            fullSize.height - insets.top - Self.expandedArtworkTopGap - 350,
            fullSize.width - 48
        )
    }
```

Read the real file before editing — the surrounding code may differ in detail from this excerpt, and only the `300` and the comment change.

- [ ] **Step 2.4: Check the geometry did not regress**

Compute `artworkSide` by hand for three cases and record them in your report:

- **iPhone 12 portrait** — `fullSize` 390×844, insets top 47, bottom 34. `min(280, 844 − 47 − 72 − 350, 390 − 48)` = `min(280, 375, 342)` = **280**. Unchanged, so the twice-verified portrait geometry (collapsed card top y = 746, expanded artwork top y = 119, clearance below the safe area exactly 72) still holds.
- **iPhone SE portrait** — 375×667, top 20, bottom 0. `min(280, 667 − 20 − 72 − 350, 327)` = **225**.
- **iPhone 12 landscape** — 844×390, top 0, bottom 21. `min(280, 390 − 0 − 72 − 350, 796)` = **−32**.

That last one is negative. **A negative value passed to `.frame(width:height:)` is clamped to zero by SwiftUI rather than crashing**, so landscape degrades to an invisible artwork with the controls still laid out and reachable — the same known landscape limitation already recorded before this plan, one step further along. Confirm by reading the code that nothing divides by `artworkSide` or indexes with it, so a zero cannot produce a crash or a NaN. If you find such a use, **stop and report it** rather than working around it.

- [ ] **Step 2.5: Clean build**

Run the clean-build command. Expect exactly `** BUILD SUCCEEDED **`.

- [ ] **Step 2.6: Run the full suite**

**Expect 59 passing.** This task adds no tests and must break none.

- [ ] **Step 2.7: Launch and screenshot**

Run the launch-and-screenshot commands, writing to `…/scratchpad/controls-task2.png`, then **Read the PNG**. Expect the unchanged empty-library state with a clean bottom edge.

Be explicit in your report that **this proves nothing about the volume slider**: nothing is playing, and `MPVolumeView` draws nothing in the simulator regardless. The control is entirely unverified until the developer runs it on a device.

- [ ] **Step 2.8: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features
git commit -F - <<'MSG'
feat: add a system volume slider below the transport row

iOS gives no way to set system volume from SwiftUI — AVAudioSession's
outputVolume is read-only and MPVolumeView is the only sanctioned route — so
this wraps Apple's own control, which stays in sync with the hardware buttons
and AirPlay for free. Its thumb is hidden and its track tinted to match the
scrubber.

Raises PlayerCard's artwork allowance from 300 to 350 in the same commit,
because the volume slider adds roughly 44pt below the artwork and leaving the
allowance alone would reintroduce the clipping fixed one round ago.

MPVolumeView renders nothing in the simulator; this control is verifiable only
on a device.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Out of scope

- The AirPlay / route-picker button beside the volume slider. The parent spec lists it for this screen; it is a separate, small addition.
- Apple Music's "…" menu, lyrics and queue buttons. Queue editing is Phase 2c and lyrics are in no phase — they would be buttons that do nothing.
- Making the volume slider a custom capsule that swells like the scrubber. Rejected in the spec: it would put a real function on `MPVolumeView`'s undocumented internals. The layout is in place if the developer decides the difference is worth that risk after comparing on device.
- Making `NowPlayingContent` a `ScrollView` to survive landscape and accessibility Dynamic Type. Recommended by an earlier review and still the right answer, but a structural change that deserves its own plan.

## Self-review

- ✅ Spec §4.1 (volume via `MPVolumeView`, thumb hidden, no function on subview traversal) → Task 2 Step 2.1, with the rejected alternative recorded in the task header and in the code comment.
- ✅ Spec §4.2 (custom scrubber, `.highPriorityGesture`) → Task 1 Steps 1.3 and 1.5.
- ✅ Spec §5 (`ScrubberBar` owns `draggingPosition` and `formatTime`; `onSeek` once on release) → Step 1.3's code and Step 1.5's deletions.
- ✅ Spec §5 (`SystemVolumeSlider` colours: `.label` and `.label` at 25%, height 44) → Steps 2.1 and 2.2.
- ✅ Spec §6 (allowance 300 → 350, same commit) → Steps 2.3 and 2.8, with the consequence of forgetting it stated in the task header.
- ✅ Spec §7 (zero/non-finite duration, clamped seeks) → `fillFraction` and `time(forX:width:duration:)` guards, covered by tests 3 and 5.
- ✅ Spec §8 (about four tests on the seek arithmetic) → five, in Step 1.1.
- ✅ Spec §9 risks → the simulator blindness is stated in the plan header and both screenshot steps; the thumb-image caveat is in Step 2.1's comment; the `.highPriorityGesture` trade is in Step 1.3's comment; the allowance is Step 2.3 with a hand-computed check in Step 2.4.
- ✅ Placeholder scan: no TBD, no TODO, no "add appropriate error handling", no "similar to Task N". Every code step gives complete code.
- ✅ Type consistency: `ScrubberBar(position:duration:onSeek:)` as called in Step 1.5 matches its definition in Step 1.3. `fillFraction` and `time(forX:width:duration:)` are called in the tests with the signatures the implementation declares. `SystemVolumeSlider()` takes no arguments in both Step 2.1 and Step 2.2.
- ✅ Task boundaries: a reviewer can approve Task 1 and reject Task 2. Task 1 ships a working knobless scrubber on its own and does not change the content's height enough to touch the artwork allowance; Task 2 is the volume slider and the allowance together.
