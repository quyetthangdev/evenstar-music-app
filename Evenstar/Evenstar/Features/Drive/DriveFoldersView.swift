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
                        Text(isWorking ? workingStatus : "Liên kết")
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
                            unlink(folder)
                        } label: {
                            Label("Gỡ", systemImage: "trash")
                        }
                    }
                }
            }
        }
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
        return seen > 0 ? "Đang lưu \(seen) bài…" : "Đang quét thư mục…"
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
    /// second tap. `folderID` carries `@Attribute(.unique)`, and SwiftData
    /// resolves a second insert with the same key as a silent upsert — no
    /// throw, just `linkedAt` (and, before this fix, `lastScannedAt`) reset
    /// out from under the row that is already there.
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
            errorMessage = "Đây không phải link thư mục Drive. Mở thư mục trên Drive, bấm Chia sẻ và sao chép liên kết."
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
