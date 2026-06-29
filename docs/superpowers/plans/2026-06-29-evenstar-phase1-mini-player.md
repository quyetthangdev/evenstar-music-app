# Evenstar — Phase 1 (Mini Player) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a single-screen SwiftUI iPhone app that plays one bundled `.mp3` file with full lock-screen integration (metadata, transport controls, scrubbing) and background audio. This is the learning-foundation deliverable before the full local-library app (Phase 2 is a separate plan).

**Architecture:** SwiftUI app with a thin `PlaybackService` (`@Observable`) wrapping an `AudioPlayerProtocol`-backed `AVAudioPlayer`. A `NowPlayingService` mirrors playback state to `MPNowPlayingInfoCenter`, and `MPRemoteCommandCenter` routes lock-screen / headphone / CarPlay controls back into the service. No SwiftData yet — Phase 1 hard-codes one track from the app bundle.

**Tech Stack:** Swift 5.9+, SwiftUI, `@Observable` (Observation framework), `AVFoundation` (`AVAudioPlayer`, `AVAudioSession`), `MediaPlayer` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`), `XCTest`. **No third-party dependencies.**

**Reference spec:** `docs/superpowers/specs/2026-06-29-music-app-phase1-2-design.md` (sections 1, 2, 5, 9 cover Phase 1).

## Global Constraints

These apply to every task — do not violate them without revising this plan.

- **Min iOS deployment target:** 17.2
- **UI framework:** SwiftUI only (no UIKit views in Phase 1)
- **State management:** `@Observable` macro from `Observation` (not `ObservableObject`)
- **Audio engine:** `AVAudioPlayer` (not `AVPlayer`, not `AVAudioEngine` — those are out of scope for Phase 1)
- **Audio session category:** `.playback`, mode `.default`
- **Background modes:** `audio` in `Info.plist` (`UIBackgroundModes`)
- **App / project name:** `Evenstar`
- **Bundle identifier prefix:** `com.<your-team-id>.evenstar` (substitute your concrete prefix; if no Apple Developer Program yet, use `com.example.evenstar` for free-provisioning)
- **No third-party libraries** (no SwiftLog, no Combine wrappers, no SPM dependencies)
- **No `try!`** in production code; no silent `catch { }`
- **Commit frequency:** every passing task end (5–10 commits across this plan)

---

## File structure created by this plan

By the end of Phase 1 the repo contains:

```
evenstar/                                          # already exists, git initialized
├── docs/
│   └── superpowers/
│       ├── specs/2026-06-29-music-app-phase1-2-design.md   # already exists
│       └── plans/2026-06-29-evenstar-phase1-mini-player.md # this file
└── Evenstar/                                      # Xcode project root
    ├── Evenstar.xcodeproj/                        # Xcode-generated
    ├── Evenstar/
    │   ├── App/
    │   │   └── EvenstarApp.swift                  # @main entry point
    │   ├── Services/
    │   │   ├── AudioPlayerProtocol.swift          # protocol + AVAudioPlayerWrapper
    │   │   ├── PlaybackService.swift              # @Observable, owns the queue (size 1 in Phase 1)
    │   │   └── NowPlayingService.swift            # MPNowPlayingInfoCenter + MPRemoteCommandCenter
    │   ├── Features/
    │   │   └── Player/
    │   │       └── SimplePlayerView.swift         # single-screen player UI
    │   ├── Resources/
    │   │   └── sample.mp3                         # bundled test track
    │   ├── Assets.xcassets/
    │   └── Info.plist                             # UIBackgroundModes=audio
    └── EvenstarTests/
        ├── MockAudioPlayer.swift
        └── PlaybackServiceTests.swift
```

Phase 2 adds `Models/`, `Features/Library/`, `Features/Playlists/`, more services, etc. — out of scope here.

---

## How to read this plan

- Each task is one self-contained deliverable. Finish the entire task (including the commit) before starting the next.
- Read the **Interfaces** block first — it tells you what types and method signatures you must produce so later tasks compile.
- Code blocks are exact: copy them verbatim into the listed file. If a block ends with `// …` it means "preserve the surrounding code", but in this plan we always show the full file for the first write.
- Where the spec demands behavior that can't be unit-tested (e.g., lock-screen UI, real audio output), the task includes a **manual verification** step with a precise expected observation.

---

## Task 1: Bootstrap Xcode project + run "Hello, Evenstar" on a device

