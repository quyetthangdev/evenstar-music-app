# Drive Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play music from a link-shared Google Drive folder without copying it to the device.

**Architecture:** Two new SwiftData models kept entirely separate from `Track`, a networking client that reads a public folder with a plain API key, and a second `AudioPlayerProtocol` implementation backed by `AVPlayer`. `PlaybackService`'s queue becomes source-agnostic through a `Playable` protocol, so repeat, the lock screen, session restore and play counting work for Drive tracks without being written again.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation, URLSession. iOS 18.6 minimum. XCTest.

**Spec:** `docs/superpowers/specs/2026-08-05-drive-streaming-design.md`

## Global Constraints

- NEVER edit `Evenstar/Evenstar.xcodeproj/project.pbxproj` or any `.xcscheme`. New `.swift` files are picked up automatically by Xcode 16 synced folders — creating the file in the right directory is enough.
- NEVER change build settings. `SWIFT_DEFAULT_ACTOR_ISOLATION` must stay `nonisolated`.
- SwiftUI only. **No third-party libraries** — this rules out every Google SDK; all networking is `URLSession`.
- No `try!`. No silent `catch { }`.
- Zero Swift warnings across **both** targets. Verify with `xcodebuild clean build-for-testing`, never plain `xcodebuild build` — plain `build` does not compile the test target and has hidden warnings there before.
- Test counts come from `xcrun xcresulttool`, never `grep "^Test case"`.
- **No test may touch the real network.** `DriveClient` tests use a stubbed `URLProtocol`.
- Phase 1 capability — background audio, lock-screen Now Playing, remote commands — must keep working.
- All user-facing copy is Vietnamese, matching the rest of the app.
- SourceKit reports spurious "cannot find type in scope" / "No such module" errors throughout this project. Trust `xcodebuild`.

**Build:**
```bash
xcodebuild clean build-for-testing -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "warning:|error:|BUILD"
```

**Test:**
```bash
rm -rf /tmp/r.xcresult
xcodebuild test-without-building -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -destination 'platform=iOS Simulator,name=iPhone 17' -resultBundlePath /tmp/r.xcresult >/dev/null 2>&1
xcrun xcresulttool get test-results summary --path /tmp/r.xcresult
```

Baseline before this plan starts: **119 tests — 116 passing, 3 skipped, 0 failing.** The three skips are `SystemVolumeSliderTests`, which need audio hardware.

---

## File Structure

| File | Responsibility |
|---|---|
| `Features/Drive/DriveLinkParser.swift` *(new)* | Share link → folder ID. Pure. |
| `Models/DriveFolder.swift` *(new)* | A linked folder. |
| `Models/DriveTrack.swift` *(new)* | One audio file in a linked folder. |
| `Services/Playable.swift` *(new)* | What `PlaybackService` needs of a queue item. |
| `Services/DriveAPIKey.swift` *(new)* | The key, and the reason it is not hidden. |
| `Services/DriveClient.swift` *(new)* | Drive REST calls. No SwiftData. |
| `Services/DriveLibraryService.swift` *(new)* | Scan a folder into SwiftData. |
| `Services/StreamingAudioPlayer.swift` *(new)* | `AudioPlayerProtocol` over `AVPlayer`. |
| `Services/AudioPlayerProtocol.swift` | Gains `didFailCallback`. |
| `Services/PlaybackService.swift` | Queue becomes `[any Playable]`; handles async failure. |
| `Services/LibraryService.swift` | Gains `findDriveTrack(byID:)`. |
| `Features/Library/SongsView.swift` | Source chips; the Drive list and its states. |
| `Features/Drive/DriveFoldersView.swift` *(new)* | Manage linked folders. |
| `Features/Account/AccountView.swift` | A row linking to `DriveFoldersView`. |
| `App/EvenstarApp.swift` | Registers the two new models. |
| `EvenstarTests/InMemoryLibrary.swift` | Registers them too. |

---

## Task 1: `DriveLinkParser`

Pure and self-contained, so the riskiest string handling is settled before anything depends on it.

**Files:**
- Create: `Evenstar/Evenstar/Features/Drive/DriveLinkParser.swift`
- Create: `Evenstar/EvenstarTests/DriveLinkParserTests.swift`

**Interfaces:**
- Produces: `enum DriveLinkParser { static func folderID(from text: String) -> String? }`

- [ ] **Step 1: Write the failing tests**

Create `Evenstar/EvenstarTests/DriveLinkParserTests.swift`:

```swift
import XCTest
@testable import Evenstar

final class DriveLinkParserTests: XCTestCase {

    /// The forms Google's own Share dialog and address bar produce.
    func testAcceptsTheLinkFormsGoogleHandsOut() {
        let id = "1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv"
        let cases = [
            "https://drive.google.com/drive/folders/\(id)",
            "https://drive.google.com/drive/folders/\(id)?usp=sharing",
            "https://drive.google.com/drive/folders/\(id)?usp=drive_link",
            "https://drive.google.com/drive/u/0/folders/\(id)",
            "https://drive.google.com/open?id=\(id)",
            "  https://drive.google.com/drive/folders/\(id)  ",
        ]
        for text in cases {
            XCTAssertEqual(DriveLinkParser.folderID(from: text), id, "failed on: \(text)")
        }
    }

    /// A user who pastes the ID alone should not be told their link is wrong.
    func testAcceptsABareFolderID() {
        let id = "1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv"
        XCTAssertEqual(DriveLinkParser.folderID(from: id), id)
    }

    /// A *file* link is the most likely wrong paste, and it must be rejected —
    /// otherwise the app would query a file ID as if it were a folder and show
    /// an empty list with no explanation.
    func testRejectsAFileLink() {
        let link = "https://drive.google.com/file/d/1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUv/view"
        XCTAssertNil(DriveLinkParser.folderID(from: link))
    }

    func testRejectsRubbish() {
        for text in ["", "   ", "hello", "https://example.com/drive/folders/abc",
                     "https://drive.google.com/drive/folders/"] {
            XCTAssertNil(DriveLinkParser.folderID(from: text), "should have rejected: \(text)")
        }
    }

    /// Drive IDs are URL-safe base64-ish. Anything with a slash or a query
    /// marker in it is a parsing mistake, not an ID.
    func testDoesNotReturnSomethingWithPathOrQueryInIt() {
        let link = "https://drive.google.com/drive/folders/abc/def?usp=sharing"
        let result = DriveLinkParser.folderID(from: link)
        XCTAssertEqual(result, "abc")
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Build. Expected: `cannot find 'DriveLinkParser' in scope`.

- [ ] **Step 3: Implement**

Create `Evenstar/Evenstar/Features/Drive/DriveLinkParser.swift`:

```swift
import Foundation

/// Turns whatever the user pasted into a Drive folder ID.
///
/// Separate from `DriveClient` and free of networking, because this is string
/// handling with many shapes and one of them — a *file* link rather than a
/// folder link — fails in a way that looks like an empty folder rather than
/// like an error. Cheap to test exhaustively; expensive to debug in the wild.
enum DriveLinkParser {
    /// Characters Drive uses in its IDs. Anything else ends the ID.
    private static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    /// The folder ID, or `nil` if this is not a Drive *folder* reference.
    static func folderID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A file link deliberately fails rather than falling through to the
        // bare-ID branch below, which would otherwise accept its ID and query
        // it as a folder.
        if trimmed.contains("/file/d/") { return nil }

