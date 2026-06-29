# Evenstar — Phase 2a (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a usable local-only music app where the user imports their own audio files, browses an alphabetical Songs list with artwork thumbnails, taps to play with auto-advance, and survives a kill-relaunch with queue+position restored.

**Architecture:** SwiftUI + `@Observable` services + SwiftData. Four services (`LibraryService`, `ImportService`, `PlaybackService` extended, `NowPlayingService` reused from Phase 1) injected via `.environment(_:)`. SwiftData `ModelContainer` owns `Track` + `PlaybackState`. Document Picker via native `.fileImporter`. `MiniPlayerBar` sits in `.safeAreaInset(.bottom)` of the root `LibraryView`.

**Tech Stack:** Swift 5.9+, SwiftUI, `@Observable`, SwiftData, `AVFoundation` (`AVAudioPlayer`, `AVAsset`, `AVAudioSession`), `MediaPlayer` (Phase 1), `XCTest`. **No third-party dependencies.**

**Reference spec:** `docs/superpowers/specs/2026-06-29-phase2a-foundation-design.md`.

## Global Constraints

- **Min iOS deployment target:** 17.6 (chosen during Phase 1)
- **UI framework:** SwiftUI only
- **State management:** `@Observable` macro (`Observation` framework)
- **Persistence:** SwiftData (`@Model`, `ModelContainer`, `ModelContext`)
- **Audio engine:** `AVAudioPlayer` (do not introduce `AVAudioEngine` / `AVPlayer`)
- **Audio session category:** `.playback`, mode `.default` (set in Phase 1; do not change)
- **Background modes:** `audio` in `Info.plist` (already set in Phase 1)
- **Bundle identifier:** `com.evenstar.app` (already set in Phase 1)
- **App / project name:** `Evenstar`
- **No third-party libraries**
- **No `try!`** in production code; **no silent `catch { }`**
- **Service responsibility boundaries:**
  - `PlaybackService` does **not** import SwiftData. Works only with `[Track]` model objects passed in.
  - `LibraryService` does **not** import `AVFoundation`. Works only with `Track` records + `FileManager`.
- **Commit frequency:** every passing task end (~11 commits across this plan).
- **Phase 1 capability:** background audio + lock screen + remote commands — **preserve** at every step (regression in lock-screen behavior is a Phase 2a failure).

---

## File structure created by this plan

By the end of Phase 2a, the repo will contain (delta from `phase1-complete` tag):

```
Evenstar/
├── Evenstar/
│   ├── App/
│   │   └── EvenstarApp.swift              # MODIFIED — ModelContainer + new services
│   ├── Models/                            # NEW
│   │   ├── Track.swift                    # @Model
│   │   └── PlaybackState.swift            # @Model (single-row)
│   ├── Services/
│   │   ├── AudioPlayerProtocol.swift      # unchanged
│   │   ├── NowPlayingService.swift        # unchanged
│   │   ├── RemoteCommandsBridge.swift     # MODIFIED — enables nextTrackCommand
│   │   ├── PlaybackService.swift          # MODIFIED — queue, persistence, restore
│   │   ├── LibraryService.swift           # NEW
│   │   └── ImportService.swift            # NEW
│   ├── Features/
│   │   ├── Library/                       # NEW
│   │   │   ├── LibraryView.swift
│   │   │   ├── SongRow.swift
│   │   │   ├── ArtworkThumbnail.swift
│   │   │   └── EmptyLibraryView.swift
│   │   ├── Player/
│   │   │   ├── MiniPlayerBar.swift        # NEW
│   │   │   └── NowPlayingView.swift       # NEW (replaces SimplePlayerView)
│   │   └── Import/                        # NEW
│   │       └── ImportProgressSheet.swift
│   ├── Utilities/                         # NEW
│   │   ├── AudioMetadataReader.swift
│   │   ├── FormatSupport.swift
│   │   └── FileLocation.swift
│   ├── Resources/                         # REMOVED (sample.mp3 deleted)
│   └── Assets.xcassets/                   # (SampleArtwork.imageset removed)
└── EvenstarTests/                         # NEW Xcode target (Task 1)
    ├── MockAudioPlayer.swift              # moved from Phase 1
    ├── PlaybackServiceTests.swift         # moved + extended
    ├── InMemoryLibrary.swift              # NEW helper
    ├── LibraryServiceTests.swift          # NEW
    ├── ImportServiceTests.swift           # NEW
    └── PlaybackServiceQueueTests.swift    # NEW
```

---

## How to read this plan

- Each task is one self-contained deliverable. Finish the entire task (including the commit) before starting the next.
- Read the **Interfaces** block first — it tells you what types and method signatures must exist so neighboring tasks compile.
- Service tasks follow TDD: write failing test → run to confirm fail → implement → run to confirm pass → commit.
- UI tasks skip TDD (per spec §9) — write the view, build, verify visually, commit.
- All code blocks are exact. Copy them verbatim.
- "Manual QA on simulator" is the default; "on a real iPhone" is called out explicitly where required.

---

## Task 1: Add Unit Testing Bundle target + SwiftData models

**Goal:** Set up `EvenstarTests` target so all Phase 1 test files compile and run. Add `Track` and `PlaybackState` `@Model` declarations. Wire a `ModelContainer` into `EvenstarApp`.

**Files:**
- Create (via Xcode UI): `Evenstar/EvenstarTests/` target with `Info.plist`, default test file.
- Move (via Xcode): `Evenstar/EvenstarTests/MockAudioPlayer.swift`, `PlaybackServiceTests.swift` into the new target.
- Create: `Evenstar/Evenstar/Models/Track.swift`
- Create: `Evenstar/Evenstar/Models/PlaybackState.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — initialise `ModelContainer`, inject context via `.modelContainer(_:)`.
- Delete: `Evenstar/Evenstar/Resources/sample.mp3`
- Delete: `Evenstar/Evenstar/Assets.xcassets/SampleArtwork.imageset/` (no longer needed; player UI rebuilt in Task 8)
- Delete: `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift` (will be replaced by `NowPlayingView` in Task 8) — **defer deletion to Task 8**, but stop loading sample track from `EvenstarApp` now.

**Interfaces (produced):**
- `Track` `@Model` with all fields from spec §4.
- `PlaybackState` `@Model` with all fields from spec §4.
- `EvenstarApp` instantiates a `ModelContainer(for: Track.self, PlaybackState.self)`.

### Steps

- [ ] **Step 1.1: Add Unit Testing Bundle target in Xcode**

In Xcode → **File → New → Target…** → **iOS** → **Unit Testing Bundle** → Next.
- Product Name: `EvenstarTests`
- Target to be tested: `Evenstar`
- Finish.

Xcode creates an `EvenstarTests/` folder + default `EvenstarTests.swift`. Delete that default file (right-click → Move to Trash).

- [ ] **Step 1.2: Add Phase 1 test files to the new target**

In Finder, the files `MockAudioPlayer.swift` and `PlaybackServiceTests.swift` already live under `Evenstar/EvenstarTests/` on disk (carried over from Phase 1). Xcode just doesn't know about them yet.

In Xcode's Project Navigator, right-click the new `EvenstarTests` group → **Add Files to "Evenstar"…** → navigate to `Evenstar/EvenstarTests/` → select both files → make sure **Add to targets: EvenstarTests** is checked → Add.

- [ ] **Step 1.3: Run the Phase 1 tests**

Press **⌘U** in Xcode. Expected: **4 tests pass** (the Phase 1 `testLoad...`, `testTogglePlayPause...` × 3) plus the 3 seek tests from Phase 1 Task 6 = **7 passing tests**, 0 failures.

If they fail to compile: the most common cause is `@testable import Evenstar` not finding the module — ensure the target's **Test Host** in Build Settings is set to `$(BUILT_PRODUCTS_DIR)/Evenstar.app/Evenstar`.

- [ ] **Step 1.4: Stop loading the bundled sample track**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift` with a minimal placeholder body (the player UI gets rebuilt in Tasks 5 + 8). We'll wire the `ModelContainer` next.

```swift
//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI

@main
struct EvenstarApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Phase 2a — under construction")
        }
    }
}
```

Build (**⌘B**). Expected: **success**. Run (**⌘R**): a screen with "Phase 2a — under construction" shows.

- [ ] **Step 1.5: Delete bundled assets no longer needed**

In Xcode Project Navigator:
- Right-click `Resources/sample.mp3` → Delete → Move to Trash.
- Right-click `Assets.xcassets` → open editor → right-click `SampleArtwork` → Remove.

Build. Expected: **success** (nothing references them now).

- [ ] **Step 1.6: Write `Track` model**

Create `Evenstar/Evenstar/Models/Track.swift`:

```swift
import Foundation
import SwiftData

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artistName: String
    var albumTitle: String
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double
    var relativePath: String
    var artworkRelativePath: String?
    var format: String
    var sampleRate: Int?
    var bitDepth: Int?
    var dateAdded: Date
    var playCount: Int
    var lastPlayedAt: Date?

    init(id: UUID = UUID(),
         title: String,
         artistName: String,
         albumTitle: String,
         trackNumber: Int? = nil,
         discNumber: Int? = nil,
         durationSeconds: Double,
         relativePath: String,
         artworkRelativePath: String? = nil,
         format: String,
         sampleRate: Int? = nil,
         bitDepth: Int? = nil,
         dateAdded: Date = .now,
         playCount: Int = 0,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.durationSeconds = durationSeconds
        self.relativePath = relativePath
        self.artworkRelativePath = artworkRelativePath
        self.format = format
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }
}
```

- [ ] **Step 1.7: Write `PlaybackState` model**

Create `Evenstar/Evenstar/Models/PlaybackState.swift`:

```swift
import Foundation
import SwiftData

@Model
final class PlaybackState {
    var currentTrackID: UUID?
    var positionSeconds: Double
    var queueTrackIDs: [UUID]
    var queueIndex: Int

    init(currentTrackID: UUID? = nil,
         positionSeconds: Double = 0,
         queueTrackIDs: [UUID] = [],
         queueIndex: Int = 0) {
        self.currentTrackID = currentTrackID
        self.positionSeconds = positionSeconds
        self.queueTrackIDs = queueTrackIDs
        self.queueIndex = queueIndex
    }
}
```

