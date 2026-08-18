# Queue Toggle Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The queue button shrinks under the finger and lights a glass capsule; the list rises as the cover shrinks into a larger header slot, all on one spring.

**Architecture:** The queue button leaves `TransportButtonStyle` for its own `QueueToggleStyle`, because a press scale of 0.9 multiplied against that style's 1.08 kick inverts the pop. The list's rise is driven by the `queueFactor` Double `PlayerCard` already animates, passed into `QueuePanel` — the same value the artwork's shrink interpolates on, so the two cannot disagree.

**Tech Stack:** Swift 6, SwiftUI, XCTest. iOS 18.0 deployment target.

**Spec:** `docs/superpowers/specs/2026-08-11-queue-toggle-motion-design.md`

## Global Constraints

- **NEVER edit `Evenstar/Evenstar.xcodeproj/project.pbxproj` or any `.xcscheme`.** New Swift files are picked up automatically — Xcode 16 synced folders.
- Every `xcodebuild` invocation passes `-configuration Debug` explicitly.
- Build tests with `clean build-for-testing`, never plain `build` — a plain `build` strips the test PlugIn and the next `test-without-building` fails with "Failed to create a bundle instance … EvenstarTests.xctest".
- Simulator destination: `platform=iOS Simulator,name=iPhone 17`.
- No third-party libraries. SwiftUI only. No `try!`. No silently swallowed `catch {}`.
- Never modify a pre-existing test to make new code pass.
- **`PlayerCard.contentBudget` must not be touched**, and **`BottomBarStyle.settle` must not be retuned** — it drives the expand/collapse morph, and changing it would retune that from a distance.
- **The scrubber and transport row must not move between modes.** A fix landed today to hold them still; this plan must not reintroduce motion there.
- Suite is at **415 tests** before this plan starts.

---

### Task 1: The button

Its own style, and the capsule behind it. No animation timing changes yet.

**Files:**
- Create: `Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`

**Interfaces:**
- Consumes: `BottomBarStyle.press` (`Animation.easeOut(duration: 0.09)`), the `View.tapHalo(trigger:)` modifier, and `TouchDownButton`.
- Produces, for Task 2: nothing. Task 2 touches different lines.

- [ ] **Step 1: Create the style**

Create `Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift`:

```swift
import SwiftUI

/// Press physics for a button that changes what you are looking at.
///
/// **Deliberately not `TransportButtonStyle`.** That style throws its glyph in
/// the direction the button's action goes — right for Next, wrong for a control
/// that goes nowhere. It also pops the glyph to 1.08 at touch-down, and a press
/// scale of 0.9 layered on top multiplies to `0.9 × 1.08 = 0.97`: the pop
/// inverts into a shrink. That is the same arithmetic that already cost this
/// project one defect, when a 0.92 held-press squeeze cancelled the kick it was
/// meant to precede.
///
/// What survives from that style is what it got right — the halo and the
/// haptic, both fired at touch-**down** — because `TouchDownButton` runs the
/// action there too, so the shrink, the feedback and the queue opening are one
/// instant rather than three.
///
/// No `trigger` parameter, unlike `.transportSkip`/`.transportToggle`: those
/// need an external counter to retrigger a kick. This style's only counter is
/// internal, and an unused parameter is an invitation to pass something into it.
struct QueueToggleStyle: ButtonStyle {

    /// Deeper than `BottomBarStyle.pressedScale` (0.96, for a tab that is a
    /// whole quarter of the bar). This is a 44pt glyph the thumb lands on
    /// squarely, and the same ratio on something that small reads as barely
    /// moving.
    fileprivate static let pressedScale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        // A nested view, not the style itself: a `ButtonStyle` is not a `View`
        // and cannot read `@Environment`, and this needs `isPressed` observed
        // through `onChange`.
        Interaction(configuration: configuration)
    }

    /// Named for what it does, not `Body` — that collides with `ButtonStyle`'s
    /// own `Body` associated type and makes the conformance fail to resolve.
    private struct Interaction: View {
        /// Counts touch-*downs*. The halo and the haptic key off this rather
        /// than off a completed tap, because an acknowledgement that waits for
        /// the finger to leave is not one.
        @State private var presses = 0
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? QueueToggleStyle.pressedScale : 1)
                // `press`, not the layout spring. A press has no known
                // duration, and a spring that overshoots on the way *in* reads
                // as the button wobbling under a finger that is still holding
                // it. The spring belongs to the layout change the press causes,
                // which is a different event with a different job.
                .animation(BottomBarStyle.press, value: configuration.isPressed)
                .tapHalo(trigger: presses)
                .sensoryFeedback(.impact(weight: .light), trigger: presses)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { presses += 1 }
                }
        }
    }
}

extension ButtonStyle where Self == QueueToggleStyle {
    /// For the control that opens the queue. See the type's doc comment for why
    /// it is not one of the transport styles.
    static var queueToggle: Self { QueueToggleStyle() }
}
```

- [ ] **Step 2: Wire it in, with the capsule**