        if let range = trimmed.range(of: "/folders/") {
            return id(from: trimmed[range.upperBound...])
        }
        if let range = trimmed.range(of: "id=") {
            return id(from: trimmed[range.upperBound...])
        }
        // A bare ID: no scheme, no slashes, and only ID characters.
        if !trimmed.contains("/"), !trimmed.contains(":"), isID(trimmed) {
            return trimmed
        }
        return nil
    }

    private static func id(from rest: Substring) -> String? {
        let candidate = rest.prefix { character in
            character.unicodeScalars.allSatisfy(idCharacters.contains)
        }
        return candidate.isEmpty ? nil : String(candidate)
    }

    private static func isID(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(idCharacters.contains)
    }
}
```

- [ ] **Step 4: Run the tests**

Expected: **124 tests — 121 passing, 3 skipped, 0 failing.**

- [ ] **Step 5: Prove the tests can fail**

Temporarily delete the `/file/d/` guard. Re-run: `testRejectsAFileLink` must fail. Revert.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Features/Drive/DriveLinkParser.swift Evenstar/EvenstarTests/DriveLinkParserTests.swift
git commit -m "feat: parse Drive share links into folder IDs"
```

---

## Task 2: The two models

**Files:**
- Create: `Evenstar/Evenstar/Models/DriveFolder.swift`
- Create: `Evenstar/Evenstar/Models/DriveTrack.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift:20`
- Modify: `Evenstar/EvenstarTests/InMemoryLibrary.swift:10`
- Create: `Evenstar/EvenstarTests/DriveModelTests.swift`

**Interfaces:**
- Produces, for every later task:
  - `DriveFolder(folderID:displayName:linkedAt:lastScannedAt:)`
  - `DriveTrack(id:fileID:folderID:fileName:title:artistName:albumTitle:durationSeconds:metadataResolved:dateAdded:playCount:lastPlayedAt:)`

**Note on one refinement from the spec:** the spec wrote `durationSeconds: Double?`. Use a **non-optional `Double` defaulting to 0**, with `metadataResolved` telling you whether it is real. `Playable` in Task 3 needs a non-optional duration, and two ways to say "unknown" in the same row is one too many.

- [ ] **Step 1: Write the failing tests**

Create `Evenstar/EvenstarTests/DriveModelTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class DriveModelTests: XCTestCase {

    /// Both models must be in the container the app builds, not just the one
    /// the tests build — a model missing from the app's schema throws at
    /// launch, which no unit test would catch.
    func testBothModelsAreInTheInMemorySchema() throws {
        let library = try InMemoryLibrary.make()
        let folder = DriveFolder(folderID: "F1", displayName: "Chill mix")
        let track = DriveTrack(fileID: "A1", folderID: "F1", fileName: "01 - Song.mp3")
        library.context.insert(folder)
        library.context.insert(track)
        try library.save()

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveFolder>()).count, 1)
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }

    /// The title falls back to the file name without its extension, because at
    /// scan time that is genuinely all the app knows.
    func testTitleDefaultsToTheFileNameWithoutItsExtension() {
        let track = DriveTrack(fileID: "A1", folderID: "F1", fileName: "01 - Giây Tiếp Theo.mp3")
        XCTAssertEqual(track.title, "01 - Giây Tiếp Theo")
        XCTAssertFalse(track.metadataResolved)
        XCTAssertEqual(track.durationSeconds, 0)
    }

    func testAFileNameWithNoExtensionIsUsedWhole() {
        let track = DriveTrack(fileID: "A1", folderID: "F1", fileName: "Untitled")
        XCTAssertEqual(track.title, "Untitled")
    }

    /// `fileID` is unique so a rescan updates rather than duplicates.
    func testInsertingTheSameFileIDTwiceKeepsOneRow() throws {
        let library = try InMemoryLibrary.make()
        library.context.insert(DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3"))
        try library.save()
        library.context.insert(DriveTrack(fileID: "A1", folderID: "F1", fileName: "a.mp3"))
        try library.save()

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }
}
```

`library.context` must be reachable from tests — if `LibraryService.context` is `private`, change it to `private(set)` and note it in the report.

- [ ] **Step 2: Run and watch it fail**

Expected: `cannot find 'DriveFolder' in scope`.

- [ ] **Step 3: Create `DriveFolder`**

```swift
import Foundation
import SwiftData

/// A Google Drive folder the user has linked.
///
/// Only folders shared as *anyone with the link* work — the app reads them with
/// a plain API key and never signs in. See the design spec for why signing in
/// is not an option here.
@Model
final class DriveFolder {
    @Attribute(.unique) var folderID: String
    var displayName: String
    var linkedAt: Date
    /// `nil` until the first successful scan, which is what distinguishes
    /// "never scanned" from "scanned and empty".
    var lastScannedAt: Date?

    init(folderID: String,
         displayName: String,
         linkedAt: Date = .now,
         lastScannedAt: Date? = nil) {
        self.folderID = folderID
        self.displayName = displayName
        self.linkedAt = linkedAt
        self.lastScannedAt = lastScannedAt
    }
}
```

- [ ] **Step 4: Create `DriveTrack`**

```swift
import Foundation
import SwiftData

/// One audio file inside a linked `DriveFolder`.
///
/// Deliberately not a variant of `Track`. Sharing that model would be cheaper
/// in the playback layer but would force every existing `@Query` to grow a
/// filter, and missing one would leak Drive rows into the local library. Two
/// models make the compiler enforce the split instead of a reviewer.
@Model
final class DriveTrack {
    /// Stable across app launches, and what `PlaybackState` persists.
    /// Distinct from `fileID`, which is Google's.
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var fileID: String
    var folderID: String
    var fileName: String
    var title: String
    /// Stored optional, because "not read yet" is real and distinct from
    /// "read, and the file has no artist tag". `Playable` exposes non-optional
    /// `artistName`/`albumTitle` computed from these — see `Playable.swift`.
    var artistNameOrNil: String?
    var albumTitleOrNil: String?
    /// 0 until `metadataResolved`. Not optional: `Playable` needs a number, and
    /// two ways to say "unknown" in one row is one too many.
    var durationSeconds: Double
    /// False until the track has been played once and its real tags read over
    /// the network. Scanning deliberately does not read tags — see the spec.
    var metadataResolved: Bool
    var dateAdded: Date
    var playCount: Int
    var lastPlayedAt: Date?

    init(id: UUID = UUID(),
         fileID: String,
         folderID: String,
         fileName: String,
         title: String? = nil,
         artistName: String? = nil,
         albumTitle: String? = nil,
         durationSeconds: Double = 0,
         metadataResolved: Bool = false,
         dateAdded: Date = .now,
         playCount: Int = 0,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.fileID = fileID
        self.folderID = folderID
        self.fileName = fileName
        self.title = title ?? Self.titleFromFileName(fileName)
        self.artistNameOrNil = artistName
        self.albumTitleOrNil = albumTitle
        self.durationSeconds = durationSeconds
        self.metadataResolved = metadataResolved
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
    }

    /// `(NSString as NSString).deletingPathExtension` rather than splitting on
    /// ".", so a title containing a dot keeps it.
    static func titleFromFileName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}
```

- [ ] **Step 5: Register both models in the two containers**

`Evenstar/Evenstar/App/EvenstarApp.swift:20`:

```swift
            container = try ModelContainer(
                for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self
            )
```

`Evenstar/EvenstarTests/InMemoryLibrary.swift:10`:

```swift
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self,
```

Then check nothing else builds a container that will now be missing them:

```bash
grep -rn "ModelContainer(" --include="*.swift" Evenstar/
```

The `#Preview` blocks in `AlbumsView`, `ArtistsView`, `AlbumDetailView`, `ArtistDetailView`, `SearchView` and `AccountView` each build their own container for `Track.self` only. Leave them alone — none of them touches a Drive model, and a preview container only needs the models that preview uses. Say in your report which ones you checked and why you left them.

