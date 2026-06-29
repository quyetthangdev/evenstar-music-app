# Music App — Phase 1 & 2 Design Spec

**Date:** 2026-06-29
**Scope:** Mini player (Phase 1) + Local files v0 (Phase 2)
**Author/Owner:** gihubtbe1@gmail.com
**Target platform:** iOS 17.2+ (iPhone)

---

## 1. Context & goals

### Long-term vision

A native iOS music app that combines a user's local music library with one or more streaming services (Apple Music in Phase 3, possibly Spotify in a later v2.x). Distributed via the App Store. Built as a learning project that should also be commercially viable in the longer term.

### Scope of this spec

This spec covers **only Phase 1 and Phase 2** of the roadmap:

- **Phase 1: Mini player** — a single-screen SwiftUI app that plays one hard-coded audio file with lock-screen integration. Purpose: learn the foundations (SwiftUI, `AVAudioPlayer`, audio session, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`).
- **Phase 2: v0 Local files** — a usable local-only music app: import audio files via the Files app, browse by song / album / artist, manage playlists, search, queue, with full background audio and CarPlay Now-Playing support.

Apple Music integration, Spotify, smart playlists, lyrics, EQ/gapless, iPad-optimized layout, iCloud sync, and CarPlay full UI are **out of scope** for this spec and will be addressed in later specs (Phase 3+).

### Success criteria

- Phase 1: a real iPhone plays a bundled mp3 with working lock-screen controls.
- Phase 2: usable for daily listening to a personal library of 1k–5k tracks, ready for internal TestFlight with friends.
- Code structure is modern enough to evolve into Phase 3+ without rewrites.

### Non-goals (Phase 1 + 2)

- No Apple Music / Spotify / YouTube Music integration.
- No EQ, ReplayGain, true gapless playback, crossfade.
- No CarPlay UI (only Now-Playing card via standard `MPNowPlayingInfoCenter`).
- No iPad-specific layout, no Mac Catalyst.
- No iCloud library sync.
- No smart playlists, recommendations, Last.fm scrobbling.
- No localization (English only).
- No subscription / IAP.

---

## 2. Approach & tech stack

**Approach: "Modern Minimal"** — the SwiftUI + `@Observable` + SwiftData + `AVAudioPlayer` stack. Chosen for:

1. Minimum new concepts for a first-time Swift developer (consistent modern idioms).
2. Significantly less boilerplate than `ObservableObject` + Core Data.
3. Sufficient audio quality for ~95% of users; audio engine can be swapped to `AVAudioEngine` later without disturbing the service layer.
4. Modern patterns will remain idiomatic for 5+ years.

### Stack summary

| Concern | Choice |
|---|---|
| Min iOS version | 17.2 (SwiftData stability) |
| UI framework | SwiftUI |
| State management | `@Observable` macro |
| Persistence | SwiftData |
| Audio engine (v0) | `AVAudioPlayer` (one player instance) |
| File import | `UIDocumentPickerViewController` + iCloud Drive via `LSSupportsOpeningDocumentsInPlace` |
| File storage | Copy into app sandbox (`Documents/Music/<uuid>.<ext>`) |
| Background audio | `UIBackgroundModes=audio` + `AVAudioSession.Category.playback` |
| Lock screen | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` |
| CarPlay | Now-Playing card only (no entitlement, no custom CarPlay UI) |
| Tests | XCTest, in-memory SwiftData, protocol-mocked audio player |

### Trade-offs accepted

- iOS 16 and the first two point releases of iOS 17 are excluded (~10–12 % of users in mid-2026).
- `AVAudioPlayer` does not provide true gapless playback (~50–200 ms gap between tracks).
- No security-scoped bookmark; we copy files (uses extra disk).

---

## 3. Architecture

### Layers

```
┌───────────────────────────────────────────────────┐
│  UI Layer — SwiftUI Views + lightweight VMs       │
│   LibraryView, NowPlayingView, MiniPlayerBar,     │
│   PlaylistsView, SearchView, ImportView           │
└────────────────────┬──────────────────────────────┘
                     │ observes
┌────────────────────▼──────────────────────────────┐
│  Service Layer — @Observable, injected via env    │
│   PlaybackService     – audio + queue + state     │
│   LibraryService      – CRUD on Track/Playlist    │
│   ImportService       – file copy + metadata      │
│   NowPlayingService   – lock-screen integration   │
└────────────────────┬──────────────────────────────┘
                     │ uses
┌────────────────────▼──────────────────────────────┐
│  Data Layer                                       │
│   SwiftData (Track, Playlist, PlaybackState)      │
│   FileManager (Documents/Music, Documents/Artwork)│
│   AVFoundation (AVAudioPlayer, AVAsset, session)  │
└───────────────────────────────────────────────────┘
```

### Principles

- Services are the single source of truth for live state (`currentTrack`, `queue`, `isPlaying`). Views only observe.
- Each service has one responsibility. `PlaybackService` does not know SwiftData; `LibraryService` does not know `AVFoundation`. They communicate through the `Track` model only.
- Services are injected via SwiftUI `.environment(_:)` rather than global singletons, which keeps unit tests clean.
- No Clean-Architecture-style use-cases, no TCA, no SPM modules at this stage. They are explicitly deferred until app complexity warrants them.

### Project structure

```
MusicApp/
├── App/
│   ├── MusicAppApp.swift          # @main, sets up ModelContainer + services
│   └── AppEnvironment.swift       # wires services into SwiftUI environment
├── Models/
│   ├── Track.swift                # @Model
│   ├── Playlist.swift             # @Model
│   └── PlaybackState.swift        # @Model (singleton row)
├── Services/
│   ├── PlaybackService.swift
│   ├── LibraryService.swift
│   ├── ImportService.swift
│   ├── NowPlayingService.swift
│   └── AudioPlayerProtocol.swift  # + AVAudioPlayerWrapper
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift
│   │   ├── SongListView.swift
│   │   ├── AlbumGridView.swift
│   │   ├── AlbumDetailView.swift
│   │   ├── ArtistListView.swift
│   │   └── ArtistDetailView.swift
│   ├── Player/
│   │   ├── NowPlayingView.swift
│   │   ├── MiniPlayerBar.swift
│   │   └── QueueView.swift
│   ├── Playlists/
│   │   ├── PlaylistsView.swift
│   │   └── PlaylistDetailView.swift
│   ├── Search/
│   │   └── SearchView.swift
│   ├── Import/
│   │   └── ImportView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Utilities/
│   ├── AudioMetadataReader.swift  # AVMetadataItem helpers
│   ├── FormatSupport.swift        # supported file extensions
│   └── FileLocation.swift         # relativePath ↔ absolute URL
└── Resources/
    └── Assets.xcassets
```

---

## 4. Data model

### SwiftData models

```swift
@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artistName: String                // denormalized
    var albumTitle: String                // denormalized
    var trackNumber: Int?
    var discNumber: Int?
    var durationSeconds: Double
    var relativePath: String              // "Music/<uuid>.mp3"
    var artworkRelativePath: String?      // "Artwork/<uuid>.jpg"
    var format: String                    // "mp3", "m4a", "flac"...
    var sampleRate: Int?
    var bitDepth: Int?
    var dateAdded: Date
    var playCount: Int = 0
    var lastPlayedAt: Date?

    @Relationship(inverse: \Playlist.tracks)
    var playlists: [Playlist] = []
}

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var dateCreated: Date
    var trackOrder: [UUID]                // explicit order — see note below
    @Relationship var tracks: [Track] = []
}

@Model
final class PlaybackState {
    // Single-row table — see note below
    var currentTrackID: UUID?
    var positionSeconds: Double = 0
    var queueTrackIDs: [UUID] = []
    var queueIndex: Int = 0
    var shuffleEnabled: Bool = false
    var repeatMode: Int = 0               // 0=off, 1=all, 2=one
}
```

### Modeling decisions

- **No separate `Artist` / `Album` entities.** Artist name and album title live denormalized on `Track`. "Artists" and "Albums" views are aggregations via SwiftData `@Query` grouping. Reasons:
  - Avoids sync issues when a user retags a track (do we update the entity or create a new one?).
  - Local libraries are small enough that aggregation is fast.
  - We can normalize later if we need per-artist artwork or bio.
- **`relativePath` instead of `URL`.** App sandbox absolute paths change between launches. We resolve to an absolute URL at playback time.
- **`PlaybackState` as a single-row table.** SwiftData has no native "singleton" concept, so `LibraryService` enforces this at runtime: on first access, fetch the only `PlaybackState` row, or create one if none exists. All reads/writes go through `LibraryService.playbackState`.
- **`Playlist.trackOrder` is the authoritative order.** SwiftData `@Relationship` arrays are unordered sets, so we maintain an explicit `[UUID]` ordering and resolve to `Track` objects when rendering. The `tracks` relationship exists so SwiftData can manage inverse links and delete propagation; `trackOrder` decides display order. `LibraryService` mutates both atomically.

### File storage layout

```
Documents/
├── Music/
│   ├── <uuid1>.mp3
│   └── <uuid2>.flac
├── Artwork/
│   ├── <uuid1>.jpg
│   └── <uuid2>.jpg
└── default.store  (SwiftData)
```

Import copies the source file into `Documents/Music/<uuid>.<ext>` and writes extracted artwork to `Documents/Artwork/<uuid>.jpg`. On track deletion, both files are removed.

### Supported formats (Phase 2)

Via native `AVFoundation`: **mp3, AAC (.m4a), ALAC, WAV, AIFF, FLAC**. OGG Vorbis and OPUS are explicitly deferred.

---

## 5. Playback

### `PlaybackService`

```swift
@Observable
final class PlaybackService {
    private(set) var currentTrack: Track?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0
    var shuffleEnabled: Bool = false
    var repeatMode: RepeatMode = .off

    private var player: AudioPlayerProtocol
    private var positionTimer: Timer?
    private let nowPlayingService: NowPlayingService
    private let libraryService: LibraryService   // used to persist PlaybackState

    func play(_ track: Track, from queue: [Track]? = nil) async
    func togglePlayPause()
    func next()
    func previous()
    func seek(to position: TimeInterval)
    func setQueue(_ tracks: [Track], startIndex: Int)
    func restoreFromPersistedState() async       // called once on app launch
}

enum RepeatMode { case off, all, one }
```

`PlaybackService` does not own a separate `PlaybackStateStore` — it reads and writes the single `PlaybackState` row via `LibraryService` (which owns the `ModelContext`). This keeps persistence centralized in one service.

### Playback lifecycle (single track)

```
View → playbackService.play(track)
  → resolve absolute URL from track.relativePath
  → configure AVAudioSession (.playback, .default), activate
  → load via AudioPlayerProtocol.load(url:)
  → start positionTimer (0.5 s tick)
  → nowPlayingService.update(track, position, isPlaying: true)
  → libraryService.savePlaybackState (throttled: every 5 s + on pause / track change)
  → on didFinishCallback → next()
```

### Audio session

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default, options: [])
try session.setActive(true)
```

- `.playback` category allows background audio and ignores the silent switch (correct behavior for a music app).
- `UIBackgroundModes=audio` in `Info.plist`.

### Interruption & route changes

Subscribe to `AVAudioSession.interruptionNotification` and `routeChangeNotification`:

- `interruption.began` → pause.
- `interruption.ended` with `.shouldResume` option → resume.
- Route change to a less-capable output (e.g., headphone unplug, BT disconnect) → pause. This is the standard iOS UX.

### Lock screen & remote commands

```swift
final class NowPlayingService {
    func update(track: Track, position: TimeInterval, isPlaying: Bool)
}
```

Sets `MPNowPlayingInfoCenter.default().nowPlayingInfo` with: title, artist, album, duration, elapsed time, playback rate, artwork (`MPMediaItemArtwork`). Called on track change, play/pause, and seek — not on every tick (the system extrapolates).

`MPRemoteCommandCenter` is wired once at app launch for: `play`, `pause`, `togglePlayPause`, `nextTrack`, `previousTrack`, `changePlaybackPosition`. These commands also drive headphone clicks, Bluetooth controls, and the CarPlay Now-Playing card.

### CarPlay scope

- **Phase 2:** Now-Playing card only. No entitlement required; works automatically once `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` are wired.
- **Out of scope:** custom CarPlay UI (`CPTemplateApplicationSceneDelegate`, `com.apple.developer.carplay-audio` entitlement). Deferred to Phase 3 or later.

---

## 6. UI structure

### Navigation skeleton

```
RootView (TabView)
├── LibraryTab (NavigationStack)
│   └── LibraryView
│       picker: Songs | Albums | Artists
│       Songs → SongListView → tap = play
│       Albums → AlbumGridView → AlbumDetailView
│       Artists → ArtistListView → ArtistDetailView
├── PlaylistsTab (NavigationStack)
│   └── PlaylistsView
│       ├── "+" New Playlist
│       └── PlaylistDetailView (reorderable)
└── SearchTab (NavigationStack)
    └── SearchView (.searchable, live results)

