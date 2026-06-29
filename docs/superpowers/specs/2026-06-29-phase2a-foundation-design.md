# Evenstar — Phase 2a (Foundation) Design Spec

**Date:** 2026-06-29
**Author/Owner:** gihubtbe1@gmail.com
**Target platform:** iOS 17.6+ (iPhone)
**Parent spec:** `docs/superpowers/specs/2026-06-29-music-app-phase1-2-design.md`
**Predecessor:** Phase 1 (Mini Player), tag `phase1-complete`

---

## 1. Context & scope

### Decomposition of Phase 2

Phase 2 of the parent spec is 4–6 weeks of work. To avoid plan staleness and motivation drops for a first-time iOS developer, Phase 2 is split into four ship-able sub-phases. Each sub-phase gets its own design spec + implementation plan + manual QA + git tag:

| Sub-phase | Scope (one-line) | This spec? |
|---|---|---|
| **2a — Foundation** | SwiftData + import + Songs list + MiniPlayerBar + auto-advance + state restore | ✅ |
| 2b — Browse | Albums grouping, Artists grouping, sort picker | ⏭ |
| 2c — Library extras | Playlists, Search, Queue editing, shuffle, repeat, prev-track | ⏭ |
| 2d — Polish + TestFlight | Interruptions, route changes, error states polish, background import, TestFlight internal | ⏭ |

### Phase 2a in one sentence

A usable local-only music app where the user imports their own `.mp3`/`.m4a`/`.flac` files, sees them in an alphabetical list with artwork thumbnails, taps to play with auto-advance through the list, and survives a kill-relaunch with the queue and position restored.

### Success criteria (definition of done)

- App passes the manual QA checklist (§8) on a real iPhone.
- All unit tests for `LibraryService`, `ImportService`, and the extended `PlaybackService` pass.
- Tag `phase2a-complete` is published.

### Non-goals (Phase 2a)

Explicitly deferred:

- Albums / Artists groupings (2b)
- Sort picker / search bar in Songs list (2b)
- Playlists, Queue sheet, shuffle, repeat, prev-track (2c)
- Long-press context menu — Play Next, Add to Queue, Add to Playlist, Show in Album (2c)
- Audio session interruption auto-resume policy refinements (2d)
- Background / non-blocking import (2d — Phase 2a uses a modal blocking sheet)
- Pull-to-refresh metadata re-scan (2d)
- TestFlight internal share (2d)
- Track metadata editing UI
- iCloud library sync, iPad layout, Mac Catalyst

---

## 2. Brainstormed decisions (record of choices)

Each row is a decision made during the 2026-06-29 brainstorming session.

| # | Topic | Decision |
|---|---|---|
| 1 | Phase 2 scope shape | Decompose into 4 sub-phases (2a–2d) |
| 2 | MiniPlayerBar in 2a? | Yes — persistent bar above no-tab-bar root |
| 3 | Queue behavior | Auto-advance through list; no shuffle/repeat in 2a |
| 4 | Import UX | Multi-select + modal progress sheet |
| 5 | Dedupe strategy | By `(title.lowercased, artist.lowercased, round(durationSeconds))` |
| 6 | Navigation shell | Single screen, no tab bar; defer `TabView` to 2b |
| 7 | State persistence | Full queue + position restored on launch (paused at exact position) |
| 8 | Songs list display | 44×44 artwork thumbnail + title + artist; sort `localizedStandardCompare` on title |
| 9 | Bundled `sample.mp3` | Remove |
| 10 | Metadata fallback | Title = filename without extension; artist/album = "Unknown Artist" / "Unknown Album" |
| 11 | Track delete UX | Swipe-trailing destructive button; no confirmation alert |
| 12 | Test target | Add Unit Testing Bundle target at start of 2a |
| 13 | Service granularity | Keep 4 separate services (`LibraryService`, `ImportService`, `PlaybackService`, `NowPlayingService`); no collapse |

---

## 3. Architecture

### Layers

