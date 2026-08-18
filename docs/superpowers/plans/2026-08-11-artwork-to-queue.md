# Artwork-to-Queue Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opening the queue shrinks the cover into the header's 44pt slot instead of cross-fading two pictures.

**Architecture:** The artwork's five `progress`-driven terms split into two groups. The mask and corner radius take `shapeProgress = progress * (1 - queueFactor)`, so queue-open reuses the appearance the code already draws at `progress == 0`. Width, height and centre gain a second interpolation toward the header slot. The arithmetic moves into one pure static function so it can be unit-tested, following `dragOffset`/`dragThreshold`'s precedent in the same file.

**Tech Stack:** Swift 6, SwiftUI, XCTest. iOS 18.0 deployment target.

**Spec:** `docs/superpowers/specs/2026-08-11-artwork-to-queue-design.md`

**One deliberate improvement on the spec.** Its Testing section says "there is
nothing here a unit test can hold" and offers an observation list instead. That
was true of the change as described — a modifier chain — and stops being true
the moment the arithmetic is lifted into a pure function, which this plan does
for exactly that reason. The observation list survives as Step 9: the geometry
becomes testable, the *animation* does not.

## Global Constraints

- **NEVER edit `Evenstar/Evenstar.xcodeproj/project.pbxproj` or any `.xcscheme`.** New Swift files are picked up automatically — Xcode 16 synced folders.
- Every `xcodebuild` invocation passes `-configuration Debug` explicitly.
- Build tests with `clean build-for-testing`, never plain `build` — a plain `build` strips the test PlugIn from the app bundle and the next `test-without-building` fails with "Failed to create a bundle instance … EvenstarTests.xctest".
- Simulator destination: `platform=iOS Simulator,name=iPhone 17`.
- No third-party libraries. SwiftUI only. No `try!`. No silently swallowed `catch {}`.
- Never modify a pre-existing test to make new code pass.
- **`PlayerCard.contentBudget` must not be touched.** This plan changes how the artwork is drawn, never how much room anything gets.
- **The two existing ends must not move.** The collapsed pill thumbnail and the full-bleed expanded cover look exactly as they do today. The design achieves this by construction — `queueFactor` is 0 in both — and the tests below pin it.
- Suite is at **408 tests** before this plan starts.

---

### Task 1: The transition

**Files:**
- Modify: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`
- Modify: `Evenstar/Evenstar/Features/Player/QueuePanel.swift`
- Test: `Evenstar/EvenstarTests/ArtworkGeometryTests.swift` (create)

**Interfaces:**
- Consumes: `PlayerCard`'s existing `collapsedArtwork`, `collapsedArtworkInset`, `collapsedHeight`, `artworkFadeFraction`, `dissolveStops(progress:)`, `grabberTopGap`, `grabberHeight`, and the `showingQueue` state added by the queue-view đợt.
- Produces: `PlayerCard.ArtworkGeometry` and `PlayerCard.artworkGeometry(...)`, plus `QueuePanel.headerArtwork` promoted from `private`.

- [ ] **Step 1: Write the failing tests**

Create `Evenstar/EvenstarTests/ArtworkGeometryTests.swift`:

```swift
import XCTest
@testable import Evenstar

/// The artwork's geometry across three states, as one pure function.
///
/// The two that already shipped — the collapsed pill and the full-bleed cover —
/// matter more here than the new one. This change works by feeding an existing
/// expression a different number, and the whole claim is that the number is
/// unchanged at both ends. These assertions are what turn that claim into
/// something that fails out loud if it stops being true.
final class ArtworkGeometryTests: XCTestCase {