- [ ] **Step 1.8: Wire `ModelContainer` into `EvenstarApp`**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift`:

```swift
//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Track.self, PlaybackState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("Phase 2a — under construction")
        }
        .modelContainer(modelContainer)
    }
}
```

Build & Run. Expected: app launches, shows placeholder text, **no crash** (SwiftData container creates `default.store` on disk).

- [ ] **Step 1.9: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar
git commit -m "feat: add test target + Track/PlaybackState models + ModelContainer (Phase 2a task 1)"
```

Expected commit: 1 deleted file (`sample.mp3`), 2 new model files, modified `EvenstarApp.swift`, modified `project.pbxproj` (test target + image set removal).

---

## Task 2: `LibraryService` CRUD + tests

**Goal:** A `@MainActor @Observable` service that owns the `ModelContext` and exposes the operations needed by all UI layers and other services: insert / delete (with file cleanup) / fetch / find / dedupe / `PlaybackState` singleton.

**Files:**
- Create: `Evenstar/Evenstar/Utilities/FileLocation.swift`
- Create: `Evenstar/Evenstar/Services/LibraryService.swift`
- Create: `Evenstar/EvenstarTests/InMemoryLibrary.swift`
- Create: `Evenstar/EvenstarTests/LibraryServiceTests.swift`

**Interfaces:**
- Consumes: `Track`, `PlaybackState` (Task 1).
- Produces:
  - `enum FileLocation` with `documentsURL()`, `musicFolderURL()`, `artworkFolderURL()`, `absoluteURL(forRelative:)`.
  - `@MainActor @Observable final class LibraryService` with:
    - `init(context: ModelContext, fileManager: FileManager = .default)`
    - `func insert(_ track: Track) throws`
    - `func delete(_ track: Track) throws`
    - `func fetchAllTracks(sortedByTitle: Bool = true) throws -> [Track]`
    - `func findTrack(byID id: UUID) throws -> Track?`
    - `func findExistingTrack(title: String, artist: String, duration: Double) throws -> Track?`
    - `var playbackState: PlaybackState { get }` (auto-creates singleton)
    - `func savePlaybackState() throws`
  - `enum LibraryError: LocalizedError` with `.persistenceFailed(underlying:)`, `.fileDeleteFailed(URL, underlying:)`.

### Steps

- [ ] **Step 2.1: Write `FileLocation` helper**

Create `Evenstar/Evenstar/Utilities/FileLocation.swift`:

```swift
import Foundation

enum FileLocation {
    static func documentsURL(_ fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static func musicFolderURL(_ fileManager: FileManager = .default) -> URL {
        documentsURL(fileManager).appendingPathComponent("Music", isDirectory: true)
    }

    static func artworkFolderURL(_ fileManager: FileManager = .default) -> URL {
        documentsURL(fileManager).appendingPathComponent("Artwork", isDirectory: true)
    }

    static func absoluteURL(forRelative path: String,
                            fileManager: FileManager = .default) -> URL {
        documentsURL(fileManager).appendingPathComponent(path)
    }

    static func relativePath(for absolute: URL,
                             fileManager: FileManager = .default) -> String {
        let docs = documentsURL(fileManager).standardizedFileURL.path
        let abs = absolute.standardizedFileURL.path
        if abs.hasPrefix(docs + "/") {
            return String(abs.dropFirst(docs.count + 1))
        }
        return absolute.lastPathComponent
    }
}
```

- [ ] **Step 2.2: Write the in-memory test helper**

Create `Evenstar/EvenstarTests/InMemoryLibrary.swift`:

```swift
import Foundation
import SwiftData
@testable import Evenstar

@MainActor
enum InMemoryLibrary {
    static func make() throws -> LibraryService {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Track.self, PlaybackState.self,
            configurations: config
        )
        return LibraryService(context: ModelContext(container))
    }

    static func makeTrack(title: String = "Sample",
                          artistName: String = "Unknown Artist",
                          albumTitle: String = "Unknown Album",
                          durationSeconds: Double = 180,
                          relativePath: String = "Music/sample.mp3",
                          format: String = "mp3") -> Track {
        Track(
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            durationSeconds: durationSeconds,
            relativePath: relativePath,
            format: format
        )
    }
}
```

- [ ] **Step 2.3: Write the failing `LibraryService` tests**

Create `Evenstar/EvenstarTests/LibraryServiceTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class LibraryServiceTests: XCTestCase {

    func testInsertPersistsTrack() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Hello")

        try library.insert(track)

        let all = try library.fetchAllTracks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Hello")
    }

    func testFetchAllTracksSortsAlphabetically() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(title: "Charlie"))
        try library.insert(InMemoryLibrary.makeTrack(title: "alpha"))
        try library.insert(InMemoryLibrary.makeTrack(title: "Bravo"))

        let titles = try library.fetchAllTracks().map(\.title)

        XCTAssertEqual(titles, ["alpha", "Bravo", "Charlie"])
    }

    func testFindTrackByID() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)

        let found = try library.findTrack(byID: track.id)

        XCTAssertEqual(found?.id, track.id)
    }

    func testFindExistingTrackMatchesByLowercaseTupleAndRoundedDuration() throws {
        let library = try InMemoryLibrary.make()
        try library.insert(InMemoryLibrary.makeTrack(
            title: "Bohemian Rhapsody",
            artistName: "Queen",
            durationSeconds: 354.27
        ))

        let hit = try library.findExistingTrack(
            title: "bohemian rhapsody",
            artist: "QUEEN",
            duration: 354.0
        )
        let miss = try library.findExistingTrack(
            title: "Another One Bites the Dust",
            artist: "Queen",
            duration: 354.0
        )

        XCTAssertNotNil(hit)
        XCTAssertNil(miss)
    }

    func testPlaybackStateAutoCreatesSingleton() throws {
        let library = try InMemoryLibrary.make()

        let first = library.playbackState
        let second = library.playbackState

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
    }

    func testDeleteRemovesTrackFromDB() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)

        try library.delete(track)

        XCTAssertEqual(try library.fetchAllTracks().count, 0)
    }
}
```

- [ ] **Step 2.4: Run the tests — they must fail to compile**

**⌘U** in Xcode. Expected: errors `Cannot find 'LibraryService' in scope`.

- [ ] **Step 2.5: Implement `LibraryService`**

Create `Evenstar/Evenstar/Services/LibraryService.swift`:

```swift
import Foundation
import SwiftData
import Observation

enum LibraryError: LocalizedError {
    case persistenceFailed(underlying: Error)
    case fileDeleteFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let error):
            return "Couldn't save changes: \(error.localizedDescription)"
        case .fileDeleteFailed(let url, let error):
            return "Couldn't delete file \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

@Observable
@MainActor
final class LibraryService {
    let context: ModelContext
    private let fileManager: FileManager

    init(context: ModelContext, fileManager: FileManager = .default) {
        self.context = context
        self.fileManager = fileManager
    }

    // MARK: - Track CRUD

    func insert(_ track: Track) throws {
        context.insert(track)
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }

    func delete(_ track: Track) throws {
        let audioURL = FileLocation.absoluteURL(forRelative: track.relativePath, fileManager: fileManager)
        try? fileManager.removeItem(at: audioURL)
        if let artworkPath = track.artworkRelativePath {
            let artworkURL = FileLocation.absoluteURL(forRelative: artworkPath, fileManager: fileManager)
            try? fileManager.removeItem(at: artworkURL)
        }
        context.delete(track)
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }

    func fetchAllTracks(sortedByTitle: Bool = true) throws -> [Track] {
        var descriptor = FetchDescriptor<Track>()
        if sortedByTitle {
            descriptor.sortBy = [SortDescriptor(\Track.title, comparator: .localizedStandard)]
        }
        return try context.fetch(descriptor)
    }

    func findTrack(byID id: UUID) throws -> Track? {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func findExistingTrack(title: String, artist: String, duration: Double) throws -> Track? {
        // SwiftData #Predicate has limited string + math support; do the work in Swift
        // after fetching candidates with the same rounded duration.
        let rounded = duration.rounded()
        let descriptor = FetchDescriptor<Track>()
        let candidates = try context.fetch(descriptor)
        let titleLower = title.lowercased()
        let artistLower = artist.lowercased()
        return candidates.first { t in
            t.title.lowercased() == titleLower
                && t.artistName.lowercased() == artistLower
                && t.durationSeconds.rounded() == rounded
        }
    }

    // MARK: - PlaybackState singleton

    var playbackState: PlaybackState {
        let descriptor = FetchDescriptor<PlaybackState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let newState = PlaybackState()
        context.insert(newState)
        try? context.save()
        return newState
    }

    func savePlaybackState() throws {
        do { try context.save() }
        catch { throw LibraryError.persistenceFailed(underlying: error) }
    }
}
```

- [ ] **Step 2.6: Run the tests — they must pass**

**⌘U**. Expected: **6 new `LibraryService` tests pass**, plus the existing 7 Phase 1 tests still pass. **13 total**.

- [ ] **Step 2.7: Commit**

```bash
git add Evenstar
git commit -m "feat: LibraryService CRUD + PlaybackState singleton (Phase 2a task 2)"
```

---

## Task 3: `AudioMetadataReader` — extract title/artist/album/duration/artwork from `AVAsset`

**Goal:** A pure helper that opens a file URL via `AVAsset`, extracts ID3 / MP4-atom / FLAC tags, and returns a value type plus optional artwork data. No file copying; no DB writes. Used by `ImportService`.

**Files:**
- Create: `Evenstar/Evenstar/Utilities/FormatSupport.swift`
- Create: `Evenstar/Evenstar/Utilities/AudioMetadataReader.swift`
- Create: `Evenstar/EvenstarTests/AudioMetadataReaderTests.swift`
- (No mock for AVAsset — tests use real files generated by `AVAssetWriter` in test setup.)

**Interfaces:**
- Produces:
  - `enum FormatSupport { static let supportedExtensions: Set<String> }`
  - `struct ExtractedMetadata { let title: String?; let artist: String?; let album: String?; let durationSeconds: Double; let sampleRate: Int?; let bitDepth: Int?; let artworkData: Data? }`
  - `protocol MetadataReading: Sendable { func read(url: URL) async throws -> ExtractedMetadata }`
  - `struct AudioMetadataReader: MetadataReading`
  - `enum AudioMetadataError: Error { case unreadable; case noAudioTrack }`

### Steps

- [ ] **Step 3.1: Write `FormatSupport`**

Create `Evenstar/Evenstar/Utilities/FormatSupport.swift`:

```swift
import Foundation

enum FormatSupport {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "alac", "flac"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
```

- [ ] **Step 3.2: Write the failing `AudioMetadataReader` tests**

