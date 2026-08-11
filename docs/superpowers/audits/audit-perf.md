# Evenstar — SwiftUI rendering/animation performance audit (PlayerCard drag)

Scope read: `PlayerCard.swift` (full, 1855 lines), `NowPlayingContent.swift`,
`QueuePanel.swift`, `ScrubberBar.swift`, `SystemVolumeSlider.swift`,
`FloatingTabBar.swift`, `MiniPlayerChrome.swift`, `ArtworkThumbnail.swift`,
`ArtworkStore.swift`, `RootView.swift`, `PlayerExpansion.swift`,
`BottomBarStyle.swift` (springs + shared shadow helper).

Evidence base: Instruments Animation Hitches, Release, iPhone 12, ~13s of
gesture — 94/771 hitches (12.2%), 50% "Expensive GPU" (backboardd = system
compositor, not app Metal calls), median 16.8ms/p90 66.7ms/max 150ms. A/B
removing the artwork's gradient-masked `.ultraThinMaterial` frost changed
nothing (114/794). **Then, on-device with Color Blended Layers + Color
Offscreen-Rendered Yellow: mini player + floating tab bar are yellow at rest;
the expanded player is entirely yellow; the queue screen is entirely yellow
with additional nested yellow layers inside it.** That is the controlling
evidence below — an offscreen pass across the whole screen is exactly the
shape of "50% Expensive GPU, all attributed to backboardd."

## PRIMARY FINDING: `.shadow()` on the full-screen, continuously-resizing card is almost certainly what forces the offscreen pass

### `PlayerCard.swift:870` — `.floatingBarShadow()` on the entire card
```swift
return ZStack(alignment: .topLeading) {
    background
    artworkView(...)
    miniChrome(width: cardWidth)
    expandedContent(size: cardSize)
    grabber(topInset: insets.top)
}
.frame(width: cardWidth, height: height, alignment: .top)
.clipShape(UnevenRoundedRectangle(...))   // line 844
.floatingBarShadow()                      // line 870  ← shadow(...) via BottomBarStyle.swift:207
```
`.floatingBarShadow()` resolves to `view.shadow(color:radius:y:)`
(`BottomBarStyle.swift:206-208`). This is applied, unconditionally, to the
**whole card** — background gradients, the artwork, the mini chrome, the
expanded controls, the grabber — at every value of `progress`, not gated by
`isDragging` or any threshold. `BottomBarStyle.swift` itself documents,
categorically, that this is expensive:

> "A shadow forces an offscreen pass... **nothing else down here draws
> offscreen.**" (`BottomBarStyle.swift:192-196`)

That comment's own mitigation — keeping the shadow's *parameters* constant
so it doesn't need "a fresh one every frame" — only addresses animating the
shadow's radius/opacity. It does **not** address the actual situation here:
the *shadowed view itself* changes size on every frame of the drag, from a
~54pt-tall pill to a ~full-screen card (roughly a 15x change in area). A
shadow computed from a view's alpha silhouette has to be regenerated at the
view's *current* bounds regardless of whether the shadow's own parameters
moved — so backboardd is asked to rasterize the entire card's contents into
a fresh offscreen buffer, at the new size, every single frame, for the whole
duration of every drag. At `progress ≈ 1` that offscreen buffer is
**the size of the screen**, which is exactly what "entire screen is yellow"
on the expanded player means, and exactly why 50% of the measured hitches
carry a GPU/backboardd label.

This single line explains all three yellow captures with no further
explanation needed:
- **Mini player + tab bar yellow (collapsed, at rest):** the card, even
  collapsed to a pill, still carries this same shadow — hence it is yellow
  even with no drag in progress.
- **Expanded player entirely yellow:** at `progress == 1` the shadowed view
  *is* the full screen.
- **Queue open, entirely yellow:** `QueuePanel` renders as an overlay
  *inside* this same shadowed `ZStack` (see `artworkView`'s `.overlay`,
  `PlayerCard.swift:1459-1560`), so it inherits the same full-screen
  offscreen surface regardless of what is showing inside it.

