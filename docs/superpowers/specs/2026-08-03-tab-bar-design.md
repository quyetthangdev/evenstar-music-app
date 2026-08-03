# Floating Tab Bar and Library Structure — Design (Đợt A)

**Status:** design, awaiting user review
**Date:** 2026-08-03

## Goal

Give Evenstar a four-destination library structure — Bài hát, Album, Nghệ sĩ,
Tìm kiếm — reached from a floating pill tab bar that sits below the collapsed
Now Playing pill, in the manner of Apple Music's current design.

This is **Đợt A** of three:

| Đợt | Scope |
|---|---|
| **A** (this spec) | Four tabs, three new screens, translucent pill tab bar, always visible |
| B | Tab bar minimises as the list scrolls |
| C | Liquid Glass materials |

B and C are deliberately excluded. B adds a second animated state machine to a
bottom layout that has already produced two Critical defects; it is worth
isolating so that a regression there is unambiguous. C was deferred by the
user.

## Non-goals

- No Liquid Glass. `.regularMaterial` only.
- No scroll-driven tab bar behaviour.
- No change to `PlaybackService`, `ImportService`, `LibraryService`, or the
  SwiftData schema.
- No `albumArtist` field. See "Known limitation" below.
- No import UI on the new tabs — importing stays on Bài hát.

## Architecture

### Navigation

`LibraryView` currently owns both the library list *and* `PlayerCard`, plus the
import toolbar button, `fileImporter`, import sheet, and error alert. It splits:

```
RootView                                 ← new app root
└─ ZStack(alignment: .bottom)
   ├─ TabView(selection: $tab)           ← system tab bar hidden
   │  ├─ SongsView      (today's LibraryView, minus PlayerCard)
   │  ├─ AlbumsView     → AlbumDetailView
   │  ├─ ArtistsView    → ArtistDetailView
   │  └─ SearchView
   ├─ FloatingTabBar(selection: $tab)
   └─ PlayerCard                         ← topmost, so expanding covers the tab bar
```

A real `TabView` is used even though its own bar is hidden, because it
preserves each tab's `NavigationStack` path and scroll position across tab
switches. A `switch` over an enum rebuilds the destination and loses both —
navigate into an album, change tabs, come back, and the detail screen is gone.
Apple Music does not behave that way.

`PlayerCard` must be **above** `FloatingTabBar` in the `ZStack` so that
expanding it covers the tab bar. It remains safe to place there because its
hit region at collapsed rest is only the pill itself — the tab bar below stays
tappable. That property is load-bearing for this design; see the extended
comment at the `.contentShape` call site in `PlayerCard`.

### Bottom layout

Three floating layers now share the bottom of the screen. Measured upward from
the safe-area bottom edge:

```
safe area  ─────────────────────────────
   +12   ┌─ tab bar (56pt) ─────────────┐
   +68   └──────────────────────────────┘
   +76   ┌─ Now Playing pill (64pt) ────┐
  +140   └──────────────────────────────┘
         lists must clear to here
```

All of it derives from one type, so that no two formulas can drift apart:

```swift
enum BottomBarMetrics {
    static let sideMargin: CGFloat = 12
    static let tabBarHeight: CGFloat = 56
    static let tabBarBottomGap: CGFloat = 12
    static let playerTabGap: CGFloat = 8

    /// Safe-area bottom up to the player pill's bottom edge.
    static let playerBottomOffset = tabBarBottomGap + tabBarHeight + playerTabGap
    /// What a list must clear with a track loaded.
    static let clearanceWithPlayer = playerBottomOffset + PlayerCard.collapsedHeight
    /// What a list must clear with no track (the pill is hidden).
    static let clearanceTabBarOnly = tabBarBottomGap + tabBarHeight
}
```

**This exists because of a defect that has now recurred twice.** `PlayerCard`'s
bottom padding and its `dragTravel` divisor must describe the same distance, or
the card lags the finger by the difference. That bug appeared first for
`insets.bottom` (R2) and again when the pill's 12pt gap was added. The pill now
sits a further 76pt up, so a third occurrence would put the card 76pt behind
the finger. Both formulas must read `playerBottomOffset`; neither may restate
the arithmetic.

Every list's bottom `safeAreaInset` uses `clearanceWithPlayer` when a track is
loaded and `clearanceTabBarOnly` when none is — the existing conditional in
`LibraryView`, with new values.

### Grouping

`Track` already carries `albumTitle`, `artistName`, and
`artworkRelativePath`. Albums and artists are groupings over the existing
`@Query` results. **No schema change and no migration.**

Grouping and search live in `LibraryGrouping`, as pure functions over
`[Track]`, so they are unit-testable without a view:

```swift
struct AlbumGroup: Identifiable {
    let id: String          // "\(albumTitle)\u{0}\(artistName)"
    let title: String
    let artist: String
    let tracks: [Track]
}

struct ArtistGroup: Identifiable {
    let id: String          // artistName
    let name: String
    let tracks: [Track]
}

enum LibraryGrouping {
    static func albums(from tracks: [Track]) -> [AlbumGroup]
    static func artists(from tracks: [Track]) -> [ArtistGroup]
    static func search(_ query: String, in tracks: [Track]) -> [Track]
}
```