**Goal:** Open the existing git repo in Xcode as a fresh iOS App project named `Evenstar`, configure the deployment target to iOS 17.2, build to a real iPhone (or simulator if a real device isn't ready), commit the scaffold.

**Files:**
- Create (via Xcode): `Evenstar/` (project directory), `Evenstar.xcodeproj/`, `Evenstar/EvenstarApp.swift`, `Evenstar/ContentView.swift`, `Evenstar/Assets.xcassets/`, `Evenstar/Info.plist` (or embedded plist if Xcode 15+ uses xcconfig)
- Modify: none (root repo `.git/` already exists from brainstorming)

**Interfaces:**
- Produces: an Xcode project named `Evenstar` rooted at `evenstar/Evenstar/` with `EvenstarApp.swift` declared as the `@main` SwiftUI App.

### Steps

- [ ] **Step 1.1: Install Xcode**

If Xcode is not installed: open the Mac App Store, search "Xcode", install (~10 GB). Launch it once and accept the license. Xcode 15.2+ (released Dec 2023) is the minimum for iOS 17.2 SDK. As of mid-2026 use the latest stable Xcode (likely Xcode 17.x).

After install, in Terminal:

```bash
xcode-select -p
```

Expected: a path under `/Applications/Xcode.app/...`. If it returns `/Library/Developer/CommandLineTools`, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

- [ ] **Step 1.2: Create the Xcode project**

In Xcode → **File → New → Project…** → choose **iOS** tab → **App** template → Next.

Fill in:

| Field | Value |
|---|---|
| Product Name | `Evenstar` |
| Team | Your personal team (Apple ID) or Developer Program team |
| Organization Identifier | `com.<your-name>` (e.g., `com.thang`) — Xcode will combine into `com.thang.Evenstar` |
| Bundle Identifier | (auto-filled, do not edit yet) |
| Interface | **SwiftUI** |
| Language | **Swift** |
| Storage | **None** (we'll add SwiftData in Phase 2) |
| Include Tests | **Checked** |

Click **Next**, then **navigate to `/Users/phanquyetthang/evenstar/`** as the save location. **Uncheck** "Create Git repository on my Mac" (the repo already exists). Click **Create**.

After creation, the layout under `/Users/phanquyetthang/evenstar/Evenstar/` will be:

```
Evenstar.xcodeproj/
Evenstar/
  EvenstarApp.swift
  ContentView.swift
  Assets.xcassets/
  Preview Content/
EvenstarTests/
EvenstarUITests/
```

- [ ] **Step 1.3: Set deployment target to iOS 17.2 and remove UITests**

In Xcode, click the blue **Evenstar** project icon at the top of the navigator → select the **Evenstar** target → **General** tab.

- Under **Minimum Deployments → iOS**, set to **17.2**.
- Under **Supported Destinations**, remove iPad and Mac if listed — keep **iPhone** only.

Then in the navigator, right-click the **EvenstarUITests** folder → **Delete** → choose **Move to Trash**. We won't write UI tests in Phase 1.

- [ ] **Step 1.4: Rearrange folders to match this plan's structure**

In Xcode's Project Navigator (left sidebar), under the `Evenstar` group:

- Right-click `Evenstar` group → **New Group** → name it `App`. Drag `EvenstarApp.swift` into it.
- Create groups `Services`, `Features`, `Features/Player`, `Resources`. Leave them empty for now.
- Delete `ContentView.swift` (we'll write a `SimplePlayerView` in Task 2).

After cleanup, the Project Navigator should show:

```
Evenstar
  App/
    EvenstarApp.swift
  Services/          (empty)
  Features/
    Player/          (empty)
  Resources/         (empty)
  Assets.xcassets
  Preview Content/
EvenstarTests/
```

- [ ] **Step 1.5: Make `EvenstarApp.swift` show a placeholder screen**

Open `Evenstar/App/EvenstarApp.swift` and replace its contents with:

```swift
import SwiftUI

@main
struct EvenstarApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "music.note")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("Hello, Evenstar")
                    .font(.largeTitle)
                    .bold()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}
```

- [ ] **Step 1.6: Build & run on the iOS Simulator**

In Xcode's toolbar, set the destination to **iPhone 15 Pro (iOS 17.2+)** or whichever simulator is available. Press **⌘R** (Run).

**Expected:** Simulator launches, app builds, and a screen with the music-note icon plus "Hello, Evenstar" appears.

If the build fails: read the error message in the Issue Navigator (⌘5). Common first-time issues — wrong Swift version, missing signing team, simulator unavailable — Xcode usually offers an inline fix-it.

- [ ] **Step 1.7: Run on a real iPhone (optional but recommended)**

Background audio behavior on the simulator is unreliable. Plug an iPhone into your Mac via USB → trust the computer on the phone → in Xcode's destination dropdown, select your device.

The first run will require **Settings → General → VPN & Device Management** on the phone → trust your developer certificate.

Press **⌘R**. Expected: same hello screen on the iPhone.

If signing fails, in Xcode → Evenstar target → **Signing & Capabilities** → check **Automatically manage signing** and pick your team. Free Apple-ID provisioning works but rebuilds every 7 days.

- [ ] **Step 1.8: Commit**

Add an iOS-flavored `.gitignore` first. Create `/Users/phanquyetthang/evenstar/.gitignore`:

```gitignore
# macOS
.DS_Store

# Xcode
build/
DerivedData/
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
*.xcuserstate
xcuserdata/
*.xcscmblueprint
*.xccheckout

# Swift Package Manager
.swiftpm/
Packages/
Package.resolved

# CocoaPods (in case we ever add)
Pods/

# Carthage
Carthage/Build/

# fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/**/*.png
fastlane/test_output

# Project-local
*.iml
```

Then in Terminal:

```bash
cd /Users/phanquyetthang/evenstar
git add .gitignore Evenstar
git -c commit.gpgsign=false commit -m "feat: bootstrap Evenstar Xcode project (Phase 1 task 1)"
```

**Expected:** A commit with the Xcode project tree (no `xcuserdata`, no `DerivedData`).

---

## Task 2: Bundled audio playback (protocol + wrapper + button)

**Goal:** Drop a sample mp3 into the bundle. Define `AudioPlayerProtocol` so the audio engine can be mocked in tests. Implement `AVAudioPlayerWrapper`. Build a minimal `@Observable PlaybackService` that holds `currentTrack` and `isPlaying`. Build `SimplePlayerView` with a play/pause button. Verify: tapping the button plays/pauses the bundled mp3.

**Files:**
- Create: `Evenstar/Evenstar/Resources/sample.mp3`
- Create: `Evenstar/Evenstar/Services/AudioPlayerProtocol.swift`
- Create: `Evenstar/Evenstar/Services/PlaybackService.swift`
- Create: `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — show `SimplePlayerView`
- Create: `Evenstar/EvenstarTests/MockAudioPlayer.swift`
- Create: `Evenstar/EvenstarTests/PlaybackServiceTests.swift`

**Interfaces:**

- Consumes: nothing from earlier tasks.
- Produces:
  - `protocol AudioPlayerProtocol: AnyObject` with members:
    - `var isPlaying: Bool { get }`
    - `var currentTime: TimeInterval { get set }`
    - `var duration: TimeInterval { get }`
    - `func load(url: URL) throws`
    - `func play()`
    - `func pause()`
    - `var didFinishCallback: (() -> Void)? { get set }`
  - `final class AVAudioPlayerWrapper: AudioPlayerProtocol`
  - `@Observable final class PlaybackService` with:
    - `init(player: AudioPlayerProtocol)`
    - `private(set) var isPlaying: Bool`
    - `private(set) var currentTrackTitle: String?`
    - `func load(url: URL, title: String) throws`
    - `func togglePlayPause()`

### Steps

- [ ] **Step 2.1: Get a sample mp3**

Pick any short royalty-free mp3 (the [Free Music Archive](https://freemusicarchive.org) has plenty under CC). Rename to `sample.mp3`. Drag it into Xcode's `Resources` group → in the import dialog: **Copy items if needed** ✓, **Add to targets: Evenstar** ✓.

Verify the file shows under `Resources/sample.mp3` in the navigator and is included in the target (right pane → **Target Membership** → `Evenstar` checked).

- [ ] **Step 2.2: Write the protocol and the failing tests for `PlaybackService`**

Create `Evenstar/EvenstarTests/MockAudioPlayer.swift`:

```swift
import Foundation
@testable import Evenstar

final class MockAudioPlayer: AudioPlayerProtocol {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 180
    var didFinishCallback: (() -> Void)?

    private(set) var loadedURL: URL?
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func load(url: URL) throws {
        loadedURL = url
        currentTime = 0
    }

    func play() {
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func simulateFinish() {
        isPlaying = false
        didFinishCallback?()
    }
}
```

Create `Evenstar/EvenstarTests/PlaybackServiceTests.swift`:

```swift
import XCTest
@testable import Evenstar

final class PlaybackServiceTests: XCTestCase {

    private func makeService() -> (PlaybackService, MockAudioPlayer) {
        let mock = MockAudioPlayer()
        let service = PlaybackService(player: mock)
        return (service, mock)
    }

    func testLoadStoresTitleAndCallsPlayerLoad() throws {
        let (service, mock) = makeService()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")

        try service.load(url: url, title: "Sample")

        XCTAssertEqual(service.currentTrackTitle, "Sample")
        XCTAssertEqual(mock.loadedURL, url)
        XCTAssertFalse(service.isPlaying)
    }

    func testTogglePlayPauseStartsPlaybackWhenPaused() throws {
        let (service, mock) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Sample")

        service.togglePlayPause()

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(mock.playCallCount, 1)
        XCTAssertEqual(mock.pauseCallCount, 0)
    }

    func testTogglePlayPausePausesPlaybackWhenPlaying() throws {
        let (service, mock) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), title: "Sample")
        service.togglePlayPause()  // -> playing

        service.togglePlayPause()  // -> paused

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(mock.pauseCallCount, 1)
    }

    func testTogglePlayPauseIsNoOpWhenNothingLoaded() {
        let (service, mock) = makeService()

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(mock.playCallCount, 0)
    }
}
```

- [ ] **Step 2.3: Run the tests — they must fail to compile**

In Xcode: **⌘U** (Run Tests). Or in Terminal:

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -30
```

**Expected:** Compile errors — `Cannot find 'AudioPlayerProtocol' in scope` and `Cannot find 'PlaybackService' in scope`. This is correct; we haven't written them yet.

- [ ] **Step 2.4: Implement `AudioPlayerProtocol` and `AVAudioPlayerWrapper`**

Create `Evenstar/Evenstar/Services/AudioPlayerProtocol.swift`:

```swift
import Foundation
import AVFoundation

protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var didFinishCallback: (() -> Void)? { get set }

    func load(url: URL) throws
    func play()
    func pause()
}

final class AVAudioPlayerWrapper: NSObject, AudioPlayerProtocol, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?

    var didFinishCallback: (() -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    var currentTime: TimeInterval {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }

    var duration: TimeInterval { player?.duration ?? 0 }

    func load(url: URL) throws {
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        player = newPlayer
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        didFinishCallback?()
    }
}
```

- [ ] **Step 2.5: Implement `PlaybackService`**

Create `Evenstar/Evenstar/Services/PlaybackService.swift`:

```swift
import Foundation
import Observation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?

    private let player: AudioPlayerProtocol
    private var hasLoaded: Bool = false

    init(player: AudioPlayerProtocol) {
        self.player = player
        self.player.didFinishCallback = { [weak self] in
            self?.isPlaying = false
        }
    }

    func load(url: URL, title: String) throws {
        try player.load(url: url)
        currentTrackTitle = title
        isPlaying = false
        hasLoaded = true
    }

    func togglePlayPause() {
        guard hasLoaded else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}
```

- [ ] **Step 2.6: Re-run the tests — they must pass**

In Xcode: **⌘U**. Or:

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -20
```

**Expected:** `Test Suite 'PlaybackServiceTests' passed`, 4 tests, 0 failures.

If a test fails, read the message and fix the implementation (or the test if its expectation was wrong) — never `try!` your way past a test failure.

- [ ] **Step 2.7: Build the `SimplePlayerView`**

Create `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift`:

```swift
import SwiftUI

struct SimplePlayerView: View {
    let playback: PlaybackService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 96))
                .foregroundStyle(.tint)
                .padding(48)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

            VStack(spacing: 4) {
                Text(playback.currentTrackTitle ?? "—")
                    .font(.title2.bold())
                Text("Sample track")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    SimplePlayerView(playback: PlaybackService(player: PreviewAudioPlayer()))
}

private final class PreviewAudioPlayer: AudioPlayerProtocol {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 180
    var didFinishCallback: (() -> Void)?
    func load(url _: URL) throws {}
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
}
```

- [ ] **Step 2.8: Wire `PlaybackService` into `EvenstarApp`**

Open `Evenstar/Evenstar/App/EvenstarApp.swift` and replace with:

```swift
import SwiftUI

@main
struct EvenstarApp: App {
    @State private var playback = PlaybackService(player: AVAudioPlayerWrapper())

    var body: some Scene {
        WindowGroup {
            SimplePlayerView(playback: playback)
                .task {
                    loadSampleTrack()
                }
        }
    }

    private func loadSampleTrack() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            assertionFailure("sample.mp3 missing from bundle")
            return
        }
        do {
            try playback.load(url: url, title: "Sample")
        } catch {
            print("Failed to load sample track: \(error)")
        }
    }
}
```

- [ ] **Step 2.9: Manual verification — audio plays**

Press **⌘R**. On the simulator or device:

1. The player screen appears with title "Sample" and a large play button.
2. Tap the play button. **Expected:** sound starts from the simulator's speakers (or the device's speakers); the icon flips to a pause icon.
3. Tap again. **Expected:** sound pauses; icon flips back.

If no sound: confirm the simulator's audio output isn't muted (Hardware → Audio Output), and confirm `sample.mp3` is actually in the bundle (in Xcode: build → Show in Finder → check `.app` package contents).

- [ ] **Step 2.10: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git -c commit.gpgsign=false commit -m "feat: bundled audio playback with PlaybackService (Phase 1 task 2)"
```