    /// An iPhone 17 at full expansion. `artworkHeight` is the real formula's
    /// output — `min(0.59 * 874, 874 - 120)`. `thumbCentre` is a *fixture*, not
    /// a measurement: it stands for wherever the header slot happens to be, and
    /// every assertion below is written against the value passed in rather than
    /// against a number this test claims to know. That is deliberate — pinning
    /// the real slot position here would make these tests fail every time the
    /// panel's padding changed, for a reason that has nothing to do with what
    /// they check.
    private let cardSize = CGSize(width: 402, height: 874)
    private let artworkHeight: CGFloat = 515.66
    private let thumbCentre = CGPoint(x: 46, y: 81)
    private let thumbSide: CGFloat = 44

    private func geometry(progress: Double, queueFactor: Double) -> PlayerCard.ArtworkGeometry {
        PlayerCard.artworkGeometry(
            progress: progress,
            queueFactor: queueFactor,
            cardSize: cardSize,
            artworkHeight: artworkHeight,
            queueThumbCentre: thumbCentre,
            queueThumbSide: thumbSide
        )
    }

    // MARK: - The two ends that already shipped

    func testTheCollapsedPillIsUnchangedByTheQueueFactor() {
        let withoutQueue = geometry(progress: 0, queueFactor: 0)
        let withQueue = geometry(progress: 0, queueFactor: 1)

        // The pill is not on screen while the queue is open, but the factor
        // must not reach it even so — an expression that changes the collapsed
        // state is an expression that will change it the day the two overlap.
        XCTAssertEqual(withoutQueue.width, withQueue.width, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.height, withQueue.height, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.centre.x, withQueue.centre.x, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.centre.y, withQueue.centre.y, accuracy: 0.001)
        XCTAssertEqual(withoutQueue.shapeProgress, withQueue.shapeProgress, accuracy: 0.001)
    }

    func testTheCollapsedPillKeepsItsOwnSizeAndPlace() {
        let g = geometry(progress: 0, queueFactor: 0)

        XCTAssertEqual(g.width, 36, accuracy: 0.001, "collapsedArtwork")
        XCTAssertEqual(g.height, 36, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, 36, accuracy: 0.001, "inset 18 + half of 36")
        XCTAssertEqual(g.centre.y, 27, accuracy: 0.001, "half of collapsedHeight 54")
        XCTAssertEqual(g.shapeProgress, 0, accuracy: 0.001, "rounded, no dissolve")
    }

    func testTheExpandedCoverIsFullBleedAndSquareCornered() {
        let g = geometry(progress: 1, queueFactor: 0)

        XCTAssertEqual(g.width, cardSize.width, accuracy: 0.001)
        XCTAssertEqual(g.height, artworkHeight, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, cardSize.width / 2, accuracy: 0.001)
        XCTAssertEqual(g.centre.y, artworkHeight / 2, accuracy: 0.001)
        XCTAssertEqual(g.shapeProgress, 1, accuracy: 0.001, "square, dissolving")
    }

    // MARK: - The new end

    func testQueueOpenLandsExactlyOnTheHeaderSlot() {
        let g = geometry(progress: 1, queueFactor: 1)

        XCTAssertEqual(g.width, thumbSide, accuracy: 0.001)
        XCTAssertEqual(g.height, thumbSide, accuracy: 0.001)
        XCTAssertEqual(g.centre.x, thumbCentre.x, accuracy: 0.001)
        XCTAssertEqual(g.centre.y, thumbCentre.y, accuracy: 0.001)
    }

    /// The observation the whole design rests on: at queue-open the artwork
    /// must look like a thumbnail, and `shapeProgress == 0` is how the existing
    /// mask and corner-radius expressions already say that.
    func testQueueOpenLooksLikeAThumbnailNotLikeACover() {
        XCTAssertEqual(geometry(progress: 1, queueFactor: 1).shapeProgress, 0, accuracy: 0.001)
    }

    // MARK: - In between