In `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, replace the label and style of `queueToggleRow`'s button. The `TouchDownButton` action and the two accessibility modifiers stay exactly as they are:

```swift
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        playback.currentTrack == nil ? AnyShapeStyle(.tertiary)
                            : showingQueue ? AnyShapeStyle(Color.accentColor)
                                           : AnyShapeStyle(.secondary)
                    )
                    .frame(width: Self.queueGlyphFrame, height: Self.queueGlyphFrame)
                    // Grows from its own centre rather than sliding or wiping:
                    // the capsule belongs to the button, so it should look like
                    // it came out of it.
                    //
                    // `.ultraThinMaterial` over the card's own frosted layer is
                    // the risk the design names. If this reads as a flat grey
                    // swatch rather than something the gradient shows through,
                    // the answer is `.regularMaterial` or a solid tint at low
                    // opacity — not more blur.
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(showingQueue ? 1 : 0)
                            .scaleEffect(showingQueue ? 1 : 0.6)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.queueToggle)
```

Then delete `@State private var queueTaps = 0` and the `queueTaps += 1` line inside the button's action. It existed only to retrigger `transportToggle`'s kick, and nothing reads it now.

- [ ] **Step 3: Build**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild build -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD" | tail -6
```

Expected: `** BUILD SUCCEEDED **`, no errors, **no warnings**. A warning about an
unused `queueTaps` means Step 2's deletion was incomplete.

- [ ] **Step 4: Run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -2
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/qt1.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/qt1.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['failedTests'])"
```

Expected: `Passed 415 0` — this task adds no tests and must break none.

- [ ] **Step 5: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Shared/QueueToggleStyle.swift \
        Evenstar/Evenstar/Features/Player/NowPlayingContent.swift
git commit -m "feat: nút hàng đợi có kiểu riêng, nhún 0.9 và capsule kính

scale 0.9 không chồng lên transportToggle được: nó nhân với cú bung
1.08 thành 0.97, tức pop đảo chiều thành co lại — đúng phép tính đã
làm hỏng một lần khi cú nhún 0.92 triệt tiêu cú bung nó đáng lẽ đi
trước.

Kiểu mới giữ halo và haptic ở touch-down, bỏ cú bung, thêm nhún 0.9
chạy trên BottomBarStyle.press chứ không phải spring: một cú nhấn
không có thời lượng biết trước, và spring vọt quá ở chiều đi vào đọc
ra như nút rung dưới ngón tay còn đang giữ.

queueTaps bị bỏ — nó chỉ tồn tại để châm lại cú bung."
```

---

### Task 2: The motion

The spring, the list's rise, and the larger header slot.

**Files:**
- Modify: `Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift`
- Modify: `Evenstar/Evenstar/Features/Player/QueuePanel.swift`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`

**Interfaces:**
- Consumes from Task 1: nothing — it touches different lines of `NowPlayingContent`.
- Produces: `BottomBarStyle.queue`, and `QueuePanel(playback:factor:)`.

- [ ] **Step 1: Name the spring**

In `Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift`, add beside the four existing animations:

```swift
    /// The queue panel opening and closing.
    ///
    /// Given as mass/stiffness/damping rather than duration/bounce because
    /// those are the terms it was specified in. Damping ratio is
    /// `22 / (2 * sqrt(180))` ≈ 0.82 and it settles in roughly 0.36s — firm,
    /// with barely any overshoot.
    ///
    /// **It drives three things and only three:** the capsule's fade-and-grow,
    /// the list's rise, and `queueFactor` — which is the artwork's shrink,
    /// since that is the value the shrink interpolates on. Those are parts of
    /// one gesture and must share a clock or they will visibly disagree.
    ///
    /// It is deliberately *not* `settle`. A drag-collapse begun while the queue
    /// is open already runs two clocks — `progress` tracks the finger while
    /// `queueFactor` runs a spring — and a third timing character makes that
    /// harder to read. If a slow collapse-drag with the queue open ever looks
    /// like two objects moving separately rather than one thing folding away,
    /// the answer is to point this at `settle` and let both share it.
    static let queue = Animation.spring(Spring(mass: 1, stiffness: 180, damping: 22))```

- [ ] **Step 2: Let the panel take a factor**

In `Evenstar/Evenstar/Features/Player/QueuePanel.swift`, add the property beside `playback`:

```swift
    /// 0 closed, 1 open — the same animated value `PlayerCard` interpolates the
    /// artwork's shrink on.
    ///
    /// Passed in rather than derived from a `Bool` here, and that is the point:
    /// the list's rise and the cover's shrink are one gesture, and reading the
    /// same number is what makes them incapable of disagreeing. A local
    /// animation would be a second clock.
    let factor: Double
```

Then apply the rise to two of the three children, and **not** to `header`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // No offset on the header. It is where the artwork is flying to,
            // and a destination that moves while something is travelling toward
            // it makes the two chase each other — the motion version of the
            // 12pt landing mismatch this file has already produced once.
            header
            pillRow
                .offset(y: Self.riseDistance * (1 - factor))
                .opacity(factor)
            upcomingList
                .offset(y: Self.riseDistance * (1 - factor))
                .opacity(factor)
        }
    }
```