Create `Evenstar/EvenstarTests/AudioMetadataReaderTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import Evenstar

final class AudioMetadataReaderTests: XCTestCase {

    /// Generates a 1-second mono 22050 Hz silent AIFF on disk, with no metadata tags.
    /// AIFF is chosen because AVFoundation can write it directly without an export session.
    private func makeSilentTestFile() throws -> URL {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).aiff")

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 22050,
            channels: 1,
            interleaved: true
        )!
        let file = try AVAudioFile(
            forWriting: tmpURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let frames: AVAudioFrameCount = 22050
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        memset(buf.int16ChannelData!.pointee, 0, Int(frames) * 2)
        try file.write(from: buf)
        return tmpURL
    }

    func testReadReturnsDurationForUntaggedFile() async throws {
        let url = try makeSilentTestFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = AudioMetadataReader()

        let metadata = try await reader.read(url: url)

        XCTAssertEqual(metadata.durationSeconds, 1.0, accuracy: 0.1)
        XCTAssertNil(metadata.title)
        XCTAssertNil(metadata.artist)
        XCTAssertNil(metadata.album)
        XCTAssertNil(metadata.artworkData)
    }

    func testReadThrowsForUnreadableFile() async throws {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).mp3")
        try Data("this is not an mp3".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }
        let reader = AudioMetadataReader()

        do {
            _ = try await reader.read(url: bogus)
            XCTFail("Expected throw")
        } catch {
            // expected
        }
    }
}
```

- [ ] **Step 3.3: Run tests — must fail to compile**

**⌘U**. Expected: `Cannot find 'AudioMetadataReader' in scope`.

- [ ] **Step 3.4: Implement `AudioMetadataReader`**

Create `Evenstar/Evenstar/Utilities/AudioMetadataReader.swift`:

```swift
import Foundation
import AVFoundation

struct ExtractedMetadata: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let trackNumber: Int?
    let discNumber: Int?
    let durationSeconds: Double
    let sampleRate: Int?
    let bitDepth: Int?
    let artworkData: Data?
}

enum AudioMetadataError: LocalizedError {
    case unreadable
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .unreadable: return "File could not be read as audio."
        case .noAudioTrack: return "File contains no audio track."
        }
    }
}

protocol MetadataReading: Sendable {
    func read(url: URL) async throws -> ExtractedMetadata
}

struct AudioMetadataReader: MetadataReading {

    func read(url: URL) async throws -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)

        // Load duration; this also validates the file is readable as audio.
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw AudioMetadataError.unreadable
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw AudioMetadataError.noAudioTrack
        }

        let metadata = (try? await asset.load(.metadata)) ?? []
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let allMetadata = metadata + commonMetadata

        let title = await stringValue(for: .commonKeyTitle, in: allMetadata)
        let artist = await stringValue(for: .commonKeyArtist, in: allMetadata)
        let album = await stringValue(for: .commonKeyAlbumName, in: allMetadata)
        let artworkData = await artworkValue(in: allMetadata)

        let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let sampleRate: Int?
        let bitDepth: Int?
        if let audioTrack = tracks.first,
           let descs = try? await audioTrack.load(.formatDescriptions),
           let desc = descs.first as CMFormatDescription? {
            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                sampleRate = Int(basic.mSampleRate)
                bitDepth = basic.mBitsPerChannel == 0 ? nil : Int(basic.mBitsPerChannel)
            } else {
                sampleRate = nil
                bitDepth = nil
            }
        } else {
            sampleRate = nil
            bitDepth = nil
        }

        return ExtractedMetadata(
            title: title,
            artist: artist,
            album: album,
            trackNumber: nil,
            discNumber: nil,
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            artworkData: artworkData
        )
    }

    private func stringValue(for key: AVMetadataKey,
                             in items: [AVMetadataItem]) async -> String? {
        let matches = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: identifier(for: key)
        )
        for item in matches {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func artworkValue(in items: [AVMetadataItem]) async -> Data? {
        let matches = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: AVMetadataIdentifier.commonIdentifierArtwork
        )
        for item in matches {
            if let value = try? await item.load(.dataValue) {
                return value
            }
        }
        return nil
    }

    private func identifier(for key: AVMetadataKey) -> AVMetadataIdentifier {
        switch key {
        case .commonKeyTitle: return .commonIdentifierTitle
        case .commonKeyArtist: return .commonIdentifierArtist
        case .commonKeyAlbumName: return .commonIdentifierAlbumName
        default: return .commonIdentifierTitle
        }
    }
}
```

- [ ] **Step 3.5: Run tests — must pass**

**⌘U**. Expected: **2 new `AudioMetadataReader` tests pass**. Phase 1 + Task 2 tests still green. **15 total**.

- [ ] **Step 3.6: Commit**

```bash
git add Evenstar
git commit -m "feat: AudioMetadataReader + FormatSupport (Phase 2a task 3)"
```

---

## Task 4: `ImportService` — Document Picker URLs → tracks in DB

**Goal:** Orchestrate the per-file pipeline: format check → metadata extraction → dedupe → copy audio → write artwork → `LibraryService.insert`. Aggregate errors into an `ImportSummary`.

**Files:**
- Create: `Evenstar/Evenstar/Services/ImportService.swift`
- Create: `Evenstar/EvenstarTests/ImportServiceTests.swift`
- Create: `Evenstar/EvenstarTests/MockMetadataReader.swift`

**Interfaces:**
- Consumes: `LibraryService` (Task 2), `MetadataReading` + `ExtractedMetadata` (Task 3), `FileLocation`, `FormatSupport`.
- Produces:
  - `struct ImportProgress { let completed: Int; let total: Int; let lastError: ImportError? }`
  - `struct ImportSummary { let imported: [Track]; let failures: [(url: URL, error: ImportError)]; let duplicates: [Track] }`
  - `enum ImportError: LocalizedError { case unsupportedFormat(String); case fileNotReadable(URL); case metadataExtractionFailed; case copyFailed(underlying: Error); case diskFull }`
  - `@MainActor @Observable final class ImportService` with:
    - `init(library: LibraryService, metadataReader: MetadataReading, fileManager: FileManager = .default)`
    - `private(set) var isImporting: Bool`
    - `private(set) var progress: ImportProgress`
    - `func importFiles(at urls: [URL]) async -> ImportSummary`

### Steps

- [ ] **Step 4.1: Write `MockMetadataReader`**

Create `Evenstar/EvenstarTests/MockMetadataReader.swift`:

```swift
import Foundation
@testable import Evenstar

final class MockMetadataReader: MetadataReading, @unchecked Sendable {
    enum Outcome {
        case success(ExtractedMetadata)
        case throwing(Error)
    }

    var outcomesByURL: [URL: Outcome] = [:]
    var defaultOutcome: Outcome = .success(
        ExtractedMetadata(
            title: nil, artist: nil, album: nil,
            trackNumber: nil, discNumber: nil,
            durationSeconds: 120,
            sampleRate: 44100, bitDepth: 16,
            artworkData: nil
        )
    )

    private(set) var readURLs: [URL] = []

    func read(url: URL) async throws -> ExtractedMetadata {
        readURLs.append(url)
        let outcome = outcomesByURL[url] ?? defaultOutcome
        switch outcome {
        case .success(let value): return value
        case .throwing(let error): throw error
        }
    }
}
```

- [ ] **Step 4.2: Write failing `ImportService` tests**

Create `Evenstar/EvenstarTests/ImportServiceTests.swift`:

```swift
import XCTest
@testable import Evenstar

@MainActor
final class ImportServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeSourceFile(name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("fake audio bytes".utf8).write(to: url)
        return url
    }

    func testImportSkipsUnsupportedFormats() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "notes.txt")

        let summary = await importer.importFiles(at: [url])

        XCTAssertEqual(summary.imported.count, 0)
        XCTAssertEqual(summary.failures.count, 1)
        if case .unsupportedFormat = summary.failures.first?.error {
            // OK
        } else {
            XCTFail("Expected unsupportedFormat")
        }
        XCTAssertTrue(reader.readURLs.isEmpty, "Reader should not be called for unsupported file")
    }

    func testImportInsertsTrackWithFallbackMetadata() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "Bohemian Rhapsody.mp3")

        let summary = await importer.importFiles(at: [url])

        XCTAssertEqual(summary.imported.count, 1)
        XCTAssertEqual(summary.failures.count, 0)
        let inserted = try XCTUnwrap(summary.imported.first)
        XCTAssertEqual(inserted.title, "Bohemian Rhapsody")    // filename fallback
        XCTAssertEqual(inserted.artistName, "Unknown Artist")
        XCTAssertEqual(inserted.albumTitle, "Unknown Album")
        XCTAssertEqual(inserted.format, "mp3")
        // Verify file was copied into sandbox
        let destURL = FileLocation.absoluteURL(forRelative: inserted.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        // Cleanup
        try? FileManager.default.removeItem(at: destURL)
    }

    func testImportUsesEmbeddedTitleWhenPresent() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "track.mp3")
        reader.outcomesByURL[url] = .success(
            ExtractedMetadata(
                title: "Real Title", artist: "Real Artist", album: "Real Album",
                trackNumber: nil, discNumber: nil,
                durationSeconds: 200,
                sampleRate: 44100, bitDepth: 16,
                artworkData: nil
            )
        )

        let summary = await importer.importFiles(at: [url])

        let inserted = try XCTUnwrap(summary.imported.first)
        XCTAssertEqual(inserted.title, "Real Title")
        XCTAssertEqual(inserted.artistName, "Real Artist")
        XCTAssertEqual(inserted.albumTitle, "Real Album")
        try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: inserted.relativePath))
    }

    func testImportDedupesByLowercaseTupleAndRoundedDuration() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url1 = try makeSourceFile(name: "Bohemian Rhapsody.mp3")
        let url2 = try makeSourceFile(name: "BOHEMIAN RHAPSODY.mp3")
        reader.defaultOutcome = .success(
            ExtractedMetadata(
                title: nil, artist: nil, album: nil,
                trackNumber: nil, discNumber: nil,
                durationSeconds: 354.27,
                sampleRate: nil, bitDepth: nil,
                artworkData: nil
            )
        )

        let summary = await importer.importFiles(at: [url1, url2])

        XCTAssertEqual(summary.imported.count, 1)
        XCTAssertEqual(summary.duplicates.count, 1)
        // Cleanup
        for t in summary.imported {
            try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: t.relativePath))
        }
    }

    func testImportWritesArtworkWhenPresent() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "with-art.mp3")
        let artworkBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]) // JPEG SOI + APP0 prefix
        reader.outcomesByURL[url] = .success(
            ExtractedMetadata(
                title: "T", artist: "A", album: "B",
                trackNumber: nil, discNumber: nil,
                durationSeconds: 100,
                sampleRate: nil, bitDepth: nil,
                artworkData: artworkBytes
            )
        )

        let summary = await importer.importFiles(at: [url])

        let inserted = try XCTUnwrap(summary.imported.first)
        let artworkPath = try XCTUnwrap(inserted.artworkRelativePath)
        let artworkURL = FileLocation.absoluteURL(forRelative: artworkPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artworkURL.path))
        try? FileManager.default.removeItem(at: artworkURL)
        try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: inserted.relativePath))
    }

    func testImportRecordsMetadataExtractionFailure() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let url = try makeSourceFile(name: "broken.mp3")
        reader.outcomesByURL[url] = .throwing(AudioMetadataError.unreadable)

        let summary = await importer.importFiles(at: [url])

        XCTAssertEqual(summary.imported.count, 0)
        XCTAssertEqual(summary.failures.count, 1)
        if case .metadataExtractionFailed = summary.failures.first?.error { } else {
            XCTFail("Expected metadataExtractionFailed")
        }
    }

    func testProgressUpdatesAsFilesAreProcessed() async throws {
        let library = try InMemoryLibrary.make()
        let reader = MockMetadataReader()
        let importer = ImportService(library: library, metadataReader: reader)
        let urls = try (0..<3).map { try makeSourceFile(name: "t\($0).mp3") }
        // Different durations so dedupe doesn't collapse them
        for (i, url) in urls.enumerated() {
            reader.outcomesByURL[url] = .success(
                ExtractedMetadata(
                    title: "t\(i)", artist: "a", album: "b",
                    trackNumber: nil, discNumber: nil,
                    durationSeconds: Double(60 + i * 10),
                    sampleRate: nil, bitDepth: nil,
                    artworkData: nil
                )
            )
        }

        let summary = await importer.importFiles(at: urls)

        XCTAssertEqual(summary.imported.count, 3)
        XCTAssertEqual(importer.progress.completed, 3)
        XCTAssertEqual(importer.progress.total, 3)
        XCTAssertFalse(importer.isImporting)
        // Cleanup
        for t in summary.imported {
            try? FileManager.default.removeItem(at: FileLocation.absoluteURL(forRelative: t.relativePath))
        }
    }
}
```

