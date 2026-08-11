# Evenstar — Apple framework / HIG conformance audit

Scope: full sweep of `Evenstar/Evenstar/` (App, Features, Services, Models, Utilities). Read-only; no build, no edits.

Overall impression: this is an unusually careful SwiftUI codebase. `@Observable` is used exclusively (no `ObservableObject`/`@Published` anywhere), every `onChange(of:)` call uses the modern two-parameter form, haptics go through `.sensoryFeedback` rather than raw `UIImpactFeedbackGenerator`, `GeometryReader` is only reached for where an actual reader is needed (not as a `onGeometryChange` substitute), settings use `List`/`Section`/`.pickerStyle(.navigationLink)` the way Apple's own Settings app does, and the localization plumbing (`AppLanguage.resolvedBundle`/`resolvedLocale`, `String(localized:bundle:locale:)` threaded everywhere, `Text("\(n) bài...")` correctly relying on `LocalizedStringKey`'s format-specifier interpolation rather than producing per-value catalogue spam) is more disciplined than most production apps. The gaps that exist are concentrated, not systemic.

---

## Findings, ranked by user-visible consequence

### 1. No `AVAudioSession` interruption or route-change handling anywhere — a phone call can silently kill playback for the rest of the session
**Files:** `Services/PlaybackService.swift` (session activation lives at lines 1205–1215), whole-project grep for `AVAudioSession.interruptionNotification` / `routeChangeNotification` / `AVAudioSession.Interruption` / `AVAudioSession.RouteChange` returns zero hits in the entire repository.

The convention: a `.playback` category audio app must observe `AVAudioSession.interruptionNotification` to react to `.began` (pause, update UI) and `.ended` (check `AVAudioSessionInterruptionOptions.shouldResume` and reactivate/resume), and should observe `routeChangeNotification` to pause on `.oldDeviceUnavailable` (headphones/Bluetooth disconnected) — otherwise audio keeps blasting out of the speaker in a pocket or a quiet room, which App Review and the HIG both call out explicitly for audio apps.

What the code does instead: `activateSessionIfNeeded()` sets `AVAudioSession.sharedInstance().setCategory(.playback, ...)` and `setActive(true)` exactly once, gated by `private var sessionActivated: Bool = false` (line 102) that is set `true` at line 1211 and **never reset anywhere in the file** (confirmed: only two references to `sessionActivated` in the whole class). Nothing observes interruptions or route changes.

What breaks in practice: a phone call arrives → iOS interrupts and deactivates the session out from under the app → the app is never told, so `isPlaying`/the lock-screen glyph/the UI still claim playback is live. When the call ends, iOS does not resume playback for you (that's the app's job, on `.ended`/`shouldResume`), and because `sessionActivated` is already `true`, `resume()`'s guard `guard !sessionActivated else { return }` means `setActive(true)` is never called again — the session was torn down by the OS but the flag lies about it. Tapping play calls `player.play()` against a possibly-inactive session and can produce silence or an audibly broken resume. The same class of bug applies to unplugging headphones mid-track: nothing pauses, so the track keeps playing out loud through the speaker until the user notices.

This is the single most consequential finding given the app's purpose — it is exactly the "survives a phone call" bar named in the task, and currently the app does not clear it.

### 2. Primary transport controls have no `accessibilityLabel` — VoiceOver reads raw English SF Symbol names in an otherwise fully Vietnamese-localized app
**Files:** `Features/Player/NowPlayingContent.swift` (transport row, ~lines 296–343: `backward.fill`, `play.fill`/`pause.fill`, `forward.fill`) and `Features/Player/MiniPlayerChrome.swift` (~lines 97–115: same three, collapsed).

The convention: every icon-only control needs an explicit `.accessibilityLabel` in the app's language; SF Symbols fall back to an auto-generated English description (e.g. "play fill") when none is supplied.

What the code does instead: `Image(systemName: "backward.fill")` / `"play.fill"`/`"pause.fill"` / `"forward.fill"`, wrapped in `TouchDownButton`, with no `.accessibilityLabel` anywhere on any of the three. This is a real inconsistency, not a blanket gap: the very same files/row add `.accessibilityLabel("Hàng đợi")` to the queue button right next to them, and `SongsView.swift`, `JamendoResultRow.swift`, `ScrubberBar.swift` all carry careful, localized `accessibilityLabel`/`accessibilityValue` on their own icon buttons. The team clearly knows the pattern; the play/pause/next/previous buttons — the controls a VoiceOver user reaches for the most, on every screen that has a player — were simply missed.

What breaks in practice: a VoiceOver user swiping through the mini player or the full-screen player hears "play fill button" / "backward fill button" in English, sitting between two labels ("Hàng đợi", track titles) that are read correctly in Vietnamese. This is the single most-used control surface in a music app and it is the one place accessibility support was skipped.

### 3. `MPRemoteCommandCenter.previousTrackCommand` is explicitly disabled despite `previous()` being fully implemented
**File:** `Services/RemoteCommandsBridge.swift:52` — `center.previousTrackCommand.isEnabled = false`, with no `addTarget` registered for it (line 18 only calls `removeTarget(nil)`).

