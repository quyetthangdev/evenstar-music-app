# A third source: Jamendo — Design

**Date:** 2026-08-08
**Status:** approved

## Goal

Give someone with an empty library something to play. Local files need files;
Drive needs a folder someone already shared. Jamendo needs neither — it is a
catalogue of Creative Commons music that anyone can search on first launch.

## Why Jamendo and not the larger catalogues

Three free sources were checked with real calls before choosing.

**Internet Archive** returns 504,072 audio items with no API key at all, and is
by far the biggest. It is also the most dangerous: public-domain and
several kinds of Creative Commons sit in the same collections with no filter
that can be trusted, so every item's licence would be this app's problem to
determine.

**Audius** has an open API and modern independent music. Streaming is its
intended use, but it offers nothing to filter licences by.

**Jamendo** was chosen because it is the only one of the three that returns a
**per-track licence at all** — `license_ccurl` on every row. That much was
verified with real calls before this document was first written.

**What this document originally claimed here — "the API itself can filter by
licence... legality is a query parameter" — was not tested against the live
API and turned out to be false.** Jamendo's `ccnc` query parameter looks like
a filter but is not one: measured live (task-9-brief.md), it can narrow a
result page to *only* NC-licensed tracks, or leave it unfiltered, but it
cannot ask for "everything except NC" — the one direction this app needs. So
there is no server-side way to exclude non-commercial tracks from a search;
`JamendoClient` fetches a page and `JamendoLicencePolicy` filters it
client-side, after decoding, against each row's `license_ccurl` (see
`## Licence filtering` below, and the two files' own doc comments).

Jamendo still holds up as the right choice, on the narrower ground that
remains true: it is the only one of the three candidates whose response
carries a licence per track in the first place. Internet Archive's mixed
public-domain/CC collections and Audius's API have nothing to filter *by*,
server-side or client-side — there is no field to read. A wrong claim about
*where* the filtering happens does not change that Jamendo is still the only
source where filtering is possible at all, which is what actually matters for
an app that cannot afford to guess at a track's legality.

YouTube, Spotify and Bandcamp were ruled out earlier: the first violates its
terms and is refused by App Review, the second needs Premium and forbids mixing
its playback with local files, and the third has no public API.

## Scope

**In:** searching Jamendo, browsing trending and genres, saving a track into the
library, playing saved tracks, licence attribution, and the errors all of that
can produce.

**Out:** playlists, downloading audio for offline use, following artists,
Jamendo tracks appearing in Album/Artist/Search screens, and any write operation
against Jamendo (favouriting on their side, uploading).

## What the user sees

The **Bài hát** tab's chips become three: **Trên máy** / **Drive** / **Jamendo**.
Three segments, still under the five the HIG allows on iPhone. The Jamendo chip
lists **saved tracks only** — the catalogue is not the library.

Empty, that chip shows a `ContentUnavailableView` whose action opens discovery.
That is the one place a first-time user is told this source exists.

**Discovery** is a screen pushed from a toolbar button on the Jamendo chip, the
same shape as the `+` that opens the file importer:

- Nothing typed → a row of genre chips, then a trending list
- Something typed → search results replace both
- Every row: artwork, title, `artist · licence`, and a save button

Saving downloads the cover, inserts the row, and the track appears in the
library. Nothing else about the app changes.

## Attribution is a requirement, not a courtesy

CC-BY obliges visible credit. It appears in three places, and a reviewer should
check all three:

1. the discovery row — `artist · licence`
2. the saved-track row in the library — the same line
3. the expanded player — a tappable line that opens the track's page on Jamendo

Hiding this in an About screen would not satisfy the licence.

## Licence filtering

**Originally written here: "the client always sends a licence filter" to the
API. Also false, for the same reason given above** — there is no request
parameter that excludes NC tracks, so nothing is ever "sent". What actually
happens: the client always *applies* a licence filter, client-side, to
whatever page Jamendo returns, before showing it. Same outcome from the
user's side (an NC track never appears in the list while the setting is on),
different mechanism, and the difference matters because it means every page
fetched pays the cost of over-fetching to compensate — see
`Services/JamendoClient.swift`'s paging comments for the measured numbers (a
`piano` search sampled at roughly 8% of a page surviving the filter).

**Default: only tracks that permit commercial use.** The app intends to charge
money eventually, CC-NC forbids commercial use, and whether "playing music
inside a paid app" is commercial use is genuinely unsettled. Shipping the
permissive default and then having to pull music out of a released app is the
outcome worth avoiding.

**Settings gains one toggle** — *"Chỉ nhạc dùng được cho mục đích thương
mại"*, on by default. Turning it off widens the catalogue and moves the
judgement to the user.

