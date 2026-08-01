# Interactive Player Morph — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Evenstar's mini player and Now Playing screen into one card whose shape is driven by a single `progress` value, dragged interactively in both directions over an artwork-tinted background — and make the play/pause icons morph instead of snapping.

**Architecture:** A shared cached downsampling image loader (`ArtworkStore`) replaces per-view decoding, which both unblocks the morph and closes a performance defect already recorded as deferred. A new `PlayerCard` owns `progress`, the drag gesture, the artwork, and the card container; the existing two player views are stripped down to chrome-only and cross-faded inside it. `LibraryView`'s Now Playing `.sheet` is replaced by a `ZStack` overlay.

**Tech Stack:** Swift 5, SwiftUI, `ImageIO` for downsampling, `CoreGraphics` for colour averaging, iOS 17.6 deployment target, Xcode 26. No third-party dependencies.

**Reference spec:** `docs/superpowers/specs/2026-08-01-player-morph-design.md`

## Global Constraints

- **Min iOS deployment target:** 17.6. `.contentTransition(.symbolEffect(.replace))` and `UnevenRoundedRectangle` both require iOS 17, so no availability checks are needed.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION` must stay `nonisolated`** on both targets. Xcode 26's template sets it to `MainActor`, which gives every MainActor-isolated class an isolated `deinit`; below iOS 26 that routes through a back-deployed shim that aborts with a libmalloc double-free on **every** dealloc.
- **Never edit `Evenstar/Evenstar.xcodeproj/project.pbxproj`.** Both targets use Xcode synced folders, so a `.swift` file on disk joins its target automatically, and deleting one removes it.
- **UI framework: SwiftUI only.** Do not introduce `UIViewControllerRepresentable` or a UIKit presentation controller.
- **No third-party libraries.** No `try!`. No silent `catch { }`.
- **A clean build must produce zero Swift warnings.** That bar has held since Phase 2a Task 7 and must not break.
- **`PlaybackService` must not be modified.** This plan is presentation only — no change to playback, queue, persistence, or import behaviour.
- **Phase 1 capability — background audio, lock-screen Now Playing, remote commands — must be preserved.**
- **The import sheet's presentation is untouched.** Its `[.medium, .large]` detents, its conditional drag indicator and its `ScrollView` all stay exactly as they are. Only the Now Playing presentation is rebuilt.
- **Two constants must not drift:** `PlayerCard.collapsedHeight = 64` and the expanded top corner radius of `38`. The collapsed height is read by both `PlayerCard` and `LibraryView`'s safe-area inset; duplicating it as a literal is how the list ends up scrolling a few points under the card.

---

## Commands

There is no Xcode UI available to subagents.

**Clean build — zero Swift warnings required:**
```bash
cd /Users/phanquyetthang/evenstar && xcodebuild clean build -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "warning:|error:|BUILD" | grep -v AppIntents | sort -u
```
Expect exactly `** BUILD SUCCEEDED **`. Allow a 600000 ms timeout.

**Full test suite:**
```bash
cd /Users/phanquyetthang/evenstar && xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "^Test case|TEST SUCCEEDED|TEST FAILED|error:"
```
47 pass today. Scope while iterating with `-only-testing:EvenstarTests/ArtworkStoreTests`.

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
Then **Read the PNG**. **If any of this fails or times out, report it — never synthesize a placeholder file in place of a real artifact.** A verification step that produces a fabricated result is worse than an admitted gap.

## What cannot be verified by a subagent

**No audio file has ever been imported into this app on the simulator.** The player card only appears when a track is playing. **A subagent cannot see the morph, the gesture, the gradient, or the artwork at any size.** The screenshot proves only that the empty library still renders and launch did not crash.

The human partner has the app running on a physical iPhone and will verify the feel there. Report honestly; do not imply the card was observed working.

## File structure

```
Evenstar/Evenstar/
├── Utilities/
│   ├── ArtworkStore.swift             # NEW — cached downsampling loader + dominant colour
│   └── ...
├── Features/
│   ├── Library/
│   │   ├── ArtworkThumbnail.swift     # MODIFIED — loads via ArtworkStore
│   │   └── LibraryView.swift          # MODIFIED — ZStack replaces the Now Playing sheet
│   └── Player/
│       ├── PlayerCard.swift           # NEW — progress, gesture, artwork, container
│       ├── MiniPlayerChrome.swift     # NEW (from MiniPlayerBar) — row only
│       ├── NowPlayingContent.swift    # NEW (from NowPlayingView) — content only
│       ├── MiniPlayerBar.swift        # DELETED
│       └── NowPlayingView.swift       # DELETED
└── EvenstarTests/
    └── ArtworkStoreTests.swift        # NEW — 5 tests