- [ ] **Step 6: Run the tests**

Expected: **128 tests — 125 passing, 3 skipped, 0 failing.**

- [ ] **Step 7: Commit**

```bash
git add Evenstar/Evenstar/Models/DriveFolder.swift Evenstar/Evenstar/Models/DriveTrack.swift \
        Evenstar/Evenstar/App/EvenstarApp.swift Evenstar/EvenstarTests/InMemoryLibrary.swift \
        Evenstar/EvenstarTests/DriveModelTests.swift
git commit -m "feat: add DriveFolder and DriveTrack models"
```

---

## Task 3: `Playable` — one queue, two sources

**This is the riskiest task in the plan.** It touches the most heavily tested file in the codebase. The 119-test baseline is the guard rail: **if the existing suite goes red, stop and report rather than adapting the tests to the new code.**

**Files:**
- Create: `Evenstar/Evenstar/Services/Playable.swift`
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift`
- Modify: `Evenstar/Evenstar/Services/LibraryService.swift`
- Create: `Evenstar/EvenstarTests/PlayableQueueTests.swift`

**Interfaces:**
- Consumes: `DriveTrack` (Task 2)
- Produces, for Tasks 4–8:
  - `protocol Playable: AnyObject`, with `Track` and `DriveTrack` conforming
  - `PlaybackService.queue: [any Playable]`, `currentTrack: (any Playable)?`
  - `PlaybackService.play(_ item: any Playable, in queue: [any Playable])`
  - `LibraryService.findDriveTrack(byID: UUID) throws -> DriveTrack?`

- [ ] **Step 1: Write the protocol**

```swift
import Foundation

/// What `PlaybackService` needs of anything it can play.
///
/// Exists so one queue can hold local files and Drive files without the service
/// knowing which is which. Everything the service already does — repeat, the
/// lock screen, session restore, play counting, the skip-forward-on-failure
/// loop — then works for both sources without being written twice.
///
/// `AnyObject` because the service mutates `playCount` and `lastPlayedAt` in
/// place on rows that SwiftData is tracking.
protocol Playable: AnyObject {
    /// Stable across launches. `PlaybackState` persists these.
    var id: UUID { get }
    var title: String { get }
    var artistName: String { get }
    var albumTitle: String { get }
    var durationSeconds: Double { get }
    /// Documents-relative. `nil` for anything with no local artwork, which is
    /// every Drive track — artwork is out of scope for this đợt.
    var artworkRelativePath: String? { get }
    var playCount: Int { get set }
    var lastPlayedAt: Date? { get set }

    /// Where the bytes are. A file URL for local tracks, an https URL for Drive.
    func playbackURL() -> URL
}

extension Track: Playable {
    func playbackURL() -> URL {
        FileLocation.absoluteURL(forRelative: relativePath)
    }
}

extension DriveTrack: Playable {
    /// `artistName` and `albumTitle` are optional on the row because they are
    /// genuinely unknown until the track has been played once; the protocol
    /// wants a string, so unknown becomes the same placeholder the local
    /// library uses for untagged files.
    var artistName: String { artistNameOrNil ?? "Nghệ sĩ không rõ" }
    var albumTitle: String { albumTitleOrNil ?? "Album không rõ" }
    var artworkRelativePath: String? { nil }

    func playbackURL() -> URL {
        DriveClient.mediaURL(fileID: fileID)
    }
}
```

`DriveTrack` already stores these as `artistNameOrNil`/`albumTitleOrNil`
(Task 2), so the computed properties above compile without renaming anything.

`DriveClient.mediaURL(fileID:)` is defined in Task 4. Until then, stub it in
this task as a `static func` on a new empty `DriveClient` enum and let Task 4
fill the type in — say so in your report.

- [ ] **Step 2: Generalise `PlaybackService`**

Change these declarations:

```swift
    private(set) var queue: [any Playable] = []
    var currentTrack: (any Playable)? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
    }

    func play(_ track: any Playable, in queueTracks: [any Playable]) {
        queue = queueTracks
        queueIndex = queueTracks.firstIndex(where: { $0.id == track.id }) ?? 0
        loadCurrentAndPlay()
        persistImmediately()
    }
```

Replace every `FileLocation.absoluteURL(forRelative: track.relativePath)` inside
`PlaybackService` with `track.playbackURL()`. There are two — in
`loadCurrentAndPlay()` and in `restoreFromPersistedState()`.

`handleTrackDeleted(_ track: Track)` keeps its `Track` parameter: deleting is a
local-library action. It matches queue members by `id`, so it needs no other
change.

- [ ] **Step 3: Resolve both stores on restore**

Add to `LibraryService`:

```swift
    func findDriveTrack(byID id: UUID) throws -> DriveTrack? {
        var descriptor = FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
```

In `restoreFromPersistedState()`, the line that resolves IDs becomes:

```swift
        let resolved: [any Playable] = state.queueTrackIDs.compactMap { id in
            // Local first: it is the commoner case and needs no second query
            // when it hits.
            if let track = try? library.findTrack(byID: id) { return track }
            return try? library.findDriveTrack(byID: id)
        }
```

- [ ] **Step 4: Write tests for the mixed queue**

Create `Evenstar/EvenstarTests/PlayableQueueTests.swift`:

```swift
import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class PlayableQueueTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player, nowPlaying: MockNowPlayingPublisher(), library: library
        )
        return (service, player, library)
    }

    private func localTrack(_ library: LibraryService) throws -> Track {
        let track = Track(
            title: "Local", artistName: "A", albumTitle: "B",
            durationSeconds: 100, relativePath: "Music/\(UUID().uuidString).mp3", format: "mp3"
        )
        try library.insert(track)
        return track
    }

    private func driveTrack(_ library: LibraryService) throws -> DriveTrack {
        let track = DriveTrack(fileID: UUID().uuidString, folderID: "F1", fileName: "remote.mp3")
        library.context.insert(track)
        try library.save()
        return track
    }

    /// The point of the protocol: one queue holding both kinds.
    func testAQueueCanHoldBothSources() throws {
        let (service, _, library) = try makeStack()
        let local = try localTrack(library)
        let remote = try driveTrack(library)

        service.play(local, in: [local, remote])
        XCTAssertEqual(service.currentTrack?.id, local.id)

        service.next()
        XCTAssertEqual(service.currentTrack?.id, remote.id)
        XCTAssertEqual(service.queue.count, 2)
    }

    /// A local track plays from a file URL and a Drive track from https. If
    /// this regresses, playback "works" in tests and fails on device.
    func testEachSourceReportsItsOwnKindOfURL() throws {
        let library = try InMemoryLibrary.make()
        let local = try localTrack(library)
        let remote = try driveTrack(library)

        XCTAssertTrue(local.playbackURL().isFileURL)
        XCTAssertEqual(remote.playbackURL().scheme, "https")
    }

    /// Session restore has to look in both stores. Resolving only local tracks
    /// would silently drop every Drive track from a restored queue.
    func testRestoreResolvesADriveTrackFromThePersistedQueue() async throws {
        let (service, _, library) = try makeStack()
        let remote = try driveTrack(library)
        service.play(remote, in: [remote])

        let relaunched = PlaybackService(
            player: MockAudioPlayer(), nowPlaying: MockNowPlayingPublisher(), library: library
        )
        await relaunched.restoreFromPersistedState()

        XCTAssertEqual(relaunched.queue.count, 1)
        XCTAssertEqual(relaunched.currentTrack?.id, remote.id)
    }

    /// Unknown tags become the same placeholder the local library shows, rather
    /// than an empty line in the player.
    func testADriveTrackWithNoTagsStillHasAnArtistAndAlbumToShow() throws {
        let library = try InMemoryLibrary.make()
        let remote = try driveTrack(library)

        XCTAssertEqual(remote.artistName, "Nghệ sĩ không rõ")
        XCTAssertEqual(remote.albumTitle, "Album không rõ")
    }
}
```

- [ ] **Step 5: Run the whole suite**

Expected: **133 tests — 130 passing, 3 skipped, 0 failing.**

**Every pre-existing test must still pass.** `PlaybackServiceQueueTests`,
`PlaybackServiceRepeatTests` and `PlaybackServiceRestoreTests` are the guard
rail on this edit. If any of them fails, do not change the test — report
`DONE_WITH_CONCERNS` or `BLOCKED` with the failure.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Services/ Evenstar/EvenstarTests/PlayableQueueTests.swift
git commit -m "feat: make the playback queue source-agnostic via Playable"
```

