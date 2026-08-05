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
/// button and from Tài khoản → Nguồn nhạc — the same screen both times.
struct DriveFoldersView: View {
    @Environment(DriveLibraryService.self) private var driveLibrary
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\DriveFolder.linkedAt)]) private var folders: [DriveFolder]

    @State private var link = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section("Thêm thư mục") {
                    TextField("Dán link thư mục Drive", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Tên hiển thị", text: $name)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Liên kết") { Task { await add() } }
                        .disabled(link.isEmpty || name.isEmpty || isWorking)
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

                Section {
                    Text("Thư mục phải được chia sẻ ở chế độ “bất kỳ ai có liên kết”. Nghĩa là bất kỳ ai có link đều xem được nhạc trong đó.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Thư mục Drive")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
        }
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
    /// 1. A folder already linked under this `folderID` — exactly the state
    ///    left behind by a `link()`-succeeds/`scan()`-throws run — is looked
    ///    up and reused instead of re-inserted. This is also what makes a
    ///    manual retry (the user re-pastes the same link once the API key is
    ///    fixed) a rescan rather than a duplicate.
    /// 2. The fields are cleared the moment a `DriveFolder` exists for this
    ///    text — right after `link()` succeeds or an existing folder is
    ///    found, not after `scan()` also succeeds — so a same-state re-tap of
    ///    "Liên kết" is no longer possible: the button disables itself.
    ///
    /// The folder *is* linked at that point; only the scan failed. So the
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
            let folder = try folders.first(where: { $0.folderID == folderID })
                ?? driveLibrary.link(folderID: folderID, displayName: name)
            link = ""
            name = ""
            try await driveLibrary.scan(folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