[Persistent overlay above tab bar: MiniPlayerBar]
  tap → NowPlayingView (.fullScreenCover)
    "Queue" → QueueView (.sheet)
```

Three tabs. Settings is reached via a toolbar gear icon on `LibraryView` — a dedicated Settings tab isn't worth the space at v0.

### MiniPlayerBar

A persistent bar above the tab bar, visible whenever `playbackService.currentTrack != nil`. Shows artwork thumbnail, title, play/pause, next. Tapping expands to `NowPlayingView`. A matched-geometry transition is a polish item for v1.x; v0 uses the default `.fullScreenCover` transition.

### NowPlayingView layout

Standard iOS music-player layout: large rounded artwork, title (bold), artist · album, scrubber with elapsed / remaining time, transport row (shuffle, prev, play/pause, next, repeat), AirPlay button (`AVRoutePickerView` wrapped via `UIViewRepresentable`), and Queue button.

### Empty & error states

| State | UI |
|---|---|
| Empty library | Hero illustration + "Tap to import music" → Document Picker |
| Import in progress | Progress bar + "Importing X of Y" |
| Import failures | Toast/alert summarizing fail count and reasons |
| No search results | "No results for '<query>'" |
| Empty playlist | Affordance to add songs |

### Common interactions

| Gesture | Action |
|---|---|
| Tap song in a list | Play, with the list as the new queue |
| Long-press / context menu | Play Next, Add to Queue, Add to Playlist, Show in Album/Artist, Delete |
| Swipe-leading on song | Queue Next |
| Swipe-trailing on song | Delete (with confirm if in any playlist) |
| Pull-to-refresh library | Re-scan metadata |
| Drag-to-reorder in playlist | SwiftUI `.onMove` |

### Search

`.searchable` modifier with live filtering against `title`, `artistName`, `albumTitle` using `localizedCaseInsensitiveContains`. Results grouped into Tracks / Albums / Artists. No fuzzy matching in v0.

### iPad / Mac

Phone-first only. iPad will run with the phone layout scaled; native iPad layout is deferred.

---

## 7. Error handling

### Error categories

| Category | Examples | Strategy |
|---|---|---|
| User-content | Corrupt file, unsupported format, missing permission | Alert/toast with clear reason; never crash |
| Transient | Audio session interruption, briefly missing file | Auto-recover or retry silently |
| Programmer | Force-unwrap, index out of bounds | `precondition` / `fatalError` in debug; in release, fail gracefully |
| System resource | Disk full, memory pressure | Meaningful message; suggest cleanup |

### Error type pattern

```swift
enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotReadable(URL)
    case metadataExtractionFailed
    case diskFull
    case duplicateTrack(Track)

    var errorDescription: String? { ... }
}
```

`ImportService` throws typed errors. `ImportViewModel` accumulates errors across a batch and presents a single summary at the end ("Imported X of Y. Z failed: …"), avoiding per-file alert spam.

### Rules

- No `try!` in production code.
- No silent `catch { }`.
- Never crash on user-content input.

---

## 8. Testing

### Scope for v0

| Layer | Tested? | Why |
|---|---|---|
| Services (`PlaybackService`, `LibraryService`, `ImportService`) | ✅ Unit | Core logic; high value; easy to isolate with protocol-mocked audio |
| SwiftData models | ✅ Light unit | Verify queries, relationships |
| SwiftUI views | ❌ Skip | Snapshot/UI tests too costly/flaky as a first iOS project |
| `AVAudioPlayer` integration | ❌ Skip | Manual QA covers this faster |

### Testability via protocol

```swift
protocol AudioPlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    func load(url: URL) throws
    func play()
    func pause()
    var didFinishCallback: (() -> Void)? { get set }
}
```

`PlaybackService` receives an `AudioPlayerProtocol` via init, so unit tests can drive a `MockAudioPlayer` to verify queue logic, auto-advance, shuffle, and repeat-mode behavior without playing any actual audio.

### SwiftData in-memory setup

```swift
func makeInMemoryContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Track.self, Playlist.self, PlaybackState.self,
        configurations: config
    )
    return ModelContext(container)
}
```

### Manual QA checklist (end of Phase 2)

- [ ] Import 10 mp3s — all appear with correct metadata + artwork.
- [ ] Import an unsupported file — alert shown, app does not crash.
- [ ] Play → lock device → playback continues; lock screen shows artwork + controls.
- [ ] Play → incoming phone call → audio pauses → on hang-up → audio resumes.
- [ ] Play → unplug Bluetooth headphones → audio pauses.
- [ ] Play → AirPlay to HomePod → audio transfers cleanly.
- [ ] Quit app → relaunch → queue and position restored.
- [ ] Connect to CarPlay → Now-Playing card visible.
- [ ] Delete a track → both `Music/<uuid>.<ext>` and `Artwork/<uuid>.jpg` removed.
- [ ] Import a batch of 100 files — progress bar updates, UI does not freeze.

---

## 9. Milestones

Estimates assume ~12 h/week of focused work.

### Phase 1 — Mini player (1–2 weeks)

| ID | Task | Output |
|---|---|---|
| M1.1 | Xcode project + run on device | Hello World on real iPhone |
| M1.2 | Bundle an mp3 + simple `AudioPlayer` wrapper + play/pause button | Plays a file in the app |
| M1.3 | Configure `AVAudioSession`, add `UIBackgroundModes=audio` | Audio continues with screen locked |
| M1.4 | `NowPlayingService` + `MPRemoteCommandCenter` | Lock-screen metadata + controls work |
| M1.5 | Position display + scrubber | Slider seeks; lock-screen scrub works |

End of Phase 1: foundational understanding of SwiftUI, `@Observable`, `AVAudioPlayer`, audio session, lock-screen integration.

### Phase 2 — v0 Local files (4–6 weeks)

| ID | Task | Output |
|---|---|---|
| M2.1 | SwiftData models + `LibraryService` CRUD | Programmatically create/delete tracks |
| M2.2 | `ImportService`: Document Picker, sandbox copy, metadata via `AVAsset` | Pick a file in Files → it appears in DB |
| M2.3 | `LibraryView` + `SongListView` with `@Query` | Songs list; tap to play |
| M2.4 | Albums grouping + AlbumDetailView, Artists grouping + ArtistDetailView | Browse by album/artist |
| M2.5 | `MiniPlayerBar` + `NowPlayingView` full-screen | Complete player UI |
| M2.6 | `Playlist` CRUD + Playlists tab + reorder | Create and manage playlists |
| M2.7 | Search with `.searchable` | Working search |
| M2.8 | Queue UI (sheet, reorder, remove) | View & edit current queue |
| M2.9 | Edge cases: interruption, route change, empty states, error alerts | App passes manual QA checklist |
| M2.10 | TestFlight internal — share with 2–3 friends | Real-user feedback |

End of Phase 2: app is usable for daily listening with a 1k–5k track library, ready for internal TestFlight. Natural point to start a separate spec for Phase 3 (Apple Music integration).

---

## 10. Non-functional guardrails

- **Memory:** Artwork loaded on demand; cap an in-memory cache at ~50 MB via `NSCache`.
- **Battery:** `Timer` at 0.5 s for position updates is sufficient — no `CADisplayLink`.
- **Startup time:** SwiftData lazy-loads; do not scan the library at launch.
- **Large libraries:** v0 targets 1k–5k tracks. >10k tracks will require paginated `@Query` predicates in v2.x.

---

## 11. Open questions to revisit before Phase 2 starts

- Final app name and bundle identifier (placeholder: `MusicApp` / `com.user.MusicApp`).
- Apple Developer Program enrollment ($99/year) needed before TestFlight (M2.10). Confirm enrollment timing.
- Whether to add a basic UI tests target now (probably no, but defer the decision until after Phase 1).

---

## Appendix A — Learning resources

- [Apple Swift Tour](https://docs.swift.org/swift-book/) — one-evening read.
- [100 Days of SwiftUI (Paul Hudson)](https://www.hackingwithswift.com/100/swiftui) — free; coming from RN, skip ahead to day 16 for SwiftUI.
- WWDC sessions: search "MusicKit", "AVFoundation", "SwiftUI Essentials", "SwiftData", "Observation".
- Kodeco's *SwiftUI by Tutorials* (optional, paid).