---

## Task 3: Background audio

**Goal:** Configure `AVAudioSession` and the app's `Info.plist` so playback continues with the screen locked and survives switching to another app.

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` — configure audio session on init
- Modify: `Evenstar/Evenstar/Info.plist` — add `UIBackgroundModes=audio`
- Modify: `Evenstar/EvenstarTests/PlaybackServiceTests.swift` — add a session-init-doesn't-throw smoke test

**Interfaces:**
- Consumes: `PlaybackService` from Task 2.
- Produces: same `PlaybackService` API with `.playback` category active on first init.

### Steps

- [ ] **Step 3.1: Add `audio` to `UIBackgroundModes`**

Xcode 15+ may use an embedded plist or a separate file. To check:

1. Select the **Evenstar** target → **Info** tab.
2. Look for **Custom iOS Target Properties**. If present, click "+" next to any row, scroll for **Required background modes** (`UIBackgroundModes`) → set its value to an Array with one item: `App plays audio or streams audio/video using AirPlay`. Xcode displays this string; the raw value is `audio`.

If you prefer editing the file: locate `Evenstar/Evenstar/Info.plist` (create one if Xcode generated it inline — right-click the Evenstar group → New File → iOS → Resource → Property List → name `Info.plist`). Set its contents to include:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dictionary>
    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
    </array>
</dictionary>
</plist>
```

