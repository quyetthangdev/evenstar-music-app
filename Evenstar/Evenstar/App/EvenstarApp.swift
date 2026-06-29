//
//  EvenstarApp.swift
//  Evenstar
//
//  Created by Phan Quyết Thắng on 29/6/26.
//

import SwiftUI
import UIKit

@main
struct EvenstarApp: App {
    @State private var playback: PlaybackService
    private let remoteCommands: RemoteCommandsBridge

    init() {
        let player = AVAudioPlayerWrapper()
        let nowPlaying = NowPlayingService()
        let service = PlaybackService(player: player, nowPlaying: nowPlaying)
        _playback = State(initialValue: service)
        remoteCommands = RemoteCommandsBridge(playback: service)
        remoteCommands.install()
    }

    var body: some Scene {
        WindowGroup {
            SimplePlayerView(playback: playback)
                .task { loadSampleTrack() }
        }
    }

    private func loadSampleTrack() {
        guard let url = Bundle.main.url(forResource: "sample", withExtension: "mp3") else {
            assertionFailure("sample.mp3 missing from bundle")
            return
        }
        let artwork = UIImage(named: "SampleArtwork")
        let metadata = TrackMetadata(
            title: "Sample",
            artist: "Unknown Artist",
            album: "Unknown Album",
            artwork: artwork,
            durationSeconds: 0
        )
        do {
            try playback.load(url: url, metadata: metadata)
        } catch {
            print("Failed to load sample track: \(error)")
        }
    }
}
