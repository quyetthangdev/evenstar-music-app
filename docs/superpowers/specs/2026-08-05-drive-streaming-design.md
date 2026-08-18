# Streaming from a public Google Drive folder — Design

**Date:** 2026-08-05
**Status:** approved

## Goal

Play music that lives in a Google Drive folder without copying it to the phone,
so a library can be larger than the device.

## Why this shape, and not OAuth

The obvious design — sign in with Google, browse your Drive — is closed to this
app, and the reason is policy rather than engineering.

Reading an arbitrary Drive folder needs the `drive.readonly` scope. That is a
**restricted scope**: a publicly distributed app using it must pass a paid
third-party CASA security assessment and **re-verify every 12 months**. The
sanctioned way around it is `drive.file` plus the Google Picker, but Google's
own documentation states that for desktop and mobile apps *"only the
`drive.file` scope is permitted … and it can't be combined with any other
scope"*, and its desktop-and-mobile Picker guide covers desktop, Android and web
— **there is no documented native iOS integration**.

What remains is the path this design takes: a folder the user has shared as
*anyone with the link*, read with a plain **API key**. No OAuth, no consent
screen, no verification, no annual fee.

**The cost is privacy, and it is the user's to accept.** A link-shared folder is
readable by anyone who has the link. The app must say so plainly at the moment
of linking, not bury it. This is the single most important thing for a reviewer
to check.

## Scope

**In:** linking public Drive folders, listing their audio files, streaming
playback, rescanning, and the errors all of that can produce.

**Out:** downloading for offline use, ID3 reading of any kind — at scan time or
on first play, see "Not in this đợt" under Metadata — artwork, background sync,
OAuth, and Drive tracks appearing in Album, Artist or Search.

## What the user sees

The **Bài hát** tab gains two chips at the top of the list: **Trên máy** /
**Drive**. The chip switches which list is rendered. Nothing merges.

**Album, Nghệ sĩ, Tìm kiếm and the detail screens do not change at all.** They
stay local-only. This is a deliberate limitation, not an oversight: at scan time
the app knows a file's name and nothing else, so there is no album to group by
until a track has been played once.

The `＋` toolbar button keeps exactly one meaning — import files from the device.
It does **not** change with the chip. Adding a Drive folder happens from the
Drive chip's empty state, from a `…` menu beside the chips, and from
**Tài khoản → Nguồn nhạc**. All three open the *same* management screen; two
entry points to one screen, not two screens.

Four states behind the Drive chip:

1. **Empty** — an explanation of what link-sharing means, and one button.
2. **Scanning** — progress with a running file count.
3. **List** — file-name titles, the folder name as subtitle, pull to rescan.
4. **Error** — an inline banner naming the specific failure.

## Data model

Two new SwiftData models, separate from `Track`:

```swift
@Model final class DriveFolder {
    @Attribute(.unique) var folderID: String
    var displayName: String
    var linkedAt: Date
    var lastScannedAt: Date?
}

@Model final class DriveTrack {
    /// Stable across launches and what `PlaybackState` persists. Distinct from
    /// `fileID`, which is Google's.
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var fileID: String
    var folderID: String
    var fileName: String
    var title: String
    var artistNameOrNil: String?
    var albumTitleOrNil: String?
    /// 0 until `metadataResolved`. Not optional: `Playable` needs a number, and
    /// two ways to say "unknown" in one row is one too many.
    var durationSeconds: Double
    var metadataResolved: Bool
    var dateAdded: Date
    var playCount: Int
    var lastPlayedAt: Date?
}
```

Separate models rather than a `driveFileID` field on `Track`. Sharing `Track`
would be cheaper in the playback layer but would require **every existing
`@Query` to grow a filter**, and missing one would leak Drive rows into the
local library — the exact shape of the defect that shipped in Đợt A, where two
screens belonged to no task. With separate models the compiler enforces the
split instead of a reviewer's attention.

## Components

**`DriveLinkParser`** — pure, no networking. Accepts the share-link forms Google
hands out (`/drive/folders/<id>`, `/folders/<id>?usp=sharing`, `open?id=<id>`,
and a bare ID) and returns a folder ID, or a typed failure. This is the
likeliest thing to get wrong and the cheapest thing to test.

**`DriveClient`** — networking only, no SwiftData. Lists audio files in a folder
and builds a playback URL.

- List: `GET https://www.googleapis.com/drive/v3/files` with
  `q='<folderID>' in parents and trashed=false`,
  `fields=nextPageToken,files(id,name,mimeType,size)`, and `key=<API_KEY>`.
- **Pagination is required, not optional.** The endpoint returns at most 100
  files per page; a folder of 300 songs silently arrives as 100 without
  following `nextPageToken`.
- Audio files are those whose `mimeType` starts with `audio/`. Everything else
  is skipped.
- Playback URL: the same `files/<id>` endpoint with `alt=media&key=<API_KEY>`.

**`DriveLibraryService`** — the join. Scans a folder, inserts tracks that are
new, removes rows whose file has disappeared from Drive, and stamps
`lastScannedAt`.

## Metadata

At scan time the title is the file name with its extension stripped; artist,
album and duration are unknown. A 500-file folder therefore appears
**immediately**, and rescanning costs one request per 100 files.

### Not in this đợt: reading tags on first play