**Why the earlier A/B failed:** the frost material that was removed
(`PlayerCard.swift:1336-1352`) was one effect drawn *inside* a card that this
shadow was already forcing offscreen. Removing it changed what gets painted
into the offscreen buffer; it did not change whether an offscreen buffer is
needed, or its size. That is the mechanism, not a guess — it is the direct,
necessary consequence of an ancestor `.shadow()` sitting above both the
frost and the artwork in the view tree.

**Confidence:** high. Directly supported by the Color Offscreen-Rendered
capture, by the shape/scale match to the measured GPU-hitch profile, and by
the code's own comment naming `.shadow()` as the offscreen trigger — the
gap is only that the comment did not anticipate a *resizing* shadowed view.

**Would removing/changing it cost anything visible?** The card's shadow is
the "lift off the list" cue for the collapsed pill and, per the type's own
doc comment, is "occluded" and contributes nothing once fully expanded
("The expanded player needs no exception: at full screen it covers
everything, so its shadow is occluded rather than wasted" —
`BottomBarStyle.swift:198-199`). That statement is itself a strong argument
for a targeted fix: gate the shadow off once the card is large enough to be
self-occluding (e.g. fade it out well before `progress` reaches its current
"occluded" point, or apply it only to a small static backdrop behind the
*collapsed* pill, the same pattern already used for `recedeCornerRadius` —
see `BottomBarStyle.swift:151-159`, which documents rejecting a full-screen
mask for exactly this reason and rounding "a static backdrop... instead of
masking the content itself"). The team has already solved this exact class
of problem once elsewhere in this file; the fix has known precedent in this
codebase, this is not a novel risk.

### `PlayerCard.swift:1413` — a second, nested `.shadow()` on the artwork alone
```swift
.shadow(color: .black.opacity(0.18), radius: 6, y: 3)
```
Independent of the finding above: the artwork (`artworkView`,
`PlayerCard.swift:1234-1561`) carries its *own* shadow, unconditionally, at
every progress value. The comment at this line explains why the shadow's
*parameters* were made constant (to stop "the whole drag" regenerating a
36pt→280pt-radius shadow) but, exactly as above, that fix does not touch the
cost of rasterizing the artwork itself at its current (animating) bounds to
get its silhouette — and the artwork is the single largest painted surface
on the card, reaching ~60-85% of the screen at full expansion. This is a
second, nested offscreen pass sitting *inside* the one described above —
compounding it, not merely duplicating it, since the artwork also carries
its own separate `.mask` and `.overlay{.mask}` (below).

**Confidence:** high, same evidentiary basis as the primary finding.

### `FloatingTabBar.swift:375, 455, 567` — three more `.floatingBarShadow()` calls, always on screen
`leadingCapsule` (455), `searchCapsule` (567), and `trailingButton` (375)
each end their modifier chain in `.clipShape(...)` followed by
`.floatingBarShadow()`. These are always mounted (`RootView.swift:138-242`)
and always shadowed, independent of the player entirely — this is the
direct explanation for "the floating tab bar [is] yellow" in the same
capture that showed the mini player yellow. Each individual surface is
pill/circle-sized (small area vs. the full-screen card above), so by the
area-ranking the coordinator asked for, these rank well below the card's own
shadow — but they are a second, always-on source of offscreen work
completely independent of `PlayerCard`, and they explain why the tab bar was
yellow *before* any card-related fix would touch it.

**Confidence:** high (same mechanism, directly visible as the "tab bar
yellow" capture).

**Would removing it cost anything visible?** The tab bar's shadow is smaller
stakes: unlike the card, these surfaces don't grow to fill the screen, so
their offscreen buffers stay pill/circle-sized regardless of state — cheap
per-instance, but a needless standing cost since they never move dynamically
except during the (occasional, non-drag) search/minimise morph.

## Secondary / compounding findings (nested inside the now-explained offscreen surface)

These do not create the offscreen pass — the shadow above does — but they
add *more* work inside a buffer that is offscreen either way, and they were
written assuming they were each individually avoiding a cost that, per the
evidence above, was already being paid one level up the tree.

### `PlayerCard.swift:1384-1390` — the dissolve `.mask(LinearGradient(dissolveStops))` on the artwork
The comment at `PlayerCard.swift:1356-1379` documents that this mask
*replaced* an `.overlay` specifically to avoid "an offscreen pass... The
cost is real and accepted." **Verified against the code as it stands today:
this claim is correct as far as it goes — it is genuinely a `.mask`, not an
overlay, exactly as the comment says — but the comment frames this as an
isolated, opt-in cost ("if it ever measures badly, the answer is to stop
compositing this per frame"), when in fact it is one more render pass inside
a card that a `.shadow()` two effects up the chain already forces offscreen
on every frame.** Removing this mask alone would very likely reproduce the
same "no measurable change" result the frost-material A/B already got, for
the identical reason: the parent surface stays offscreen regardless.

**Confidence:** the "this is a `.mask`" fact is directly verified from
source. Its *marginal* contribution to hitch count, on top of the shadow
above, is theoretical/unmeasured — plausible but not isolated by any A/B.

### `PlayerCard.swift:1336-1352` — the frost `.overlay{ .fill(.ultraThinMaterial).mask(...) }`
Already A/B-tested and cleared as a standalone change — consistent with the
finding above: it was never the thing creating the offscreen surface, only
one effect painted inside it.

### `PlayerCard.swift:1049-1053` — `background`'s live `.thinMaterial` rectangle, resized every frame while `progress < 0.34`
Distinct from the frost material above (this is the card's *background*
layer, not the artwork's). A live blur whose bounds are the animating
`cardSize` — expensive on its own terms, and, like the mask above, sitting
inside the same already-offscreen card. Not yet isolated by any A/B.
**Confidence:** theoretical.

### `PlayerCard.swift:844 → 870` — `.clipShape(UnevenRoundedRectangle(...))` immediately followed by `.shadow`
Worth naming explicitly: an `UnevenRoundedRectangle` with four
independently-interpolating radii has no cheap analytic shadow path the way
a plain rectangle or a single-radius `RoundedRectangle` might; combined with
a shadow, this all but guarantees the rasterize-then-blur path rather than
any hardware shortcut, on a shape that is *itself* changing every frame
(corner radii interpolate with `progress`). This compounds the primary
finding — it is part of *why* the card's shadow can't be cheap — rather than
a separate, independently-fixable line.

**Confidence:** theoretical (I could not verify from source alone whether
SwiftUI/Core Animation ever takes a cheaper path for `UnevenRoundedRectangle`
specifically; flagging as open).

### Queue screen's *additional* nested yellow (rows, header, pills)
I did not find an explicit `.shadow()` or `.mask()` inside `QueuePanel.swift`
— no `.shadow(` hits there at all. The most likely explanations I can name
without further on-device isolation, in descending confidence:
- `List`'s own row/cell compositing (`QueuePanel.swift:149-207`): system
  `List`/`UITableView` internals are a common, independent source of
  offscreen-rendered yellow (selection/edit-mode chrome, row backgrounds),
  especially combined with `.listRowBackground(Color.clear)` over a
  non-opaque parent (`QueuePanel.swift:167`) and `.environment(\.editMode,
  .constant(.active))` (`QueuePanel.swift:209`), which keeps drag handles
  live on every row.
- `.contentTransition(.symbolEffect(.replace))` on the pill glyphs
  (`QueuePanel.swift:247`) — SF Symbol content-transitions are known to
  require rendering old/new symbol states for cross-fade, which can surface
  as a small offscreen pass during the actual toggle (shuffle/repeat), not
  continuously.
- All of `QueuePanel` is, regardless of its own effects, painted inside the
  same shadowed/clipped `PlayerCard` surface identified above, so its yellow
  is at minimum guaranteed by inheritance even before any of its own effects
  are considered.

**Confidence:** low/theoretical for the row-level specifics — I could not
pin an exact line inside `QueuePanel.swift` the way I could for the shadow
findings; this needs a follow-up on-device capture with the queue open and
the card's shadow already removed, to see what (if anything) is left yellow.

## Other findings from the original pass (kept, lower priority given the above)

### `NowPlayingContent.swift:287-293` — `playback.position` read inside `NowPlayingContent.body`
`@Observable` (`PlaybackService.swift:7-9`) tracks dependencies at the
granularity of what is read *during a given body's evaluation*. `scrubber`
reads `playback.position` while `NowPlayingContent.body` itself is
evaluating, so every playback-position tick invalidates the whole
`NowPlayingContent` subtree (title, transport, volume, queue toggle) rather
than just `ScrubberBar`'s fill. This is a CPU/diffing cost, not a compositor
cost, so it plausibly explains some of the **non**-GPU-labelled half of the
hitches (Commit / Rendering / Delay Frame Swap) more than the GPU half the
shadow findings above target. Confidence: the scoping claim is verified from
source; its contribution to the measured hitches is unmeasured.

### `RootView.swift` / `SystemVolumeSlider.swift` — accumulation of always-mounted layers
`FloatingTabBar`, the full `TabView` content (scaled but not removed, via
the already-well-engineered `RecedeBehindPlayer`, `PlayerExpansion.swift:98-106`
— genuinely avoids a mask, no fix needed there), and an always-mounted
`MPVolumeView`-wrapping `SystemVolumeSlider` inside `NowPlayingContent` all
sit underneath or alongside the card while it animates. Given the shadow
findings above, this is now best read as "more surfaces the compositor has
to combine with the offscreen card," not an independent primary cause.
Confidence: theoretical/architectural.

## Ranked-by-area summary (as requested: full-screen pass outranks pill-sized by area ratio)

1. **`PlayerCard.swift:870`** — shadow on the whole card. Area: pill-sized
   at rest, up to 100% of the screen at full expansion. Affects all three
   captured screens. **Primary.**
2. **`PlayerCard.swift:1413`** — shadow on the artwork alone, nested inside
   #1. Area: up to ~60-85% of the screen at full expansion, always active.
3. **`PlayerCard.swift:1384-1390`** — dissolve mask on the artwork, nested
   inside #1 and #2. Same area as #2; adds compositing work but not, on its
   own, the offscreen trigger.
4. **`PlayerCard.swift:1049-1053`** — resizing `.thinMaterial` background
   rectangle, nested inside #1. Area: full card width, up to ~34% progress.
5. **`FloatingTabBar.swift:375/455/567`** — three shadows, always mounted,
   independent of the player. Area: pill/circle-sized each, small relative
   to #1-#4, but standing (non-drag) cost.
6. **QueuePanel's nested yellow** — area unclear without further capture;
   inherited from #1 at minimum, possibly `List`-internal on top.

## Verdict: is 12.2% hitches abnormal for this iPhone 12?

**Revised, given the offscreen-rendering evidence: yes, this reads as
abnormal, and as a specific, fixable defect rather than an intrinsic cost of
the design.** Before the Color Offscreen-Rendered capture I could only say
the architecture (a full-bleed image resizing under masks/materials) made a
double-digit hitch rate *plausible* without needing a bug. That capture
changes the answer: an **entire full-screen offscreen rasterization pass,
every frame, for the whole duration of every drag**, driven by a single
`.shadow()` modifier on a view that itself grows from a 54pt pill to the
full display, is not what a well-built version of this interaction would be
paying for. iOS sheets, Apple Music's own now-playing transition, and this
app's *own* `RecedeBehindPlayer` modifier (which explicitly rejected a
full-screen mask for the background-recede effect, with a comment
documenting exactly this reasoning) all show that this exact effect is
avoidable by standard means: don't shadow the thing that is resizing to fill
the screen. The team already knows the pattern — `BottomBarStyle.swift`'s
own comment states plainly that shadows force offscreen passes, and
`RecedeBehindPlayer`'s comment shows the fix already applied once, for a
different effect, in the same interaction. What's missing is applying that
same reasoning to the card's own shadow.

So: the median (16.8ms) being close to one dropped 60Hz frame is not, on its
own, alarming for a screen-filling animation on an A14. But p90 (66.7ms,
~4 frames) and max (150ms, ~9 frames), combined with 50% of all hitches
carrying a specific, single-mechanism GPU signature that traces cleanly to
one modifier on one line, argue against "this is just what full-screen photo
morphs cost on an iPhone 12." I would not flatter this as expected, nor
would I call it a fundamentally broken architecture — it is one shadow
modifier, applied one level too high in the tree, on a view that changes
size by an order of magnitude during the interaction it was written for.
