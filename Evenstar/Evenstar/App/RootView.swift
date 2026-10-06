import SwiftUI

/// The app's root: the five destinations in a native `TabView`, with the player
/// card on top.
///
/// The tab bar, its scroll-minimise and the detached search tab are the
/// system's (iOS 26). The mini player lives in the bar's bottom accessory; the
/// full player is `PlayerCard`, which grows out of that accessory's frame.
struct RootView: View {
    /// Kho đã tụt xuống bộ nhớ tạm. Xem `EvenstarStores.Tier`.
    private let storeUnavailable: Bool

    /// Dựng từ `storeUnavailable` ngay trong `init` chứ không đặt trong một
    /// `.task`: `body` đã có một `.task` rồi, và hai `.task` anh em không được
    /// SwiftUI xếp thứ tự — xem ghi chú ở cuối `body` về đúng cái bẫy ấy.
    @State private var showingStoreWarning: Bool

    /// Mặc định `false` để `RootView()` không tham số vẫn dựng được:
    /// `ReduceMotionTests` dùng dạng ấy.
    init(storeUnavailable: Bool = false) {
        self.storeUnavailable = storeUnavailable
        _showingStoreWarning = State(initialValue: storeUnavailable)
    }

    /// Ba chuỗi của hộp thoại kho, tra ngoài environment.
    ///
    /// Xem ghi chú ở chỗ `.alert` cuối `body`: hộp thoại nằm trên
    /// `.environment(\.locale,)` nên `LocalizedStringKey` ở đó tra nhầm ngôn
    /// ngữ. Tách ra thành thuộc tính để chỗ gọi đọc được, và để test ghim được
    /// mà không phải dựng SwiftUI — cùng lý do `PlayerSubtitle` được tách khỏi
    /// `NowPlayingContent`.
    static var storeWarningTitle: String {
        String(localized: "Không mở được thư viện",
               bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
    }

    static var storeWarningDismiss: String {
        String(localized: "Đã hiểu",
               bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
    }

    static var storeWarningBody: String {
        String(localized: "Lần chạy này dùng bộ nhớ tạm, nên thư viện hiện ra trống dù nhạc trên máy vẫn còn nguyên. Đừng nhập lại — hãy đóng hẳn app rồi mở lại.",
               bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
    }

    @Environment(PlaybackService.self) private var playback
    @State private var tab: LibraryTab = .songs
    @State private var query = ""
    /// How far the player has opened, 0 collapsed to 1 full screen.
    ///
    /// A `@State` reference type, not a value: `RootView`'s body never reads
    /// `progress`, so it is not invalidated when the card moves. Only the one
    /// modifier that applies the transform re-runs. See `PlayerExpansion.swift`
    /// — the version before this was a `Binding`, and rebuilding this body and
    /// its five tabs on every dragged frame is what made the recede stutter.
    @State private var expansion = PlayerExpansion()

    /// The user's appearance override, or `.system` for none. Edited in
    /// `SettingsView`; both read the one key on `AppTheme`.
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    /// The system's Reduce Motion setting, and **the app's only read of it**.
    ///
    /// It is pushed straight into `BottomBarStyle.reduceMotion` below and never
    /// used by this body for anything else — every constant that has to answer
    /// the setting answers it there, not here. `grep accessibilityReduceMotion`
    /// returning exactly one hit is the invariant: the moment a second view
    /// reads the environment directly, two halves of the same morph can
    /// disagree within a frame, which is the failure that flag's doc comment
    /// exists to prevent.
    ///
    /// Reading it here rather than inside `BottomBarStyle` is what makes the
    /// value *live*. `UIAccessibility.isReduceMotionEnabled` would answer the
    /// same question from anywhere, but nothing would invalidate a view when it
    /// changed; an `@Environment` read is a dependency, so this body re-runs
    /// when the user flips the switch and the `.onChange` below gets to fire.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The user's language override. Read here only so this body re-runs when
    /// it changes — the value itself comes from `AppLanguage.resolvedLocale`,
    /// which everything outside a view uses too.
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    /// Lớp làm nóng đã được vẽ xong chưa — xem chỗ dùng nó bên dưới.
    @State private var hasWarmedPlayerChrome = false

    var body: some View {
        ZStack {
            // The app's one `@Query` on `Track`, in a view that draws nothing.
            // See `LibraryStore` — a `@Query` here would invalidate this body,
            // which rebuilds the `TabView` and all five tabs.
            LibraryQueryBridge()

            TabView(selection: $tab) {
                Tab(LibraryTab.songs.label, systemImage: LibraryTab.songs.symbol, value: LibraryTab.songs) {
                    SongsView()
                }
                Tab(LibraryTab.albums.label, systemImage: LibraryTab.albums.symbol, value: LibraryTab.albums) {
                    AlbumsView()
                }
                Tab(LibraryTab.artists.label, systemImage: LibraryTab.artists.symbol, value: LibraryTab.artists) {
                    ArtistsView()
                }
                Tab(LibraryTab.account.label, systemImage: LibraryTab.account.symbol, value: LibraryTab.account) {
                    AccountView()
                }
                Tab(value: LibraryTab.search, role: .search) {
                    SearchView(query: $query)
                }
            }
            // Thanh tab, cú thu nhỏ khi cuộn và tab tìm kiếm tách riêng đều là
            // của hệ thống — thay cho `FloatingTabBar` và `ScrollMinimise`.
            .tabBarMinimizeBehavior(.onScrollDown)
            // The content recedes as the player opens. The transform lives in
            // the modifier, not here — see `PlayerExpansion.swift`.
            .recedesBehindPlayer(expansion)

            // Trả trước hoá đơn vẽ-lần-đầu của chrome mở rộng: xem ghi chú cũ
            // ở bản trước của file này (git log) — lý lẽ không đổi.
            if !hasWarmedPlayerChrome {
                NowPlayingContent(playback: playback, showingQueue: .constant(false))
                    .padding(.horizontal, 24)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(-1)
            }

            // Tạm cho tới Task 5: thẻ cũ, không bao giờ thu nhỏ.
            PlayerCard(playback: playback, minimised: 0, expansion: expansion)
        }
        // The one write of `BottomBarStyle.reduceMotion`, in the whole app.
        //
        // In an action closure and not in the body above, deliberately: the
        // body is SwiftUI evaluating a view, and writing global state during
        // that is undefined behaviour — the flag would be read by some views on
        // this pass and by others on the next one, which is precisely the
        // split-frame disagreement the flag exists to rule out.
        //
        // `initial: true` is load-bearing rather than tidy. Without it the flag
        // stays `false` for a session that launched with Reduce Motion already
        // on, and only corrects itself if the user goes and toggles the setting
        // — so the people this is for would be the one group it never reached.
        //
        // The first evaluation of every body below therefore captures the
        // default `false`. That is harmless and worth stating so nobody hunts
        // it: nothing animates on the first frame, `withAnimation` sites read
        // the constant at the moment they fire, and a `.animation(_:value:)`
        // cannot fire until its `value` changes, which requires the body that
        // built it to run again and re-read. See `BottomBarStyle.reduceMotion`.
        .onChange(of: reduceMotion, initial: true) { _, isOn in
            BottomBarStyle.reduceMotion = isOn
        }
        // Chỉ lựa chọn giao diện của người dùng. **Player không còn ép cả cửa
        // sổ sang tối nữa** — nó chỉ tô tối phần chrome của chính nó, xem
        // `expandedContent` trong `PlayerCard`.
        //
        // Cú ép toàn cửa sổ hỏng theo hai cách. Thấy được: ở chế độ sáng, mở
        // player làm **cả phần UI còn lại** đen theo, trong lúc morph và cả sau
        // khi đã thu. Đo được: đổi `preferredColorScheme` ở gốc bắt mọi view
        // trong cửa sổ tính lại màu và vẽ lại — hai khung hình đứng im, 66ms,
        // rơi đúng khung đầu tiên của lò xo.
        //
        // `preferredColorScheme` là *preference*: nó đi ngược lên cửa sổ, nên
        // không có cách nào giới hạn phạm vi. `\.colorScheme` trong environment
        // thì đi xuôi xuống, và đó là thứ chrome của player cần.
        .task {
            // Xem lớp làm nóng trong `ZStack` bên trên. Nửa giây là quá đủ cho
            // một lượt vẽ; giữ lâu hơn chỉ tốn công vô ích.
            try? await Task.sleep(for: .milliseconds(500))
            hasWarmedPlayerChrome = true
        }
        .preferredColorScheme(theme.colorScheme)
        // Covers every `Text` in the app, live and without a relaunch: a
        // `LocalizedStringKey` resolves against the environment's locale.
        //
        // It does NOT cover `String(localized:)`, which reads the process's
        // languages — those call sites pass `AppLanguage.resolvedLocale`
        // explicitly. Nor does it cover system-supplied UI: the photo picker,
        // the file importer and the volume slider are the system's, and they
        // stay in the phone's language whatever this says.
        .environment(\.locale, AppLanguage.resolvedLocale)
        // Reading `language` is what makes the line above re-evaluate; without
        // it the environment would keep the locale resolved at first launch.
        .id(language)
        // Sau `.id(language)`: đổi ngôn ngữ dựng lại cả cây bên dưới, và một
        // hộp thoại đang mở không được biến mất vì chuyện đó.
        //
        // Nhưng chỗ đứng ấy có cái giá của nó, và đây là cách trả: hộp thoại
        // nằm **trên** `.environment(\.locale,)` trong chuỗi modifier, nên một
        // `LocalizedStringKey` ở đây sẽ tra theo ngôn ngữ của máy chứ không
        // theo lựa chọn trong Cài đặt của app — đúng thứ dòng environment kia
        // tồn tại để sửa. Ba chuỗi dưới vì thế đi qua `String(localized:)` với
        // bundle và locale lấy thẳng từ `AppLanguage`, cùng lối mà `AppLanguage.
        // label` và các chỗ ngoài tầm environment khác đã dùng.
        //
        // Đổi lại thì chúng không còn là `LocalizedStringKey` để Xcode tự trích
        // nữa; ba khoá này đã nằm sẵn trong catalogue và phải ở lại đó.
        .alert(Text(verbatim: Self.storeWarningTitle),
               isPresented: $showingStoreWarning) {
            Button(Self.storeWarningDismiss, role: .cancel) { }
        } message: {
            Text(verbatim: Self.storeWarningBody)
        }
        // Khôi phục hàng đợi đã lưu **không** còn ở đây. Nó đã dời lên `.task`
        // của `EvenstarApp`, ngay sau lượt quét trùng, và phải chạy sau lượt
        // ấy — xem ghi chú dài ở chỗ đó. Đừng thêm lại một `.task` khôi phục ở
        // đây: hai `.task` anh em không được SwiftUI xếp thứ tự, và cái giá là
        // một hàng đợi bị xoá trắng.
    }
}