```
┌──────────────────────────────────────────────────────────┐
│  UI Layer — SwiftUI                                       │
│    LibraryView (root, NavigationStack)                    │
│      List of SongRow                                      │
│      .toolbar: Import button (.plus.circle)               │
│    .safeAreaInset(.bottom): MiniPlayerBar (overlay)       │
│    .fileImporter: native multi-select Document Picker     │
│    .sheet: ImportProgressSheet (modal during import)      │
│    .fullScreenCover: NowPlayingView                       │
└──────────────────────────┬───────────────────────────────┘
                           │ observes @Observable services
┌──────────────────────────▼───────────────────────────────┐
│  Service Layer — injected via .environment(_:)           │
│    LibraryService     — ModelContext owner; Track CRUD;  │
│                         PlaybackState singleton          │
│    ImportService      — orchestrates Document Picker →   │
│                         AudioMetadataReader → file copy  │
│                         → LibraryService.insert          │
│    PlaybackService    — queue + position; persistence;   │
│                         restore (extended from Phase 1)  │
│    NowPlayingService  — Phase 1, unchanged               │
│    RemoteCommandsBridge — Phase 1, nextTrackCommand on   │
└──────────────────────────┬───────────────────────────────┘
                           │ uses
┌──────────────────────────▼───────────────────────────────┐
│  Data Layer                                              │
│    SwiftData ModelContainer(Track, PlaybackState)        │
│    FileManager: Documents/Music, Documents/Artwork       │
│    AVFoundation: AVAudioPlayer, AVAsset, AVAudioSession  │
└──────────────────────────────────────────────────────────┘
```

### Principles (carried from parent spec)

- Services are the single source of truth for live state. Views observe only.
- `PlaybackService` does **not** know SwiftData; works with `[Track]` only.
- `LibraryService` does **not** know `AVFoundation`. Communication via the `Track` model.
- Services injected via `.environment(_:)`, not global singletons.

### Project structure (delta from Phase 1)

```
Evenstar/Evenstar/
├── App/
│   ├── EvenstarApp.swift              # @main: ModelContainer + service wiring
│   └── AppEnvironment.swift           # NEW — service injection helper
├── Models/                            # NEW
│   ├── Track.swift                    # @Model
│   └── PlaybackState.swift            # @Model (single-row)
├── Services/
│   ├── AudioPlayerProtocol.swift      # Phase 1 (unchanged)
│   ├── NowPlayingService.swift        # Phase 1 (unchanged)
│   ├── RemoteCommandsBridge.swift     # Phase 1 (next-command enabled in 2a)
│   ├── PlaybackService.swift          # EXTENDED — queue, persistence, restore
│   ├── LibraryService.swift           # NEW
│   └── ImportService.swift            # NEW
├── Features/
│   ├── Library/                       # NEW
│   │   ├── LibraryView.swift
│   │   ├── SongRow.swift
│   │   └── EmptyLibraryView.swift
│   ├── Player/
│   │   ├── MiniPlayerBar.swift        # NEW
│   │   └── NowPlayingView.swift       # NEW — replaces SimplePlayerView
│   └── Import/                        # NEW
│       └── ImportProgressSheet.swift
└── Utilities/                         # NEW
    ├── AudioMetadataReader.swift      # AVAsset → TrackMetadata
    ├── FormatSupport.swift            # supported extensions whitelist
    └── FileLocation.swift             # relativePath ↔ absolute URL
```

**Removed at start of 2a:**
- `Evenstar/Evenstar/Resources/sample.mp3`
- `Evenstar/Evenstar/Features/Player/SimplePlayerView.swift`
- All hard-coded sample-track wiring in `EvenstarApp.swift`

---

## 4. Data model

### `Track`

```swift
@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String                 // ID3 title; fallback = filename without extension
    var artistName: String            // fallback = "Unknown Artist"
    var albumTitle: String            // fallback = "Unknown Album"
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double
    var relativePath: String          // "Music/<uuid>.mp3"
    var artworkRelativePath: String?  // "Artwork/<uuid>.jpg" — nil if file had no embedded artwork
    var format: String                // "mp3", "m4a", "aac", "wav", "aiff", "alac", "flac"
    var sampleRate: Int?
    var bitDepth: Int?
    var dateAdded: Date
    var playCount: Int = 0            // incremented on track finish or after 30s of playback
    var lastPlayedAt: Date?           // set on track finish or after 30s of playback
}
```