```

---

## Task 1: `ArtworkStore` — cached, downsampling artwork loading

**Goal:** One shared loader that decodes artwork at the size actually needed, caches the result, and can produce a dominant colour. It replaces `ArtworkThumbnail`'s per-render full-resolution decode, which is a recorded performance defect in its own right — so this task is independently valuable even before the morph exists.

**Files:**
- Create: `Evenstar/Evenstar/Utilities/ArtworkStore.swift`
- Create: `Evenstar/EvenstarTests/ArtworkStoreTests.swift`
- Modify: `Evenstar/Evenstar/Features/Library/ArtworkThumbnail.swift`

**Interfaces (produced):**
- `enum ArtworkStore` with `static func image(for relativePath: String?, maxPixel: CGFloat) async -> UIImage?` and `static func dominantColor(for relativePath: String?) async -> Color?`

**Background.** Embedded cover art is routinely 1000×1000 to 3000×3000. Decoding a 3000×3000 JPEG to draw a 44 pt thumbnail allocates roughly 36 MB, and `ArtworkThumbnail` does it inside `body` — so on every render of every visible row, with no cache. Task 2's drag gesture would hit that on every frame.

### Steps

- [ ] **Step 1.1: Write the failing tests**

Create `Evenstar/EvenstarTests/ArtworkStoreTests.swift`:

```swift
import XCTest
import UIKit
@testable import Evenstar

final class ArtworkStoreTests: XCTestCase {

    /// Writes a solid-colour JPEG of the given pixel size into Documents/Artwork
    /// and returns its Documents-relative path. ArtworkStore resolves paths
    /// through FileLocation, so the fixture has to live where it would in real use.
    private func makeArtwork(side: CGFloat, color: UIColor) throws -> String {
        let folder = FileLocation.artworkFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "test-\(UUID().uuidString).jpg"
        let url = folder.appendingPathComponent(name)

        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        try data.write(to: url)
        return "Artwork/\(name)"
    }

