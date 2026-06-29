//
//  EvenstarApp.swift
//  Evenstar
//
//  Created by Phan Quyết Thắng on 29/6/26.
//

import SwiftUI

@main
struct EvenstarApp: App {
    @State private var playback = PlaybackService(player: AVAudioPlayerWrapper())

    var body: some Scene {
        WindowGroup {
            SimplePlayerView(playback: playback)
                .task {
                    loadSampleTrack()
                }
        }
    }

    private func loadSampleTrack() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            assertionFailure("sample.mp3 missing from bundle")
            return
        }
        do {
            try playback.load(url: url, title: "Sample")
        } catch {
            print("Failed to load sample track: \(error)")
        }
    }
}