No `playlists` relationship in 2a — added in 2c when the `Playlist` model arrives.

### `PlaybackState`

```swift
@Model
final class PlaybackState {
    var currentTrackID: UUID?
    var positionSeconds: Double = 0
    var queueTrackIDs: [UUID] = []
    var queueIndex: Int = 0
    // Reserved for 2c — declared but unused in 2a:
    // var shuffleEnabled: Bool = false
    // var repeatMode: Int = 0
}
```

Singleton pattern enforced via `LibraryService.playbackState` (computed): fetch first row, or create one if none exists. All reads/writes go through this property.

### Format whitelist (`FormatSupport.swift`)

```swift
enum FormatSupport {
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "alac", "flac"
    ]
}
```

Files outside the whitelist are counted as `ImportError.unsupportedFormat` and reported in the import summary.

### Dedupe key

Tuple `(title.lowercased, artistName.lowercased, round(durationSeconds))`. Calls `LibraryService.findExistingTrack(title:artist:duration:)` before any file copy.

### File storage layout

```
Documents/
├── Music/<uuid>.<ext>
├── Artwork/<uuid>.jpg
└── default.store              # SwiftData
```

Track deletion removes both the audio file and (if present) the artwork file. Best-effort — log failures, do not block DB delete.

---

## 5. Services API

### `LibraryService`

```swift
@Observable
@MainActor
final class LibraryService {
    let context: ModelContext

    init(context: ModelContext)

    // Track CRUD
    func insert(_ track: Track) throws
    func delete(_ track: Track) throws            // also deletes Music/<uuid>.<ext> + Artwork/<uuid>.jpg
    func fetchAllTracks(sortedByTitle: Bool = true) throws -> [Track]
    func findTrack(byID id: UUID) throws -> Track?
    func findExistingTrack(title: String, artist: String, duration: Double) throws -> Track?

    // PlaybackState singleton
    var playbackState: PlaybackState { get }       // auto-create on first access
    func savePlaybackState() throws
}
```

### `ImportService`

```swift
@Observable
@MainActor
final class ImportService {
    private(set) var isImporting: Bool = false
    private(set) var progress: ImportProgress = .init(completed: 0, total: 0, lastError: nil)

    init(library: LibraryService,
         metadataReader: AudioMetadataReader,
         fileManager: FileManager = .default)

    func importFiles(at urls: [URL]) async -> ImportSummary
}

struct ImportProgress {
    let completed: Int
    let total: Int
    let lastError: ImportError?
}

struct ImportSummary {
    let imported: [Track]
    let failures: [(url: URL, error: ImportError)]
    let duplicates: [Track]   // skipped due to dedupe
}

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotReadable(URL)
    case metadataExtractionFailed
    case copyFailed(underlying: Error)
    case diskFull
}
```

Per-file algorithm inside `importFiles`:

1. Check extension is in `FormatSupport.supportedExtensions`. If not → `unsupportedFormat`.
2. `AudioMetadataReader.read(url:)` extracts title/artist/album/duration/sampleRate/bitDepth/artwork. If `AVAsset` can't decode → `metadataExtractionFailed`.
3. Compute dedupe key; `library.findExistingTrack(...)` → if exists, append to `duplicates`.
4. Generate UUID, copy file to `Documents/Music/<uuid>.<ext>` (`FileManager.copyItem(at:to:)`). On `ENOSPC` → `diskFull`, stop the whole batch and return.
5. If artwork exists, write JPEG to `Documents/Artwork/<uuid>.jpg`.
6. Build `Track`, `library.insert(track)`.
7. Append to `imported`, increment `progress.completed`.

### `PlaybackService` (extended)