- [ ] **Step 4.3: Run tests — must fail to compile**

**⌘U**. Expected: `Cannot find 'ImportService' in scope`.

- [ ] **Step 4.4: Implement `ImportService`**

Create `Evenstar/Evenstar/Services/ImportService.swift`:

```swift
import Foundation
import Observation

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotReadable(URL)
    case metadataExtractionFailed
    case copyFailed(underlying: Error)
    case diskFull

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext)"
        case .fileNotReadable(let url): return "Cannot read file: \(url.lastPathComponent)"
        case .metadataExtractionFailed: return "Could not extract audio metadata."
        case .copyFailed(let error): return "Copy failed: \(error.localizedDescription)"
        case .diskFull: return "Storage is full."
        }
    }
}

struct ImportProgress: Equatable {
    let completed: Int
    let total: Int
    let lastError: ImportError?

    init(completed: Int = 0, total: Int = 0, lastError: ImportError? = nil) {
        self.completed = completed
        self.total = total
        self.lastError = lastError
    }

    static func == (lhs: ImportProgress, rhs: ImportProgress) -> Bool {
        lhs.completed == rhs.completed && lhs.total == rhs.total
    }
}

struct ImportSummary {
    let imported: [Track]
    let failures: [(url: URL, error: ImportError)]
    let duplicates: [Track]
}

@Observable
@MainActor
final class ImportService {
    private(set) var isImporting: Bool = false
    private(set) var progress: ImportProgress = .init()

    private let library: LibraryService
    private let metadataReader: MetadataReading
    private let fileManager: FileManager

    init(library: LibraryService,
         metadataReader: MetadataReading,
         fileManager: FileManager = .default) {
        self.library = library
        self.metadataReader = metadataReader
        self.fileManager = fileManager
    }

    func importFiles(at urls: [URL]) async -> ImportSummary {
        isImporting = true
        progress = ImportProgress(completed: 0, total: urls.count, lastError: nil)
        defer { isImporting = false }

        try? ensureFolderExists(FileLocation.musicFolderURL(fileManager))
        try? ensureFolderExists(FileLocation.artworkFolderURL(fileManager))

        var imported: [Track] = []
        var failures: [(url: URL, error: ImportError)] = []
        var duplicates: [Track] = []

        for url in urls {
            let outcome = await importOne(url: url)
            switch outcome {
            case .inserted(let track):
                imported.append(track)
            case .duplicate(let track):
                duplicates.append(track)
            case .failed(let error):
                failures.append((url, error))
                progress = ImportProgress(
                    completed: progress.completed,
                    total: progress.total,
                    lastError: error
                )
                if case .diskFull = error {
                    // Stop the whole batch.
                    progress = ImportProgress(
                        completed: progress.completed,
                        total: progress.total,
                        lastError: error
                    )
                    return ImportSummary(imported: imported, failures: failures, duplicates: duplicates)
                }
            }
            progress = ImportProgress(
                completed: progress.completed + 1,
                total: progress.total,
                lastError: progress.lastError
            )
        }

        return ImportSummary(imported: imported, failures: failures, duplicates: duplicates)
    }

    private enum ImportOutcome {
        case inserted(Track)
        case duplicate(Track)
        case failed(ImportError)
    }

    private func importOne(url: URL) async -> ImportOutcome {
        let ext = url.pathExtension.lowercased()
        guard FormatSupport.isSupported(url) else {
            return .failed(.unsupportedFormat(ext))
        }

        let extracted: ExtractedMetadata
        do {
            extracted = try await metadataReader.read(url: url)
        } catch {
            return .failed(.metadataExtractionFailed)
        }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = extracted.title?.nonEmpty ?? fallbackTitle
        let artist = extracted.artist?.nonEmpty ?? "Unknown Artist"
        let album = extracted.album?.nonEmpty ?? "Unknown Album"

        if let existing = try? library.findExistingTrack(
            title: title, artist: artist, duration: extracted.durationSeconds
        ) {
            return .duplicate(existing)
        }

        let id = UUID()
        let musicFolder = FileLocation.musicFolderURL(fileManager)
        let destAudio = musicFolder.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            try fileManager.copyItem(at: url, to: destAudio)
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain && error.code == ENOSPC {
                return .failed(.diskFull)
            }
            return .failed(.copyFailed(underlying: error))
        }

        var artworkRelative: String? = nil
        if let artworkData = extracted.artworkData, !artworkData.isEmpty {
            let artworkFolder = FileLocation.artworkFolderURL(fileManager)
            let destArtwork = artworkFolder.appendingPathComponent("\(id.uuidString).jpg")
            do {
                try artworkData.write(to: destArtwork)
                artworkRelative = "Artwork/\(id.uuidString).jpg"
            } catch {
                artworkRelative = nil
            }
        }

        let audioRelative = "Music/\(id.uuidString).\(ext)"
        let track = Track(
            id: id,
            title: title,
            artistName: artist,
            albumTitle: album,
            trackNumber: extracted.trackNumber,
            discNumber: extracted.discNumber,
            durationSeconds: extracted.durationSeconds,
            relativePath: audioRelative,
            artworkRelativePath: artworkRelative,
            format: ext,
            sampleRate: extracted.sampleRate,
            bitDepth: extracted.bitDepth
        )

        do {
            try library.insert(track)
            return .inserted(track)
        } catch {
            try? fileManager.removeItem(at: destAudio)
            if let artworkRelative {
                try? fileManager.removeItem(
                    at: FileLocation.absoluteURL(forRelative: artworkRelative, fileManager: fileManager)
                )
            }
            return .failed(.copyFailed(underlying: error))
        }
    }

    private func ensureFolderExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

- [ ] **Step 4.5: Run tests — must pass**

**⌘U**. Expected: 7 new `ImportService` tests pass. **22 total**.

- [ ] **Step 4.6: Commit**

```bash
git add Evenstar
git commit -m "feat: ImportService with dedupe + artwork + error aggregation (Phase 2a task 4)"
```

---

## Task 5: `LibraryView` + `SongRow` + `EmptyLibraryView` + `ArtworkThumbnail`

**Goal:** Render the Songs list. No tap-to-play yet (added in Task 7). No `MiniPlayerBar` yet (Task 8). Just: empty state with import CTA, populated state with rows.

**Files:**
- Create: `Evenstar/Evenstar/Features/Library/ArtworkThumbnail.swift`
- Create: `Evenstar/Evenstar/Features/Library/SongRow.swift`
- Create: `Evenstar/Evenstar/Features/Library/EmptyLibraryView.swift`
- Create: `Evenstar/Evenstar/Features/Library/LibraryView.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — render `LibraryView` instead of placeholder.

**Interfaces:**
- Produces:
  - `struct ArtworkThumbnail: View` — size param + track input.
  - `struct SongRow: View` — track input.
  - `struct EmptyLibraryView: View` — `onImportTap` closure.
  - `struct LibraryView: View` — observes `@Query var tracks: [Track]`.

### Steps

- [ ] **Step 5.1: Write `ArtworkThumbnail`**

Create `Evenstar/Evenstar/Features/Library/ArtworkThumbnail.swift`:

```swift
import SwiftUI

struct ArtworkThumbnail: View {
    let relativePath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
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

    private func loadImage() -> UIImage? {
        guard let path = relativePath else { return nil }
        let url = FileLocation.absoluteURL(forRelative: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
```

Note: this loads from disk on every render. The parent spec mentions a `NSCache`-backed loader as a future improvement. For 1k–5k tracks rendering in a `List` (which only realizes visible rows), the naive load is acceptable for 2a.

- [ ] **Step 5.2: Write `SongRow`**

Create `Evenstar/Evenstar/Features/Library/SongRow.swift`:

```swift
import SwiftUI

struct SongRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(relativePath: track.artworkRelativePath, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 5.3: Write `EmptyLibraryView`**

Create `Evenstar/Evenstar/Features/Library/EmptyLibraryView.swift`:

```swift
import SwiftUI