(Most Xcode 15+ projects keep `UIBackgroundModes` in the target's INFOPLIST_KEY_… build settings instead of a file. Either approach works; the Info tab UI is the safest.)

- [ ] **Step 3.2: Configure `AVAudioSession` in `PlaybackService`**

Open `Evenstar/Evenstar/Services/PlaybackService.swift` and replace with:

```swift
import Foundation
import Observation
import AVFoundation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?

    private let player: AudioPlayerProtocol
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false

    init(player: AudioPlayerProtocol) {
        self.player = player
        self.player.didFinishCallback = { [weak self] in
            self?.isPlaying = false
        }
    }

    func load(url: URL, title: String) throws {
        try player.load(url: url)
        currentTrackTitle = title
        isPlaying = false
        hasLoaded = true
    }

    func togglePlayPause() {
        guard hasLoaded else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            activateSessionIfNeeded()
            player.play()
            isPlaying = true
        }
    }

    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            sessionActivated = true
        } catch {
            print("Failed to activate audio session: \(error)")
            // Playback may still work via the simulator/system default; do not crash.
        }
    }
}
```

- [ ] **Step 3.3: Update the test for the new behavior**

`MockAudioPlayer` and `PlaybackServiceTests` keep working because the new session code only runs the first time `togglePlayPause` starts playback. No test changes required — but verify by running:

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -15
```

**Expected:** still 4 passing tests.

- [ ] **Step 3.4: Manual verification — lock screen + app switch**

This **must** be tested on a real iPhone — the simulator does not honor background audio.

1. Build & run on the device (**⌘R** with the device selected).
2. Tap play. Audio plays.
3. Press the **side / power button** to lock the device. **Expected:** audio continues.
4. Unlock, swipe up to the home screen, open another app (e.g., Safari). **Expected:** Evenstar's audio continues in the background.

If audio cuts off when the screen locks or when leaving the app: re-check **Signing & Capabilities → Background Modes → Audio, AirPlay, and Picture in Picture** is enabled. (In some Xcode versions you must add the capability via the **+ Capability** button in addition to setting the Info.plist key.)

- [ ] **Step 3.5: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git -c commit.gpgsign=false commit -m "feat: background audio via AVAudioSession.playback (Phase 1 task 3)"
```

---

## Task 4: Lock-screen Now Playing metadata + artwork

**Goal:** When the user locks the device, the lock screen shows the current title, artist, album, artwork, and elapsed time. Implement `NowPlayingService` and have `PlaybackService` push updates on every state change.

**Files:**
- Create: `Evenstar/Evenstar/Services/NowPlayingService.swift`
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` — accept and call `NowPlayingService`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — wire `NowPlayingService`
- Modify: `Evenstar/EvenstarTests/PlaybackServiceTests.swift` — assert `NowPlayingService` is called
- Add: a placeholder cover image into `Assets.xcassets` named `SampleArtwork`

**Interfaces:**
- Consumes: `PlaybackService` from Task 3.
- Produces:
  - `protocol NowPlayingPublisher` (so we can mock it in tests):
    ```swift
    protocol NowPlayingPublisher: AnyObject {
        func update(title: String, artist: String, album: String,
                    artwork: UIImage?, duration: TimeInterval,
                    elapsed: TimeInterval, isPlaying: Bool)
        func clear()
    }
    ```
  - `final class NowPlayingService: NowPlayingPublisher` writing to `MPNowPlayingInfoCenter`.
  - `PlaybackService.init(player:nowPlaying:)` extended signature.

### Steps

- [ ] **Step 4.1: Add a placeholder artwork image**

In Xcode → `Assets.xcassets` → right-click → **New Image Set** → name it `SampleArtwork`. Drag any 1024×1024 JPG/PNG (album-style art) into the 1x slot. If you have nothing handy, generate a solid-color image: in Terminal,

```bash
sips -s format png --resampleHeightWidth 1024 1024 \
  /System/Library/Desktop\ Pictures/Solid\ Colors/Stone.png \
  --out /tmp/sample-art.png
```

— then drag `/tmp/sample-art.png` into the image set.

- [ ] **Step 4.2: Write the `NowPlayingPublisher` mock and failing tests**

Open `Evenstar/EvenstarTests/MockAudioPlayer.swift` and append at the bottom of the file:

```swift
import UIKit

final class MockNowPlayingPublisher: NowPlayingPublisher {
    struct Update {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let elapsed: TimeInterval
        let isPlaying: Bool
    }

    private(set) var updates: [Update] = []
    private(set) var clearCallCount = 0

    func update(title: String, artist: String, album: String,
                artwork _: UIImage?, duration: TimeInterval,
                elapsed: TimeInterval, isPlaying: Bool) {
        updates.append(.init(title: title, artist: artist, album: album,
                             duration: duration, elapsed: elapsed,
                             isPlaying: isPlaying))
    }

    func clear() { clearCallCount += 1 }
}
```

Open `Evenstar/EvenstarTests/PlaybackServiceTests.swift` and **replace** the file with:

```swift
import XCTest
@testable import Evenstar

final class PlaybackServiceTests: XCTestCase {

    private func makeService() -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying)
        return (service, player, nowPlaying)
    }

    func testLoadStoresMetadataAndCallsPlayerLoad() throws {
        let (service, player, _) = makeService()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")

        try service.load(url: url, metadata: .sample)

        XCTAssertEqual(service.currentTrackTitle, "Sample")
        XCTAssertEqual(player.loadedURL, url)
        XCTAssertFalse(service.isPlaying)
    }

    func testTogglePlayPauseStartsPlaybackAndPushesNowPlaying() throws {
        let (service, player, nowPlaying) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.togglePlayPause()

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.title, "Sample")
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, true)
    }

    func testTogglePlayPausePausesAndPushesNowPlaying() throws {
        let (service, player, nowPlaying) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)
        service.togglePlayPause()

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, false)
    }

    func testTogglePlayPauseIsNoOpWhenNothingLoaded() {
        let (service, player, nowPlaying) = makeService()

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 0)
        XCTAssertEqual(nowPlaying.updates.count, 0)
    }
}

