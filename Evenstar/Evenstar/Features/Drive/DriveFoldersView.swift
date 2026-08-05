import SwiftUI
import SwiftData

// NOTE: this file is Task 8's Step 1, landed here in Task 7 unchanged.
//
// Task 7's brief presents `DriveSongsList` with `.sheet { DriveFoldersView() }`
// and an empty state whose only button opens it, so Task 7 does not compile
// without this type existing — an ordering gap in the plan, not a decision made
// here. It is the plan's own code, copied as written; Task 8's Step 2 (the
// Tài khoản row) is deliberately left undone so Task 8 still owns this screen.

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

    private func add() async {
        errorMessage = nil
        guard let folderID = DriveLinkParser.folderID(from: link) else {
            errorMessage = "Đây không phải link thư mục Drive. Mở thư mục trên Drive, bấm Chia sẻ và sao chép liên kết."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let folder = try driveLibrary.link(folderID: folderID, displayName: name)
            try await driveLibrary.scan(folder)
            link = ""
            name = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