    private func remove(_ relativePath: String) {
        try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: relativePath))
    }

    func testDownsamplesToRequestedSize() async throws {
        let path = try makeArtwork(side: 600, color: .red)
        defer { remove(path) }

        let image = try XCTUnwrap(await ArtworkStore.image(for: path, maxPixel: 44))

        XCTAssertLessThanOrEqual(image.size.width, 44)
        XCTAssertLessThanOrEqual(image.size.height, 44)
    }

    func testSecondLoadReturnsTheCachedInstance() async throws {
        let path = try makeArtwork(side: 200, color: .green)
        defer { remove(path) }

        let first = try XCTUnwrap(await ArtworkStore.image(for: path, maxPixel: 44))
        let second = try XCTUnwrap(await ArtworkStore.image(for: path, maxPixel: 44))

        XCTAssertTrue(first === second, "Expected the cached instance, not a fresh decode")
    }

    func testMissingFileReturnsNil() async {
        let image = await ArtworkStore.image(
            for: "Artwork/does-not-exist-\(UUID().uuidString).jpg",
            maxPixel: 44
        )

        XCTAssertNil(image)
    }

    func testUndecodableDataReturnsNil() async throws {
        let folder = FileLocation.artworkFolderURL()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "not-an-image-\(UUID().uuidString).jpg"
        try Data("this is not a jpeg".utf8).write(to: folder.appendingPathComponent(name))
        let path = "Artwork/\(name)"
        defer { remove(path) }

        let image = await ArtworkStore.image(for: path, maxPixel: 44)

        XCTAssertNil(image)
    }

    func testDominantColorOfASolidImageIsThatColor() async throws {
        let path = try makeArtwork(side: 120, color: UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        defer { remove(path) }

        let color = try XCTUnwrap(await ArtworkStore.dominantColor(for: path))

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.9, accuracy: 0.15)
        XCTAssertEqual(g, 0.1, accuracy: 0.15)
        XCTAssertEqual(b, 0.1, accuracy: 0.15)
    }
}
```

- [ ] **Step 1.2: Run the tests — they must fail to compile**

Run the scoped test command with `-only-testing:EvenstarTests/ArtworkStoreTests`.
Expected: `Cannot find 'ArtworkStore' in scope`.

- [ ] **Step 1.3: Implement `ArtworkStore`**

Create `Evenstar/Evenstar/Utilities/ArtworkStore.swift`:

```swift
import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Shared artwork loading. Decodes at the size actually needed rather than at
/// the file's full resolution, and caches the result.
///
/// Embedded cover art is routinely 1000x1000 to 3000x3000. Decoding a
/// 3000x3000 JPEG to draw a 44pt thumbnail allocates roughly 36 MB, and doing
/// that inside a view's `body` repeats it on every render. Downsampling through
/// ImageIO decodes only what is drawn.
///
/// Every function here is `nonisolated async`, so the decode runs on the
/// cooperative pool rather than the main actor. Nothing throws — every failure
/// path returns nil, so a corrupt or missing image file can never crash a view.
enum ArtworkStore {

    /// ~50 MB, as the parent design spec has required since Phase 2.
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    private static let colors = NSCache<NSString, UIColor>()

    /// - Parameter maxPixel: the longest edge, in pixels, the decoded image needs.
    ///   Pass the point size multiplied by the screen scale for a crisp result.
    static func image(for relativePath: String?, maxPixel: CGFloat) async -> UIImage? {
        guard let relativePath else { return nil }
        let key = "\(relativePath)@\(Int(maxPixel))" as NSString
        if let cached = images.object(forKey: key) { return cached }

        let url = FileLocation.absoluteURL(forRelative: relativePath)
        guard let image = downsample(url: url, maxPixel: maxPixel) else { return nil }

        images.setObject(image, forKey: key, cost: cost(of: image))
        return image
    }

    /// The average colour of the artwork, used to tint the expanded player's
    /// background. Derived from a 10px decode, so it costs almost nothing.
    static func dominantColor(for relativePath: String?) async -> Color? {
        guard let relativePath else { return nil }
        let key = relativePath as NSString
        if let cached = colors.object(forKey: key) { return Color(uiColor: cached) }

        guard let small = await image(for: relativePath, maxPixel: 10),
              let averaged = averageColor(of: small) else { return nil }

        colors.setObject(averaged, forKey: key)
        return Color(uiColor: averaged)
    }

    // MARK: - Private

    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    private static func averageColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }

        var red = 0, green = 0, blue = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[index])
            green += Int(pixels[index + 1])
            blue += Int(pixels[index + 2])
        }
        let count = width * height
        return UIColor(
            red: CGFloat(red) / CGFloat(count) / 255,
            green: CGFloat(green) / CGFloat(count) / 255,
            blue: CGFloat(blue) / CGFloat(count) / 255,
            alpha: 1
        )
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
```

- [ ] **Step 1.4: Run the tests — they must pass**

Run the scoped test command. Expected: **5 `ArtworkStoreTests` pass**.

If `testSecondLoadReturnsTheCachedInstance` fails, the cache key or the `setObject` call is wrong — do not weaken the assertion to `==`; identity is exactly what the test is for.

- [ ] **Step 1.5: Point `ArtworkThumbnail` at the store**

Replace `Evenstar/Evenstar/Features/Library/ArtworkThumbnail.swift`:

```swift
import SwiftUI