private extension TrackMetadata {
    static let sample = TrackMetadata(
        title: "Sample",
        artist: "Unknown Artist",
        album: "Unknown Album",
        artwork: nil,
        durationSeconds: 180
    )
}
```

- [ ] **Step 4.3: Run the tests — they must fail to compile**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -15
```

**Expected:** errors about `NowPlayingPublisher`, `TrackMetadata`, and the new `PlaybackService` initializer signature.

- [ ] **Step 4.4: Implement `NowPlayingPublisher`, `NowPlayingService`, and `TrackMetadata`**

Create `Evenstar/Evenstar/Services/NowPlayingService.swift`:

```swift
import Foundation
import MediaPlayer
import UIKit

struct TrackMetadata: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: UIImage?
    let durationSeconds: TimeInterval
}

protocol NowPlayingPublisher: AnyObject {
    func update(title: String,
                artist: String,
                album: String,
                artwork: UIImage?,
                duration: TimeInterval,
                elapsed: TimeInterval,
                isPlaying: Bool)
    func clear()
}

final class NowPlayingService: NowPlayingPublisher {
    func update(title: String,
                artist: String,
                album: String,
                artwork: UIImage?,
                duration: TimeInterval,
                elapsed: TimeInterval,
                isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in
                artwork
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
```

- [ ] **Step 4.5: Update `PlaybackService` to push Now Playing**

Replace `Evenstar/Evenstar/Services/PlaybackService.swift` with:

```swift
import Foundation
import Observation
import AVFoundation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?

    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false

    init(player: AudioPlayerProtocol, nowPlaying: NowPlayingPublisher) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.player.didFinishCallback = { [weak self] in
            self?.handleFinish()
        }
    }

    func load(url: URL, metadata: TrackMetadata) throws {
        try player.load(url: url)
        currentMetadata = metadata
        currentTrackTitle = metadata.title
        isPlaying = false
        hasLoaded = true
        pushNowPlaying()
    }

    func togglePlayPause() {
        guard hasLoaded else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            activateSessionIfNeeded()
            player.play()
            isPlaying = true
        }
        pushNowPlaying()
    }

    private func handleFinish() {
        isPlaying = false
        pushNowPlaying()
    }

    private func pushNowPlaying() {
        guard let metadata = currentMetadata else { return }
        nowPlaying.update(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            artwork: metadata.artwork,
            duration: metadata.durationSeconds,
            elapsed: player.currentTime,
            isPlaying: isPlaying
        )
    }

    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            sessionActivated = true
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
}
```

