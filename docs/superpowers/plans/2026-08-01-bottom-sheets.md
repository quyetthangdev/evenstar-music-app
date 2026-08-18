# Bottom Sheets to iOS Standard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both of Evenstar's presented surfaces behave like standard iOS sheets — rounded corners, a grabber, and drag-to-dismiss — using the system's presentation mechanics rather than hand-rolled gestures.

**Architecture:** Presentation-layer only. `NowPlayingView` moves from `.fullScreenCover` to `.sheet` with a `.large` detent, which brings drag-to-dismiss for free and makes its hand-rolled chevron button redundant. `ImportProgressSheet` gains a second detent, a drag indicator that is hidden exactly while dismissal is disabled, and a `ScrollView` so its failure-reason list can no longer clip. No playback, queue, persistence or import logic is touched.

**Tech Stack:** Swift 5, SwiftUI, iOS 17.6 deployment target, Xcode 26. No third-party dependencies.

**Reference spec:** `docs/superpowers/specs/2026-08-01-bottom-sheets-design.md`

## Global Constraints

- **Min iOS deployment target:** 17.6
- **`SWIFT_DEFAULT_ACTOR_ISOLATION` must stay `nonisolated`** on both targets. Xcode 26's template sets it to `MainActor`, which gives every MainActor-isolated class an isolated `deinit`; below iOS 26 that routes through a back-deployed shim that aborts with a libmalloc double-free on **every** dealloc. Do not re-enable it.
- **Never edit `Evenstar/Evenstar.xcodeproj/project.pbxproj`.** Both targets use Xcode synced folders (`PBXFileSystemSynchronizedRootGroup`), so a `.swift` file on disk joins its target automatically.
- **UI framework:** SwiftUI only. Phone-first.
- **No third-party libraries.** No `try!`. No silent `catch { }`.
- **The test count must stay at 47**, in either direction. This plan adds no tests and must break none.
- **A clean build must produce zero Swift warnings.** That bar has held since Phase 2a Task 7.
- **Do not change playback, queue, persistence, or import behaviour.** This plan is presentation only.
- **Phase 1 capability — background audio, lock-screen Now Playing, remote commands — must be preserved.**

---

## Commands

There is no Xcode UI available. Use these.

**Clean build (zero Swift warnings required):**
```bash
cd /Users/phanquyetthang/evenstar && xcodebuild clean build -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "warning:|error:|BUILD" | grep -v AppIntents | sort -u
```
Expect exactly `** BUILD SUCCEEDED **`. Allow a 600000 ms timeout.

**Full test suite (47 must pass):**
```bash
cd /Users/phanquyetthang/evenstar && xcodebuild test -project Evenstar/Evenstar.xcodeproj -scheme Evenstar -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E "^Test case|TEST SUCCEEDED|TEST FAILED|error:"
```

**Reading a test failure.** `xcodebuild` prints no message when a test fails by *throwing* rather than by a failed assertion. A bare `TEST FAILED` with no detail is not an environmental problem — read the real message:
```bash
R=$(ls -td ~/Library/Developer/Xcode/DerivedData/Evenstar-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool get test-results tests --path "$R"
```

**Launch and screenshot:**
```bash
xcrun simctl boot "iPhone 17" 2>/dev/null
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/Evenstar-*/Build/Products/Debug-iphonesimulator/Evenstar.app
xcrun simctl terminate booted com.evenstar.app 2>/dev/null
xcrun simctl launch booted com.evenstar.app
sleep 3
xcrun simctl io booted screenshot /tmp/claude-501/-Users-phanquyetthang-evenstar/0e6e70ca-2ba8-4e82-b804-3618ac2f7281/scratchpad/<name>.png
```

## What cannot be verified here

**No audio file has ever been imported into this app.** `NowPlayingView` only appears when a track is playing, and `ImportProgressSheet` only appears after driving the Files-app picker by hand. **Neither surface this plan changes can be opened on the simulator.** The screenshot step proves only that the empty library still renders and the app did not crash on launch.

Both are confirmed during manual QA on a physical iPhone. Say so plainly in reports rather than implying the sheets were observed working.

## File structure

Three source files change, all presentation. No files are created or deleted.

```
Evenstar/Evenstar/Features/
├── Library/LibraryView.swift          # MODIFIED — two presentation modifiers
├── Player/NowPlayingView.swift        # MODIFIED — remove chevron handle + dismiss, adjust padding
└── Import/ImportProgressSheet.swift   # MODIFIED — conditional indicator, ScrollView
```