struct EmptyLibraryView: View {
    let onImportTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.house")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("No music yet")
                .font(.title2.bold())
            Text("Import audio files from the Files app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onImportTap) {
                Label("Import Music", systemImage: "plus.circle.fill")
                    .font(.body.bold())
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
```

- [ ] **Step 5.4: Write `LibraryView`**

Create `Evenstar/Evenstar/Features/Library/LibraryView.swift`:

```swift
import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Track.title, order: .forward) private var tracks: [Track]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            // Wired in Task 6
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .disabled(true)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: {})
        } else {
            List(tracks) { track in
                SongRow(track: track)
            }
            .listStyle(.plain)
        }
    }
}
```

- [ ] **Step 5.5: Render `LibraryView` from `EvenstarApp`**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift`:

```swift
//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Track.self, PlaybackState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(modelContainer)
    }
}
```

- [ ] **Step 5.6: Build & run on simulator**

**⌘R**. Expected: app launches, empty state shows the hero + "Import Music" button. The button does nothing (wired in Task 6). The "+" toolbar icon is disabled (wired in Task 6).

- [ ] **Step 5.7: Commit**

```bash
git add Evenstar
git commit -m "feat: LibraryView empty state + Songs list + SongRow (Phase 2a task 5)"
```

---

## Task 6: Wire `.fileImporter` and `ImportProgressSheet`

**Goal:** Tapping "Import Music" or the toolbar "+" opens the system Document Picker (audio files, multi-select). On selection, a modal sheet drives `ImportService.importFiles` and shows progress + summary.

**Files:**
- Create: `Evenstar/Evenstar/Features/Import/ImportProgressSheet.swift`
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift` — `.fileImporter`, `.sheet`, state vars.
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — instantiate `LibraryService` + `ImportService`, inject via `.environment`.
- Modify: `Evenstar/Evenstar/Features/Library/EmptyLibraryView.swift` — already takes `onImportTap`, no change.

**Interfaces:**
- Consumes: `LibraryService` (Task 2), `ImportService` (Task 4).
- Produces: `struct ImportProgressSheet: View` with init `(urls: [URL], importer: ImportService)`.

### Steps

- [ ] **Step 6.1: Write `ImportProgressSheet`**

Create `Evenstar/Evenstar/Features/Import/ImportProgressSheet.swift`:

```swift
import SwiftUI

struct ImportProgressSheet: View {
    let urls: [URL]
    let importer: ImportService

    @Environment(\.dismiss) private var dismiss
    @State private var summary: ImportSummary?

    var body: some View {
        VStack(spacing: 20) {
            if importer.isImporting || summary == nil {
                ProgressView(
                    value: Double(importer.progress.completed),
                    total: Double(max(importer.progress.total, 1))
                )
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)
                Text("Importing \(importer.progress.completed) of \(importer.progress.total)")
                    .font(.body)
            } else if let summary {
                Image(systemName: summary.failures.isEmpty
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(summary.failures.isEmpty ? .green : .orange)
                Text("Import complete")
                    .font(.title2.bold())
                VStack(spacing: 4) {
                    summaryLine(count: summary.imported.count, text: "imported")
                    if summary.duplicates.count > 0 {
                        summaryLine(count: summary.duplicates.count, text: "duplicate(s) skipped")
                    }
                    if summary.failures.count > 0 {
                        summaryLine(count: summary.failures.count, text: "failed")
                    }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled(importer.isImporting)
        .task {
            summary = await importer.importFiles(at: urls)
        }
    }

    private func summaryLine(count: Int, text: String) -> some View {
        Text("\(count) \(text)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 6.2: Wire services in `EvenstarApp`**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift`:

```swift
//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer
    @State private var library: LibraryService
    @State private var importService: ImportService

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Track.self, PlaybackState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        let libService = LibraryService(context: container.mainContext)
        _library = State(initialValue: libService)
        _importService = State(initialValue: ImportService(
            library: libService,
            metadataReader: AudioMetadataReader()
        ))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(importService)
        }
        .modelContainer(modelContainer)
    }
}
```

- [ ] **Step 6.3: Wire `.fileImporter` + `.sheet` in `LibraryView`**

Replace `Evenstar/Evenstar/Features/Library/LibraryView.swift`:

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryService.self) private var library
    @Environment(ImportService.self) private var importer
    @Query(sort: \Track.title, order: .forward) private var tracks: [Track]

    @State private var showFileImporter = false
    @State private var pendingURLs: [URL] = []
    @State private var showImportSheet = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                pendingURLs = secureScopedURLs(urls)
                showImportSheet = !pendingURLs.isEmpty
            case .failure:
                pendingURLs = []
            }
        }
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(urls: pendingURLs, importer: importer)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: { showFileImporter = true })
        } else {
            List(tracks) { track in
                SongRow(track: track)
            }
            .listStyle(.plain)
        }
    }

    /// Document Picker delivers security-scoped URLs. We start access here and
    /// stop it on sheet dismiss; the import work happens between those calls.
    private func secureScopedURLs(_ urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    private func stopAccessingURLs() {
        for url in pendingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        pendingURLs = []
    }
}
```

- [ ] **Step 6.4: Build & run — verify import end-to-end on simulator**

**⌘R**. On the simulator:

1. App launches → empty state.
2. Tap "Import Music" → Files app sheet opens.
3. In the simulator, drag a couple of `.mp3` files from your Mac onto the simulator window (they appear under On My iPhone → Downloads), then back in the picker navigate to them and select multi.
4. Tap Open → `ImportProgressSheet` shows the progress bar advancing.
5. On completion: summary screen with "X imported". Tap Done.
6. Sheet dismisses → Songs list appears with the imported tracks.

If the simulator can't see your files: drop them into the simulator via Finder → Files app → On My iPhone.

- [ ] **Step 6.5: Commit**

```bash
git add Evenstar
git commit -m "feat: wire .fileImporter + ImportProgressSheet end-to-end (Phase 2a task 6)"
```

---

## Task 7: Extend `PlaybackService` with queue + `play(_:in:)` + `next()` + playCount

**Goal:** `PlaybackService` gains `queue`, `queueIndex`, `currentTrack`. Tapping a song in `LibraryView` calls `playback.play(track, in: tracks)`. Auto-advance on finish. Increment `playCount` once per track after 30 s.

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` — add queue properties, `play(_:in:)`, `next()`, `handleFinish` change, `playCount` tracking, accept `LibraryService` injection.
- Modify: `Evenstar/Evenstar/Services/RemoteCommandsBridge.swift` — enable `nextTrackCommand`.
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` — instantiate `PlaybackService`, `NowPlayingService`, `RemoteCommandsBridge`.
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift` — tap row → `playback.play(track, in: tracks)`.
- Create: `Evenstar/EvenstarTests/PlaybackServiceQueueTests.swift`
- Modify: `Evenstar/EvenstarTests/PlaybackServiceTests.swift` — adjust existing tests for new constructor signature.

**Interfaces:**
- Consumes: `LibraryService`, `Track`, `AudioPlayerProtocol` (Phase 1), `NowPlayingPublisher` (Phase 1).
- Produces (on `PlaybackService`):
  - `init(player: AudioPlayerProtocol, nowPlaying: NowPlayingPublisher, library: LibraryService)`
  - `private(set) var queue: [Track]`, `private(set) var queueIndex: Int`
  - `var currentTrack: Track?`
  - `func play(_ track: Track, in queue: [Track])`
  - `func next()`

### Steps

- [ ] **Step 7.1: Write the failing queue tests**

Create `Evenstar/EvenstarTests/PlaybackServiceQueueTests.swift`:

```swift
import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceQueueTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, nowPlaying, library)
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

    func testPlayInQueueSetsQueueAndStartsPlayback() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)

        service.play(list[1], in: list)

        XCTAssertEqual(service.queue.map(\.id), list.map(\.id))
        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
    }

    func testFinishAdvancesToNextTrack() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)
        let initialPlayCount = player.playCallCount

        player.simulateFinish()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertTrue(service.isPlaying)
        XCTAssertGreaterThan(player.playCallCount, initialPlayCount)
    }

    func testFinishOnLastTrackStopsAndClearsQueue() throws {
        let (service, player, nowPlaying, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)

        player.simulateFinish()

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertGreaterThan(nowPlaying.clearCallCount, 0)
    }

    func testNextManuallyAdvances() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.next()

        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, list[1].id)
    }

    func testPlayCountIncrementsAfter30Seconds() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)

        player.currentTime = 30.5
        service.tickForTesting()  // exposed helper that drives the same code path as the 0.5s timer

        XCTAssertEqual(list[0].playCount, 1)
        XCTAssertNotNil(list[0].lastPlayedAt)
    }

    func testPlayCountIncrementsOnlyOncePerPlayback() throws {
        let (service, player, _, library) = try makeStack()
        let list = try tracks(1, library: library)
        service.play(list[0], in: list)

        player.currentTime = 31
        service.tickForTesting()
        player.currentTime = 60
        service.tickForTesting()

        XCTAssertEqual(list[0].playCount, 1)
    }
}
```

- [ ] **Step 7.2: Run tests — must fail to compile**

**⌘U**. Expected: missing types `PlaybackService(player:nowPlaying:library:)`, `tickForTesting`, etc.

- [ ] **Step 7.3: Rewrite `PlaybackService` with queue + library + play-count**

Replace `Evenstar/Evenstar/Services/PlaybackService.swift`:

```swift
import Foundation
import Observation
import AVFoundation

@Observable
@MainActor
final class PlaybackService {
    // MARK: - Observable state
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?
    private(set) var position: TimeInterval = 0
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    var duration: TimeInterval { player.duration }
    var currentTrack: Track? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
    }

    // MARK: - Dependencies
    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private let library: LibraryService

    // MARK: - Internal state
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false
    private var positionTimer: Timer?
    private var playCountedForCurrent: Bool = false

    init(player: AudioPlayerProtocol,
         nowPlaying: NowPlayingPublisher,
         library: LibraryService) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.library = library
        self.player.didFinishCallback = { [weak self] in
            Task { @MainActor in self?.handleFinish() }
        }
    }

    // MARK: - Public

    func play(_ track: Track, in queueTracks: [Track]) {
        queue = queueTracks
        queueIndex = queueTracks.firstIndex(where: { $0.id == track.id }) ?? 0
        loadCurrentAndPlay()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopPositionUpdates()
        pushNowPlaying()
    }

    func resume() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
    }

    func seek(to target: TimeInterval) {
        guard hasLoaded else { return }
        let clamped = max(0, min(target, player.duration))
        player.currentTime = clamped
        position = clamped
        pushNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCountedForCurrent = false
            loadCurrentAndPlay()
        } else {
            stopPlayback()
        }
    }

    /// Test-only hook: drives the same code path as the 0.5s position timer.
    /// Not for production callers.
    func tickForTesting() { tickPosition() }

    // MARK: - Private

    private func loadCurrentAndPlay() {
        guard let track = currentTrack else {
            stopPlayback()
            return
        }
        let url = FileLocation.absoluteURL(forRelative: track.relativePath)
        do {
            try player.load(url: url)
            hasLoaded = true
        } catch {
            stopPlayback()
            return
        }
        currentMetadata = metadata(from: track)
        currentTrackTitle = track.title
        position = 0
        playCountedForCurrent = false
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
    }

    private func stopPlayback() {
        player.pause()
        isPlaying = false
        hasLoaded = false
        queue = []
        queueIndex = 0
        currentMetadata = nil
        currentTrackTitle = nil
        position = 0
        playCountedForCurrent = false
        stopPositionUpdates()
        nowPlaying.clear()
    }

    private func handleFinish() {
        if queueIndex + 1 < queue.count {
            next()
        } else {
            stopPlayback()
        }
    }

    private func tickPosition() {
        position = player.currentTime
        if !playCountedForCurrent, position >= 30, let track = currentTrack {
            track.playCount += 1
            track.lastPlayedAt = .now
            try? library.savePlaybackState()
            playCountedForCurrent = true
        }
    }

    private func startPositionUpdates() {
        stopPositionUpdates()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickPosition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = nil
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

    private func metadata(from track: Track) -> TrackMetadata {
        var artwork: UIImage? = nil
        if let path = track.artworkRelativePath,
           let data = try? Data(contentsOf: FileLocation.absoluteURL(forRelative: path)) {
            artwork = UIImage(data: data)
        }
        return TrackMetadata(
            title: track.title,
            artist: track.artistName,
            album: track.albumTitle,
            artwork: artwork,
            durationSeconds: track.durationSeconds
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

- [ ] **Step 7.4: Update Phase 1 `PlaybackServiceTests.swift` for the new constructor**

`PlaybackServiceTests.swift` Phase 1 tests must accept the new `library:` parameter. Replace its helper:

```swift
// In PlaybackServiceTests.swift, replace makeService():
@MainActor
private func makeService() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher) {
    let player = MockAudioPlayer()
    let nowPlaying = MockNowPlayingPublisher()
    let library = try InMemoryLibrary.make()
    let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
    return (service, player, nowPlaying)
}
```

The existing Phase 1 tests use `try service.load(url:metadata:)` — that API is **gone** in 2a. Replace those tests' helper calls: they should use a single-track library and call `service.play(track, in: [track])` instead. Rewrite the four `testLoadStoresMetadataAndCallsPlayerLoad`, `testTogglePlayPause...`, etc. as below (replace the file's body except imports):

```swift
import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, MockNowPlayingPublisher, Track) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        let track = InMemoryLibrary.makeTrack(title: "Sample")
        try library.insert(track)
        return (service, player, nowPlaying, track)
    }

    func testPlayingTrackPushesNowPlaying() throws {
        let (service, player, nowPlaying, track) = try makeStack()

        service.play(track, in: [track])

        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.title, "Sample")
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, true)
    }

    func testPausePausesPlaybackAndPushesNowPlaying() throws {
        let (service, player, nowPlaying, track) = try makeStack()
        service.play(track, in: [track])

        service.togglePlayPause()

        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(nowPlaying.updates.last?.isPlaying, false)
    }

    func testSeekClampsBetweenZeroAndDuration() throws {
        let (service, player, _, track) = try makeStack()
        player.duration = 120
        service.play(track, in: [track])

        service.seek(to: -10)
        XCTAssertEqual(service.position, 0)

        service.seek(to: 999)
        XCTAssertEqual(service.position, 120)

        service.seek(to: 42)
        XCTAssertEqual(player.currentTime, 42)
        XCTAssertEqual(service.position, 42)
    }
}
```

- [ ] **Step 7.5: Enable `nextTrackCommand` in `RemoteCommandsBridge`**

Replace `Evenstar/Evenstar/Services/RemoteCommandsBridge.swift`:

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
            self?.playback.resume()
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
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playback.next()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.playback.seek(to: positionEvent.positionTime)
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = true
    }
}
```

- [ ] **Step 7.6: Wire `PlaybackService` + `NowPlayingService` + `RemoteCommandsBridge` in `EvenstarApp`**

Replace `Evenstar/Evenstar/App/EvenstarApp.swift`:

```swift
//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer
    @State private var library: LibraryService
    @State private var importService: ImportService
    @State private var playback: PlaybackService
    private let remoteCommands: RemoteCommandsBridge

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Track.self, PlaybackState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        let libService = LibraryService(context: container.mainContext)
        let imp = ImportService(library: libService, metadataReader: AudioMetadataReader())
        let now = NowPlayingService()
        let player = AVAudioPlayerWrapper()
        let play = PlaybackService(player: player, nowPlaying: now, library: libService)
        _library = State(initialValue: libService)
        _importService = State(initialValue: imp)
        _playback = State(initialValue: play)
        remoteCommands = RemoteCommandsBridge(playback: play)
        remoteCommands.install()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(importService)
                .environment(playback)
        }
        .modelContainer(modelContainer)
    }
}
```

- [ ] **Step 7.7: Tap-to-play in `LibraryView`**

Edit `Evenstar/Evenstar/Features/Library/LibraryView.swift` — add `@Environment(PlaybackService.self)` and tap handler. Replace `content` body's List:

```swift
@Environment(PlaybackService.self) private var playback
```

```swift
// Inside `content`, replace the List:
List(tracks) { track in
    SongRow(track: track)
        .contentShape(Rectangle())
        .onTapGesture {
            playback.play(track, in: tracks)
        }
}
.listStyle(.plain)
```

- [ ] **Step 7.8: Run tests — must pass**

**⌘U**. Expected: 6 new queue tests + 3 rewritten `PlaybackServiceTests` + 6 `LibraryServiceTests` + 7 `ImportServiceTests` + 2 `AudioMetadataReaderTests` = **24 passing**, 0 failures.