struct ArtworkThumbnail: View {
    let relativePath: String?
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
        .task(id: relativePath) {
            image = await ArtworkStore.image(
                for: relativePath,
                maxPixel: size * UIScreen.main.scale
            )
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.secondary)
        }
    }
}
```

The synchronous `loadImage()` is gone. Loading now happens once per path in a `.task(id:)` rather than on every render, and a row recycled back into view hits the cache.

- [ ] **Step 1.6: Clean build**

Run the clean-build command. Expect exactly `** BUILD SUCCEEDED **`.

If a Sendability warning appears about returning `UIImage` across a concurrency boundary, do not suppress it — report it, since the fix affects the store's signature and needs a decision.

- [ ] **Step 1.7: Run the full suite**

**Expect 52 passing** (47 existing + 5 new), 0 failures.

- [ ] **Step 1.8: Launch and screenshot**

Run the launch-and-screenshot commands, writing to `…/scratchpad/morph-task1.png`, then **Read the PNG**. Expect the unchanged empty-library state: "Library" title, an enabled "+", the blue `music.note.house` hero, "No music yet", the subtitle, an "Import Music" button, nothing at the bottom edge.

The library is empty, so no artwork renders — this is a launch regression check only. Say so.

- [ ] **Step 1.9: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git commit -F - <<'MSG'
feat: cached downsampling artwork loading via ArtworkStore

ArtworkThumbnail decoded artwork at full resolution inside body, so every
render of every visible row re-read and re-decoded the file — routinely a
3000x3000 JPEG allocating ~36 MB to draw a 44pt thumbnail, with no cache.
ArtworkStore decodes at the size actually needed through ImageIO and caches
the result under the ~50 MB limit the design spec has always specified.

Also exposes a dominant colour, which the player morph will use to tint its
background.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Task 2: `PlayerCard` — one card, driven by `progress`

**Goal:** Mini player and Now Playing become the same card. A `progress` value from 0 to 1 drives its height, its artwork's size and position, its corner radius, its background, and which chrome is visible. A drag gesture tracks the finger in both directions.

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/PlayerCard.swift`
- Create: `Evenstar/Evenstar/Features/Player/MiniPlayerChrome.swift`
- Create: `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift`
- Delete: `Evenstar/Evenstar/Features/Player/MiniPlayerBar.swift`
- Delete: `Evenstar/Evenstar/Features/Player/NowPlayingView.swift`
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift`

**Interfaces:**
- Consumes: `ArtworkStore` (Task 1), `PlaybackService` (unchanged), `ArtworkThumbnail` (unchanged, still used by `SongRow`).
- Produces: `struct PlayerCard: View` with `init(playback: PlaybackService)` and `static let collapsedHeight: CGFloat`.

**A refinement over the spec.** The spec sketched `PlayerCard(playback:progress:)` with the progress bound from `LibraryView`. It is cleaner for `PlayerCard` to own its own state and collapse itself when the track goes away — that removes a binding, removes state from `LibraryView`, and keeps the collapse rule next to the thing it collapses. The plan takes that shape. `LibraryView` therefore does **not** gain a `playerProgress` property, and its existing `.onChange(of: playback.currentTrack?.id)` is deleted rather than repurposed.

### Steps

- [ ] **Step 2.1: Extract `MiniPlayerChrome`**

Create `Evenstar/Evenstar/Features/Player/MiniPlayerChrome.swift`:

```swift
import SwiftUI

