import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
    private var tracks: [Track] { store.tracks }

    /// Owned by `RootView`, which drives both the tab bar and the player from
    /// it. Written here only by `minimisesBottomBar` on this screen's list.
    @Binding var isMinimised: Bool

    @State private var showFileImporter = false
    @State private var accessibleURLs: [URL] = []
    @State private var inaccessibleFailures: [(url: URL, error: ImportError)] = []
    @State private var showImportSheet = false
    @State private var pickerErrorMessage: String?

    /// The track whose cover the photo picker is about to replace.
    ///
    /// Held separately from the picker's own selection because the two are
    /// answered at different moments: the row is known when the menu item is
    /// tapped, the image only when the picker returns. Keeping the track here
    /// rather than deriving it later is what stops a slow picker from writing
    /// its result onto whatever row happens to be current afterwards.
    @State private var artworkTarget: Track?
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
                SongRow(track: track)
                    .contentShape(Rectangle())
                    .onTapGesture {
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
                            artworkTarget = track
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
    @MainActor
    private func applyArtwork(from item: PhotosPickerItem, to track: Track) async {
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

    private func deleteTrack(_ track: Track) {
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
            print("Delete failed: \(error)")
        }
    }

}