---

## Task 4: `DriveClient` and the API key

**Files:**
- Create: `Evenstar/Evenstar/Services/DriveAPIKey.swift`
- Create: `Evenstar/Evenstar/Services/DriveClient.swift`
- Create: `Evenstar/EvenstarTests/DriveClientTests.swift`
- Create: `Evenstar/EvenstarTests/StubURLProtocol.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces, for Tasks 5–8:
  - `struct DriveFile { let id: String; let name: String; let mimeType: String }`
  - `enum DriveError: LocalizedError { case missingAPIKey, notShared, notFound, offline, quotaExceeded, server(Int), malformedResponse }`
  - `struct DriveClient { init(apiKey: String = DriveAPIKey.value, session: URLSession = .shared); func listAudioFiles(inFolder: String) async throws -> [DriveFile]; static func mediaURL(fileID: String) -> URL }`

- [ ] **Step 1: Write the stub `URLProtocol`**

Create `Evenstar/EvenstarTests/StubURLProtocol.swift`:

```swift
import Foundation

/// Answers every request from a queue the test sets up, so no test in this
/// suite touches the network.
final class StubURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let body: Data
    }

    nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    static func reset() {
        responses = []
        requestedURLs = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requestedURLs.append(url) }
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let next = Self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Write the failing tests**

Create `Evenstar/EvenstarTests/DriveClientTests.swift`:

```swift
import XCTest
@testable import Evenstar

final class DriveClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func page(_ files: [(String, String, String)], nextToken: String? = nil) -> Data {
        let items = files.map { #"{"id":"\#($0.0)","name":"\#($0.1)","mimeType":"\#($0.2)"}"# }
        let token = nextToken.map { #""nextPageToken":"\#($0)","# } ?? ""
        return Data(#"{\#(token)"files":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    /// The whole point of pagination: Drive returns at most 100 files per page,
    /// so a folder of 150 songs arrives as 100 unless nextPageToken is followed.
    /// Without this test the bug looks exactly like a smaller folder.
    func testFollowsPaginationToTheEnd() async throws {
        StubURLProtocol.responses = [
            .init(status: 200, body: page([("1", "a.mp3", "audio/mpeg")], nextToken: "T2")),
            .init(status: 200, body: page([("2", "b.mp3", "audio/mpeg")])),
        ]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        let files = try await client.listAudioFiles(inFolder: "F1")

        XCTAssertEqual(files.map(\.id), ["1", "2"])
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2)
        XCTAssertTrue(
            StubURLProtocol.requestedURLs[1].absoluteString.contains("pageToken=T2"),
            "the second request must carry the token from the first response"
        )
    }

    func testKeepsOnlyAudioFiles() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: page([
            ("1", "song.mp3", "audio/mpeg"),
            ("2", "cover.jpg", "image/jpeg"),
            ("3", "notes.txt", "text/plain"),
            ("4", "song.m4a", "audio/mp4"),
        ]))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        let files = try await client.listAudioFiles(inFolder: "F1")

        XCTAssertEqual(files.map(\.id), ["1", "4"])
    }

    func testAnEmptyFolderIsNotAnError() async throws {
        StubURLProtocol.responses = [.init(status: 200, body: page([]))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        let files = try await client.listAudioFiles(inFolder: "F1")

        XCTAssertTrue(files.isEmpty)
    }

    /// The commonest real failure: the user linked a folder they forgot to
    /// share. It must be distinguishable so the message can say what to fix.
    func testAPrivateFolderReportsNotShared() async {
        StubURLProtocol.responses = [.init(status: 403, body: Data("{}".utf8))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .notShared)
        }
    }

    func testAMissingFolderReportsNotFound() async {
        StubURLProtocol.responses = [.init(status: 404, body: Data("{}".utf8))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .notFound)
        }
    }

    func testQuotaExhaustionIsItsOwnError() async {
        StubURLProtocol.responses = [.init(status: 429, body: Data("{}".utf8))]
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .quotaExceeded)
        }
    }

    /// No responses queued makes the stub fail the connection.
    func testNoConnectionReportsOffline() async {
        let client = DriveClient(apiKey: "test-key", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .offline)
        }
    }

    func testMediaURLPointsAtTheFileWithAltMedia() {
        let url = DriveClient.mediaURL(fileID: "ABC").absoluteString
        XCTAssertTrue(url.contains("/files/ABC"))
        XCTAssertTrue(url.contains("alt=media"))
    }
}

/// XCTest has no async `XCTAssertThrowsError`.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
```

- [ ] **Step 3: Run and watch it fail**

Expected: `cannot find 'DriveClient' in scope`.

- [ ] **Step 4: Create the API key holder**

Create `Evenstar/Evenstar/Services/DriveAPIKey.swift`:

```swift
import Foundation

/// The Google API key used to read public Drive folders.
///
/// **This is empty in the repository on purpose, and the app reports a specific
/// error rather than failing obscurely when it is.** Fill it in locally and do
/// not commit the change.
///
/// Hiding a key inside an app binary is theatre — anyone can extract it. The
/// real boundary is in Google Cloud Console: restrict the key to the **Drive
/// API only** and to this app's **bundle ID**. Do that before shipping; a key
/// without those restrictions is a key anyone can spend your quota with.
enum DriveAPIKey {
    static let value = ""

    static var isConfigured: Bool { !value.isEmpty }
}
```

- [ ] **Step 5: Create `DriveClient`**

