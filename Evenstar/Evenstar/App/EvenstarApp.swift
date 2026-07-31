//
//  EvenstarApp.swift
//  Evenstar
//

import SwiftUI
import SwiftData

@main
struct EvenstarApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Track.self, PlaybackState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(modelContainer)
    }
}