The convention: a remote command should be enabled and wired whenever the app can act on it. `PlaybackService.previous()` is a complete, well-specified implementation (restart-vs-skip-back threshold, wrap under repeat modes) and is bound to the in-app UI's back button.

What the code does instead: `nextTrackCommand` and `changePlaybackPositionCommand` are enabled and given targets; `previousTrackCommand` is deliberately turned off, with no target and no explanatory comment anywhere in the file.

What breaks in practice: the lock screen, Control Center, CarPlay, and AirPods/hardware remote all lose the Previous button — every one of the app's *other* remote surfaces (in-app UI) has it, so this reads as broken rather than intentional to anyone controlling playback from outside the app.

### 4. Collapsed mini-player transport buttons are 32×32pt — below the 44×44pt HIG minimum hit target
**File:** `Features/Player/MiniPlayerChrome.swift:37` (`private static let buttonSize: CGFloat = 32`), used for the play/pause and next buttons at lines ~97–115.

The convention: HIG requires interactive controls to have (or effectively provide, via padding/hit-testing) at least a 44×44pt touch target.

What the code does instead: the collapsed pill's play/pause and next buttons are given an explicit 32×32pt frame — smaller than the minimum, and it is a *documented* choice ("32 is the floor here — below it the buttons drop under the 44pt Apple asks for by more than the surrounding pill can excuse"), not an oversight, and the full-screen player's transport row does use 44pt (`queueGlyphFrame`/`transportGlyphFrame`). Still, it's a real deviation on a control that is tapped constantly.

What breaks in practice: users with larger fingers or motor-control difficulty will have a measurably harder time hitting Next/Play in the collapsed pill specifically; this is the kind of finding App Review's Accessibility guideline can flag if scrutinized, though it is the least severe of the transport-control issues since the full player's controls meet the target and this one is a conscious, constrained trade-off (54pt-tall pill) rather than carelessness.

### 5. `Localizable.xcstrings` has `vi` as source language with no `en` translations yet
**File:** `Localizable.xcstrings` (`sourceLanguage: "vi"`, 134 keys, only Vietnamese strings populated).

This matches the user's own project notes (`project_localization.md` — "Localization plan — English + Vietnamese via String Catalog, its own đợt") — i.e., this is known, staged future work, not a defect. Flagging only for completeness: as it stands today, an App Store listing or a device set to English will show Vietnamese UI text throughout (the string catalog will fall back to the source language, `vi`, for any locale it has no translation for). Not a bug against the current phase, but worth remembering it blocks submission to any market where English is expected unless intentionally shipping Vietnamese-only.

### 6. Accessibility coverage is real but narrow — confined to a handful of custom controls, not audited across the library screens
**Files:** grep for `accessibilityLabel|accessibilityElement|accessibilityValue|accessibilityHint|accessibilityAddTraits` across `Features/` hits only 6 of the ~40 feature files (`ScrubberBar.swift`, `NowPlayingContent.swift`, `PlayerCard.swift`, `SongsView.swift`, `JamendoResultRow.swift`, `JamendoDiscoveryView.swift`/nearby). Most `List`-driven screens (`AlbumsView`, `ArtistsView`, `SearchView`, `AccountView`, `SettingsView`, `DriveFoldersView`, `TrackMetadataEditor`) rely entirely on SwiftUI's automatic accessibility tree from `Text`/`Image` content, which is often adequate for plain rows but has not been verified for grid cells (`AlbumsView`/`ArtistsView` use `GeometryReader` + `ArtworkThumbnail` circular/square cells with a caption below — VoiceOver's default grouping of an image + two text lines in a grid cell is usually serviceable but was evidently not deliberately checked, unlike the controls in finding 2's neighbors). Lower severity than 1–4 because nothing here is confirmed broken, only unaudited — flagging so it doesn't get missed in a real device/VoiceOver pass before submission.

---

## Areas that are genuinely solid (no padding, one line each)
- State management: `@Observable`/`@MainActor` used correctly and exclusively; no legacy `ObservableObject`/`Combine` anywhere.
- SwiftUI idiom currency: two-parameter `onChange(of:)` everywhere, no deprecated `NavigationView`/`.alert(isPresented:)`/`.actionSheet`, haptics via `.sensoryFeedback` not raw `UIFeedbackGenerator`, `GeometryReader` only where a true reader is needed.
- Localization plumbing (bundle/locale threading, `LocalizedStringKey` interpolation correctness, avoiding the `Text(String)` bypass trap) is more careful than most production apps its size.
- `MPNowPlayingInfoCenter`/`MPMediaItemArtwork` payload construction (downsampled artwork, deferred/throttled pushes, duration-arrives-late handling for streaming) is thoughtfully engineered — the actual Now Playing *data* is correct even though the *session lifecycle* around it (finding 1) is not.
- Settings/navigation surfaces (`SettingsView`, detail pushes) follow the platform idiom (`List`, `Section`, `.pickerStyle(.navigationLink)`) rather than reinventing controls.