```swift
import Foundation

struct DriveFile {
    let id: String
    let name: String
    let mimeType: String
}

enum DriveError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case notShared
    case notFound
    case offline
    case quotaExceeded
    case server(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Chưa cấu hình API key cho Google Drive."
        case .notShared:
            "Thư mục này chưa được chia sẻ công khai. Trên Drive, đổi quyền thành “bất kỳ ai có liên kết”."
        case .notFound:
            "Không tìm thấy thư mục. Link có thể sai hoặc thư mục đã bị xoá."
        case .offline:
            "Không có kết nối mạng."
        case .quotaExceeded:
            "Đã vượt hạn ngạch truy cập Google Drive. Thử lại sau ít phút."
        case .server(let status):
            "Google Drive trả về lỗi \(status)."
        case .malformedResponse:
            "Không đọc được dữ liệu Google Drive trả về."
        }
    }
}

/// Reads a link-shared Drive folder with a plain API key. No OAuth, no SDK.
///
/// Deliberately knows nothing about SwiftData: it answers questions about
/// Drive and returns plain values, which is what lets every test here run
/// against a stubbed `URLProtocol` instead of the network.
struct DriveClient {
    private let apiKey: String
    private let session: URLSession
    private static let base = "https://www.googleapis.com/drive/v3/files"

    /// The key is injected rather than read from `DriveAPIKey` inside, so tests
    /// can supply one without making the real key a mutable global that every
    /// test in the suite shares.
    init(apiKey: String = DriveAPIKey.value, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// Every audio file directly inside `folderID`.
    ///
    /// **Follows `nextPageToken` to the end.** Drive returns at most 100 files
    /// per page, so stopping at the first page turns a 300-song folder into a
    /// 100-song folder with no error anywhere — a bug that looks exactly like a
    /// smaller folder.
    func listAudioFiles(inFolder folderID: String) async throws -> [DriveFile] {
        guard !apiKey.isEmpty else { throw DriveError.missingAPIKey }

        var files: [DriveFile] = []
        var pageToken: String?

        repeat {
            let (data, response) = try await fetch(page: pageToken, folderID: folderID)
            try Self.check(response)
            let page = try Self.decodePage(data)
            files.append(contentsOf: page.files.filter { $0.mimeType.hasPrefix("audio/") })
            pageToken = page.nextPageToken
        } while pageToken != nil

        return files
    }

    /// Where the bytes of one file are. `alt=media` returns content rather than
    /// metadata, and supports the range requests `AVPlayer` streams with.
    static func mediaURL(fileID: String) -> URL {
        URL(string: "\(base)/\(fileID)?alt=media&key=\(DriveAPIKey.value)")!
    }

    private func fetch(page: String?, folderID: String) async throws -> (Data, URLResponse) {
        var components = URLComponents(string: Self.base)!
        var items = [
            URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType)"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        if let page { items.append(URLQueryItem(name: "pageToken", value: page)) }
        components.queryItems = items

        do {
            return try await session.data(from: components.url!)
        } catch {
            throw DriveError.offline
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DriveError.malformedResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw DriveError.notShared
        case 404: throw DriveError.notFound
        case 429: throw DriveError.quotaExceeded
        default: throw DriveError.server(http.statusCode)
        }
    }

    private struct Page: Decodable {
        struct Item: Decodable {
            let id: String
            let name: String
            let mimeType: String
        }
        let files: [Item]
        let nextPageToken: String?
    }

    private static func decodePage(_ data: Data) throws -> (files: [DriveFile], nextPageToken: String?) {
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            throw DriveError.malformedResponse
        }
        return (page.files.map { DriveFile(id: $0.id, name: $0.name, mimeType: $0.mimeType) },
                page.nextPageToken)
    }
}
```

`DriveAPIKey.value` stays a `let`. Every test constructs its client as
`DriveClient(apiKey: "test-key", session: StubURLProtocol.session())` — update
the test bodies above accordingly. A mutable global would have worked too and is
the wrong trade: tests share it, so one forgetting to reset it changes the
outcome of another.

Add one test for the guard itself:

```swift
    func testAnEmptyKeyIsItsOwnError() async {
        let client = DriveClient(apiKey: "", session: StubURLProtocol.session())

        await XCTAssertThrowsErrorAsync(try await client.listAudioFiles(inFolder: "F1")) { error in
            XCTAssertEqual(error as? DriveError, .missingAPIKey)
        }
    }
```

- [ ] **Step 6: Run the tests**

Expected: **142 tests — 139 passing, 3 skipped, 0 failing.**

- [ ] **Step 7: Prove pagination is really tested**

Temporarily change the `repeat`/`while` loop to run once. Re-run:
`testFollowsPaginationToTheEnd` must fail. Revert.

- [ ] **Step 8: Commit**

```bash
git add Evenstar/Evenstar/Services/DriveClient.swift Evenstar/Evenstar/Services/DriveAPIKey.swift \
        Evenstar/EvenstarTests/DriveClientTests.swift Evenstar/EvenstarTests/StubURLProtocol.swift
git commit -m "feat: read a public Drive folder with an API key"
```

---

## Task 5: `DriveLibraryService` — scanning into SwiftData

**Files:**
- Create: `Evenstar/Evenstar/Services/DriveLibraryService.swift`
- Create: `Evenstar/EvenstarTests/DriveLibraryServiceTests.swift`

**Interfaces:**
- Consumes: `DriveClient`, `DriveFile`, `DriveError` (Task 4); `DriveFolder`, `DriveTrack` (Task 2)
- Produces, for Tasks 6–8:
  - `@Observable @MainActor final class DriveLibraryService`
  - `func link(folderID: String, displayName: String) throws -> DriveFolder`
  - `func scan(_ folder: DriveFolder) async throws -> Int` — returns the number of tracks after the scan
  - `func unlink(_ folder: DriveFolder) throws`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import SwiftData
@testable import Evenstar

@MainActor
final class DriveLibraryServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func page(_ files: [(String, String)]) -> Data {
        let items = files.map { #"{"id":"\#($0.0)","name":"\#($0.1)","mimeType":"audio/mpeg"}"# }
        return Data(#"{"files":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    private func makeService() throws -> (DriveLibraryService, LibraryService) {
        let library = try InMemoryLibrary.make()
        let service = DriveLibraryService(
            library: library,
            client: DriveClient(apiKey: "test-key", session: StubURLProtocol.session())
        )
        return (service, library)
    }

    func testScanInsertsOneTrackPerAudioFile() async throws {
        let (service, library) = try makeService()
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")

        let count = try await service.scan(folder)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 2)
        XCTAssertNotNil(folder.lastScannedAt)
    }

    /// Rescanning must not duplicate. This is the behaviour a user exercises
    /// every time they pull to refresh.
    func testRescanningIsIdempotent() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]

        _ = try await service.scan(folder)

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }

    func testANewFileOnDriveAppearsOnTheNextScan() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]

        _ = try await service.scan(folder)

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 2)
    }

    /// A file deleted on Drive must stop appearing, or the user taps a row that
    /// can never play.
    func testAFileRemovedFromDriveIsRemovedLocally() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3"), ("2", "b.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]

        _ = try await service.scan(folder)

        let remaining = try library.context.fetch(FetchDescriptor<DriveTrack>())
        XCTAssertEqual(remaining.map(\.fileID), ["1"])
    }

    /// A failed scan must leave what was already there alone — otherwise one
    /// trip through a tunnel empties the list.
    func testAFailedScanKeepsTheExistingTracks() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)
        StubURLProtocol.responses = [.init(status: 403, body: Data("{}".utf8))]

        do {
            _ = try await service.scan(folder)
            XCTFail("expected the scan to throw")
        } catch {
            XCTAssertEqual(error as? DriveError, .notShared)
        }
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 1)
    }

    func testUnlinkRemovesTheFolderAndItsTracks() async throws {
        let (service, library) = try makeService()
        let folder = try service.link(folderID: "F1", displayName: "Chill mix")
        StubURLProtocol.responses = [.init(status: 200, body: page([("1", "a.mp3")]))]
        _ = try await service.scan(folder)

        try service.unlink(folder)

        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveFolder>()).count, 0)
        XCTAssertEqual(try library.context.fetch(FetchDescriptor<DriveTrack>()).count, 0)
    }
}
```

- [ ] **Step 2: Run and watch it fail**

Expected: `cannot find 'DriveLibraryService' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation
import SwiftData

/// Turns what `DriveClient` sees on Drive into rows in SwiftData.
///
/// The split matters: `DriveClient` is testable without a database and this is
/// testable without a network, and neither has to know how the other fails.
@Observable
@MainActor
final class DriveLibraryService {
    private let library: LibraryService
    private let client: DriveClient

    /// Non-nil while a scan is running, so the list can show progress. Reset in
    /// a `defer` so a thrown error cannot leave a spinner on screen forever.
    private(set) var scanningFolderID: String?
    private(set) var scannedFileCount: Int = 0

    init(library: LibraryService, client: DriveClient = DriveClient()) {
        self.library = library
        self.client = client
    }

