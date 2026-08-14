//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer
    @State private var library: LibraryService
    @State private var importService: ImportService
    @State private var playback: PlaybackService
    @State private var driveLibrary: DriveLibraryService
    @State private var jamendoLibrary: JamendoLibraryService
    private let remoteCommands: RemoteCommandsBridge

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self, JamendoTrack.self
            )
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
        // The local library's half of the same wiring the two remote sources get
        // below. `SongsView.deleteTrack` used to make this call by hand, which
        // held only for as long as it stayed the single caller of
        // `library.delete(_:)`. See `LibraryService.onTrackWillBeDeleted`.
        //
        // `[weak play]`, unlike the two below, and the difference is real rather
        // than defensive: `PlaybackService` holds `LibraryService` (it reads and
        // writes `PlaybackState` through it), so a strong capture here would
        // close the loop — play → library → this closure → play. It holds no
        // reference to either remote service, so those two need no such care.
        libService.onTrackWillBeDeleted = { [weak play] in play?.handleTrackDeleted($0) }
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
        }
        .modelContainer(modelContainer)
    }
}
