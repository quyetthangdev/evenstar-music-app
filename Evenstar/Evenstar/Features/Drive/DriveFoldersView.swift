import SwiftUI
import SwiftData

// NOTE: this file is Task 8's Step 1, landed here in Task 7 unchanged.
//
// Task 7's brief presents `DriveSongsList` with `.sheet { DriveFoldersView() }`
// and an empty state whose only button opens it, so Task 7 does not compile
// without this type existing — an ordering gap in the plan, not a decision made
// here. It is the plan's own code, copied as written, with `unlink` reporting
// errors instead of discarding them (see below) and `add`'s partial-failure
// path fixed against a duplicate insert (see its doc comment) — both closed
// out by Task 8, which also adds the Tài khoản → Nguồn nhạc row.

/// Add, rescan and unlink Drive folders. Reached from the Drive list's `…`
/// button and from Tài khoản → Nguồn nhạc — the same screen both times, but
/// not the same navigation context: see `showsDoneButton` below.
struct DriveFoldersView: View {
    @Environment(DriveLibraryService.self) private var driveLibrary
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\DriveFolder.linkedAt)]) private var folders: [DriveFolder]

    /// Whether this instance draws its own "Xong" button to leave the screen.
    ///
    /// Defaults to `true` for the sheet call site (`DriveSongsList`): a sheet
    /// has no back chevron, so without this button there is no way off the
    /// screen at all. The pushed call site (`AccountView`'s `NavigationLink`)
    /// passes `false`: the pushed navigation bar already supplies a back
    /// chevron that does the same job, and a second "Xong" button beside it
    /// would be redundant chrome, not a second way to leave.
    var showsDoneButton: Bool = true

    @State private var link = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    /// Seeded from whether anything is linked yet — see the section itself.
    @State private var isHelpExpanded = false

    /// The three steps that happen outside this app.
    ///
    /// Static and plain rather than a formatted string, so each step is its own
    /// line at any Dynamic Type size. Named in the order they are performed, and
    /// naming the buttons as Drive labels them rather than describing them, so
    /// the user is matching words rather than interpreting.
    private static var linkSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Mở ứng dụng Google Drive, giữ vào thư mục nhạc.")
            Text("2. Chọn **Chia sẻ** → **Quản lý quyền truy cập**, đổi thành **Bất kỳ ai có đường liên kết**.")
            Text("3. Bấm **Sao chép đường liên kết**, rồi quay lại đây và dán vào ô trên.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    // No `NavigationStack` here — matching `AlbumDetailView` and
    // `ArtistDetailView`, the app's other two push destinations, which also
    // leave navigation context to their caller and add a `NavigationStack`
    // only inside `#Preview`. `AccountView` already owns a `NavigationStack`;
    // wrapping this body in a second one gave the pushed route two stacked
    // title bars — an outer "‹ Tài khoản" above an inner "Thư mục Drive" —
    // which also pushed the sharing warning below the fold. The sheet call
    // site in `DriveSongsList` supplies its own `NavigationStack` instead.
    var body: some View {
        List {
            // The privacy warning is this section's **footer**, not a section of
            // its own further down the list. That is a product requirement, not
            // layout: the spec calls saying a link-shared folder is readable by
            // anyone with the link "the single most important thing for a
            // reviewer to check", and it has to be said *at the moment of
            // linking*.
            //
            // It used to be section 3 of 3, below "Đã liên kết" — a list that
            // grows without bound. Task 8 verified it by screenshot in the
            // zero-folder state, where it is one row down and perfectly visible;
            // with six folders linked it is off the bottom of the screen, and a
            // user reaching this screen from Tài khoản → Nguồn nhạc could paste,
            // type, tap Liên kết and never see the sentence. A footer cannot
            // drift that way: it is bound to the section it explains and renders
            // immediately under the "Liên kết" button, which is the last thing
            // the eye passes before the tap.
            //
            // **Tapping "Liên kết" deliberately does not restate it in a
            // confirmation dialog.** The sentence is on screen, adjacent to the
            // button, at the instant of the tap — a dialog would be a second
            // reading of text the user is already looking at, and one shown on
            // every folder becomes a dialog people dismiss without reading. That
            // trains the warning to be ignored, which is a worse outcome than
            // stating it once, in the right place, and leaving it there.
            Section {
                // `.URL` on both counts: the keyboard gains the `/` and `.`
                // keys and a `.com` key, and the content type lets the system
                // offer a URL sitting on the clipboard. Neither was set, and a
                // field whose placeholder says "paste a link" arriving with a
                // plain alphabet keyboard is the kind of mismatch the interface
                // guidelines are explicit about.
                TextField("Dán link thư mục Drive", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.next)
                // Optional, and the placeholder says so. Nothing here needs the
                // user's answer — the name is a label in a list — so requiring
                // one made them invent something before they were allowed to do
                // what they came to do. Blank is resolved by
                // `DriveLibraryService.link`, which is the only place that knows
                // whether this folder is new or already named.
                TextField("Tên hiển thị (không bắt buộc)", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                // The row keeps its identity while working — same button, label
                // swapped, spinner on the trailing edge — rather than being
                // replaced by a status row. A row that appears and disappears
                // moves the footer under it, and the footer is the privacy
                // warning.
                //
                // Before this, `isWorking` only *disabled* the button: the user
                // tapped Liên kết, the row went grey, and nothing else happened
                // for as long as the network took. Feedback for anything that is
                // not instantaneous is not optional.
                Button {
                    Task { await add() }
                } label: {
                    HStack {
                        // Two `Text`s rather than one with a ternary. A
                        // ternary whose other branch is a `String` types the
                        // whole expression as `String`, which picks `Text`'s
                        // non-localizing initialiser and drops "Liên kết" out
                        // of the catalog without any visible sign.
                        if isWorking {
                            Text(workingStatus)
                        } else {
                            Text("Liên kết")
                        }
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(link.isEmpty || isWorking)
            } header: {
                Text("Thêm thư mục")
            } footer: {
                Text("Thư mục phải được chia sẻ ở chế độ “bất kỳ ai có liên kết”. Nghĩa là bất kỳ ai có link đều xem được nhạc trong đó.")
            }

            // Its own section, below the form rather than inside it.
            //
            // Inside, expanding it would push the "Liên kết" button and — worse
            // — the privacy footer down the screen, which is the one thing on
            // this screen that must not move out of sight. Below, opening it
            // moves only the list of linked folders.
            //
            // Open by default the first time, closed afterwards: the guidelines
            // put helping someone avoid an error ahead of reporting it, and this
            // flow *requires* leaving the app to fetch something. A collapsed
            // disclosure that nobody opens does not help a first-time user; a
            // permanently expanded one is clutter for everybody else.
            Section {
                DisclosureGroup("Cách lấy link", isExpanded: $isHelpExpanded) {
                    Self.linkSteps
                }
            }

            Section("Đã liên kết") {
                if folders.isEmpty {
                    Text("Chưa có thư mục nào").foregroundStyle(.secondary)
                }
                ForEach(folders) { folder in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName)
                            // `LocalizedStringKey` spelled out: with two bare
                            // literals the ternary's type comes from context,
                            // and `Text` offers an initialiser for `String`
                            // too. Naming the type is what guarantees the
                            // catalog is consulted.
                            Text(folder.lastScannedAt == nil
                                 ? LocalizedStringKey("Chưa quét")
                                 : LocalizedStringKey("Đã quét"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if driveLibrary.scanningFolderID == folder.folderID {
                            Spacer()
                            ProgressView()
                        }
                    }
                    // Leading for the constructive action, trailing for the
                    // destructive one — the arrangement Mail uses, and the one a
                    // thumb already knows.
                    //
                    // A row that shows a state usually has to offer the action
                    // that changes it. "Chưa quét" is the state a user lands on
                    // when the key is wrong, the folder is private or the network
                    // dropped; before this, the only documented way out was to
                    // re-paste the same link into the form above, which is a
                    // recovery nobody would guess at.
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await rescan(folder) }
                        } label: {
                            Label("Quét lại", systemImage: "arrow.clockwise")
                        }
                        .tint(.accentColor)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            unlink(folder)
                        } label: {
                            Label("Gỡ", systemImage: "trash")
                        }
                    }
                }
            }
        }
        // Runs once per presentation. `@State` cannot be initialised from a
        // `@Query`, and this only has to be right at the moment the screen
        // opens: linking the first folder mid-session leaves the help open,
        // which is correct — that user has just used it.
        .task { isHelpExpanded = folders.isEmpty }
        .navigationTitle("Thư mục Drive")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    /// What the button says while the network is out.
    ///
    /// Two phases, because the wait has two and they take very different
    /// lengths of time. Listing a folder is one or more round trips and is
    /// almost all of the wall clock; reconciling the rows afterwards is local
    /// and quick. `DriveLibraryService` already published `scannedFileCount`
    /// for exactly this, with a doc comment saying "so the list can show
    /// progress" — nothing had ever read it.
    private var workingStatus: String {
        let seen = driveLibrary.scannedFileCount
        guard seen > 0 else {
            return String(
                localized: "Đang quét thư mục…",
                bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
            )
        }
        return String(
            localized: "Đang lưu \(seen) bài…",
            bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
        )
    }

    /// The plan writes this as `try? driveLibrary.unlink(folder)`. Reported
    /// instead of discarded: a swipe that appears to delete and does not is the
    /// worst kind of silent failure, and the app forbids swallowing errors.
    private func unlink(_ folder: DriveFolder) {
        errorMessage = nil
        do {
            try driveLibrary.unlink(folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Task 7's review flagged this as carried-forward work: on the most
    /// likely first run (a folder linked before the API key is configured),
    /// `link()` succeeds and `scan()` throws. The plan's version left `link`
    /// and `name` untouched in that case, so the folder sat in "Đã liên kết"
    /// while the still-filled, still-enabled "Liên kết" button invited a
    /// second tap. At the time this was written, `folderID` carried
    /// `@Attribute(.unique)`, and SwiftData resolved a second insert with the
    /// same key as a silent upsert — no throw, just `linkedAt` (and, before
    /// this fix, `lastScannedAt`) reset out from under the row that is
    /// already there. CloudKit sync (Task 1) later removed that attribute —
    /// CloudKit rejects it — so a second insert now would not upsert at all;
    /// it would produce a second row outright. Either way the fix below is
    /// what actually prevents the duplicate: `link()`'s fetch-existing-or-insert
    /// guard never depended on the attribute.
    ///
    /// Two changes close both the accidental and the deliberate path to that
    /// duplicate insert:
    ///
    /// 1. `driveLibrary.link` now fetches an existing folder for this
    ///    `folderID` and reuses it instead of always inserting — see its own
    ///    doc comment for why that check lives there and not here as a read
    ///    of `folders`, the `@Query` snapshot from the last render pass. This
    ///    is what makes a manual retry (the user re-pastes the same link once
    ///    the API key is fixed) a rescan rather than a duplicate, and it also
    ///    means a retyped display name lands on the existing row rather than
    ///    being silently dropped.
    /// 2. The fields are cleared the moment `link()` returns — whether it
    ///    inserted or reused — not after `scan()` also succeeds, so a
    ///    same-state re-tap of "Liên kết" is no longer possible: the button
    ///    disables itself.
    ///
    /// The folder *is* linked at that point; only the scan may fail. So the
    /// error surfaced here is scan-shaped ("Chưa cấu hình API key…", "Thư mục
    /// này chưa được chia sẻ công khai…", …), not "linking failed" — and the
    /// row is exactly where a user recovering from that error needs it: already
    /// listed under "Đã liên kết", marked "Chưa quét", ready to rescan by
    /// pasting the same link again.
    private func add() async {
        errorMessage = nil
        guard let folderID = DriveLinkParser.folderID(from: link) else {
            errorMessage = String(
                localized: "Đây không phải link thư mục Drive. Mở thư mục trên Drive, bấm Chia sẻ và sao chép liên kết.",
                bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
            )
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            // `name` passed straight through, blank included: `link` resolves
            // it, because only it knows whether this folder is new (take a
            // default) or already linked (keep the name it has).
            let folder = try driveLibrary.link(folderID: folderID, displayName: name)
            link = ""
            name = ""
            try await driveLibrary.scan(folder)
            // Both halves succeeded, so the task this screen was opened to do is
            // finished — and a modal whose task is finished closes itself.
            //
            // **Only when it is a modal.** `showsDoneButton` already carries
            // exactly that distinction: true means the sheet from the Drive
            // list, where staying leaves the user on a form with its primary
            // action disabled and nothing saying what happened; false means the
            // pushed screen under Tài khoản → Nguồn nhạc, which is a management
            // screen the user navigated *to* and popping it out from under them
            // would be wrong.
            //
            // After the `scan`, never before: a scan that throws is exactly the
            // case where the user has to stay and read the error.
            if showsDoneButton { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rescans one already-linked folder, from its own row.
    ///
    /// Shares `errorMessage` with `add` rather than carrying its own: only one
    /// of the two can be running, and a second error slot would be a second
    /// place for a stale message to sit.
    private func rescan(_ folder: DriveFolder) async {
        errorMessage = nil
        do {
            try await driveLibrary.scan(folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create preview ModelContainer: \(error)")
    }
    let library = LibraryService(context: container.mainContext)
    let driveLibrary = DriveLibraryService(library: library)
    return NavigationStack {
        DriveFoldersView()
    }
    .environment(driveLibrary)
    .modelContainer(container)
}