Plus one documentation file: `docs/superpowers/plans/2026-08-01-phase2a-qa-guide.md`.

---

## Task 1: `NowPlayingView` becomes a draggable sheet

**Goal:** Tapping the mini player presents Now Playing as a standard large sheet that can be dismissed by dragging down. The hand-rolled chevron button goes away.

**Files:**
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift:80-82`
- Modify: `Evenstar/Evenstar/Features/Player/NowPlayingView.swift:6`, `:12-27`, `:29-39`
- Modify: `docs/superpowers/plans/2026-08-01-phase2a-qa-guide.md`

**Interfaces:**
- Consumes: `NowPlayingView(playback:)`, `PlaybackService.currentTrack` — both unchanged.
- Produces: nothing new. `NowPlayingView`'s initialiser signature is untouched, so no other file needs to change.

### Steps

- [ ] **Step 1.1: Change the presentation in `LibraryView`**

In `Evenstar/Evenstar/Features/Library/LibraryView.swift`, replace this block:

```swift
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(playback: playback)
        }
```

with:

```swift
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView(playback: playback)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
```

Leave the `.onChange(of: playback.currentTrack?.id)` immediately below it exactly as it is — it dismisses the sheet when playback ends and works identically with a sheet.

- [ ] **Step 1.2: Remove the chevron handle from `NowPlayingView`**

In `Evenstar/Evenstar/Features/Player/NowPlayingView.swift`, delete this entire computed property:

```swift
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
```

- [ ] **Step 1.3: Remove `handle` from the body and adjust the top padding**

In the same file, replace the `body`:

```swift
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
```

with:

```swift
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            artwork
            titleBlock
            scrubber
            transport
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
```

The system grabber occupies roughly 20 pt at the top of a sheet, and removing `handle` took a row out of the `VStack`, so the top padding grows from 8 to 24 to keep the artwork clear of it. That value is a starting point to confirm on device, not a measured constant.

- [ ] **Step 1.4: Remove the now-unused `dismiss` environment value**

In the same file, delete this line:

```swift
    @Environment(\.dismiss) private var dismiss
```

The chevron button was its only consumer. If the build reports it is still used somewhere, stop and report that instead of leaving it in — it would mean the file has a dismissal path this plan did not account for.

- [ ] **Step 1.5: Clean build**

Run the clean-build command from the Commands section. Expect exactly `** BUILD SUCCEEDED **` with no `warning:` or `error:` lines. Report the output verbatim.

If the compiler warns that `dismiss` or `handle` is unused, you missed a deletion in 1.2 or 1.4.

- [ ] **Step 1.6: Run the full test suite**

Run the test command from the Commands section. **Expect 47 passing, 0 failures** — this task adds no tests and must break none.

- [ ] **Step 1.7: Launch and screenshot**

Run the launch-and-screenshot commands, writing to `…/scratchpad/sheets-task1.png`, then **Read the PNG**.

Expect the unchanged empty-library state: "Library" title, an enabled "+" in the toolbar, the blue `music.note.house` hero, "No music yet", the subtitle "Import audio files from the Files app.", an "Import Music" button, and nothing at the bottom edge.

This is a launch regression check only. The sheet itself cannot be opened — there is no track to play. Report what you actually observe, and state plainly that the sheet was not exercised.

- [ ] **Step 1.8: Add the scrubber risk to the QA guide**

In `docs/superpowers/plans/2026-08-01-phase2a-qa-guide.md`, find the section headed `## Nhóm 2 — Lỗi đã biết còn tồn đọng, cần bạn xác nhận mức độ` and add this entry at the end of that section:

```markdown
### 2.4 Kéo thanh scrubber có làm đóng sheet không?  ⚠️ chưa kiểm chứng được
Mở Now Playing, kéo thanh scrubber để tua bài — kéo vài lần, cả chậm lẫn nhanh.

**Câu hỏi cụ thể:** có lần nào sheet bị đóng lại thay vì tua không?

Now Playing giờ là `.sheet`, nên kéo dọc ở vùng trống sẽ đóng nó. Kéo ngang để tua thì đúng, nhưng nếu ngón tay lệch dọc lúc bắt đầu, hệ thống có thể hiểu nhầm. Apple Music cũng có đặc tính này.

- Nếu **không bao giờ** xảy ra → không cần làm gì
- Nếu **thỉnh thoảng** xảy ra → cho tôi biết tần suất, có cách giới hạn cử chỉ của slider
```

