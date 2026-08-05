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
    private let remoteCommands: RemoteCommandsBridge

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        let libService = LibraryService(context: container.mainContext)
        let imp = ImportService(library: libService, metadataReader: AudioMetadataReader())
        let now = NowPlayingService()
        let player = AVAudioPlayerWrapper()
        let play = PlaybackService(player: player, nowPlaying: now, library: libService)
        _library = State(initialValue: libService)
        _importService = State(initialValue: imp)
        _playback = State(initialValue: play)
        remoteCommands = RemoteCommandsBridge(playback: play)
        remoteCommands.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(importService)
                .environment(playback)
        }
        .modelContainer(modelContainer)
    }
}