- [ ] **Step 4.6: Wire `NowPlayingService` and metadata into `EvenstarApp`**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift` with:

```swift
import SwiftUI
import UIKit

@main
struct EvenstarApp: App {
    @State private var playback: PlaybackService

    init() {
        let player = AVAudioPlayerWrapper()
        let nowPlaying = NowPlayingService()
        _playback = State(initialValue: PlaybackService(player: player, nowPlaying: nowPlaying))
    }

    var body: some Scene {
        WindowGroup {
            SimplePlayerView(playback: playback)
                .task { loadSampleTrack() }
        }
    }

    private func loadSampleTrack() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            assertionFailure("sample.mp3 missing from bundle")
            return
        }
        let artwork = UIImage(named: "SampleArtwork")
        let metadata = TrackMetadata(
            title: "Sample",
            artist: "Unknown Artist",
            album: "Unknown Album",
            artwork: artwork,
            durationSeconds: 0  // updated after load
        )
        do {
            try playback.load(url: url, metadata: metadata)
        } catch {
            print("Failed to load sample track: \(error)")
        }
    }
}
```

- [ ] **Step 4.7: Run the tests — they must pass**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -15
```

**Expected:** 4 tests pass.

- [ ] **Step 4.8: Manual verification — lock-screen card**

On a real device (simulator may show metadata but is unreliable):

1. Launch app. Tap play.
2. Lock the device.
3. Wake the screen. **Expected:** lock screen shows "Sample" / "Unknown Artist" / "Unknown Album", the artwork tile, and the artwork color tint behind the controls.
4. The transport buttons on the lock screen will be greyed out (we wire them in Task 5).

- [ ] **Step 4.9: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git -c commit.gpgsign=false commit -m "feat: lock-screen Now Playing metadata via NowPlayingService (Phase 1 task 4)"
```

---

## Task 5: Lock-screen / headphone / CarPlay remote commands

**Goal:** Wire `MPRemoteCommandCenter` so the lock-screen play/pause, headphone clicks, AirPods squeeze, and CarPlay Now-Playing card all drive `PlaybackService`.

For Phase 1 we only have one track loaded, so `nextTrack` / `previousTrack` are disabled — wiring them is Phase 2 territory.

**Files:**
- Modify: `Evenstar/Evenstar/Services/NowPlayingService.swift` — add a small command-registration helper, *or* keep a separate `RemoteCommandsBridge` (preferred — keeps SRP).
- Create: `Evenstar/Evenstar/Services/RemoteCommandsBridge.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — install the bridge once on launch.

**Interfaces:**
- Consumes: `PlaybackService` from Task 4.
- Produces: `final class RemoteCommandsBridge` with `init(playback: PlaybackService)` and `func install()`.

### Steps

- [ ] **Step 5.1: Add a `play()` and `pause()` API on `PlaybackService`**

The current API has `togglePlayPause`. The remote-command center distinguishes "play" from "pause" (Siri sends one or the other directly). Add the two explicit methods that share the same internal logic.

Open `Evenstar/Evenstar/Services/PlaybackService.swift` and replace the `togglePlayPause()` method with:

```swift
    func play() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        pushNowPlaying()
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        pushNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }
```

The previous tests still pass because `togglePlayPause` keeps the same observable behavior.

- [ ] **Step 5.2: Run the existing tests — they must still pass**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -10
```

**Expected:** 4 passing tests.

- [ ] **Step 5.3: Implement `RemoteCommandsBridge`**

Create `Evenstar/Evenstar/Services/RemoteCommandsBridge.swift`:

```swift
import Foundation
import MediaPlayer

final class RemoteCommandsBridge {
    private let playback: PlaybackService

    init(playback: PlaybackService) {
        self.playback = playback
    }

    func install() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.playback.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.playback.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playback.togglePlayPause()
            return .success
        }

        // Phase 1 has a single track — disable advance commands.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }
}
```

- [ ] **Step 5.4: Install the bridge from `EvenstarApp`**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift` with:

```swift
import SwiftUI
import UIKit

@main
struct EvenstarApp: App {
    @State private var playback: PlaybackService
    private let remoteCommands: RemoteCommandsBridge

    init() {
        let player = AVAudioPlayerWrapper()
        let nowPlaying = NowPlayingService()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying)
        _playback = State(initialValue: service)
        remoteCommands = RemoteCommandsBridge(playback: service)
        remoteCommands.install()
    }

    var body: some Scene {
        WindowGroup {
            SimplePlayerView(playback: playback)
                .task { loadSampleTrack() }
        }
    }

    private func loadSampleTrack() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            assertionFailure("sample.mp3 missing from bundle")
            return
        }
        let artwork = UIImage(named: "SampleArtwork")
        let metadata = TrackMetadata(
            title: "Sample",
            artist: "Unknown Artist",
            album: "Unknown Album",
            artwork: artwork,
            durationSeconds: 0
        )
        do {
            try playback.load(url: url, metadata: metadata)
        } catch {
            print("Failed to load sample track: \(error)")
        }
    }
}
```

- [ ] **Step 5.5: Manual verification — lock-screen controls + headphones**

On a real device:

1. Launch app. Tap play. Lock the device.
2. On the lock screen, press the play/pause icon. **Expected:** audio toggles. The icon and "now playing" view update.
3. Connect AirPods or wired EarPods → press the headset's play/pause once. **Expected:** audio toggles.
4. Press the Siri/Action button (if available) → say "Hey Siri, pause" / "Hey Siri, play". **Expected:** audio responds.

The next/previous buttons should appear *disabled* on the lock screen — that is correct for Phase 1.