    func testTheTransitionIsMonotonicInTheQueueFactor() {
        // Half-open must sit strictly between the two ends on every term, or
        // the artwork would double back on itself mid-animation.
        let open = geometry(progress: 1, queueFactor: 0)
        let half = geometry(progress: 1, queueFactor: 0.5)
        let queued = geometry(progress: 1, queueFactor: 1)

        XCTAssertTrue(queued.width < half.width && half.width < open.width)
        XCTAssertTrue(queued.height < half.height && half.height < open.height)
        XCTAssertTrue(queued.centre.y < half.centre.y && half.centre.y < open.centre.y)
        XCTAssertTrue(queued.shapeProgress < half.shapeProgress && half.shapeProgress < open.shapeProgress)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep error: | head -3
```

Expected: `type 'PlayerCard' has no member 'artworkGeometry'`.

- [ ] **Step 3: Add the pure function**

In `Evenstar/Evenstar/Features/Player/PlayerCard.swift`, add near `dragOffset`/`dragThreshold` — the other static geometry functions this file already extracts for testability:

```swift
    /// Where the artwork is and what shape it is, for one pair of progresses.
    ///
    /// `shapeProgress` is deliberately separate from the size and position: the
    /// mask and the corner radius only need to know whether the artwork
    /// currently looks like a thumbnail or like a full-bleed cover, and both
    /// existing expressions already answer that from a single number.
    struct ArtworkGeometry: Equatable {
        let width: CGFloat
        let height: CGFloat
        let centre: CGPoint
        let shapeProgress: Double
    }

    /// The artwork's geometry across all three states it can be in.
    ///
    /// Pure and `static` for the reason `dragOffset` and `dragThreshold` are:
    /// this is the arithmetic that is easy to get wrong and impossible to see
    /// wrong, and a view modifier chain cannot be asserted against.
    ///
    /// **`queueFactor` is folded into `progress` for shape, and applied after
    /// it for position.** That asymmetry is the design. For shape,
    /// `progress * (1 - queueFactor)` reuses the appearance the code already
    /// draws at `progress == 0` — rounded, opaque, no dissolve — which is
    /// exactly what a 44pt thumbnail wants, so no new formula is written and
    /// the two shipped ends cannot move. For position, the queue slot is a
    /// third destination the collapsed→expanded interpolation has to reach
    /// *through*, so it is applied to the expanded end before that
    /// interpolation runs.
    static func artworkGeometry(
        progress: Double,
        queueFactor: Double,
        cardSize: CGSize,
        artworkHeight: CGFloat,
        queueThumbCentre: CGPoint,
        queueThumbSide: CGFloat
    ) -> ArtworkGeometry {
        // Where the artwork ends up once the card is fully open — full bleed,
        // or the header slot if the queue is showing.
        let openWidth = cardSize.width + (queueThumbSide - cardSize.width) * queueFactor
        let openHeight = artworkHeight + (queueThumbSide - artworkHeight) * queueFactor
        let expandedCentre = CGPoint(x: cardSize.width / 2, y: artworkHeight / 2)
        let openCentre = CGPoint(
            x: expandedCentre.x + (queueThumbCentre.x - expandedCentre.x) * queueFactor,
            y: expandedCentre.y + (queueThumbCentre.y - expandedCentre.y) * queueFactor
        )

        // The collapsed end is untouched by any of this — see the tests.
        let collapsedCentre = CGPoint(
            x: Self.collapsedArtworkInset + Self.collapsedArtwork / 2,
            y: Self.collapsedHeight / 2
        )

        return ArtworkGeometry(
            width: Self.collapsedArtwork + (openWidth - Self.collapsedArtwork) * progress,
            height: Self.collapsedArtwork + (openHeight - Self.collapsedArtwork) * progress,
            centre: CGPoint(
                x: collapsedCentre.x + (openCentre.x - collapsedCentre.x) * progress,
                y: collapsedCentre.y + (openCentre.y - collapsedCentre.y) * progress
            ),
            shapeProgress: progress * (1 - queueFactor)
        )
    }
```

- [ ] **Step 4: Run the tests**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EvenstarTests/ArtworkGeometryTests 2>&1 \
  | grep -E "Test case .*(passed|failed)" | sed 's/ on .*//'
```

Expected: 6 passed, 0 failed.

- [ ] **Step 5: Let `PlayerCard` read the header slot's size**

In `Evenstar/Evenstar/Features/Player/QueuePanel.swift`, promote one constant and hide the thumbnail it describes:

```swift
    /// Read by `PlayerCard`, which flies the real artwork down into this slot —
    /// so the two must agree on its size. Not `private` for that reason alone;
    /// `rowArtwork` beside it stays private because nothing outside needs it.
    static let headerArtwork: CGFloat = 44
```

Then, in `header`, make the thumbnail hold its place without drawing:

```swift
            // Invisible, and that is the whole job. `PlayerCard` shrinks the
            // real artwork down onto exactly this rect, so drawing a second
            // copy here would double it for the length of the animation and
            // leave two thumbnails stacked at rest. What this still does is
            // reserve the space, so the title and artist do not slide sideways
            // when the queue opens.
            ArtworkThumbnail(
                relativePath: playback.currentTrack?.artworkRelativePath,
                size: Self.headerArtwork
            )
            .opacity(0)
            .accessibilityHidden(true)
```

- [ ] **Step 6: Wire the function into `artworkView`**

In `PlayerCard.artworkView(size:artworkHeight:topInset:)`, replace the hand-rolled `width` / `height` / `collapsedCentre` / `expandedCentre` / `centre` block at the top with a call, and name the side margin so the two places that need it cannot drift:

```swift
        // The queue panel's own horizontal inset, named because two things
        // depend on it: the panel's `.padding(.horizontal,)` below, and the
        // header slot's centre computed here. A literal in both places is two
        // numbers that must agree and nothing to notice when they stop.
        let sideMargin = Self.queuePanelSideMargin
        let panelTop = topInset + Self.grabberTopGap + Self.grabberHeight
        let geometry = Self.artworkGeometry(
            progress: progress,
            queueFactor: showingQueue ? 1 : 0,
            cardSize: size,
            artworkHeight: artworkHeight,
            // The header slot, derived from constants rather than measured: a
            // measurement would depend on a layout pass that has not run on
            // the first frame of the transition.
            queueThumbCentre: CGPoint(
                x: sideMargin + QueuePanel.headerArtwork / 2,
                y: panelTop + QueuePanel.headerArtwork / 2
            ),
            queueThumbSide: QueuePanel.headerArtwork
        )
        let width = geometry.width
        let height = geometry.height
        let centre = geometry.centre
```

Add the constant beside the other layout constants:

```swift
    /// How far `QueuePanel` is inset from each side of the card.
    private static let queuePanelSideMargin: CGFloat = 24
```

Change the two shape modifiers to read `geometry.shapeProgress` instead of `progress`:

```swift
        .mask(
            LinearGradient(
                stops: Self.dissolveStops(progress: geometry.shapeProgress),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: width * 0.12 * (1 - geometry.shapeProgress)))
```

**Leave `.shadow(color: .black.opacity(0.18), radius: 6, y: 3)` exactly as it is.** An earlier draft of the design scaled it with `shapeProgress`; that is wrong twice — it removes the shadow at queue-open, and `shapeProgress` is also 0 for the collapsed pill, so it would silently change how the pill has looked since Phase 2.

**Delete `.opacity(showingQueue ? 0 : 1)`.** The artwork no longer disappears when the queue opens — it *becomes* the header thumbnail. Leaving the fade in would shrink an invisible view onto an invisible slot.

Replace the panel's `.padding(.horizontal, 24)` with `.padding(.horizontal, sideMargin)`.

- [ ] **Step 7: Build and run the whole suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild build -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \
  | grep -E "error:|warning: .*\.swift|BUILD" | tail -6
xcodebuild clean build-for-testing -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -2
xcodebuild test-without-building -scheme Evenstar -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/artwork.xcresult 2>&1 | tail -1
xcrun xcresulttool get test-results summary --path /tmp/artwork.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'], d['totalTestCount'], d['failedTests'])"
```

Expected: `BUILD SUCCEEDED` with no warnings, then `Passed 414 0`. `DragOffsetTests` must still pass — it covers the neighbouring static functions in the same file.

- [ ] **Step 8: Mutation check — prove the shipped ends are really pinned**

Temporarily change `shapeProgress` to ignore the queue:

```swift
            shapeProgress: progress
```

Re-run `-only-testing:EvenstarTests/ArtworkGeometryTests`. Expected:
`testQueueOpenLooksLikeAThumbnailNotLikeACover` and
`testTheTransitionIsMonotonicInTheQueueFactor` **fail**; the two shipped-end
tests still pass, because that mutation does not touch them.

Then temporarily change the collapsed centre to depend on the factor:

```swift
            x: Self.collapsedArtworkInset + Self.collapsedArtwork / 2 + 10 * queueFactor,
```

Expected: `testTheCollapsedPillIsUnchangedByTheQueueFactor` **fails**. Restore
both and confirm all six pass. Report all outcomes.

- [ ] **Step 9: Run it and look at it**

The geometry is now pinned by tests; the animation is not. Build to the
simulator, play a Jamendo track with something upcoming, open the player, and
open and close the queue. Report what you see against each of these:

- the cover shrinks into the header slot, corners rounding as it goes
- the bottom fade disappears **with** the shrink, not one frame before or after it
- closing the queue runs the same motion in reverse, back to full bleed
- there is exactly one thumbnail at rest, not two stacked
- collapsing the player while the queue is open ends at the pill

**If the fade snaps while the size glides, say so and stop.** That is the risk
the design names: `Gradient.Stop` may not interpolate. The fix is a
`@State private var queueFactor: Double` driven by the same `withAnimation`
that flips `showingQueue`, passed to `artworkGeometry` in place of the ternary
— but make that change only on the evidence, and report the evidence.

Practical notes: the simulator's local library fixtures are broken and will not
play; use Jamendo. Synthetic coordinate clicks miss this app's touch-down
buttons — click the accessibility element directly.

- [ ] **Step 10: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar/Evenstar/Features/Player/PlayerCard.swift \
        Evenstar/Evenstar/Features/Player/QueuePanel.swift \
        Evenstar/EvenstarTests/ArtworkGeometryTests.swift
git commit -m "feat: ảnh bìa thu nhỏ vào dòng đầu hàng đợi

Năm số hạng hình học của ảnh bìa tách thành hai nhóm. Mask và bo góc
nhận progress * (1 - queueFactor), nên trạng thái hàng đợi dùng lại
đúng hình dáng code đã vẽ ở progress = 0: bo góc, đục, không tan dần.
Không viết công thức mới nào, và hai đầu đã ship không thể xê dịch —
theo cấu trúc, không nhờ cẩn thận.

Chiều rộng, chiều cao và tâm nội suy tiếp về ô 44pt ở dòng đầu panel.
Ô đó suy ra từ hằng số chứ không đo lúc chạy: đo nghĩa là phụ thuộc
một lượt layout chưa xảy ra ở khung hình đầu tiên.

Số học chuyển vào một hàm thuần static, theo tiền lệ dragOffset và
dragThreshold ngay trong cùng file — đây là loại phép tính dễ sai và
không thể nhìn ra sai."
```

---

## Manual QA (needs the phone)

Step 9 covers this in the simulator. On a real device, add:

1. A track with no artwork — the placeholder shrinks the same way, since it goes through the same view.
2. A slow drag-collapse with the queue open: the artwork should end at the pill, and the queue should be closed when the player is reopened.
3. Landscape, on the smallest device available: the header slot's y is `topInset + grabberTopGap + grabberHeight + 22`, which does not depend on orientation, but the artwork's expanded height does. Confirm the shrink still lands on the slot rather than overshooting.
4. Both appearances — the dissolve mask is white-on-clear and reads differently against a light background.
