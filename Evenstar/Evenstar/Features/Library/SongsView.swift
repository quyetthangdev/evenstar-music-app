import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct SongsView: View {
    @Environment(LibraryService.self) private var library
    @Environment(ImportService.self) private var importer
    @Environment(PlaybackService.self) private var playback
    /// The local library, fetched once for the whole app — see `LibraryStore`.
    /// The rows are the same `Track` objects a `@Query` here would have
    /// returned, so `SongRow` still redraws on an in-place edit.
    @Environment(LibraryStore.self) private var store
    // No `@Query private var jamendoTracks` here — see `JamendoSongsList`'s
    // doc comment for why that query moved into its own view instead of
    // living on this one, always active regardless of the selected chip.

    /// Read only from `localContent`, so picking the Drive or Jamendo chip
    /// leaves this screen with no dependency on the local library at all.
    /// Danh sách đã sắp, thứ mọi chỗ trong màn này đọc.
    ///
    /// `store.tracks` vốn đã theo tên A→Z, nên kiểu `.title` chạy qua đây là một
    /// lượt sắp lại thứ đã đúng thứ tự. Chấp nhận: giữ một đường đi duy nhất
    /// đáng hơn tiết kiệm một lượt sort, và `TrackSort.title` so cùng kiểu mà
    /// `LibraryStore` so nên kết quả trùng khít.
    private var tracks: [Track] { sort.apply(to: store.tracks) }

    /// Nhớ qua lần mở app, cùng cách `theme` và `language` đang làm.
    @AppStorage("library.trackSort") private var sort: TrackSort = .default

    /// Owned by `RootView`, which drives both the tab bar and the player from
    /// it. Written here only by `minimisesBottomBar` on this screen's list.
    @Binding var isMinimised: Bool

    @State private var showFileImporter = false
    @State private var accessibleURLs: [URL] = []
    @State private var inaccessibleFailures: [(url: URL, error: ImportError)] = []
    @State private var showImportSheet = false
    @State private var pickerErrorMessage: String?

    /// Identifies the track whose cover the photo picker is about to replace.
    ///
    /// Held separately from the picker's own selection because the two are
    /// answered at different moments: the row is known when the menu item is
    /// tapped, the image only when the picker returns. Naming the row here
    /// rather than deriving it later is what stops a slow picker from writing
    /// its result onto whatever row happens to be current afterwards.
    ///
    /// An id rather than the `Track` itself, and that is the whole point. This
    /// property is never written back to `nil` on the cancel path — the picker
    /// uses `isPresented:`, so a dismissal with no selection tells this view
    /// nothing — which means whatever is stored here outlives the interaction:
    /// past the sheet closing, past a tab switch, past the row being deleted.
    /// A `Track` kept that way is a strong reference to a `PersistentModel`
    /// that may already be `delete`d and `save`d, and reading any property off
    /// one raises `NSObjectInaccessibleException`, an Objective-C exception
    /// Swift cannot catch. A `PersistentIdentifier` is a value: stale, it is
    /// merely an id that resolves to nothing. See `applyArtwork`, which
    /// resolves it against the live library at the moment of the write.
    @State private var artworkTarget: PersistentIdentifier?
    @State private var showArtworkPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var artworkErrorMessage: String?

    /// The track whose tags the editor sheet is showing, or nil when it is
    /// closed. The identity drives the presentation, so there is no separate
    /// `isPresented` flag to fall out of step with it.
    @State private var editingTrack: Track?

    /// Which source the list is showing. Local by default — the Drive chip is
    /// an opt-in, and a user with no linked folder should never land on an
    /// empty screen they did not ask for.
    @State private var source: LibrarySource = .local

    /// Bài đang chờ xác nhận xoá vì nó không có trên máy này. `nil` khi không
    /// có hộp thoại nào đang mở.
    ///
    /// Giữ chính hàng chứ không giữ `persistentModelID`: khác với
    /// `artworkTarget`, đường này không đi qua một picker của hệ thống có thể
    /// đóng mà không báo, và hàng vẫn sống suốt lúc hộp thoại mở.
    @State private var pendingAbsentDelete: Track?

    enum LibrarySource: String, CaseIterable {
        case local, drive, jamendo
        /// See `LibraryTab.label` for why this is `String(localized:)` and
        /// not a bare literal.
        var label: String {
            switch self {
            case .local: String(localized: "Trên máy", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
            case .drive: String(localized: "Drive", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
            case .jamendo: String(localized: "Jamendo", bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale)
            }
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Bài hát")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        // One glyph for all three chips, because this corner
                        // has one meaning: add music to the source you are
                        // looking at. Only the destination differs — a file
                        // importer for the two local-ish sources, Jamendo's
                        // catalogue for the third.
                        //
                        // It used to show `magnifyingglass` for Jamendo, on the
                        // reasoning that its screen "is reached by search, not
                        // by picking files off the device". That is true of the
                        // mechanism and wrong about the user: nobody arrives
                        // wanting a search mechanism, they arrive wanting more
                        // music. Three things broke because of it. The `+` that
                        // means "add" on two chips vanished on the third.
                        // A magnifying glass already means "search the library"
                        // a few points away, in `FloatingTabBar`'s own search
                        // field. And with the affordance unrecognisable, the
                        // only remaining signpost to discovery was
                        // `JamendoSongsList`'s empty state — which deletes
                        // itself the moment the first track is saved, leaving a
                        // user who had saved exactly one track with no way
                        // back in that they could find.
                        //
                        // The label is what carries the difference now, and it
                        // has to: two identical glyphs would otherwise read the
                        // same to VoiceOver.
                        if source == .jamendo {
                            NavigationLink {
                                JamendoDiscoveryView(isMinimised: $isMinimised)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .accessibilityLabel(String(
                                localized: "Khám phá Jamendo",
                                bundle: AppLanguage.resolvedBundle,
                                locale: AppLanguage.resolvedLocale
                            ))
                        } else {
                            Button {
                                showFileImporter = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            // "Thêm nhạc", not a new string: it is already in
                            // the catalogue, already translated, and already
                            // what `EmptyLibraryView`'s own import button says.
                            // Two names for one action is how a glossary rots.
                            .accessibilityLabel(String(
                                localized: "Thêm nhạc",
                                bundle: AppLanguage.resolvedBundle,
                                locale: AppLanguage.resolvedLocale
                            ))
                        }
                    }
                }
                // The system tab bar is hidden in favour of `FloatingTabBar`.
                // This modifier applies to the content *inside* a tab, never
                // to the `TabView` itself, which is why it lives here on each
                // tab's root view rather than in `RootView`.
                .toolbar(.hidden, for: .tabBar)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let (accessible, inaccessible) = partitionByScopeAccess(urls)
                accessibleURLs = accessible
                inaccessibleFailures = inaccessible
                showImportSheet = !urls.isEmpty
            case .failure(let error):
                accessibleURLs = []
                inaccessibleFailures = []
                pickerErrorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showImportSheet, onDismiss: stopAccessingURLs) {
            ImportProgressSheet(
                urls: accessibleURLs,
                inaccessibleFailures: inaccessibleFailures,
                importer: importer
            )
            // Drag indicator lives inside ImportProgressSheet — it depends on importer.isImporting.
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingTrack) { track in
            TrackMetadataEditor(track: track)
        }
        // `matching: .images` keeps videos and Live Photos out of a picker whose
        // result has to end up as a still JPEG.
        .photosPicker(
            isPresented: $showArtworkPicker,
            selection: $pickedPhoto,
            matching: .images
        )
        // Keyed on the item, not on the picker closing: the picker dismisses
        // before its selection has been transferred, and a dismissal with no
        // change — the user tapping Cancel — must do nothing at all.
        .onChange(of: pickedPhoto) { _, item in
            guard let item, let target = artworkTarget else { return }
            // Cleared here rather than left standing: this is the one moment
            // the view learns the interaction is over. The cancel path never
            // arrives, which is why `artworkTarget` holds an id and not a row.
            artworkTarget = nil
            Task { await applyArtwork(from: item, to: target) }
        }
        .alert(
            "Không đặt được ảnh bìa",
            isPresented: Binding(
                get: { artworkErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { artworkErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(artworkErrorMessage ?? "")
        }
        .alert(
            "Không mở được file",
            isPresented: Binding(
                get: { pickerErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { pickerErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pickerErrorMessage ?? "")
        }
        .alert(
            "Xoá khỏi mọi máy?",
            isPresented: Binding(
                get: { pendingAbsentDelete != nil },
                set: { isPresented in
                    if !isPresented { pendingAbsentDelete = nil }
                }
            ),
            presenting: pendingAbsentDelete
        ) { track in
            Button("Xoá", role: .destructive) { performDelete(track) }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("Bài này không có trên máy này. Xoá sẽ gỡ nó khỏi mọi máy.")
        }
    }

    /// Nút sắp xếp, chỉ ở nguồn **Trên máy**.
    ///
    /// Drive và Jamendo cũng mang `playCount`, nhưng danh sách của chúng do
    /// service khác dựng và không đi qua `store.tracks` — kéo vào là ba đường
    /// riêng thay vì một, cho một tính năng chưa ai đòi ở đó.
    ///
    /// `Menu` chứ không `Picker` phân đoạn thứ hai: hai thanh phân đoạn chồng
    /// nhau đọc ra như hai bộ lọc ngang hàng, mà chúng không ngang hàng — nguồn
    /// đổi *nội dung*, sắp xếp chỉ đổi *thứ tự* của nội dung ấy.
    private var sortRow: some View {
        HStack {
            Spacer()
            Menu {
                Picker("Sắp xếp", selection: $sort) {
                    ForEach(TrackSort.allCases) { option in
                        Label(option.label, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
            } label: {
                // Chỉ glyph, không kèm chữ — dạng Apple dùng cho điều khiển sắp
                // xếp ở Ảnh và Tệp.
                //
                // Bản trước bày cả `sort.label` cạnh icon. Nó cho biết đang sắp
                // theo gì, nhưng phải trả bằng một hàng chữ đổi bề rộng mỗi lần
                // đổi kiểu — "Tên A→Z" và "Nghe nhiều nhất" lệch nhau khá xa,
                // nên hàng nhích qua nhích lại. Trạng thái đã nằm trong `Menu`:
                // mở ra là thấy dấu tick ở mục đang chọn.
                //
                // `.fill` khi khác mặc định, viền rỗng khi đang ở `.title`: đó
                // là cách Apple nói "bộ lọc này đang có tác dụng" mà không cần
                // thêm chữ nào.
                Image(systemName: sort == .default
                      ? "arrow.up.arrow.down.circle"
                      : "arrow.up.arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(sort == .default ? AnyShapeStyle(.secondary)
                                                      : AnyShapeStyle(Color.accentColor))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(
                localized: "Sắp xếp",
                bundle: AppLanguage.resolvedBundle,
                locale: AppLanguage.resolvedLocale
            ))
            .accessibilityValue(sort.label)
        }
        .padding(.horizontal)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Picker("Nguồn", selection: $source) {
                ForEach(LibrarySource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if source == .local {
                sortRow
            }

            // `.clearsBottomBar()` sits on each branch rather than on this
            // `VStack`, and that placement is load-bearing.
            // `.safeAreaInset(edge: .bottom)` inserts its spacer into the safe
            // area of the view it is applied to: on the stack it would shrink
            // the stack and leave the list ending in a band of empty
            // background, instead of extending the list's own scroll inset so
            // the last row can scroll clear of the floating bar. Applied here,
            // `localContent` receives exactly the modifier chain it had before
            // the picker existed.
            switch source {
            case .local:
                localContent
                    .clearsBottomBar()
            case .drive:
                DriveSongsList(isMinimised: $isMinimised)
                    .clearsBottomBar()
            case .jamendo:
                JamendoSongsList(isMinimised: $isMinimised)
                    .clearsBottomBar()
            }
        }
    }

    @ViewBuilder
    private var localContent: some View {
        if tracks.isEmpty {
            EmptyLibraryView(onImportTap: { showFileImporter = true })
        } else {
            List(tracks) { track in
                SongRow(track: track,
                        subtitle: sort.subtitle(for: track),
                        isAbsent: !store.isPresent(track))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Chạm vào hàng vắng mặt không làm gì, và **không** bật
                        // một hộp thoại giải thích: hàng đã mờ và đã mang chữ
                        // "Không có trên máy này" trước khi ngón tay chạm vào.
                        // Một hộp thoại cho mỗi cú chạm nhầm là tiếng ồn, và nó
                        // dạy người dùng bấm-qua-không-đọc đúng lúc lời cảnh
                        // báo lúc xoá cần được đọc.
                        guard store.isPresent(track) else { return }
                        playback.play(track, in: tracks)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTrack(track)
                        } label: {
                            Label("Xoá", systemImage: "trash")
                        }
                    }
                    // Only on the local list. A `DriveTrack` is a file on
                    // someone else's server with no artwork column to write and
                    // nowhere to put the image — offering the action there
                    // would be a menu item that cannot work.
                    .contextMenu {
                        Button {
                            // Set before the picker opens, not read back after
                            // it closes. See `artworkTarget`.
                            artworkTarget = track.persistentModelID
                            pickedPhoto = nil
                            showArtworkPicker = true
                        } label: {
                            Label("Đổi ảnh bìa", systemImage: "photo")
                        }
                        Button {
                            editingTrack = track
                        } label: {
                            Label("Sửa thông tin", systemImage: "pencil")
                        }
                    }
            }
            .listStyle(.plain)
            // On the scrollable container itself rather than on the branch
            // above it, so what the modifier observes is unambiguous.
            .minimisesBottomBar($isMinimised)
        }
    }

    /// Loads the picked photo, shrinks it, and writes it onto the track.
    ///
    /// Three failures, each with its own message rather than one catch-all: the
    /// transfer can fail (the photo lives in iCloud and cannot be fetched), the
    /// bytes can fail to decode, and the write can fail. Only the last one is
    /// something the user can act on, but a silent no-op for the first two is
    /// exactly the "I picked an image and nothing happened" the fresh-filename
    /// rule in `setArtwork` exists to prevent — so none of them is swallowed.
    ///
    /// **Takes an id, not a row, and re-resolves it after the waiting.** There
    /// are two real suspensions in here, not formalities: a photo that lives in
    /// iCloud makes `loadTransferable` take seconds, and
    /// `ArtworkStore.jpegForStorage` is `@concurrent`, so it genuinely leaves
    /// the main actor. The picker is already dismissed and the list already
    /// fully interactive throughout both, so the user can swipe away the very
    /// row this task was started for. `LibraryService.onTrackWillBeDeleted`
    /// reaches `PlaybackService`, `LibraryStore` and `SearchResultsStore` — it
    /// cannot reach a `Task` — so a captured `Track` would come back to a row
    /// that had been `delete`d and `save`d, and `setArtwork` reads and writes
    /// its properties: `NSObjectInaccessibleException`, uncatchable in Swift.
    ///
    /// The shape is `PlaybackService.loadArtworkIntoNowPlaying`'s: lift the
    /// identity out before the waiting, then check it against live state
    /// afterwards. `store.tracks` is the live state here, because
    /// `LibraryStore.remove(_:)` is what guarantees it holds no dead row.
    ///
    /// A row that has gone gets no error message. The user deleted the song
    /// they had asked to re-cover; telling them the cover failed would be
    /// reporting a problem they created on purpose.
    @MainActor
    private func applyArtwork(from item: PhotosPickerItem, to targetID: PersistentIdentifier) async {
        let raw: Data?
        do { raw = try await item.loadTransferable(type: Data.self) }
        catch {
            artworkErrorMessage = String(
                localized: "Không tải được ảnh đã chọn: \(error.localizedDescription)",
                bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
            )
            return
        }
        guard let raw else {
            artworkErrorMessage = String(
                localized: "Không tải được ảnh đã chọn.",
                bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
            )
            return
        }
        guard let jpeg = await ArtworkStore.jpegForStorage(from: raw) else {
            artworkErrorMessage = String(
                localized: "Không đọc được ảnh đã chọn.",
                bundle: AppLanguage.resolvedBundle, locale: AppLanguage.resolvedLocale
            )
            return
        }
        guard let track = store.tracks.first(where: { $0.persistentModelID == targetID }) else {
            return
        }
        do { try library.setArtwork(jpeg, for: track) }
        catch { artworkErrorMessage = error.localizedDescription }
    }

    /// Document Picker delivers security-scoped URLs. We start access here and
    /// stop it on sheet dismiss; the import work happens between those calls.
    /// URLs whose access could not be started are reported as import failures
    /// rather than silently dropped from the summary.
    private func partitionByScopeAccess(
        _ urls: [URL]
    ) -> (accessible: [URL], inaccessible: [(url: URL, error: ImportError)]) {
        var accessible: [URL] = []
        var inaccessible: [(url: URL, error: ImportError)] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                accessible.append(url)
            } else {
                inaccessible.append((url, .fileNotAccessible(url)))
            }
        }
        return (accessible, inaccessible)
    }

    private func stopAccessingURLs() {
        for url in accessibleURLs {
            url.stopAccessingSecurityScopedResource()
        }
        accessibleURLs = []
        inaccessibleFailures = []
    }

    /// Vào đây từ cú vuốt. Bài có mặt thì xoá luôn; bài vắng mặt thì hỏi trước.
    ///
    /// Xoá một bài vắng mặt trông như dọn một hàng rác nhưng nó gỡ bài khỏi
    /// **mọi máy**, kể cả máy đang giữ file thật. Xem `TrackPresence.deleteAction`.
    private func deleteTrack(_ track: Track) {
        switch TrackPresence.deleteAction(isPresent: store.isPresent(track)) {
        case .deleteNow:
            performDelete(track)
        case .confirmFirst:
            pendingAbsentDelete = track
        }
    }

    private func performDelete(_ track: Track) {
        // No `playback.handleTrackDeleted(track)` here any more, and its absence
        // is the fix rather than an omission: `LibraryService.delete(_:)` now
        // announces the row itself, so the ordering this view used to be
        // responsible for cannot be got wrong by the next caller. See
        // `LibraryService.onTrackWillBeDeleted`.
        //
        // Unchanged: queue adjustment still lands before the DB delete, so if
        // `library.delete` throws, the row can survive pointing at
        // already-adjusted playback state and possibly-removed files.
        // Recovering from that is Phase 2d's job.
        do {
            try library.delete(track)
        } catch {
            // 2a: log only. A polished alert is part of 2d.
            AppLog.library.error("Delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}