Phase 1 surface preserved (`isPlaying`, `position`, `duration`, `currentMetadata`, `togglePlayPause`, `seek`). New surface:

```swift
@Observable
@MainActor
final class PlaybackService {
    // existing Phase 1 fields preserved...

    // NEW
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    var currentTrack: Track? { queue.indices.contains(queueIndex) ? queue[queueIndex] : nil }

    init(player: AudioPlayerProtocol,
         nowPlaying: NowPlayingPublisher,
         library: LibraryService)

    // NEW
    func play(_ track: Track, in queue: [Track])
    func next()
    func handleTrackDeleted(_ track: Track)
    func restoreFromPersistedState() async
}
```

Behavioral contract:

- `play(track, in: queue)` → set `queue = queue`, `queueIndex = queue.firstIndex(of: track) ?? 0`, build `TrackMetadata` from the track, call existing `load(url:metadata:)` + `play()`.
- `next()` → if `queueIndex + 1 < queue.count`: increment, load the next track, play. Otherwise: `isPlaying = false`, clear `queue` and `currentTrack`, hide `MiniPlayerBar`, call `nowPlaying.clear()`.
- `handleTrackDeleted(track)` → if `track.id == currentTrack?.id`: `next()` (or stop if last). Remove from `queue` array, adjust `queueIndex` accordingly.
- `restoreFromPersistedState()` → load `library.playbackState`. Resolve `queueTrackIDs` to `[Track]` (skip missing IDs). Set `queue`, `queueIndex`, load current track into the player, set `currentTime = positionSeconds`, keep `isPlaying = false`. Push Now Playing so the lock-screen card and `MiniPlayerBar` reflect the correct paused state.
- Persistence: throttled 5 s while playing + always on `pause()`, `seek()`, `next()`, queue change, `handleTrackDeleted`.

### `NowPlayingService` + `RemoteCommandsBridge`

Phase 1 implementations unchanged. `RemoteCommandsBridge.install()` is amended:

- `nextTrackCommand.isEnabled = true` (calls `playback.next()`).
- `previousTrackCommand.isEnabled = false` (still deferred to 2c).
- `changePlaybackPositionCommand` remains enabled.

---

## 6. UI

### `LibraryView` (root)

```
NavigationStack {
    if tracks.isEmpty {
        EmptyLibraryView(onImportTap: { showFileImporter = true })
    } else {
        List(tracks) { track in
            SongRow(track: track)
                .onTapGesture { playback.play(track, in: tracks) }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { delete(track) }
                }
        }
        .listStyle(.plain)
    }
}
.navigationTitle("Library")
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button { showFileImporter = true } label: { Image(systemName: "plus.circle") }
    }
}
.safeAreaInset(edge: .bottom) {
    if playback.currentTrack != nil {
        MiniPlayerBar(playback: playback)
            .onTapGesture { showNowPlaying = true }
    }
}
.fileImporter(
    isPresented: $showFileImporter,
    allowedContentTypes: [.audio],
    allowsMultipleSelection: true
) { result in
    if case .success(let urls) = result {
        pendingImportURLs = urls
        showImportSheet = true
    }
}
.sheet(isPresented: $showImportSheet) {
    ImportProgressSheet(urls: pendingImportURLs, importer: importService)
}
.fullScreenCover(isPresented: $showNowPlaying) {
    NowPlayingView(playback: playback)
}
```

### `SongRow`

```
HStack(spacing: 12) {
    ArtworkThumbnail(track: track, size: 44)
    VStack(alignment: .leading) {
        Text(track.title).font(.body)
        Text(track.artistName).font(.caption).foregroundStyle(.secondary)
    }
    Spacer()
}
.padding(.vertical, 4)
```

`ArtworkThumbnail` loads from `Documents/Artwork/<uuid>.jpg` via a cached `UIImage` loader (NSCache, ~50 MB cap as per parent spec §10).

### `EmptyLibraryView`

Hero illustration (SF Symbol `music.note.house` large) + heading "No music yet" + subhead "Import audio files from the Files app." + primary button "Import Music" → triggers `.fileImporter`.

