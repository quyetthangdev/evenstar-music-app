//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData
import OSLog

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer
    @State private var library: LibraryService
    @State private var importService: ImportService
    @State private var playback: PlaybackService
    @State private var driveLibrary: DriveLibraryService
    @State private var jamendoLibrary: JamendoLibraryService
    /// The local library, fetched once and read by five screens. See
    /// `LibraryStore` for why it is not five `@Query`s any more.
    @State private var libraryStore: LibraryStore
    /// Tìm kiếm's result list, owned here rather than by the screen so the
    /// delete hook below can prune it. See `SearchResultsStore`.
    @State private var searchResults: SearchResultsStore
    private let remoteCommands: RemoteCommandsBridge

    init() {
        let container: ModelContainer
        do {
            // Một container, **hai** kho: bốn bảng thư viện đồng bộ qua
            // CloudKit, `PlaybackState` ở lại máy này. Toàn bộ lý lẽ — kể cả
            // vì sao kho thư viện phải giữ tên mặc định — nằm ở
            // `EvenstarStores`.
            container = try EvenstarStores.makeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        let libService = LibraryService(context: container.mainContext)
        let imp = ImportService(library: libService, metadataReader: AudioMetadataReader())
        let now = NowPlayingService()
        // Not `AVAudioPlayerWrapper()` directly any more: that one cannot open an
        // https URL, so every Drive track would fail to load. The router owns one
        // of each engine and picks by URL — see `RoutingAudioPlayer`.
        let player = RoutingAudioPlayer()
        let play = PlaybackService(player: player, nowPlaying: now, library: libService)
        // Seeded here, synchronously, so the first frame renders the real
        // library instead of the empty state — see `LibraryStore.init`. The
        // same sort the query uses, because the two have to agree.
        //
        // The cost, said plainly: one extra fetch and one extra localized sort
        // on the launch path, which `LibraryQueryBridge` repeats the moment it
        // first updates. That is a real cost on the very path this change exists
        // to make cheaper, and it is kept only because the alternative is a
        // possible frame of `EmptyLibraryView` in front of a user whose library
        // is full. It stays one fetch where this screenful used to cost five.
        //
        // A failed seed is survivable and so is not fatal: the bridge fills the
        // store on the first update pass regardless.
        let store: LibraryStore
        // Cùng lượt quét mà `replace(with:)` sẽ chạy lại về sau, làm ngay ở đây
        // để khung hình đầu tiên vẽ đúng hàng nào mờ — không phải vẽ đủ rồi mờ
        // đi ở khung thứ hai.
        let present = TrackPresence.scan()
        do {
            store = LibraryStore(tracks: try libService.fetchAllTracks(),
                                 presence: present)
        } catch {
            // 2a: log only, like `SongsView.deleteTrack`. A user-facing failure
            // path for the library not opening at all belongs to 2d.
            AppLog.library.error("Initial library fetch failed: \(error.localizedDescription, privacy: .public)")
            store = LibraryStore(presence: present)
        }
        // The local library's half of the same wiring the two remote sources get
        // below. `SongsView.deleteTrack` used to make this call by hand, which
        // held only for as long as it stayed the single caller of
        // `library.delete(_:)`. See `LibraryService.onTrackWillBeDeleted`.
        //
        // Three riders on one closure — the playing queue, the songs list, and
        // Tìm kiếm's own filtered list — and each of them has to land on this
        // hook rather than in a refresh afterwards, because each must run while
        // the row is still readable. See `LibraryStore.remove(_:)` for the
        // crash they close.
        //
        // The closure body lives in `LibraryDeletionWiring` rather than here,
        // and only so a test can reach it: nothing built inside `App.init` is
        // reachable from a unit test, so the coverage for a single point of
        // failure this size was a copy of the closure rebuilt inside the test.
        let search = SearchResultsStore()
        LibraryDeletionWiring.install(
            on: libService, playback: play, store: store, search: search
        )
        let driveLib = DriveLibraryService(library: libService)
        // The only wiring that keeps a deleted `DriveTrack` out of the playing
        // queue. Unlinking a folder, and a rescan that finds a file gone from
        // Drive, both delete rows the queue may be holding. Without it the queue
        // reads properties off deleted-and-saved rows and raises an uncatchable
        // Objective-C exception. See `DriveLibraryService.onTrackWillBeDeleted`.
        //
        // No retain cycle: `PlaybackService` holds no reference to
        // `DriveLibraryService`, and both are owned for the app's lifetime by
        // the `@State` properties above.
        driveLib.onTrackWillBeDeleted = { play.handleTrackDeleted($0) }
        let jamendoLib = JamendoLibraryService(library: libService)
        // Same wiring as `driveLib` above, and for the same reason: without
        // it, deleting a saved Jamendo track that is in the queue (or
        // currently playing) leaves the queue holding a deleted-and-saved
        // row and raises an uncatchable Objective-C exception the next time
        // anything reads a property off it. See
        // `JamendoLibraryService.onTrackWillBeDeleted`.
        jamendoLib.onTrackWillBeDeleted = { play.handleTrackDeleted($0) }
        _libraryStore = State(initialValue: store)
        _searchResults = State(initialValue: search)
        _library = State(initialValue: libService)
        _importService = State(initialValue: imp)
        _playback = State(initialValue: play)
        _driveLibrary = State(initialValue: driveLib)
        _jamendoLibrary = State(initialValue: jamendoLib)
        remoteCommands = RemoteCommandsBridge(playback: play)
        remoteCommands.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(importService)
                .environment(playback)
                .environment(driveLibrary)
                .environment(jamendoLibrary)
                .environment(libraryStore)
                .environment(searchResults)
                // ─────────────────────────────────────────────────────────
                // MỘT `.task` LÚC MỞ APP, VÀ THỨ TỰ BÊN TRONG LÀ BẮT BUỘC
                // ─────────────────────────────────────────────────────────
                // Quét trùng **trước**, khôi phục hàng đợi **sau**, tuần tự
                // trong cùng một task. Đừng tách ra thành hai `.task` song
                // song cho app mở nhanh hơn: đó chính là hình dạng vừa bị sửa,
                // và đây là chuyện nó làm.
                //
                // Trước, lượt quét nằm ở `.task` này còn khôi phục nằm ở một
                // `.task` bên trong `RootView`. **SwiftUI không xếp thứ tự hai
                // `.task` anh em.** Nếu khôi phục thắng, hàng đợi trong bộ nhớ
                // đang giữ đúng hàng mà lượt quét sắp xoá — và lượt quét báo
                // từng hàng sắp xoá qua `PlaybackService.handleTrackDeleted`.
                // Nhánh xấu nhất: hàng bị gộp đi là bài **đang phát**, nằm
                // **cuối** hàng đợi, repeat **tắt**. `handleTrackDeleted` rơi
                // vào `queueIndex >= queue.count`, gọi `stopPlayback()`, rồi
                // ghi đè `PlaybackState` bằng một hàng đợi rỗng. Người dùng mở
                // lại app và thấy hàng đợi lẫn vị trí đang nghe biến mất sạch.
                //
                // Chạy tuần tự thì lượt quét xong khi hàng đợi trong bộ nhớ
                // vẫn còn **rỗng** — chưa có gì để `handleTrackDeleted` phá —
                // và `PlaybackState` mà `restoreFromPersistedState` đọc ngay
                // sau đó đã được trỏ lại và khử trùng lặp xong. Cái móc báo
                // trước vẫn giữ, nhưng từ đây nó là dây bảo hiểm chứ không còn
                // là thứ đứng giữa người dùng và một hàng đợi bị xoá trắng.
                //
                // Ở đây chứ không trong `RootView`: đây là chỗ duy nhất cả
                // `modelContainer` lẫn `playback` đều sẵn trong tầm, và thân
                // `RootView` mang `.id(language)`, thứ có thể dựng lại một
                // `.task` nằm bên trong khi người dùng đổi ngôn ngữ. `.task`
                // này bám vào `RootView()` ở `WindowGroup`, ngoài chỗ `.id`
                // với tới được, nên nó chạy đúng **một** lượt mỗi lần mở app.
                .task {
                    // Một lượt mỗi lần mở app. Hàng trùng đến trong phiên này
                    // được dọn ở lần mở sau — xem `DuplicateSweep`.
                    //
                    // `onRowWillBeDeleted` là bản thứ tư của cùng cái móc mà
                    // `libService`, `driveLib` và `jamendoLib` đã có ở trên, và
                    // nó phải có ở đây vì lượt quét cũng xoá hàng.
                    //
                    // Thất bại chỉ ghi log: một lượt dọn dẹp không chạy được
                    // không phải lý do để chặn người dùng nghe nhạc — và cũng
                    // không phải lý do để bỏ luôn bước khôi phục bên dưới, nên
                    // `catch` nằm quanh riêng lượt quét.
                    do {
                        try DuplicateSweep.run(
                            context: modelContainer.mainContext,
                            onRowWillBeDeleted: { playback.handleTrackDeleted($0) }
                        )
                    } catch {
                        AppLog.library.error(
                            "Lượt gộp trùng thất bại: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    // Khôi phục hàng đợi đã lưu là việc của lúc mở app, nên nó
                    // ở gốc chứ không ở một tab nào. Ở Bài hát thì nó chỉ chạy
                    // được nhờ tab ấy tình cờ được chọn trước, và sẽ âm thầm
                    // hỏng vào ngày tab mặc định đổi.
                    await playback.restoreFromPersistedState()
                }
        }
        .modelContainer(modelContainer)
    }
}