Albums key on **both** title and artist, because "Greatest Hits" by two
different artists is two albums. The id joins them with a NUL separator so that
an artist named `X` with album `Y-Z` cannot collide with artist `X-Y`, album
`Z`.

Ordering: albums and artists sort by name using `localizedStandard`
comparison, matching the existing track sort.

Tracks within an album sort by `discNumber`, then `trackNumber`, then title.
Both fields already exist on `Track` and are populated by the importer, so an
album must present in its real running order, not alphabetically — an
alphabetical album listing is wrong in a way users notice immediately. Both are
`Int?`; a track missing a number sorts after every numbered track rather than
being treated as 0, so a single untagged file cannot jump to the top of an
otherwise correct album.

Search matches title, artist, or album with `localizedStandardContains`, which
is both case- and diacritic-insensitive. **This matters for Vietnamese**: a
query of `bien` must match `Biển`, and `HOA` must match `hoà`. A plain
`lowercased().contains` would fail both and must not be used. An empty or
whitespace-only query returns no results rather than everything.

## Screens

**SongsView** — today's `LibraryView` with the `ZStack` and `PlayerCard`
removed. Keeps the toolbar `+`, `fileImporter`, import progress sheet, error
alert, and empty state. Unchanged behaviour.

One thing does **not** stay with it: `.task { await
playback.restoreFromPersistedState() }` moves to `RootView`. Restoring the
saved queue is an app-launch concern, not a tab's. Left on Bài hát it would
merely happen to work because that tab is selected first, and would silently
stop working the day the default tab changes or the view is rebuilt.

**AlbumsView** — `LazyVGrid`, two columns, artwork over album title over artist
name. Artwork comes from the group's first track via the existing
`ArtworkThumbnail`. Tapping opens `AlbumDetailView`.

**AlbumDetailView** — large artwork, title, artist, then the album's tracks as
`SongRow`s. Tapping a track calls `playback.play(track, in: album.tracks)`, so
the queue is the album.

**ArtistsView** — `LazyVGrid`, two columns, **circular** artwork over the
artist name, taken from that artist's first track. Circular rather than square
is what distinguishes it from Albums at a glance, and matches Apple Music.
Tapping opens `ArtistDetailView`.

**ArtistDetailView** — the artist's tracks as a flat list, sorted by album then
title. Playing sets the queue to that artist's tracks. An album-grouped layout
here was considered and dropped as more structure than the content justifies at
this size.

**SearchView** — a `.searchable` field over the whole library. Results are
`SongRow`s; playing sets the queue to the current results. Distinct empty
states for "no query yet" and "no matches".

## Tab bar

A `Capsule` filled with `.regularMaterial`, 56pt tall, inset
`BottomBarMetrics.sideMargin` from each screen edge, sitting
`tabBarBottomGap` above the safe area. Four equal-width items, each an icon
above a caption:

| Tab | Symbol | Label |
|---|---|---|
| Bài hát | `music.note.list` | Bài hát |
| Album | `square.stack` | Album |
| Nghệ sĩ | `music.mic` | Nghệ sĩ |
| Tìm kiếm | `magnifyingglass` | Tìm kiếm |

Selected items render in `.primary`, unselected in `.secondary`. Each item is a
`Button` carrying `.isSelected` as an accessibility trait, so VoiceOver
announces the current tab. Labels are always visible; they are not hidden at
small sizes, because a four-item bar has room and unlabelled icons are worse
for a first-time user.

The bar is hidden — `.opacity(0)` with hit-testing off — while `PlayerCard` is
expanded, so it cannot be reached through the expanded player.

## Testing

New unit tests cover `LibraryGrouping` only; the views are verified by hand.

- albums group by title *and* artist, so same-titled albums by different
  artists stay separate
- artists group by name and gather every track
- album ids cannot collide across a separator-shaped artist/album pair
- ordering is `localizedStandard` for both groupings
- search matches on title, artist, and album
- **search is diacritic-insensitive both ways**: `bien` finds `Biển`, and
  `Biển` finds a track stored as `Bien`
- search is case-insensitive
- an empty or whitespace-only query returns nothing
- grouping an empty library returns empty, not a crash
- an album's tracks order by disc, then track number, then title
- a track with no `trackNumber` sorts after every numbered track, not first

## Known limitation

A compilation album — one album, many track artists — splits into one album per
artist, because `Track` has no `albumArtist` field and the grouping key
includes the artist. Fixing this needs a schema field and a re-import, so it is
out of scope here. It should be stated plainly rather than discovered: a user
with compilations will see them fragmented.

## Risks

1. **The bottom-layout arithmetic.** The `playerBottomOffset` / `dragTravel`
   pairing has failed twice. Any task touching it must be reviewed against
   both formulas together, not one at a time.
2. **Hit-testing between the three layers.** The tab bar sits under the
   player's full-screen frame. If the player's collapsed hit region is ever
   widened again, the tab bar becomes unreachable — the same failure that made
   the library untappable, one layer down.
3. **`.toolbar(.hidden, for: .tabBar)` placement.** It applies to the content
   inside each tab, not to the `TabView`. Applied in the wrong place, the
   system bar reappears beneath the custom one.
4. **Deployment target.** Raised to iOS 18.6 during this work. The app target
   is already set; the test target must match or the test bundle cannot import
   the app module.