- [ ] **Step 1.9: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar docs
git commit -F - <<'MSG'
feat: present Now Playing as a draggable sheet instead of a full-screen cover

Now Playing could only be dismissed with a small chevron in the top-left
corner. It is now a standard .large sheet with a grabber, so dragging down
returns to the mini player the way every other iOS music app behaves. The
hand-rolled chevron and its dismiss environment value are gone.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Task 2: `ImportProgressSheet` gains honest affordances and stops clipping

**Goal:** The import sheet can be dragged up when its summary is long, its grabber appears only when dragging actually works, and its failure-reason list can never be cut off.

**Files:**
- Modify: `Evenstar/Evenstar/Features/Library/LibraryView.swift:59-66`
- Modify: `Evenstar/Evenstar/Features/Import/ImportProgressSheet.swift:14-61`, `:85-88`

**Interfaces:**
- Consumes: `ImportProgressSheet(urls:inaccessibleFailures:importer:)`, `ImportService.isImporting`, `ImportSummary` — all unchanged.
- Produces: nothing new. The initialiser signature is untouched.

**Background — the bug this closes.** Phase 2a's final review parked an item (P2): `ImportError.fileNotAccessible` embeds the filename in its message, so N inaccessible files produce N *distinct* reasons that the existing dedupe cannot collapse. Four Vietnamese filenames wrap to two lines each — roughly 118 pt against about 100 pt of headroom in a `.medium` detent, with no scrolling. The text clips. Picking undownloaded iCloud Drive files is the most likely way to hit it.

### Steps

- [ ] **Step 2.1: Allow the import sheet to be dragged up**

In `Evenstar/Evenstar/Features/Library/LibraryView.swift`, replace this block:

```swift
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(
                urls: accessibleURLs,
                inaccessibleFailures: inaccessibleFailures,
                importer: importer
            )
            .presentationDetents([.medium])
        }
```

with:

```swift
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(
                urls: accessibleURLs,
                inaccessibleFailures: inaccessibleFailures,
                importer: importer
            )
            .presentationDetents([.medium, .large])
        }
```

The drag indicator is set inside `ImportProgressSheet` itself, in the next step, because it depends on that view's `importer.isImporting` state.

- [ ] **Step 2.2: Show the grabber only when dragging actually works, and stop the summary clipping**

In `Evenstar/Evenstar/Features/Import/ImportProgressSheet.swift`, replace the whole `body`:

```swift
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
                if !failureReasons(for: summary).isEmpty {
                    failureReasonsList(for: summary)
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
            let result = await importer.importFiles(at: urls)
            summary = ImportSummary(
                imported: result.imported,
                failures: result.failures + inaccessibleFailures,
                duplicates: result.duplicates
            )
        }
    }
```

with:

```swift
    var body: some View {
        Group {
            if importer.isImporting || summary == nil {
                VStack(spacing: 20) {
                    ProgressView(
                        value: Double(importer.progress.completed),
                        total: Double(max(importer.progress.total, 1))
                    )
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 32)
                    Text("Importing \(importer.progress.completed) of \(importer.progress.total)")
                        .font(.body)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary {
                // Scrolls because the failure-reason list has no fixed height:
                // `.fileNotAccessible` embeds the filename, so those reasons
                // never dedupe and several long ones can exceed the detent.
                ScrollView {
                    VStack(spacing: 20) {
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
                        if !failureReasons(for: summary).isEmpty {
                            failureReasonsList(for: summary)
                        }
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .interactiveDismissDisabled(importer.isImporting)
        // Hidden while importing: dismissal is disabled then, and a grabber
        // the user cannot act on is a false affordance.
        .presentationDragIndicator(importer.isImporting ? .hidden : .visible)
        .task {
            let result = await importer.importFiles(at: urls)
            summary = ImportSummary(
                imported: result.imported,
                failures: result.failures + inaccessibleFailures,
                duplicates: result.duplicates
            )
        }
    }
```

Note what changed and what did not. The in-progress branch keeps its centred layout via `maxHeight: .infinity`; only the summary branch scrolls, and it drops `maxHeight` because a `ScrollView`'s content sizes to itself. `.interactiveDismissDisabled`, `.task`, and both helper functions are unchanged.

- [ ] **Step 2.3: Correct the stale comment on the reason cap**

In the same file, replace this doc comment:

```swift
    /// Caps the visible list at 4 distinct reasons, folding the rest into a
    /// "+N more" line so a batch with many different failure kinds doesn't
    /// blow out the sheet's `.medium` presentation detent.
```

with:

```swift
    /// Caps the visible list at 4 distinct reasons, folding the rest into a
    /// "+N more" line to keep the common case tidy. The sheet also scrolls
    /// and can be dragged to `.large`, so the cap is about readability now
    /// rather than about fitting a fixed height.
```

- [ ] **Step 2.4: Clean build**

Run the clean-build command. Expect exactly `** BUILD SUCCEEDED **`. Report the output verbatim.

- [ ] **Step 2.5: Run the full test suite**

Run the test command. **Expect 47 passing, 0 failures.**

- [ ] **Step 2.6: Launch and screenshot**

Run the launch-and-screenshot commands, writing to `…/scratchpad/sheets-task2.png`, then **Read the PNG**. Expect the unchanged empty-library state described in Step 1.7.

The import sheet cannot be opened here — it requires driving the Files-app picker by hand. Say so plainly.

- [ ] **Step 2.7: Update the QA guide's iCloud entry**

In `docs/superpowers/plans/2026-08-01-phase2a-qa-guide.md`, the entry `### 2.2 Import file iCloud chưa tải về` currently describes the clipping as an open problem. Replace its final two paragraphs — the one beginning `- **Vấn đề đã biết (P2):**` and the line `Cho tôi biết nó bị cắt hay vẫn đọc được.` — with:

```markdown
- **Đã sửa:** sheet giờ cuộn được và kéo lên cao được, nên danh sách lý do không còn bị cắt. Việc của bạn là xác nhận: kéo sheet lên và cuộn thử, có đọc được hết mọi lý do không?
```

- [ ] **Step 2.8: Commit**

```bash
cd /Users/phanquyetthang/evenstar
git add Evenstar docs
git commit -F - <<'MSG'
fix: let the import sheet scroll and expand, and stop faking its grabber

The summary could clip: fileNotAccessible embeds the filename, so those
reasons never dedupe and several long ones exceeded the fixed .medium
detent with no way to scroll. The summary now scrolls and the sheet can be
dragged to .large. The grabber is hidden while importing, where
interactiveDismissDisabled means dragging does nothing.

Closes the P2 item parked during the Phase 2a final review.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

## Out of scope

Explicitly NOT in this plan, and recorded so the decisions are not re-litigated by accident:

- **The Apple Music matched-geometry morph** — artwork growing continuously from the 40 pt mini-player thumbnail into the full hero, the bar itself becoming the card. `matchedGeometryEffect` does not work across `.sheet` or `.fullScreenCover` boundaries, so this requires abandoning system presentation for a hand-built `ZStack` overlay with its own drag gesture, rubber-banding and safe-area handling. Deferred by explicit decision.
- Blurred artwork-tinted background behind `NowPlayingView`.
- Hiding the mini player while `NowPlayingView` is open.
- Constraining the scrubber's gesture so a vertical drift cannot dismiss the sheet. This is a real risk but an unmeasured one; Task 1 adds it to the QA guide so it is fixed with evidence rather than in anticipation.
- Any change to playback, queue, persistence, or import logic.

---

## Self-review

- ✅ Spec §4.1 (`LibraryView`) → Task 1 Step 1.1 and Task 2 Step 2.1.
- ✅ Spec §4.2 (`NowPlayingView`) → Task 1 Steps 1.2, 1.3, 1.4 — handle removed, `dismiss` removed, padding 8 → 24.
- ✅ Spec §4.3 (`ImportProgressSheet`) → Task 2 Steps 2.2 and 2.3 — conditional indicator and `ScrollView` on the summary branch only, as the spec specifies.
- ✅ Spec §5 (verification) → clean build, 47 tests, screenshot in both tasks, with the honest limit stated in both.
- ✅ Spec §6 (known risk) → Task 1 Step 1.8 adds the scrubber question to the QA guide; the Out of scope section records why it is not pre-emptively fixed.
- ✅ Spec §7 (files changed) → the four files in the table are exactly those touched, and the QA guide is touched by both tasks (1.8 adds an entry, 2.7 updates one).
- ✅ Placeholder scan: no TBD or TODO, no "add appropriate error handling", no "similar to Task N". Every code step shows complete before-and-after code.
- ✅ Type consistency: no new types, functions or signatures are introduced. `NowPlayingView(playback:)` and `ImportProgressSheet(urls:inaccessibleFailures:importer:)` keep their existing initialisers, so no call site outside these files changes.
- ✅ Task boundaries: a reviewer can reject Task 2 while approving Task 1 — they touch different surfaces and different files, sharing only `LibraryView`'s modifier chain in non-overlapping places.