    func link(folderID: String, displayName: String) throws -> DriveFolder {
        let folder = DriveFolder(folderID: folderID, displayName: displayName)
        library.context.insert(folder)
        try library.save()
        return folder
    }

    /// Reconciles the folder's rows with what Drive currently holds, and
    /// returns how many tracks it has afterwards.
    ///
    /// Nothing is written until the listing has arrived in full: a scan that
    /// throws leaves the existing rows exactly as they were, so losing signal
    /// mid-scan does not empty a user's list.
    @discardableResult
    func scan(_ folder: DriveFolder) async throws -> Int {
        scanningFolderID = folder.folderID
        scannedFileCount = 0
        defer { scanningFolderID = nil }

        let files = try await client.listAudioFiles(inFolder: folder.folderID)
        scannedFileCount = files.count

        let folderID = folder.folderID
        let existing = try library.context.fetch(
            FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.folderID == folderID })
        )
        let existingByFileID = Dictionary(uniqueKeysWithValues: existing.map { ($0.fileID, $0) })
        let liveFileIDs = Set(files.map(\.id))

        for file in files where existingByFileID[file.id] == nil {
            library.context.insert(
                DriveTrack(fileID: file.id, folderID: folderID, fileName: file.name)
            )
        }
        for row in existing where !liveFileIDs.contains(row.fileID) {
            library.context.delete(row)
        }

        folder.lastScannedAt = .now
        try library.save()
        return files.count
    }

    func unlink(_ folder: DriveFolder) throws {
        let folderID = folder.folderID
        let tracks = try library.context.fetch(
            FetchDescriptor<DriveTrack>(predicate: #Predicate { $0.folderID == folderID })
        )
        for track in tracks { library.context.delete(track) }
        library.context.delete(folder)
        try library.save()
    }
}
```

- [ ] **Step 4: Run the tests**

Expected: **148 tests — 145 passing, 3 skipped, 0 failing.**

- [ ] **Step 5: Prove the failure test bites**

Temporarily move the deletion loop above the `try await client.listAudioFiles`
call. Re-run: `testAFailedScanKeepsTheExistingTracks` must fail. Revert.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Services/DriveLibraryService.swift Evenstar/EvenstarTests/DriveLibraryServiceTests.swift
git commit -m "feat: scan a Drive folder into the library"
```

---

## Task 6: Streaming playback

**Files:**
- Modify: `Evenstar/Evenstar/Services/AudioPlayerProtocol.swift`
- Create: `Evenstar/Evenstar/Services/StreamingAudioPlayer.swift`
- Modify: `Evenstar/Evenstar/Services/PlaybackService.swift`
- Modify: `Evenstar/EvenstarTests/MockAudioPlayer.swift`
- Create: `Evenstar/EvenstarTests/StreamingFailureTests.swift`

**Interfaces:**
- Consumes: `Playable` (Task 3)
- Produces: `AudioPlayerProtocol.didFailCallback`, `StreamingAudioPlayer`

- [ ] **Step 1: Add the failure callback to the protocol**

In `AudioPlayerProtocol.swift`:

```swift
protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var didFinishCallback: (() -> Void)? { get set }
    /// Playback failed after loading succeeded — or failed to load at all, for
    /// players that cannot report that synchronously.
    ///
    /// **Required, not tidiness.** `AVAudioPlayer` reports a bad file by
    /// throwing from `load(url:)`, and `PlaybackService`'s skip-forward loop is
    /// built on that throw. `AVPlayer` reports failure asynchronously through
    /// `AVPlayerItem.status`, so without this an offline device would leave
    /// playback silently hung — the skip loop would never run.
    var didFailCallback: ((Error) -> Void)? { get set }

    func load(url: URL) throws
    func play()
    func pause()
}
```

Add `var didFailCallback: ((Error) -> Void)?` to `AVAudioPlayerWrapper`. It is
never called there — a local file that fails to open still throws from `load`,
so local behaviour is unchanged.

- [ ] **Step 2: Add it to `MockAudioPlayer` and give tests a way to fire it**

In `Evenstar/EvenstarTests/MockAudioPlayer.swift`:

```swift
    var didFailCallback: ((Error) -> Void)?

    /// Drives the async-failure path the way `AVPlayer` would.
    func simulateFailure(_ error: Error = URLError(.notConnectedToInternet)) {
        isPlaying = false
        didFailCallback?(error)
    }
```

- [ ] **Step 3: Write the failing test**

Create `Evenstar/EvenstarTests/StreamingFailureTests.swift`:

```swift
import XCTest
@testable import Evenstar

@MainActor
final class StreamingFailureTests: XCTestCase {

    private func makeStack() throws -> (PlaybackService, MockAudioPlayer, LibraryService) {
        let player = MockAudioPlayer()
        let library = try InMemoryLibrary.make()
        let service = PlaybackService(
            player: player, nowPlaying: MockNowPlayingPublisher(), library: library
        )
        return (service, player, library)
    }

    private func track(_ library: LibraryService, title: String) throws -> Track {
        let track = Track(
            title: title, artistName: "A", albumTitle: "B",
            durationSeconds: 100, relativePath: "Music/\(UUID().uuidString).mp3", format: "mp3"
        )
        try library.insert(track)
        return track
    }

    /// Without this, an offline device leaves the player showing a track that
    /// will never start and no way to find out why.
    func testAnAsyncFailureStopsPlaybackAndSurfacesTheError() throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        service.play(one, in: [one])
        XCTAssertTrue(service.isPlaying)

        player.simulateFailure()

        XCTAssertFalse(service.isPlaying)
        XCTAssertNotNil(service.lastPlaybackError)
    }

    /// The error must clear when something plays again, or the banner sticks
    /// around after the problem is gone.
    func testStartingAnotherTrackClearsTheError() throws {
        let (service, player, library) = try makeStack()
        let one = try track(library, title: "One")
        let two = try track(library, title: "Two")
        service.play(one, in: [one, two])
        player.simulateFailure()
        XCTAssertNotNil(service.lastPlaybackError)

        service.play(two, in: [one, two])

        XCTAssertNil(service.lastPlaybackError)
    }
}
```

- [ ] **Step 4: Handle failure in `PlaybackService`**

Add to the observable state block:

```swift
    /// The last playback failure, for the UI to show. Cleared whenever a track
    /// starts successfully.
    private(set) var lastPlaybackError: Error?
```

In `init`, beside the existing `didFinishCallback` wiring:

```swift
        self.player.didFailCallback = { [weak self] error in
            Task { @MainActor in self?.handleFailure(error) }
        }
```

And in the private section:

```swift
    /// A player that failed after `load()` returned.
    ///
    /// Deliberately does not skip to the next track: the commonest cause is no
    /// network, and skipping would march through the whole queue failing once
    /// per track. Stopping and saying why is the useful behaviour.
    private func handleFailure(_ error: Error) {
        lastPlaybackError = error
        player.pause()
        isPlaying = false
        stopPositionUpdates()
        pushNowPlaying()
    }
```

Clear it where a track successfully starts, at the end of the `autoPlay` branch
in `loadCurrentAndPlay()`:

```swift
            lastPlaybackError = nil
```

- [ ] **Step 5: Create the streaming player**