/// The collapsed player's row: title, artist, transport. No artwork and no
/// background — `PlayerCard` owns both, because they must be continuous
/// across the morph rather than belonging to one end of it.
struct MiniPlayerChrome: View {
    let playback: PlaybackService

    var body: some View {
        if let current = playback.currentTrack {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(current.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Button {
                    playback.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(playback.queueIndex >= playback.queue.count - 1)
            }
        }
    }
}
```

Note `.contentTransition(.symbolEffect(.replace))` on the play/pause icon. Without it SwiftUI treats the two symbol names as different views and swaps them abruptly; with it, the glyph morphs.

- [ ] **Step 2.2: Extract `NowPlayingContent`**

Create `Evenstar/Evenstar/Features/Player/NowPlayingContent.swift` by taking the current `NowPlayingView.swift` and removing its artwork and background. Read the existing file first; the code below is the whole of the new one:

```swift
import SwiftUI

/// The expanded player's content: title, scrubber, transport. No artwork and
/// no background — `PlayerCard` owns both.
struct NowPlayingContent: View {
    let playback: PlaybackService

    @State private var draggingPosition: TimeInterval?

    var body: some View {
        VStack(spacing: 24) {
            titleBlock
            scrubber
            transport
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(playback.currentTrack?.title ?? "—")
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(metadataSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metadataSubtitle: String {
        guard let track = playback.currentTrack else { return "" }
        if track.albumTitle == "Unknown Album" { return track.artistName }
        return "\(track.artistName) · \(track.albumTitle)"
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { draggingPosition ?? playback.position },
                    set: { draggingPosition = $0 }
                ),
                in: 0...max(playback.duration, 0.001),
                onEditingChanged: { editing in
                    if !editing, let target = draggingPosition {
                        playback.seek(to: target)
                        draggingPosition = nil
                    }
                }
            )
            HStack {
                Text(formatTime(draggingPosition ?? playback.position))
                Spacer()
                Text("-" + formatTime(max(0, playback.duration - (draggingPosition ?? playback.position))))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var transport: some View {
        HStack(spacing: 48) {
            Image(systemName: "backward.fill")
                .font(.title2)
                .foregroundStyle(.tertiary)
                // previous deferred to 2c

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)

            Button {
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(playback.queueIndex >= playback.queue.count - 1)
        }
        .padding(.top, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

The `artworkImage` state, `loadArtwork()`, `decodeImage`, the `artwork` property and the `.background(...)` are all gone — `PlayerCard` takes them over.

- [ ] **Step 2.3: Write `PlayerCard`**

Create `Evenstar/Evenstar/Features/Player/PlayerCard.swift`:

```swift
import SwiftUI

/// The player. One card whose shape is a function of `progress`: 0 is the
/// collapsed bar above the library, 1 is the full screen.
///
/// Mini player and Now Playing are not separate views. They are this card at
/// two ends of one continuum, which is what lets the artwork grow continuously
/// instead of one view replacing another. `matchedGeometryEffect` cannot do
/// this: it interpolates between two discrete states as views appear and
/// disappear, and never tracks a finger.
struct PlayerCard: View {
    let playback: PlaybackService

    /// Read by `LibraryView`'s safe-area inset as well, so the list scrolls
    /// clear of the collapsed card. Do not duplicate this as a literal.
    static let collapsedHeight: CGFloat = 64

    private static let collapsedArtwork: CGFloat = 40
    private static let expandedArtwork: CGFloat = 280
    private static let expandedCornerRadius: CGFloat = 38
    /// Gap between the top safe area and the expanded artwork.
    private static let expandedArtworkTopGap: CGFloat = 72

    /// Where the card rests: 0 collapsed, 1 expanded. Changed only on release.
    @State private var settled: Double = 0
    /// How far the in-flight drag has moved it. Zeroed when the drag settles.
    @State private var dragDelta: Double = 0

    @State private var artwork: UIImage?
    @State private var tint: Color?

    private var progress: Double { min(max(settled + dragDelta, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.height - Self.collapsedHeight, 1)
            let height = Self.collapsedHeight + travel * progress

            ZStack(alignment: .topLeading) {
                background
                miniChrome(width: geo.size.width)
                expandedContent(size: geo.size, topInset: geo.safeAreaInsets.top)
                artworkView(size: geo.size, topInset: geo.safeAreaInsets.top)
            }
            .frame(width: geo.size.width, height: height, alignment: .top)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Self.expandedCornerRadius * progress,
                    topTrailingRadius: Self.expandedCornerRadius * progress
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            .onTapGesture { if progress < 0.5 { expand() } }
        }
        .ignoresSafeArea()
        .opacity(playback.currentTrack == nil ? 0 : 1)
        .allowsHitTesting(playback.currentTrack != nil)
        .task(id: playback.currentTrack?.id) { await loadArtwork() }
        .onChange(of: playback.currentTrack?.id) { _, id in
            if id == nil { collapse() }
        }
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .opacity(1 - progress)
            LinearGradient(
                colors: [tint ?? Color(.systemGroupedBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)
        }
    }

    private func miniChrome(width: CGFloat) -> some View {
        MiniPlayerChrome(playback: playback)
            .padding(.leading, Self.collapsedArtwork + 24)
            .padding(.trailing, 12)
            .frame(width: width, height: Self.collapsedHeight)
            .opacity(max(0, 1 - progress * 3))
            .allowsHitTesting(progress < 0.1)
    }

    private func expandedContent(size: CGSize, topInset: CGFloat) -> some View {
        NowPlayingContent(playback: playback)
            .padding(.horizontal, 24)
            .frame(width: size.width)
            .offset(y: topInset + Self.expandedArtworkTopGap + Self.expandedArtwork + 40)
            .opacity(max(0, (progress - 0.5) * 2))
            .allowsHitTesting(progress > 0.9)
    }

    private func artworkView(size: CGSize, topInset: CGFloat) -> some View {
        let side = Self.collapsedArtwork
            + (Self.expandedArtwork - Self.collapsedArtwork) * progress
        let collapsedCentre = CGPoint(
            x: 12 + Self.collapsedArtwork / 2,
            y: Self.collapsedHeight / 2
        )
        let expandedCentre = CGPoint(
            x: size.width / 2,
            y: topInset + Self.expandedArtworkTopGap + Self.expandedArtwork / 2
        )
        let centre = CGPoint(
            x: collapsedCentre.x + (expandedCentre.x - collapsedCentre.x) * progress,
            y: collapsedCentre.y + (expandedCentre.y - collapsedCentre.y) * progress
        )

        return Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color(.tertiarySystemFill))
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.4))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.12))
        .shadow(radius: 10 * progress, y: 4 * progress)
        .position(centre)
    }

    // MARK: - Gesture

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                var delta = -value.translation.height / travel
                let raw = settled + delta
                // Past the top, damp the excess so the card feels tethered
                // rather than rigid.
                if raw > 1 { delta -= (raw - 1) * 0.8 }
                dragDelta = delta
            }
            .onEnded { value in
                // Decide on the predicted end, not the current offset, so a
                // quick flick settles the card even though the finger barely
                // moved. Comparing raw distance is what makes hand-rolled
                // sheets feel heavy.
                let predicted = settled - value.predictedEndTranslation.height / travel
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    settled = predicted > 0.5 ? 1 : 0
                    dragDelta = 0
                }
            }
    }

    private func expand() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            settled = 1
            dragDelta = 0
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            settled = 0
            dragDelta = 0
        }
    }

    private func loadArtwork() async {
        let path = playback.currentTrack?.artworkRelativePath
        async let image = ArtworkStore.image(
            for: path,
            maxPixel: Self.expandedArtwork * UIScreen.main.scale
        )
        async let colour = ArtworkStore.dominantColor(for: path)
        let (loadedImage, loadedColour) = await (image, colour)

        guard playback.currentTrack?.artworkRelativePath == path else { return }
        artwork = loadedImage
        tint = loadedColour
    }
}
```

Two things worth understanding rather than transcribing blindly.

The `guard` at the end of `loadArtwork()` discards a load that finished after the track changed. `.task(id:)` cancels cooperatively, but the decode never checks `Task.isCancelled`, so a slow load for the previous track could otherwise land on top of a newer one. The same guard exists in the current `NowPlayingView` for the same reason.

`.allowsHitTesting` on each chrome set stops the invisible one from swallowing taps. Without it the collapsed bar's buttons stay tappable behind the expanded player.

- [ ] **Step 2.4: Rewire `LibraryView`**

Read `Evenstar/Evenstar/Features/Library/LibraryView.swift` in full first. It is the most complex file in the app: an import flow with security-scoped URL partitioning, a picker-error alert, tap-to-play, swipe-to-delete, a `.task` that restores playback state, plus the two presentations. **Edit it surgically — do not paste over it.**

Four changes, and nothing else:

1. Wrap the `NavigationStack` in a `ZStack`, adding `PlayerCard` as the second child.
2. Replace `MiniPlayerBar(playback: playback)` inside `.safeAreaInset(edge: .bottom)` with a spacer of the card's height.
3. Delete the `.fullScreenCover`/`.sheet` block that presented `NowPlayingView`, along with the `showNowPlaying` state.
4. Delete the `.onChange(of: playback.currentTrack?.id)` that reset `showNowPlaying` — `PlayerCard` now collapses itself.

The `body`'s outer shape becomes:

```swift
    var body: some View {
        ZStack {
            NavigationStack {
                content
                    .navigationTitle("Library")
                    .toolbar { … unchanged … }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear
                            .frame(height: playback.currentTrack == nil ? 0 : PlayerCard.collapsedHeight)
                    }
                    .task { await playback.restoreFromPersistedState() }
            }
            PlayerCard(playback: playback)
        }
        .fileImporter( … unchanged … )
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) { … unchanged … }
        .alert( … unchanged … )
    }
```

Keep the `.fileImporter`, the import `.sheet` and the `.alert` exactly as they are, attached outside the `ZStack`. Keep `partitionByScopeAccess`, `stopAccessingURLs`, `deleteTrack` and every `@State` except `showNowPlaying`.

- [ ] **Step 2.5: Delete the two replaced files**

```bash
cd /Users/phanquyetthang/evenstar
rm Evenstar/Evenstar/Features/Player/MiniPlayerBar.swift
rm Evenstar/Evenstar/Features/Player/NowPlayingView.swift
```

Then confirm nothing references them:

```bash
grep -rn "MiniPlayerBar\|NowPlayingView" Evenstar/ || echo "clean"
```

Expect `clean`. Synced folders pick up the deletions with no project-file edit.

- [ ] **Step 2.6: Clean build**

Run the clean-build command. Expect exactly `** BUILD SUCCEEDED **` with zero Swift warnings. Report it verbatim.

- [ ] **Step 2.7: Run the full suite**

**Expect 52 passing**, 0 failures. This task adds no tests and must break none — the deleted views had none.

- [ ] **Step 2.8: Launch and screenshot**

Run the launch-and-screenshot commands, writing to `…/scratchpad/morph-task2.png`, then **Read the PNG**.

Expect the empty-library state, unchanged, with **nothing at the bottom edge** — `PlayerCard` is fully transparent and non-interactive when `currentTrack` is nil, and the safe-area spacer collapses to zero height. If a strip, a divider or a band of material appears at the bottom, the `opacity`/`allowsHitTesting` gating or the spacer height is wrong.

Say plainly that the morph itself is unexercised: no track has ever been imported on the simulator, so the card has never rendered in its visible state.

- [ ] **Step 2.9: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git commit -F - <<'MSG'
feat: mini player and Now Playing become one card driven by progress

Tapping the mini player used to present a separate sheet. The two are now a
single card whose height, artwork frame, corner radius, background and visible
chrome are all functions of one progress value, so the artwork grows
continuously instead of one view replacing another. A drag tracks the finger in
both directions and settles on predicted velocity, so a flick collapses it.

matchedGeometryEffect cannot express this: it interpolates between two discrete
states as views appear and disappear, and never follows a gesture.

Play/pause icons now morph via symbolEffect(.replace) instead of snapping.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Tuning, and what only the device can settle

Every constant in `PlayerCard` is a considered starting point, not a measured one. These are the ones expected to need adjustment once the human partner has it in hand:

- `expandedArtworkTopGap` (72) — how far the artwork sits below the notch
- the `40` in `expandedContent`'s offset — the gap between artwork and title
- the spring `response` (0.42–0.45) and `dampingFraction` (0.85–0.86)
- the `0.8` damping factor on over-drag
- the `0.5` settle threshold
- the chrome cross-fade windows (`1 - progress * 3` and `(progress - 0.5) * 2`)

Do not tune them blind. Land the plan, then adjust with the device.

## Out of scope

- Landscape optimisation. It must not break, but it is not designed for.
- Any change to `PlaybackService`, the queue, persistence or import.
- The import sheet's presentation.
- A queue-editing sheet, shuffle, repeat, previous-track — all Phase 2c.
- Collapsing `LibraryView`'s remaining sheet and alert into an enum-driven route. Recommended by the Phase 2a final reviewer for when a third presented surface arrives; this plan removes one rather than adding one, so it can wait.

## Self-review

- ✅ Spec §4.2 `ArtworkStore` → Task 1 Steps 1.1–1.4, with the ~50 MB cache, ImageIO downsampling and the averaged dominant colour.
- ✅ Spec §4.2 `ArtworkThumbnail` migration → Step 1.5.
- ✅ Spec §4.2 `MiniPlayerChrome` / `NowPlayingContent`, both losing artwork and background → Steps 2.1 and 2.2.
- ✅ Spec §4.2 `PlayerCard` → Step 2.3.
- ✅ Spec §4.3 placement, safe-area spacer, self-collapse → Step 2.4, with the binding refinement stated explicitly at the task header.
- ✅ Spec §4.4 the progress table → `PlayerCard`'s `background`, `miniChrome`, `expandedContent`, `artworkView` and `clipShape`, including `collapsedHeight` 64 and corner radius 38 as named constants.
- ✅ Spec §4.5 gesture, over-drag damping, predicted-velocity settle → `drag(travel:)`.
- ✅ Spec §4.6 symbol animation → both chrome files, Steps 2.1 and 2.2.
- ✅ Spec §5 error handling → `ArtworkStore` returns nil throughout; `artworkView` falls back to the `music.note` placeholder; `background` falls back to `systemGroupedBackground` when `tint` is nil.
- ✅ Spec §6 testing → 5 `ArtworkStoreTests`; no view tests; 47 → 52.
- ✅ Spec §8 file table → matches this plan's file structure exactly, including the two deletions.
- ✅ Placeholder scan: no TBD, no TODO, no "add appropriate error handling", no "similar to Task N". Every code step gives complete code.
- ✅ Type consistency: `ArtworkStore.image(for:maxPixel:)` and `dominantColor(for:)` are called in Task 2 exactly as Task 1 defines them. `PlayerCard.collapsedHeight` is referenced by `LibraryView` in Step 2.4 as Task 2 declares it. `MiniPlayerChrome(playback:)` and `NowPlayingContent(playback:)` match their call sites in `PlayerCard`.
- ✅ Task boundaries: a reviewer can approve Task 1 and reject Task 2. Task 1 ships a standalone performance fix that leaves the app working and better; Task 2 depends on it but is separately judgeable.