This design originally described a **second stage**: when a track is played,
`AVURLAsset` reads its real ID3 tags over the network (range requests, tens of
kilobytes) and the row is updated with `metadataResolved = true`.

**No task implemented it, and it is deferred to its own đợt rather than being
squeezed into this one.** It is a separable feature — a network read, a write
back to the row, and a rule for when to re-read — and this đợt is already the
largest in the project. What follows is the state that actually ships, stated
plainly, because a spec whose Self-Review claims coverage it does not have is
worse than one that admits the gap:

- `metadataResolved` is written only by its default (`false`) and read only by a
  test. Nothing ever sets it.
- `artistNameOrNil`, `albumTitleOrNil` and `durationSeconds` are never written
  after insert.
- **Every Drive track therefore shows its file name as the title, "Unknown
  Artist" and "Unknown Album", permanently** — however many times it is played.
  In the player this collapses to the artist alone (see `PlayerSubtitle`), so
  what the user actually reads under the title is the literal string
  "Unknown Artist".
- **No Drive track has a duration from metadata.** `durationSeconds` stays 0.
  The scrubber and the lock screen get a duration only from the player once
  `AVPlayer` resolves the asset's own — see the device-QA note in the plan about
  whether that ever happens for a chunked `alt=media` response.

The rest of the design does not depend on this stage: `Playable` already reports
non-optional `artistName`/`albumTitle` computed from the optional columns, and
those columns exist and are nullable, so the deferred đợt has somewhere to write
without a migration.

## The audio engine

`AVAudioPlayer` cannot stream — it needs a complete local file. Drive playback
needs a second `AudioPlayerProtocol` implementation backed by `AVPlayer`.

`AudioPlayerProtocol` keeps its current shape and gains exactly one member:

```swift
var didFailCallback: ((Error) -> Void)? { get set }
```

This is **required, not tidiness**. `AVAudioPlayer` reports a bad file by
throwing from `load(url:)`, and `PlaybackService`'s skip-forward loop is built
on that throw. `AVPlayer` reports failure asynchronously through
`AVPlayerItem.status == .failed`, so without this callback an offline device or
a deleted file would leave playback **silently hung** — the skip loop would
never run. `AVAudioPlayerWrapper` never calls it, so local playback is
unchanged.

`load(url:)` does **not** need to become async. `AVPlayer(url:)` does not block,
and the duration that arrives late is absorbed by the 0.5s position timer
`PlaybackService` already runs. This was checked against the existing code
before committing to it; an earlier reading of this design assumed the protocol
had to be reshaped and it does not.

## One queue, two sources

`PlaybackService.queue` becomes `[any Playable]`, where:

```swift
protocol Playable: AnyObject {
    var id: UUID { get }
    var title: String { get }
    var artistName: String { get }
    var albumTitle: String { get }
    var durationSeconds: Double { get }
    /// Documents-relative; `nil` for every Drive track, since artwork is out of
    /// scope for this đợt.
    var artworkRelativePath: String? { get }
    var playCount: Int { get set }
    var lastPlayedAt: Date? { get set }
    func playbackURL() -> URL
}
```

`Track` returns a file URL; `DriveTrack` returns the `alt=media` URL.

This is the most expensive part of the đợt — it touches the most heavily tested
file in the codebase. It is also what makes repeat, the queue, the lock screen,
session restore and play counting work for Drive tracks **without writing any of
them again**.

Session restore has to resolve an ID against both stores. `DriveTrack` needs a
`UUID` `id` for this, distinct from its `fileID`.

## Errors

Every failure gets its own Vietnamese message. Nothing fails silently.

| Situation | Where it shows |
|---|---|
| Link is not a Drive folder link | Under the input, on paste |
| Folder is not shared publicly (403/404) | Under the input, naming link-sharing as the fix |
| No network while scanning | Inline banner, with retry |
| No network while playing | Inline banner: Drive music needs a connection |
| File deleted from Drive mid-playback | Skip to next, note it |
| API quota exhausted (429) | Inline banner, ask to try later |

## API key

The key ships inside the binary and can be extracted. Obfuscating it is
theatre. The real boundary is in Google Cloud Console: restrict the key to the
**Drive API only** and to the app's **bundle ID**.

In the repo it lives in a git-ignored file with a checked-in `.example`
alongside. The trade-off is explicit: a fresh clone does not build until the
developer supplies a key.

## Testing

Most of this is pure and testable without a network.

- `DriveLinkParser` — a table of real link forms, including malformed ones.
- `DriveClient` — a stubbed `URLProtocol`, with fixtures for a paginated
  listing, an empty folder, a 403, and a 429. No test touches the network.
- `DriveLibraryService` — the existing in-memory store; new files appear,
  vanished files are removed, a rescan is idempotent.
- `PlaybackService` — its 119 existing tests must keep passing through the
  `Playable` change; that is the guard rail on the riskiest edit here.

Streaming itself needs a device. The simulator can list and can fail, but only
hardware proves playback, background audio and the lock screen.

## Risks

- **`Playable` touches everything.** If any task ends with the existing suite
  red, stop rather than adapting the tests.
- **The privacy warning can be softened by accident.** It is a product
  requirement, not copy.
- **Google may rate-limit or block API-key traffic** to Drive without notice.
  This design has no fallback if that happens; the feature would need OAuth,
  which is what the whole first section rules out.