Build & run. With imported tracks from Task 6: tap a song → audio plays (no visible mini bar yet — that's Task 8). Verify in Xcode console there are no warnings.

- [ ] **Step 7.9: Commit**

```bash
git add Evenstar
git commit -m "feat: PlaybackService queue + play(_:in:) + next() + playCount (Phase 2a task 7)"
```

---

## Task 8: `MiniPlayerBar` + `NowPlayingView` (replaces `SimplePlayerView`)

**Goal:** Persistent `MiniPlayerBar` shows the currently-playing track at the bottom of `LibraryView`. Tapping the bar opens `NowPlayingView` as `.fullScreenCover`. Delete the Phase 1 `SimplePlayerView`.

**Files:**
- Create: `Evenstar/Evenstar/Features/Player/MiniPlayerBar.swift`
- Create: `Evenstar/Evenstar/Features/Player/NowPlayingView.swift`
- Delete: `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift`
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift` — `.safeAreaInset` + `.fullScreenCover`.

**Interfaces:**
- Consumes: `PlaybackService` (Task 7).
- Produces:
  - `struct MiniPlayerBar: View`
  - `struct NowPlayingView: View`

### Steps

- [ ] **Step 8.1: Write `MiniPlayerBar`**

Create `Evenstar/Evenstar/Features/Player/MiniPlayerBar.swift`:

```swift
import SwiftUI

struct MiniPlayerBar: View {
    let playback: PlaybackService

    var body: some View {
        if let current = playback.currentTrack {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    ArtworkThumbnail(relativePath: current.artworkRelativePath, size: 40)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
        }
    }
}
```

- [ ] **Step 8.2: Write `NowPlayingView`**

Create `Evenstar/Evenstar/Features/Player/NowPlayingView.swift`:

```swift
import SwiftUI

struct NowPlayingView: View {
    let playback: PlaybackService

    @Environment(\.dismiss) private var dismiss
    @State private var draggingPosition: TimeInterval?

    var body: some View {
        VStack(spacing: 24) {
            handle
            Spacer(minLength: 0)
            artwork
            titleBlock
            scrubber
            transport
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var handle: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .padding(8)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var artwork: some View {
        ArtworkThumbnail(
            relativePath: playback.currentTrack?.artworkRelativePath,
            size: 280
        )
        .shadow(radius: 10, y: 4)
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
            }
            .buttonStyle(.plain)

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

- [ ] **Step 8.3: Wire `MiniPlayerBar` + `NowPlayingView` in `LibraryView`**

Edit `Evenstar/Evenstar/Features/Library/LibraryView.swift`. Add a `@State private var showNowPlaying = false` and inside the `NavigationStack` apply `.safeAreaInset(edge: .bottom)`; outside, add `.fullScreenCover`. Final file:

```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryService.self) private var library
    @Environment(ImportService.self) private var importer
    @Environment(PlaybackService.self) private var playback
    @Query(sort: \Track.title, order: .forward) private var tracks: [Track]

    @State private var showFileImporter = false
    @State private var pendingURLs: [URL] = []
    @State private var showImportSheet = false
    @State private var showNowPlaying = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFileImporter = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    MiniPlayerBar(playback: playback)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if playback.currentTrack != nil { showNowPlaying = true }
                        }
                }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                pendingURLs = secureScopedURLs(urls)
                showImportSheet = !pendingURLs.isEmpty
            case .failure:
                pendingURLs = []
            }
        }
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(urls: pendingURLs, importer: importer)
                .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(playback: playback)
        }
    }

    @ViewBuilder
    private var content: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: { showFileImporter = true })
        } else {
            List(tracks) { track in
                SongRow(track: track)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playback.play(track, in: tracks)
                    }
            }
            .listStyle(.plain)
        }
    }

    private func secureScopedURLs(_ urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    private func stopAccessingURLs() {
        for url in pendingURLs { url.stopAccessingSecurityScopedResource() }
        pendingURLs = []
    }
}
```

- [ ] **Step 8.4: Delete `SimplePlayerView`**

In Xcode Project Navigator: right-click `Evenstar/Features/Player/SimplePlayerView.swift` → Delete → Move to Trash. Build to confirm nothing else references it.

- [ ] **Step 8.5: Build & run — verify UI on simulator**

**⌘R**:

1. Empty library → import a few mp3s (as in Task 6).
2. Tap a song → `MiniPlayerBar` appears at the bottom.
3. Confirm artwork thumbnail, title, artist, play/pause toggle, next button.
4. Tap the bar → `NowPlayingView` opens fullscreen.
5. Drag scrubber, confirm audio jumps; tap chevron-down to dismiss.

- [ ] **Step 8.6: Commit**

```bash
git add Evenstar
git commit -m "feat: MiniPlayerBar + NowPlayingView; remove SimplePlayerView (Phase 2a task 8)"
```

---

## Task 9: Persistence (throttled save) + `restoreFromPersistedState()`

**Goal:** `PlaybackService` persists `(currentTrackID, positionSeconds, queueTrackIDs, queueIndex)` to `PlaybackState` every 5 s during playback + on every state-change event. On app launch, restore the queue + position and load (but do not play) the current track.

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` — add persist + restore.
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift` — `.task { await playback.restoreFromPersistedState() }`.
- Create: `Evenstar/EvenstarTests/PlaybackServiceRestoreTests.swift`

**Interfaces (added on `PlaybackService`):**
- `func restoreFromPersistedState() async`

### Steps

- [ ] **Step 9.1: Write the failing restore tests**

Create `Evenstar/EvenstarTests/PlaybackServiceRestoreTests.swift`:

```swift
import XCTest
@testable import Evenstar

@MainActor
final class PlaybackServiceRestoreTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let nowPlaying = MockNowPlayingPublisher()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying, library: library)
        return (service, player, library)
    }

    private func seed(_ count: Int, library: LibraryService) throws -> [Track] {
        try (0..<count).map { i in
            let t = Track(
                title: "T\(i)",
                artistName: "A",
                albumTitle: "B",
                durationSeconds: 100,
                relativePath: "Music/\(UUID().uuidString).mp3",
                format: "mp3"
            )
            try library.insert(t)
            return t
        }
    }

    func testRestoreLoadsLastTrackAtPersistedPositionButDoesNotAutoplay() async throws {
        let (service, player, library) = try makeStack()
        let tracks = try seed(3, library: library)
        let state = library.playbackState
        state.queueTrackIDs = tracks.map(\.id)
        state.queueIndex = 1
        state.positionSeconds = 42
        try library.savePlaybackState()

        await service.restoreFromPersistedState()

        XCTAssertEqual(service.queue.map(\.id), tracks.map(\.id))
        XCTAssertEqual(service.queueIndex, 1)
        XCTAssertEqual(service.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(player.currentTime, 42, accuracy: 0.01)
        XCTAssertFalse(service.isPlaying)
    }

    func testRestoreSkipsMissingTracks() async throws {
        let (service, _, library) = try makeStack()
        var tracks = try seed(3, library: library)
        let state = library.playbackState
        state.queueTrackIDs = tracks.map(\.id)
        state.queueIndex = 1
        state.positionSeconds = 0
        try library.savePlaybackState()
        // Delete the middle track from the library after persistence captured the ID.
        let deleted = tracks.remove(at: 1)
        try library.delete(deleted)

        await service.restoreFromPersistedState()

        XCTAssertEqual(service.queue.map(\.id), tracks.map(\.id))
        // queueIndex was 1 (the deleted one). After shrink, index is clamped to remaining bounds.
        XCTAssertGreaterThanOrEqual(service.queueIndex, 0)
        XCTAssertLessThan(service.queueIndex, service.queue.count)
    }

    func testRestoreEmptyStateIsNoOp() async throws {
        let (service, _, _) = try makeStack()

        await service.restoreFromPersistedState()

        XCTAssertTrue(service.queue.isEmpty)
        XCTAssertNil(service.currentTrack)
        XCTAssertFalse(service.isPlaying)
    }

    func testPersistWritesStateOnPause() throws {
        let (service, player, library) = try makeStack()
        let tracks = try seed(2, library: library)
        service.play(tracks[0], in: tracks)
        player.currentTime = 17

        service.pause()

        XCTAssertEqual(library.playbackState.currentTrackID, tracks[0].id)
        XCTAssertEqual(library.playbackState.positionSeconds, 17, accuracy: 0.01)
        XCTAssertEqual(library.playbackState.queueTrackIDs, tracks.map(\.id))
    }
}
```

- [ ] **Step 9.2: Run tests — must fail**

**⌘U**. Expected: missing `restoreFromPersistedState`, persisted state assertions fail.

- [ ] **Step 9.3: Add persistence + restore to `PlaybackService`**

Modify `Evenstar/Evenstar/Services/PlaybackService.swift`. Add `lastPersistAt`, `persistThrottled`, `persistImmediately`, `restoreFromPersistedState`. Replace the file to keep state consistent (full file below — diff from Task 7 is the persistence + restore methods and their hooks in `play`, `pause`, `resume`, `next`, `seek`, `stopPlayback`):

```swift
import Foundation
import Observation
import AVFoundation

@Observable
@MainActor
final class PlaybackService {
    // Observable
    private(set) var isPlaying: Bool = false
    private(set) var currentTrackTitle: String?
    private(set) var currentMetadata: TrackMetadata?
    private(set) var position: TimeInterval = 0
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    var duration: TimeInterval { player.duration }
    var currentTrack: Track? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
    }

    // Dependencies
    private let player: AudioPlayerProtocol
    private let nowPlaying: NowPlayingPublisher
    private let library: LibraryService

    // Internal
    private var hasLoaded: Bool = false
    private var sessionActivated: Bool = false
    private var positionTimer: Timer?
    private var playCountedForCurrent: Bool = false
    private var lastPersistAt: Date = .distantPast
    private let persistInterval: TimeInterval = 5

    init(player: AudioPlayerProtocol,
         nowPlaying: NowPlayingPublisher,
         library: LibraryService) {
        self.player = player
        self.nowPlaying = nowPlaying
        self.library = library
        self.player.didFinishCallback = { [weak self] in
            Task { @MainActor in self?.handleFinish() }
        }
    }

    // MARK: - Public

    func play(_ track: Track, in queueTracks: [Track]) {
        queue = queueTracks
        queueIndex = queueTracks.firstIndex(where: { $0.id == track.id }) ?? 0
        loadCurrentAndPlay()
        persistImmediately()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard hasLoaded, isPlaying else { return }
        player.pause()
        isPlaying = false
        stopPositionUpdates()
        pushNowPlaying()
        persistImmediately()
    }

    func resume() {
        guard hasLoaded, !isPlaying else { return }
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
        persistImmediately()
    }

    func seek(to target: TimeInterval) {
        guard hasLoaded else { return }
        let clamped = max(0, min(target, player.duration))
        player.currentTime = clamped
        position = clamped
        pushNowPlaying()
        persistImmediately()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            playCountedForCurrent = false
            loadCurrentAndPlay()
            persistImmediately()
        } else {
            stopPlayback()
        }
    }

    func restoreFromPersistedState() async {
        let state = library.playbackState
        guard !state.queueTrackIDs.isEmpty else { return }
        let resolved: [Track] = state.queueTrackIDs.compactMap { id in
            try? library.findTrack(byID: id)
        }
        guard !resolved.isEmpty else {
            // Stale state — clear it.
            state.queueTrackIDs = []
            state.queueIndex = 0
            state.currentTrackID = nil
            state.positionSeconds = 0
            try? library.savePlaybackState()
            return
        }
        queue = resolved
        queueIndex = max(0, min(state.queueIndex, resolved.count - 1))
        guard let track = currentTrack else { return }
        let url = FileLocation.absoluteURL(forRelative: track.relativePath)
        do {
            try player.load(url: url)
            hasLoaded = true
        } catch {
            // File missing — clear the state.
            stopPlayback()
            return
        }
        let pos = max(0, min(state.positionSeconds, player.duration))
        player.currentTime = pos
        position = pos
        currentMetadata = metadata(from: track)
        currentTrackTitle = track.title
        playCountedForCurrent = pos >= 30
        isPlaying = false
        pushNowPlaying()
    }

    func tickForTesting() { tickPosition() }

    // MARK: - Private

    private func loadCurrentAndPlay() {
        guard let track = currentTrack else {
            stopPlayback()
            return
        }
        let url = FileLocation.absoluteURL(forRelative: track.relativePath)
        do {
            try player.load(url: url)
            hasLoaded = true
        } catch {
            stopPlayback()
            return
        }
        currentMetadata = metadata(from: track)
        currentTrackTitle = track.title
        position = 0
        playCountedForCurrent = false
        activateSessionIfNeeded()
        player.play()
        isPlaying = true
        startPositionUpdates()
        pushNowPlaying()
    }

    private func stopPlayback() {
        player.pause()
        isPlaying = false
        hasLoaded = false
        queue = []
        queueIndex = 0
        currentMetadata = nil
        currentTrackTitle = nil
        position = 0
        playCountedForCurrent = false
        stopPositionUpdates()
        nowPlaying.clear()
        persistImmediately()
    }

    private func handleFinish() {
        if queueIndex + 1 < queue.count {
            next()
        } else {
            stopPlayback()
        }
    }

    private func tickPosition() {
        position = player.currentTime
        if !playCountedForCurrent, position >= 30, let track = currentTrack {
            track.playCount += 1
            track.lastPlayedAt = .now
            try? library.savePlaybackState()
            playCountedForCurrent = true
        }
        persistThrottled()
    }

    private func startPositionUpdates() {
        stopPositionUpdates()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickPosition() }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func stopPositionUpdates() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func persistThrottled() {
        if Date.now.timeIntervalSince(lastPersistAt) >= persistInterval {
            persistImmediately()
        }
    }

    private func persistImmediately() {
        let state = library.playbackState
        state.queueTrackIDs = queue.map(\.id)
        state.queueIndex = queueIndex
        state.currentTrackID = currentTrack?.id
        state.positionSeconds = position
        try? library.savePlaybackState()
        lastPersistAt = .now
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

    private func metadata(from track: Track) -> TrackMetadata {
        var artwork: UIImage? = nil
        if let path = track.artworkRelativePath,
           let data = try? Data(contentsOf: FileLocation.absoluteURL(forRelative: path)) {
            artwork = UIImage(data: data)
        }
        return TrackMetadata(
            title: track.title,
            artist: track.artistName,
            album: track.albumTitle,
            artwork: artwork,
            durationSeconds: track.durationSeconds
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

- [ ] **Step 9.4: Call `restoreFromPersistedState()` on app launch**

Edit `Evenstar/Evenstar/Features/Library/LibraryView.swift`. Add `.task` to the `NavigationStack`:

```swift
// Inside body, after the .navigationTitle / toolbar / safeAreaInset chain
// add this modifier on `content` (above .safeAreaInset, doesn't matter):
.task {
    await playback.restoreFromPersistedState()
}
```

(Add it inside the `NavigationStack` content chain, after `.safeAreaInset(...)`.)

- [ ] **Step 9.5: Run tests — must pass**

**⌘U**. Expected: 4 restore tests pass + all previous tests still green. **28 total**.

- [ ] **Step 9.6: Manual verify on simulator**

**⌘R**:

1. Import a few tracks (Task 6). Tap one to start playing.
2. Let it play ~10 s; pause via mini bar.
3. Cmd-Shift-H (Home), then long-press the Evenstar icon, **stop the app** from the Xcode toolbar or from app switcher.
4. Launch again. Expected: `MiniPlayerBar` appears showing the same track, paused, at the previous position. Tap play → resumes at exactly that position.

- [ ] **Step 9.7: Commit**

```bash
git add Evenstar
git commit -m "feat: throttled persistence + restoreFromPersistedState (Phase 2a task 9)"
```

---

## Task 10: Track delete flow

**Goal:** Swipe-trailing on a song row deletes the track from DB + disk. If the deleted track is currently playing, advance to next (or stop). `PlaybackService.handleTrackDeleted(_:)` keeps queue consistent when the deleted track isn't the current one but is in the queue.

**Files:**
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift` — add `handleTrackDeleted(_ track: Track)`.
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift` — swipe action.
- Modify: `Evenstar/EvenstarTests/PlaybackServiceQueueTests.swift` — add deletion tests.

**Interfaces (added on `PlaybackService`):**
- `func handleTrackDeleted(_ track: Track)`

### Steps

- [ ] **Step 10.1: Write the failing deletion tests**

Add to `Evenstar/EvenstarTests/PlaybackServiceQueueTests.swift` (inside the existing class):

```swift
    func testHandleDeletedCurrentTrackAdvances() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.handleTrackDeleted(list[0])

        XCTAssertEqual(service.currentTrack?.id, list[1].id)
        XCTAssertEqual(service.queue.count, 2)
    }

    func testHandleDeletedLastTrackWhenItIsCurrentStopsPlayback() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(2, library: library)
        service.play(list[1], in: list)

        service.handleTrackDeleted(list[1])

        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentTrack)
    }

    func testHandleDeletedFutureTrackAdjustsQueueButKeepsCurrent() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[0], in: list)

        service.handleTrackDeleted(list[2])

        XCTAssertEqual(service.currentTrack?.id, list[0].id)
        XCTAssertEqual(service.queue.count, 2)
    }

    func testHandleDeletedPastTrackAdjustsIndex() throws {
        let (service, _, _, library) = try makeStack()
        let list = try tracks(3, library: library)
        service.play(list[2], in: list)
        XCTAssertEqual(service.queueIndex, 2)

        service.handleTrackDeleted(list[0])

        XCTAssertEqual(service.currentTrack?.id, list[2].id)
        XCTAssertEqual(service.queueIndex, 1)  // shifted because one earlier item was removed
        XCTAssertEqual(service.queue.count, 2)
    }