The mapping from that toggle to a pass/fail decision on one track's licence
URL (`JamendoLicencePolicy.permits(licenceURL:commercialOnly:)`) is a **pure
function**, so it can be tested without a network: the point under test is
that the restrictive setting never lets an NC-licensed — or unreadable, or
non-CC — licence through.

## Data model

`JamendoTrack`, a SwiftData `@Model` conforming to `Playable`, alongside `Track`
and `DriveTrack`. It stores what the catalogue returned at save time — the app
never re-queries to render a row.

Deduplication is by **Jamendo's own track id**, not by title: two different
recordings can share a title, and the same recording must not be saved twice.

### The artwork mismatch, and why the cover is downloaded

`Playable.artworkRelativePath` is a **Documents-relative path**. Jamendo returns
a **remote URL**. The two do not meet.

The cover is therefore **downloaded into `Artwork/` when the user saves the
track**, exactly as `ImportService` does for an embedded tag. A saved Jamendo
track is then a first-class citizen: full-bleed artwork in the expanded player,
a dominant colour for the background, a thumbnail in every list — with no change
to `Playable`, and therefore no change to `Track` or `DriveTrack`.

The alternative — widening `Playable` with a remote-artwork case — would push a
network concept into a protocol whose entire purpose is to hide where the bytes
live, and would touch both existing conformers to serve neither.

Cost: one extra download per save, and tens of kilobytes on disk per track.

## Components

| File | Responsibility | Modelled on |
|---|---|---|
| `Services/JamendoAPIKey.swift` | the client id; empty in the repo | `DriveAPIKey` |
| `Services/JamendoClient.swift` | `init(clientID:session:)`, requests, DTOs | `DriveClient` |
| `Models/JamendoTrack.swift` | the saved row, conforms to `Playable` | `DriveTrack` |
| `Services/JamendoLibraryService.swift` | save, unsave, query, dedupe | `DriveLibraryService` |
| `Features/Jamendo/JamendoDiscoveryView.swift` | search, trending, genres | — |

**Nothing in the audio path changes.** `StreamingAudioPlayer` and
`RoutingAudioPlayer` already play an `https` URL, and `PlaybackService` already
holds a queue of `any Playable`. Repeat, the lock screen, session restore, play
counting and skip-past-a-failure are inherited rather than rewritten — the same
dividend the Drive đợt collected from that protocol.

## Errors

Mirrors `DriveError` case for case, because the failures are the same failures:
no client id configured, offline, rate limited, response not decodable, track
gone. Vietnamese is the source language, with English in the catalogue.

## Offline

**No new code.** A saved Jamendo track is a stream URL, so losing the network
takes the identical path a Drive track already takes: `lastPlaybackError`, the
red line on the list, and the automatic skip past a track that will not load.

This is the honest limitation of the design: saving a track does not make it
available offline. Downloading audio is out of scope, and for some licences it
would not be permitted anyway.

## API key

A free client id from `devportal.jamendo.com`. It lives in
`JamendoAPIKey.swift`, empty in the repository, marked `skip-worktree` exactly
as the Drive key is, and the app reports a specific error rather than failing
obscurely when it is missing.

As with the Drive key: hiding a credential in an app binary is theatre. The
boundary is the quota and restrictions on Jamendo's side.

## Testing

No test touches the real network — `JamendoClient` takes an injected
`URLSession`, and the suite drives it through the existing `StubURLProtocol`.

- the client: search, trending, genre, error mapping (including Jamendo's own
  success/failure envelope, not just HTTP status), paging past one page, **and
  that `include=licenses` — not a licence filter, there is no such request
  parameter; the field that makes `license_ccurl` non-empty at all — is
  present in the URL**
- the library service: save, unsave, dedupe by Jamendo id, against an in-memory
  container
- `JamendoTrack` as a `Playable`: `playbackURL()`, and the placeholder metadata
  path a track with missing fields takes
- the licence-policy function, run against a decoded track, both settings

## Risks

**The JSON field names in this document are unverified.** No call has been made
against the real API, because no client id exists yet. The first implementation
task is therefore to make one real call, print the response, and reconcile it
with this design **before** the model is written. Nothing is built on the
assumption.

**Jamendo's terms may have changed.** This design was written against
documentation and recollection, not against a signed agreement. Reading the
current terms before shipping is the user's job, not the implementer's, and no
part of this document is legal advice.

**A third source multiplies the states the Bài hát screen can be in.** Three
chips, each with its own empty, loading, error and populated state. If that
screen starts to strain, splitting it is the fix — not another flag.