### `MiniPlayerBar`

```
HStack(spacing: 12) {
    ArtworkThumbnail(track: playback.currentTrack, size: 40)
    VStack(alignment: .leading) {
        Text(currentTrack.title).font(.subheadline).lineLimit(1)
        Text(currentTrack.artistName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    Spacer()
    Button { playback.togglePlayPause() } label: {
        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title2)
    }
    Button { playback.next() } label: {
        Image(systemName: "forward.fill").font(.title3)
    }
    .disabled(playback.queueIndex >= playback.queue.count - 1)
}
.padding(.horizontal, 12)
.padding(.vertical, 8)
.background(.thinMaterial)
```

A thin `Divider()` sits above the bar to separate it from the list.

### `NowPlayingView` (replaces Phase 1 `SimplePlayerView`)

Standard iOS music-player layout:

- Toolbar leading: chevron-down to dismiss.
- Large rounded artwork (square, ~280 pt edge), or `music.note` placeholder.
- Title (bold, 2 lines max), artist · album (subhead).
- Scrubber (Phase 1 component) + elapsed / remaining labels.
- Transport row: prev (disabled), play/pause, next.
- Bottom row reserved for future (AirPlay / Queue button — added in 2c).

### `ImportProgressSheet`

A `.sheet` (modal) presented with `interactiveDismissDisabled(true)` while importing.

```
VStack {
    if importer.isImporting {
        ProgressView(value: Double(importer.progress.completed), total: Double(importer.progress.total))
        Text("Importing \(importer.progress.completed) of \(importer.progress.total)")
    } else if let summary {
        Text("Imported \(summary.imported.count).")
        if summary.duplicates.count > 0 { Text("\(summary.duplicates.count) duplicates skipped.") }
        if summary.failures.count > 0 { Text("\(summary.failures.count) failed.") }
        Button("Done") { dismiss() }
    }
}
.task { summary = await importer.importFiles(at: urls) }
```

### Empty / error states summary

| State | Shown where | UI |
|---|---|---|
| Empty library | `LibraryView` | Hero + "Import Music" CTA |
| Importing | `.sheet` (modal) | Progress bar + count |
| Import complete | `.sheet` (modal) | Summary with imported / duplicates / failed counts |
| Disk full during import | `.alert` after sheet dismisses | "Storage full" + suggest cleanup |
| Track delete failure | `.alert` | "Couldn't delete" + reason; track remains visible |
| Restore failure on launch | Silent (log + clear state) | App still launches; library appears empty-of-queue |

---

## 7. Key user flows

### Flow 1 — First launch (empty library) → import

1. `EvenstarApp.init` creates `ModelContainer`, services. `RemoteCommandsBridge.install()`.
2. `LibraryView.task` awaits `playback.restoreFromPersistedState()` (queue is empty → no-op).
3. Body: `@Query` returns `[]`. Renders `EmptyLibraryView`.
4. User taps "Import Music" → `.fileImporter` opens.
5. User selects N files in Files app. `pendingImportURLs = urls`, `showImportSheet = true`.
6. `ImportProgressSheet` mounts, calls `importService.importFiles(at: urls)`.
7. Sheet observes `importer.progress` — bar advances per file.
8. On completion, sheet shows `ImportSummary`. User taps Done → dismiss.
9. `@Query` auto-refreshes → tracks render in the list.

### Flow 2 — Tap song → play → MiniPlayerBar → NowPlayingView

1. `SongRow.onTapGesture` → `playback.play(track, in: tracks)`.
2. `PlaybackService.play(_:in:)` sets queue + index, loads URL, activates session, calls `player.play()`, pushes Now Playing, schedules throttled persist.
3. `MiniPlayerBar` becomes visible (currentTrack is non-nil) at the bottom.
4. User taps the bar → `showNowPlaying = true` → `.fullScreenCover` opens.
5. `NowPlayingView` shares the same `PlaybackService` instance — scrubber, play/pause, next all bound.