```

- [ ] **Step 10.2: Run tests — must fail**

**⌘U**. Expected: missing method `handleTrackDeleted`.

- [ ] **Step 10.3: Add `handleTrackDeleted` to `PlaybackService`**

Add to `PlaybackService`:

```swift
    func handleTrackDeleted(_ track: Track) {
        guard let removalIndex = queue.firstIndex(where: { $0.id == track.id }) else { return }
        let wasCurrent = (removalIndex == queueIndex)
        queue.remove(at: removalIndex)

        if wasCurrent {
            if queueIndex >= queue.count {
                stopPlayback()
            } else {
                // queueIndex stays; the new track at this index becomes current.
                playCountedForCurrent = false
                loadCurrentAndPlay()
                persistImmediately()
            }
        } else if removalIndex < queueIndex {
            queueIndex -= 1
            persistImmediately()
        } else {
            persistImmediately()
        }
    }
```

- [ ] **Step 10.4: Wire swipe-trailing in `LibraryView`**

Modify the `List` inside `LibraryView.content` to add `.swipeActions(edge: .trailing)`:

```swift
List(tracks) { track in
    SongRow(track: track)
        .contentShape(Rectangle())
        .onTapGesture {
            playback.play(track, in: tracks)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTrack(track)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
}
.listStyle(.plain)
```

Add the helper inside `LibraryView`:

```swift
private func deleteTrack(_ track: Track) {
    playback.handleTrackDeleted(track)
    do {
        try library.delete(track)
    } catch {
        // 2a: log only. A polished alert is part of 2d.
        print("Delete failed: \(error)")
    }
}
```

- [ ] **Step 10.5: Run tests — must pass**

**⌘U**. Expected: 4 new deletion tests pass. **32 total**.

- [ ] **Step 10.6: Manual verify on simulator**

**⌘R**:

1. Import 3 tracks. Tap the first → playing.
2. Swipe-trailing on the currently playing row → Delete → playback advances to track 2.
3. Confirm `Documents/Music/<uuid>.<ext>` no longer exists (use `Devices and Simulators` → Apps → Download Container → inspect on Mac).

- [ ] **Step 10.7: Commit**

```bash
git add Evenstar
git commit -m "feat: track delete via swipe + PlaybackService.handleTrackDeleted (Phase 2a task 10)"
```

---

## Task 11: Phase 2a wrap-up — full manual QA + tag

**Goal:** Run the manual QA checklist from the spec on a real iPhone. Fix any regressions. Tag `phase2a-complete`.

### Steps

- [ ] **Step 11.1: Run the full test suite**

**⌘U**. Expected: **32 passing tests, 0 failures**.

If anything fails, fix before continuing. Do not skip.

- [ ] **Step 11.2: Build a clean Release build for the device**

In Xcode: Product → Scheme → Edit Scheme → Run → Build Configuration = Release. Choose a connected iPhone as destination. **⌘R**.

(Use a Debug build if Release signing trips a free-Apple-ID limit; behaviour is the same for QA purposes.)

- [ ] **Step 11.3: Run the manual QA matrix on a real iPhone**

Each row must pass; fix any failure before tagging.

- [ ] First launch shows `EmptyLibraryView` with hero + Import CTA.
- [ ] Tap Import → Files app → multi-select 5 mp3s → progress sheet runs → "Imported 5".
- [ ] Re-import the same 5 files → "0 imported, 5 duplicates skipped".
- [ ] Import a single `.txt` file → "0 imported, 1 failed".
- [ ] Songs list renders rows with thumbnails, sorted alphabetically by title (`localizedStandardCompare` puts lowercase first / accent-folded correctly for Vietnamese tag strings).
- [ ] Tap a song → `MiniPlayerBar` appears at the bottom; audio plays.
- [ ] Tap `MiniPlayerBar` → `NowPlayingView` opens fullscreen. Scrubber, play/pause, next all work.
- [ ] Track ends → next track in the list plays automatically.
- [ ] Last track ends → `MiniPlayerBar` hides; lock-screen Now Playing clears.
- [ ] Swipe-trailing on the currently playing row → Delete → playback advances; the row vanishes.
- [ ] Lock the device while playing → lock-screen shows title / artist / album / artwork / scrubber; play/pause + next work from the lock screen.
- [ ] AirPods / wired EarPods play/pause click toggles audio.
- [ ] Kill the app from App Switcher → relaunch → `MiniPlayerBar` shows last track, paused, at saved position. Tap play → resumes from that position.
- [ ] Delete the currently-playing track → relaunch → restore handles the gap (queue shrinks; another track becomes current, paused).

- [ ] **Step 11.4: Tag `phase2a-complete`**

```bash
cd /Users/phanquyetthang/evenstar
git tag -a phase2a-complete -m "Phase 2a (Foundation) complete: import, library, mini player, queue, state restore"
git push origin phase2a-complete
```

---

## Out of scope (deferred to 2b / 2c / 2d)

Explicitly NOT in this plan:

- Albums grouping, Artists grouping, sort picker (2b)
- Playlists CRUD, reorder, Playlists tab (2c)
- Search bar, `.searchable` (2c)
- Queue editing sheet (2c)
- Shuffle, repeat, previous-track command (2c)
- Long-press context menu (Play Next / Add to Queue / Add to Playlist / Show in Album) (2c)
- Audio session interruption auto-resume policy refinements (2d)
- Background / non-blocking import (2d)
- Pull-to-refresh metadata re-scan (2d)
- TestFlight internal share (2d)
- Polished error alerts for delete failure (2d)
- Settings tab / gear icon (2d or later)

Each gets its own plan once 2a is shipped.

---

## Self-review

- ✅ Spec §1–§2 (scope + brainstorm decisions) → Tasks 1–10 implement each decision row by row; out-of-scope items collected in §"Out of scope" of this plan.
- ✅ Spec §3 (architecture) → Task structure mirrors the service-layer split; Task 1 sets up project layout.
- ✅ Spec §4 (data model) → Task 1 writes the models with all fields verbatim.
- ✅ Spec §5 (services API) → Task 2 (`LibraryService`), Task 4 (`ImportService`), Task 7 (`PlaybackService` queue), Task 9 (`PlaybackService` persistence + restore), Task 10 (`PlaybackService.handleTrackDeleted`), Task 7 (RemoteCommandsBridge update).
- ✅ Spec §6 (UI) → Task 5 (`LibraryView` / `SongRow` / `EmptyLibraryView`), Task 6 (`ImportProgressSheet`), Task 8 (`MiniPlayerBar` / `NowPlayingView`).
- ✅ Spec §7 (flows) → mirrored by Task 5 + 6 (import), Task 7 (tap-to-play + auto-advance), Task 8 (mini bar → full-screen), Task 9 (kill → restore), Task 10 (delete).
- ✅ Spec §8 (error handling) → `ImportError` in Task 4, `LibraryError` in Task 2, no `try!` enforced in Global Constraints.
- ✅ Spec §9 (testing) → Task 1 sets up the test target; each service task includes red→green TDD with the in-memory helper.
- ✅ Spec §11 (estimate breakdown) → 10 task days map roughly to the 11 tasks in this plan (some days bundle multiple tasks).
- ✅ Placeholder scan: no TBD/TODO; no "add appropriate error handling"; no "similar to Task N"; every code step shows real code.
- ✅ Type consistency: `LibraryService`, `ImportService`, `PlaybackService` constructors and method names align across tasks; `Track` field names match the model declaration in Task 1.