- [ ] **Step 5.6: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git -c commit.gpgsign=false commit -m "feat: remote command center routes lock-screen controls (Phase 1 task 5)"
```

---

## Task 6: Position display, in-app scrubber, lock-screen seek

**Goal:** Show elapsed and remaining time in the player UI. Drive a SwiftUI slider that scrubs the audio. Push live position updates to the lock screen and accept seeks from `MPChangePlaybackPositionCommandEvent`.

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` — expose `position`, `duration`; start a 0.5 s timer; expose `seek(to:)`.
- Modify: `Evenstar/Evenstar/Services/RemoteCommandsBridge.swift` — register `changePlaybackPositionCommand`.
- Modify: `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift` — show a slider and time labels.
- Modify: `Evenstar/EvenstarTests/PlaybackServiceTests.swift` — assert seek logic.

**Interfaces:**
- Consumes: `PlaybackService`, `MockAudioPlayer`, `MockNowPlayingPublisher`.
- Produces:
  - `PlaybackService.position: TimeInterval` (published via `@Observable`)
  - `PlaybackService.duration: TimeInterval` (computed from underlying player)
  - `PlaybackService.seek(to: TimeInterval)` — clamps to `[0, duration]`
  - Internal: a 0.5 s `Timer` is started inside `play()` and stopped inside `pause()` / `handleFinish()`. Not part of the public API — do not call from views.

### Steps

- [ ] **Step 6.1: Write the failing seek + position tests**

Open `Evenstar/EvenstarTests/PlaybackServiceTests.swift` and append two new tests inside the class:

```swift
    func testSeekUpdatesPlayerCurrentTime() throws {
        let (service, player, _) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.seek(to: 42)

        XCTAssertEqual(player.currentTime, 42)
        XCTAssertEqual(service.position, 42)
    }

    func testSeekClampsAtZero() throws {
        let (service, _, _) = makeService()
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.seek(to: -10)

        XCTAssertEqual(service.position, 0)
    }

    func testSeekClampsAtDuration() throws {
        let (service, player, _) = makeService()
        player.duration = 120
        try service.load(url: URL(fileURLWithPath: "/tmp/test.mp3"), metadata: .sample)

        service.seek(to: 999)

        XCTAssertEqual(service.position, 120)
    }
```

Also update the existing `testLoadStoresMetadataAndCallsPlayerLoad` and others if needed to read `service.position` (it should start at 0 — keep tests as they are if green).

- [ ] **Step 6.2: Run tests — they must fail**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -20
```

**Expected:** errors — `Value of type 'PlaybackService' has no member 'seek'` and `'position'`.

- [ ] **Step 6.3: Implement position + seek in `PlaybackService`**

Replace `Evenstar/Evenstar/Services/PlaybackService.swift` with:

```swift
import Foundation
import Observation
import AVFoundation

@Observable
final class PlaybackService {
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?
    private(set) var position: TimeInterval = 0
    var duration: TimeInterval { player.duration }

    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false
    private var positionTimer: Timer?

    init(player: AudioPlayerProtocol, nowPlaying: NowPlayingPublisher) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.player.didFinishCallback = { [weak self] in
            self?.handleFinish()
        }
    }

    func load(url: URL, metadata: TrackMetadata) throws {
        try player.load(url: url)
        currentMetadata = metadata
        currentTrackTitle = metadata.title
        isPlaying = false
        position = 0
        hasLoaded = true
        pushNowPlaying()
    }

    func play() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopPositionUpdates()
        pushNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to target: TimeInterval) {
        guard hasLoaded else { return }
        let clamped = max(0, min(target, player.duration))
        player.currentTime = clamped
        position = clamped
        pushNowPlaying()
    }

    // MARK: - Position polling

    private func startPositionUpdates() {
        stopPositionUpdates()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.position = self.player.currentTime
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func handleFinish() {
        isPlaying = false
        position = player.duration
        stopPositionUpdates()
        pushNowPlaying()
    }

    private func pushNowPlaying() {
        guard let metadata = currentMetadata else { return }
        nowPlaying.update(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            artwork: metadata.artwork,
            duration: player.duration,
            elapsed: position,
            isPlaying: isPlaying
        )
    }

    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            sessionActivated = true
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
}
```

- [ ] **Step 6.4: Run tests — they must pass**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -15
```

**Expected:** 7 passing tests (4 original + 3 new).

- [ ] **Step 6.5: Wire `changePlaybackPositionCommand` in `RemoteCommandsBridge`**

Open `Evenstar/Evenstar/Services/RemoteCommandsBridge.swift` and replace with:

```swift
import Foundation
import MediaPlayer

final class RemoteCommandsBridge {
    private let playback: PlaybackService

    init(playback: PlaybackService) {
        self.playback = playback
    }

    func install() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.addTarget { [weak self] _ in
            self?.playback.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.playback.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playback.togglePlayPause()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.playback.seek(to: positionEvent.positionTime)
            return .success
        }

        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = true
    }
}
```

- [ ] **Step 6.6: Update `SimplePlayerView` with a slider and time labels**

Replace `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift` with:

```swift
import SwiftUI

struct SimplePlayerView: View {
    let playback: PlaybackService

    @State private var draggingPosition: TimeInterval?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 96))
                .foregroundStyle(.tint)
                .padding(48)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

            VStack(spacing: 4) {
                Text(playback.currentMetadata?.title ?? "—")
                    .font(.title2.bold())
                Text(playback.currentMetadata?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            scrubber

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
        .padding(.horizontal)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 6.7: Manual verification — scrubber + lock-screen seek**

Run on the device:

1. Play the sample. **Expected:** the slider advances; elapsed time grows.
2. Drag the slider mid-track to a new position. Release. **Expected:** audio jumps to the new position; time labels update.
3. Lock the device. **Expected:** lock-screen scrubber matches the in-app position.
4. Drag the lock-screen scrubber. **Expected:** audio jumps. (On some iOS versions the lock-screen scrubber appears only after a few seconds of metadata; if it doesn't appear, double-check `MPMediaItemPropertyPlaybackDuration` in `NowPlayingService`.)

- [ ] **Step 6.8: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git -c commit.gpgsign=false commit -m "feat: scrubber + lock-screen seek (Phase 1 task 6)"
```