### Flow 3 — Track ends → auto-advance

1. `AVAudioPlayer.audioPlayerDidFinishPlaying` triggers `PlaybackService.handleFinish`.
2. If `queueIndex + 1 < queue.count`: `next()` (load next track, play).
3. Else: `isPlaying = false`, clear `currentTrack`, `MiniPlayerBar` hides. `nowPlaying.clear()`. `persistStateThrottled()`.

### Flow 4 — Swipe-trailing delete

1. `SongRow.swipeActions(.trailing)` → `Button(role: .destructive)`.
2. Inside: if `track.id == playback.currentTrack?.id`, call `playback.handleTrackDeleted(track)` (advances or stops).
3. `library.delete(track)` removes audio + artwork files from disk, `context.delete`, `context.save`.
4. `@Query` auto-refreshes; row disappears.

### Flow 5 — Kill app → relaunch (state restore)

1. `EvenstarApp.init` creates services with empty `PlaybackService.queue`.
2. `LibraryView.task` calls `await playback.restoreFromPersistedState()`.
3. Service loads `PlaybackState`, resolves `queueTrackIDs` to `[Track]` (skipping missing), populates `queue` + `queueIndex`, calls `player.load(url:)` for the current track, sets `player.currentTime = positionSeconds`, calls `pushNowPlaying()`.
4. `isPlaying = false` (we never auto-play after a cold launch).
5. `MiniPlayerBar` becomes visible in the paused state at the saved position.
6. User taps play to resume.

### Concurrency

- `LibraryService`, `ImportService`, `PlaybackService` are `@MainActor`.
- Inside `ImportService.importFiles` the heavy work — file copy via `FileManager.copyItem`, AVAsset metadata extraction — runs as `async` operations whose work happens on the cooperative pool; each track insert hops back to the MainActor via the `LibraryService` reference.
- `Timer` for position polling stays on the main run loop.

---

## 8. Error handling

### Categories

| Category | Examples (2a) | Strategy |
|---|---|---|
| User-content | Corrupt mp3, unsupported format, missing metadata | Skip file, count in `ImportSummary.failures`, show in summary alert. Never crash. |
| Transient | Audio session interruption (Phase 1 covers), brief disk write failure | Retry once silently; surface only on second failure. |
| Programmer | Force-unwrap, index-out-of-bounds | `precondition` / `assertionFailure` (debug crash, release fail-safe). |
| System resource | Disk full during copy | Stop the batch, surface "Storage full" alert with imported-count, suggest cleanup. |

### Typed error pattern

```swift
enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotReadable(URL)
    case metadataExtractionFailed
    case copyFailed(underlying: Error)
    case diskFull
}

enum LibraryError: LocalizedError {
    case persistenceFailed(underlying: Error)
    case fileDeleteFailed(URL, underlying: Error)
}
```

### Rules (enforced via code review)

- No `try!` in production code.
- No silent `catch { }`.
- No crash on user-content input.
- Every alert / toast has an explicit dismiss button.

---

## 9. Testing

### Scope

| Layer | Tested? | Notes |
|---|---|---|
| `LibraryService` | ✅ Unit | In-memory `ModelContext`. Cover insert/delete/dedupe/PlaybackState singleton. |
| `ImportService` | ✅ Unit | Mock `AudioMetadataReader` + `FileManager`. Cover unsupported-format, dedupe-skip, copy-failed, disk-full, happy path. |
| `PlaybackService` extensions | ✅ Unit | Reuse `MockAudioPlayer` + `MockNowPlayingPublisher` from Phase 1. Add: queue auto-advance, last-track-stop, `handleTrackDeleted`, restore-from-state. |
| `Track`, `PlaybackState` models | ✅ Light | Verify `@Query` predicates and relationships. |
| SwiftUI views | ❌ Skip | Cost prohibitive for a first iOS project. |
| `AVAudioPlayer` / `AVAsset` integration | ❌ Skip | Covered by manual QA. |

### Test target setup (one-time at start of 2a)