```swift
import AVFoundation
import Foundation

/// `AudioPlayerProtocol` over `AVPlayer`, for tracks that live on the network.
///
/// `AVAudioPlayer` cannot do this — it needs a complete local file. `AVPlayer`
/// streams with range requests, which is what makes playing from Drive possible
/// without downloading first.
///
/// `load(url:)` deliberately does not block or throw. `AVPlayer(url:)` returns
/// immediately and resolves the asset in the background; the duration that
/// arrives late is picked up by `PlaybackService`'s existing 0.5s timer, and a
/// failure arrives through `didFailCallback`.
final class StreamingAudioPlayer: NSObject, AudioPlayerProtocol {
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?

    var didFinishCallback: (() -> Void)?
    var didFailCallback: ((Error) -> Void)?

    var isPlaying: Bool { (player?.rate ?? 0) > 0 }

    var currentTime: TimeInterval {
        get {
            let seconds = player?.currentTime().seconds ?? 0
            return seconds.isFinite ? seconds : 0
        }
        set {
            player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
        }
    }

    /// 0 until the asset reports a real duration. `AVPlayer` returns
    /// `indefinite` — whose `seconds` is NaN — before then, and NaN reaching
    /// the scrubber's arithmetic would put the thumb somewhere undefined.
    var duration: TimeInterval {
        let seconds = player?.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    func load(url: URL) throws {
        teardown()
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error ?? URLError(.cannotLoadFromNetwork)
            self?.didFailCallback?(error)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        player = AVPlayer(playerItem: item)
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    @objc private func itemDidFinish() {
        didFinishCallback?()
    }

    private func teardown() {
        statusObservation?.invalidate()
        statusObservation = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        player?.pause()
        player = nil
    }

    deinit {
        statusObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
```

- [ ] **Step 6: Run the whole suite**

Expected: **150 tests — 147 passing, 3 skipped, 0 failing.** Every pre-existing
`PlaybackService` test must still pass.

- [ ] **Step 7: Commit**

```bash
git add Evenstar/Evenstar/Services/ Evenstar/EvenstarTests/MockAudioPlayer.swift \
        Evenstar/EvenstarTests/StreamingFailureTests.swift
git commit -m "feat: stream remote tracks with AVPlayer"
```

---

## Task 7: The source chips and the Drive list

**Files:**
- Modify: `Evenstar/Evenstar/Features/Library/SongsView.swift`
- Create: `Evenstar/Evenstar/Features/Drive/DriveSongsList.swift`
- Modify: `Evenstar/Evenstar/App/EvenstarApp.swift` (put `DriveLibraryService` in the environment)

**Interfaces:**
- Consumes: `DriveLibraryService` (Task 5), `DriveTrack` (Task 2), `PlaybackService.play(_:in:)` (Task 3)

This task has **no unit tests** — this project has no view tests and verifies
layout by screenshot. Step 4 is the verification, and it is not optional.

- [ ] **Step 1: Put `DriveLibraryService` in the environment**

In `EvenstarApp.swift`, beside where `PlaybackService` is created and injected,
create `DriveLibraryService(library: library)` and add
`.environment(driveLibrary)` alongside the existing `.environment` calls.

- [ ] **Step 2: Add the chips to `SongsView`**

Add the state and the picker, and branch `content`:

```swift
    /// Which source the list is showing. Local by default — the Drive chip is
    /// an opt-in, and a user with no linked folder should never land on an
    /// empty screen they did not ask for.
    @State private var source: LibrarySource = .local

    enum LibrarySource: String, CaseIterable {
        case local, drive
        var label: String {
            switch self {
            case .local: "Trên máy"
            case .drive: "Drive"
            }
        }
    }
```

```swift
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Picker("Nguồn", selection: $source) {
                ForEach(LibrarySource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch source {
            case .local:
                localContent
            case .drive:
                DriveSongsList(isMinimised: $isMinimised)
            }
        }
    }
```

Move the existing body of `content` into `localContent` unchanged. **Do not
alter it** — the local path must behave exactly as before.

The `＋` toolbar button keeps one meaning. Do **not** make it depend on `source`.

- [ ] **Step 3: Create `DriveSongsList`**

```swift
import SwiftUI
import SwiftData

/// The Drive half of the Bài hát tab: the four states behind the Drive chip.
struct DriveSongsList: View {
    @Environment(DriveLibraryService.self) private var driveLibrary
    @Environment(PlaybackService.self) private var playback
    @Query(sort: [SortDescriptor(\DriveFolder.linkedAt)]) private var folders: [DriveFolder]
    @Query(sort: [SortDescriptor(\DriveTrack.title, comparator: .localizedStandard)])
    private var tracks: [DriveTrack]

    @Binding var isMinimised: Bool
    @State private var showManager = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if folders.isEmpty {
                empty
            } else {
                list
            }
        }
        .sheet(isPresented: $showManager) {
            DriveFoldersView()
        }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Chưa có thư mục nào")
                .font(.title3.bold())
            // The privacy cost, stated plainly at the moment it is incurred.
            // This is a product requirement, not copy — see the spec.
            Text("Nhạc trên Drive được phát trực tiếp, không tốn dung lượng máy. Thư mục phải được chia sẻ ở chế độ “bất kỳ ai có liên kết”, nghĩa là ai có link cũng xem được.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Thêm thư mục") { showManager = true }
                .buttonStyle(.prominentAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            ForEach(tracks) { track in
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                    Text(folderName(for: track))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { playback.play(track, in: tracks) }
            }
        }
        .listStyle(.plain)
        .refreshable { await rescanAll() }
        .minimisesBottomBar($isMinimised)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showManager = true } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func folderName(for track: DriveTrack) -> String {
        folders.first { $0.folderID == track.folderID }?.displayName ?? "Drive"
    }

    private func rescanAll() async {
        errorMessage = nil
        for folder in folders {
            do {
                try await driveLibrary.scan(folder)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }
}
```

- [ ] **Step 4: Verify by screenshot — mandatory**

A clean build proves nothing here. This project has shipped seven layout
defects behind a green build, including a view that reserved its space and drew
nothing.

```bash
./run.sh "iPhone 17"
xcrun simctl io booted screenshot /tmp/warm.png   # the first shot usually catches the launch screen
xcrun simctl io booted screenshot /tmp/drive.png
```

Read `/tmp/drive.png`. Confirm: both chips render and switch; the local list is
unchanged under the local chip; the Drive chip with no folders shows the empty
state **including the sharing warning**; the `＋` button is still there and did
not change. Say in your report what you actually saw.

Note `./run.sh` performs a plain `build`, which removes the test bundle — run
`build-for-testing` again before the suite in Step 5.

- [ ] **Step 5: Rebuild and run the suite**

Expected: **150 tests — 147 passing, 3 skipped, 0 failing.** No new tests here.

- [ ] **Step 6: Commit**

```bash
git add Evenstar/Evenstar/Features/ Evenstar/Evenstar/App/EvenstarApp.swift
git commit -m "feat: source chips and the Drive list in the songs tab"
```

---

## Task 8: Folder management

**Files:**
- Create: `Evenstar/Evenstar/Features/Drive/DriveFoldersView.swift`
- Modify: `Evenstar/Evenstar/Features/Account/AccountView.swift`

**Interfaces:**
- Consumes: `DriveLinkParser` (Task 1), `DriveLibraryService` (Task 5)

One screen, two entry points — the `…` button from Task 7 and a row in
Tài khoản. Do not build a second screen for the second entry point.

- [ ] **Step 1: Create `DriveFoldersView`**

