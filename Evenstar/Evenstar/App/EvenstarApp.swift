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

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Track.self, PlaybackState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        let libService = LibraryService(context: container.mainContext)
        _library = State(initialValue: libService)
        _importService = State(initialValue: ImportService(
            library: libService,
            metadataReader: AudioMetadataReader()
        ))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(importService)
        }
        .modelContainer(modelContainer)
    }
}