In Xcode: **File → New → Target → Unit Testing Bundle**, name `EvenstarTests`, target = `Evenstar`. Drag in existing Phase 1 test files (`MockAudioPlayer.swift`, `PlaybackServiceTests.swift`). Add `LibraryServiceTests.swift`, `ImportServiceTests.swift`, `PlaybackServiceQueueTests.swift`, `PlaybackServiceRestoreTests.swift`.

### In-memory SwiftData helper

```swift
@MainActor func makeInMemoryLibrary() throws -> LibraryService {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Track.self, PlaybackState.self,
        configurations: config
    )
    return LibraryService(context: ModelContext(container))
}
```

### Manual QA checklist (must pass on a real iPhone before tagging `phase2a-complete`)

- [ ] First launch shows the `EmptyLibraryView` with an Import CTA.
- [ ] Tap Import → Files app opens → multi-select 5 mp3s → progress sheet runs → "Imported 5".
- [ ] Re-import the same 5 files → "0 imported, 5 duplicates skipped".
- [ ] Import a single `.txt` file → "0 imported, 1 failed (unsupported format)".
- [ ] Songs list renders 5 rows with thumbnails, sorted alphabetically by title.
- [ ] Tap a song → `MiniPlayerBar` appears at the bottom, audio plays.
- [ ] Tap `MiniPlayerBar` → `NowPlayingView` opens fullscreen; scrubber and play/pause work.
- [ ] Let a track end → next track in the list plays automatically.
- [ ] Reach the last track and let it finish → `MiniPlayerBar` hides; lock-screen Now Playing clears.
- [ ] Swipe-trailing on the currently playing row → Delete → playback advances to the next track; the deleted row disappears; its files in `Documents/Music/` and `Documents/Artwork/` are gone.
- [ ] Lock the device while playing → lock-screen still shows title / artist / album / artwork / scrubber and accepts play/pause/next (Phase 1 capability preserved).
- [ ] Kill the app from the App Switcher → relaunch → `MiniPlayerBar` shows the last-played track, paused, scrubber at the saved position. Tap play → audio resumes from that exact position.
- [ ] Delete the currently-playing track via swipe → playback advances; relaunch the app → state restore handles the missing track gracefully (skips it; queue shrinks).

---

## 10. Open questions revisited at end of 2a

- Should Albums grouping (2b) use the parent spec's denormalized aggregation via `@Query` grouping, or should we introduce a normalized `Album` entity? Decide after seeing how 1k–5k tracks scroll in the Songs list.
- Should `NowPlayingView` get an AirPlay button row at the bottom (`AVRoutePickerView` wrapped via `UIViewRepresentable`)? Cheap to add; decide based on whether the user actually uses AirPlay in real testing.

---

## 11. Estimate

~1.5 weeks at 12 h / week (decided in brainstorm Q1 + Q11). The +12% bump from Q6's "full queue restore" was absorbed into this estimate.

Breakdown (refined in the implementation plan):

| Day | Task |
|---|---|
| 1 | Add Unit Testing Bundle target; write `Track` + `PlaybackState` models; `LibraryService` CRUD + tests. |
| 2 | `AudioMetadataReader` (AVAsset); `ImportService` skeleton + dedupe + tests. |
| 3 | `ImportService` file copy + artwork extraction + error paths + tests. |
| 4 | `LibraryView` + `SongRow` + `EmptyLibraryView` + `.fileImporter`. |
| 5 | `ImportProgressSheet` wired end-to-end. |
| 6 | Extend `PlaybackService` queue + `play(_:in:)` + `next()` + tests. |
| 7 | `MiniPlayerBar` + `.safeAreaInset` integration; `NowPlayingView` replaces `SimplePlayerView`. |
| 8 | Persistence (throttled save) + `restoreFromPersistedState()` + tests. |
| 9 | Track delete flow + `handleTrackDeleted` + tests. |
| 10 | Manual QA pass on iPhone; bug fixes; tag `phase2a-complete`. |

10 working days ≈ 1.5 weeks at 12 h / week with slack.