```swift
import SwiftUI
import SwiftData

/// Add, rescan and unlink Drive folders. Reached from the Drive list's `…`
/// button and from Tài khoản → Nguồn nhạc — the same screen both times.
struct DriveFoldersView: View {
    @Environment(DriveLibraryService.self) private var driveLibrary
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\DriveFolder.linkedAt)]) private var folders: [DriveFolder]

    @State private var link = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section("Thêm thư mục") {
                    TextField("Dán link thư mục Drive", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Tên hiển thị", text: $name)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Liên kết") { Task { await add() } }
                        .disabled(link.isEmpty || name.isEmpty || isWorking)
                }

                Section("Đã liên kết") {
                    if folders.isEmpty {
                        Text("Chưa có thư mục nào").foregroundStyle(.secondary)
                    }
                    ForEach(folders) { folder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName)
                            Text(folder.lastScannedAt == nil ? "Chưa quét" : "Đã quét")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                try? driveLibrary.unlink(folder)
                            } label: {
                                Label("Gỡ", systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                    Text("Thư mục phải được chia sẻ ở chế độ “bất kỳ ai có liên kết”. Nghĩa là bất kỳ ai có link đều xem được nhạc trong đó.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Thư mục Drive")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private func add() async {
        errorMessage = nil
        guard let folderID = DriveLinkParser.folderID(from: link) else {
            errorMessage = "Đây không phải link thư mục Drive. Mở thư mục trên Drive, bấm Chia sẻ và sao chép liên kết."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let folder = try driveLibrary.link(folderID: folderID, displayName: name)
            try await driveLibrary.scan(folder)
            link = ""
            name = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Add the row to `AccountView`**

Between the "Thư viện" and "Ứng dụng" sections:

```swift
                Section("Nguồn nhạc") {
                    NavigationLink("Thư mục Drive") {
                        DriveFoldersView()
                    }
                }
```

- [ ] **Step 3: Verify by screenshot — mandatory**

```bash
xcodebuild clean build-for-testing -project Evenstar/Evenstar.xcodeproj -scheme Evenstar \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "warning:|error:|BUILD"
./run.sh "iPhone 17"
xcrun simctl io booted screenshot /tmp/warm2.png
xcrun simctl io booted screenshot /tmp/folders.png
```

Read the screenshot. Confirm the management screen opens from Tài khoản, both
fields render, and the sharing warning is visible without scrolling. Then paste
a deliberately wrong link (`https://example.com/x`) and confirm the specific
error message appears rather than a generic one. Report what you saw.

- [ ] **Step 4: Rebuild and run the suite**

Expected: **150 tests — 147 passing, 3 skipped, 0 failing.**

- [ ] **Step 5: Commit**

```bash
git add Evenstar/Evenstar/Features/
git commit -m "feat: manage linked Drive folders"
```

---

## Device QA (developer, on hardware)

The simulator can list and can fail. Only a device proves playback.

1. Fill in `DriveAPIKey.value`, restrict the key to the Drive API and this bundle ID in Google Cloud Console.
2. Link a folder of 5 songs. They appear with file-name titles.
3. **Does a Drive stream's duration ever resolve? Check this first — several
   other steps below only mean something once it is answered.** Play a track and
   watch the scrubber's right-hand time label, and the lock screen's progress
   bar, for a full minute.

   The codebase currently contradicts itself about the answer, and neither side
   can be settled without hardware and a live API key. `StreamingAudioPlayer`'s
   `pendingSeek` doc comment asserts that an `alt=media` response is served
   chunked with **no `Content-Length`**, so the item reaches `.readyToPlay` with
   an *indefinite* duration and keeps it for the whole track. Step 4 below
   assumes the opposite. Do not guess which is right; observe it.

   - **A real duration appears.** The `pendingSeek` comment's premise is wrong
     for `alt=media` and should be corrected — including the reasoning it hangs
     off, which is why deferring and draining a seek both test readiness rather
     than the duration. That gate is still correct either way (readiness is the
     honest condition), but the justification would need rewriting rather than
     being left asserting something false. `PlaybackService.pushedDuration` then
     does its job: the lock screen gets the number on the first tick after it
     resolves, and its scrubber has a range.
   - **It stays `--:--` for the whole track.** The comment is right, and the
     consequence has to be written down as a shipped limitation rather than
     rediscovered: the scrubber's thumb has no range, the lock screen's
     progress bar sits at zero, and its scrubber cannot be dragged — for every
     Drive track, always. `pushedDuration` costs nothing in that case (it fires
     only when the number changes, and it never changes) but fixes nothing
     either, and the real fix would be to obtain a duration some other way —
     the deferred ID3 đợt, or a `HEAD` request for `Content-Length`.
4. Play one. It starts within a few seconds; the scrubber shows a real duration once loading finishes **if step 3 said one ever arrives**.
5. Lock the phone mid-track. Playback continues; the lock screen shows the title; next/previous work.
6. Turn on Airplane Mode mid-track. Playback stops and an error appears — it does not hang, and it does not march through the queue failing once per track.
7. Turn Airplane Mode off, play again. The error clears.
8. Link a folder with **more than 100 songs**. All of them appear, not 100.
9. Add a song to the folder on Drive, pull to refresh. It appears.
10. Delete a song on Drive, pull to refresh. It disappears.
11. **Delete a song on Drive *while it is playing*.** Playback skips to the next track rather than stopping, and the banner says the file was deleted or unshared — not "Không thể kết nối tới Google Drive", which would be false. This is the one path `DriveError.classify`'s HTTP-shaped branch cannot be verified without: the exact `NSError` domain and code AVFoundation reports for a Drive 404 is unobserved, and if it is not in the list the symptom is the old generic connection message rather than anything broken.
12. Link a folder that is *not* shared publicly. The message names link-sharing as the fix.
13. Play a Drive track, force-quit, relaunch. The session restores and the track is still current.
14. Arm repeat-all on a Drive queue and let the last track finish. It wraps.
15. Play a Drive track, then unlink its folder from Tài khoản → Nguồn nhạc while it plays. Playback moves on or stops cleanly; the app does not crash. (The crash it must not produce is `NSObjectInaccessibleException` from the queue reading a deleted row — an Objective-C exception, so it terminates the app rather than throwing.)

---

## Self-Review

**Spec coverage.** Public-folder + API key → Task 4. Link parsing → Task 1.
Models → Task 2. `Playable` → Task 3. Streaming and `didFailCallback` → Task 6.
Scanning and reconciliation → Task 5. Chips, four states, privacy warning →
Task 7. Two entry points, one management screen → Tasks 7 and 8. Errors →
Task 4's `DriveError` plus Task 6's `lastPlaybackError`. Out-of-scope items
(offline download, bulk ID3, artwork, background sync, OAuth, Drive in
Album/Artist/Search) appear in no task, correctly.

**Correction, from the whole-feature review.** This paragraph claimed coverage
it did not have. The spec's **second metadata stage** — reading a played track's
real ID3 tags over the network and setting `metadataResolved` — appears in no
task either, and unlike the list above that was not deliberate: it was simply
missed, and every per-task review passed because no task owned it. It is now
deferred to its own đợt and the spec says so explicitly, with the consequences
spelled out (every Drive track shows its file name, "Unknown Artist" and
"Unknown Album", permanently, and has no duration from metadata). See "Not in
this đợt" under Metadata in the design.

**Deliberate refinement of the spec:** `DriveTrack.durationSeconds` is a
non-optional `Double` defaulting to 0, not `Double?`. `Playable` needs a
number, and `metadataResolved` already carries "unknown". Noted in Task 2.

**Placeholders.** None: every code step carries the code, every test step the
assertions, every verification step the command and the expected output.

**Type consistency.** `DriveLinkParser.folderID(from:)`, `DriveFile`,
`DriveError`, `DriveClient.listAudioFiles(inFolder:)`,
`DriveClient.mediaURL(fileID:)`, `DriveLibraryService.link/scan/unlink`,
`Playable.playbackURL()`, `AudioPlayerProtocol.didFailCallback` and
`PlaybackService.lastPlaybackError` are spelled identically where defined and
where consumed.

**Test-count arithmetic.** 119 baseline → 124 (T1) → 128 (T2) → 133 (T3) →
142 (T4) → 148 (T5) → 150 (T6) → 150 (T7) → 150 (T8). Three skips throughout.
