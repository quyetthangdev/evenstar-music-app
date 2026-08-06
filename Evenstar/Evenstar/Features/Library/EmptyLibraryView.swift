import SwiftUI

/// The Bài hát tab with nothing in it.
///
/// Built on `ContentUnavailableView` like every other empty state in the app
/// (`AlbumsView`, `ArtistsView`, `SearchView`, `DriveSongsList`) rather than on
/// a hand-stacked `VStack`. The hand-built version this replaced had drifted:
/// a 64pt glyph where the framework uses its own metric, and a
/// `systemGroupedBackground` fill that no other empty state has — so the tab
/// with no music had a visibly different background from the tab with no
/// albums.
///
/// It stays a named view rather than being inlined into `SongsView` only
/// because it takes a callback; the mechanism is now the shared one.
struct EmptyLibraryView: View {
    let onImportTap: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Chưa có bài hát nào", systemImage: "music.note.house")
        } description: {
            Text("Nhập file nhạc từ ứng dụng Tệp để bắt đầu.")
        } actions: {
            Button("Thêm nhạc", action: onImportTap)
                .buttonStyle(.prominentAction)
        }
    }
}