Add the constant beside the others:

```swift
    /// How far the list starts below its resting place.
    private static let riseDistance: CGFloat = 50
```

- [ ] **Step 3: Grow the header slot**

Same file. `headerArtwork` becomes 54, and its doc records why it is the odd one out:

```swift
    /// Read by `PlayerCard`, which flies the real artwork down into this slot —
    /// so the two must agree on its size.
    ///
    /// **54, where every other artwork thumbnail in this app is 44** —
    /// `SongRow`, `QueueRow`, `JamendoResultRow`. Chosen deliberately for
    /// prominence at the top of the panel. Recorded here so a later reader
    /// finds a decision rather than an inconsistency.
    static let headerArtwork: CGFloat = 54
```

- [ ] **Step 4: Point the toggle and the factor at the new spring**

In `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`, inside `queueToggleRow`'s `TouchDownButton` action:

```swift
                withAnimation(BottomBarStyle.queue) {
                    showingQueue.toggle()
                }
```

In `Evenstar/Evenstar/Features/Player/PlayerCard.swift`, the `.onChange(of: showingQueue)` that drives `queueFactor` — swap its `withAnimation(BottomBarStyle.settle)` for `withAnimation(BottomBarStyle.queue)`.

Then pass the factor to the panel at its call site:

```swift
                    QueuePanel(playback: playback, factor: queueFactor)
```

**Change nothing else in `PlayerCard`.** In particular `BottomBarStyle.settle` keeps every other use it has — it drives the expand/collapse morph, and retuning it from here would change that at a distance.

- [ ] **Step 5: Build**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild build -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD" | tail -6
```

Expected: `** BUILD SUCCEEDED **`, no errors, no warnings.

- [ ] **Step 6: Run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -2
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/qt2.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/qt2.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['failedTests'])"
```

Expected: `Passed 415 0`.

**`ArtworkGeometryTests` is the one to watch.** It passes `thumbSide` in as a
fixture, so growing `headerArtwork` to 54 should not move it — if it fails, the
test is reading the real constant somewhere it should not, and that is worth
reporting rather than patching.

- [ ] **Step 7: Run it and look at it**

Nothing here is testable; all of it is motion. Build to the simulator, play a
Jamendo track with something upcoming, and open and close the queue. Report what
you saw against each of these:

- pressing the button shrinks it to 0.9 **while held**, and the queue starts
  opening on contact rather than on release
- the capsule fades and grows **from its centre** — not from an edge, not sliding
- the capsule reads as glass over the card's gradient, **not as a grey swatch**.
  If it is a swatch, say so and stop: the design's answer is `.regularMaterial`
  or a solid low-opacity tint, and it wants evidence before the change
- the list rises from below as it fades, while the **header stays put** and the
  cover lands on it
- the scrubber and transport row **do not move at all** between modes
- a slow drag-collapse with the queue open still reads as **one** object folding
  away. If it reads as two things on different clocks, say so — the design's
  answer is to point `BottomBarStyle.queue` at `settle`, and that too wants
  evidence first

Practical notes from earlier sessions in this simulator: the local library
fixtures are broken and will not play — use Jamendo. Synthetic coordinate clicks
miss this app's touch-down buttons; click the accessibility element directly.

- [ ] **Step 8: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Shared/BottomBarStyle.swift \
        Evenstar/Evenstar/Features/Player/QueuePanel.swift \
        Evenstar/Evenstar/Features/Player/NowPlayingContent.swift \
        Evenstar/Evenstar/Features/Player/PlayerCard.swift
git commit -m "feat: danh sách hàng đợi trượt lên, ô header 54pt, một spring chung

Spring mass 1 / stiffness 180 / damping 22 lái đúng ba thứ: capsule
hiện ra, danh sách trượt lên, và queueFactor — tức cả cú co của ảnh
bìa, vì đó là giá trị nó nội suy theo. Ba thứ này là các phần của một
cử chỉ nên phải chung đồng hồ.

Danh sách nhận factor từ PlayerCard chứ không tự dựng animation: đọc
chung một con số là thứ khiến nó không thể lệch pha với ảnh bìa.

Header KHÔNG trượt — đó là chỗ ảnh bìa đang bay tới đậu.

BottomBarStyle.settle giữ nguyên mọi chỗ dùng khác của nó."
```

---

## Manual QA (needs the phone)

Step 7 covers the simulator. On a real device, add:

1. Both appearances. `.ultraThinMaterial` reads very differently in light mode over a pale gradient, and the capsule's whole job is to be visible.
2. The smallest screen available, portrait and landscape — the header slot grew 10pt and the panel is bounded by `contentOffset`, which collapses toward 0 in landscape.
3. Reduce Motion on. The rise and the shrink are both position animations; confirm the app is still usable rather than checking whether they are disabled.
4. VoiceOver — the button's label and selected state are unchanged by this plan, so this is a regression check, not new ground.