---

## Task 7: Phase-1 wrap-up

**Goal:** Final manual QA against the spec's Phase 1 success criteria; tag the commit.

### Steps

- [ ] **Step 7.1: Run the full test suite**

```bash
cd /Users/phanquyetthang/evenstar/Evenstar
xcodebuild -scheme Evenstar -destination "platform=iOS Simulator,name=iPhone 15 Pro" test 2>&1 | tail -10
```

**Expected:** 7 passing tests, 0 failures.

- [ ] **Step 7.2: Run the Phase 1 manual QA matrix**

On a real iPhone, confirm every row:

- [ ] App launches and shows the player UI with sample artwork.
- [ ] Tapping play starts audio from the bundled `sample.mp3`.
- [ ] Tapping pause stops audio.
- [ ] Locking the device keeps audio playing.
- [ ] Lock screen shows title / artist / album / artwork / scrubber.
- [ ] Lock-screen play/pause button toggles audio.
- [ ] Lock-screen scrubber seeks audio.
- [ ] AirPods / wired headset play/pause clicks toggle audio.
- [ ] Switching to another app keeps audio playing in the background.
- [ ] Phone call interrupts audio (system pause) — when the call ends, audio remains paused (resume-on-interruption-end is Phase 2; OK to be paused after a call).
- [ ] When the track ends, the play button returns to the play state and the elapsed time freezes at duration.

Any row that fails is a Phase 1 regression — fix before tagging.

- [ ] **Step 7.3: Tag the Phase 1 milestone**

```bash
cd /Users/phanquyetthang/evenstar
git tag -a phase1-complete -m "Phase 1 (Mini Player) complete: bundled audio, lock screen, scrubber"
```

(No push yet — push only if you have set up a remote.)

---

## Out of scope for this plan (explicitly Phase 2 or later)

- Document Picker / sandbox file import
- SwiftData models (`Track`, `Playlist`, `PlaybackState`)
- Library UI (Songs / Albums / Artists / Playlists)
- Multi-track queues, next/previous, shuffle, repeat
- Search
- Interruption auto-resume policy refinements
- CarPlay custom UI (entitlement-gated)
- Apple Music / MusicKit
- iCloud sync, iPad layout, EQ, gapless

Each of those gets its own task block in the Phase 2 implementation plan, which is written **after** Phase 1 ships and the developer has Swift / SwiftUI / AVFoundation fluency.

---

## Appendix: Common pitfalls

- **No sound on simulator after Task 3:** macOS sometimes routes audio away from the simulator. Open the simulator's **I/O → Audio Output** menu and pick your speakers.
- **"App Transport Security" or other errors:** Phase 1 plays bundled local files — no network — so these errors usually indicate the wrong file path. `Bundle.main.url(forResource: "sample", withExtension: "mp3")` returning `nil` means `sample.mp3` wasn't added to the target.
- **Lock-screen metadata missing:** `MPNowPlayingInfoCenter.default().nowPlayingInfo` must be set *after* the audio session is active. The plan handles this implicitly — `play()` activates the session before `pushNowPlaying()` runs.
- **Lock-screen scrubber not draggable:** `MPMediaItemPropertyPlaybackDuration` must be a finite, positive `Double`. If you don't set it (or set it before the file has been loaded), the scrubber is read-only.
- **Background audio stops after ~30 s on the simulator:** Expected. The simulator's energy management is not faithful — always verify background audio on a real device.
- **`@Observable` view not updating:** make sure the property you observe is *not* declared with `@ObservationIgnored`, and that you read it inside a SwiftUI `View`'s `body` (not in an `onAppear` closure-captured snapshot).
- **`MPRemoteCommandCenter` commands not firing on lock screen:** they only work if `MPNowPlayingInfoCenter.default().nowPlayingInfo` is set *and* the audio session is `.playback` *and* a foreground audio play has happened at least once.

---

## Self-review checklist (already executed by plan author)

- ✅ Spec section 1 (scope, success criteria) → Task 7 manual QA verifies Phase 1 success criteria.
- ✅ Spec section 2 (tech stack) → Global Constraints + Tech Stack header.
- ✅ Spec section 3 architecture layers → Service layer (PlaybackService, NowPlayingService) + UI layer (SimplePlayerView). Data layer skipped — Phase 2.
- ✅ Spec section 5 playback (audio session, lifecycle, lock screen, remote commands, CarPlay Now-Playing card) → Tasks 3–6.
- ✅ Spec section 7 error-handling rule "no `try!`, no silent catch" → noted in Global Constraints; `AVAudioPlayerWrapper.load` throws.
- ✅ Spec section 8 testing approach (services unit-tested via `AudioPlayerProtocol` mock; SwiftUI views skipped) → mirrored in Tasks 2, 4, 6.
- ✅ Spec section 9 Phase 1 milestones M1.1–M1.5 → mapped to Tasks 1 (M1.1), 2 (M1.2), 3 (M1.3), 4+5 (M1.4), 6 (M1.5).
- ✅ Method signatures: `PlaybackService.play/pause/togglePlayPause/seek(to:)`, `NowPlayingPublisher.update(...)/clear()`, `AudioPlayerProtocol.load(url:)` — used consistently across tasks.
- ✅ Placeholder scan: no TBD / TODO / "add appropriate error handling" / "similar to Task N" patterns.
