import SwiftUI

struct SimplePlayerView: View {
    let playback: PlaybackService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "music.note")
                .font(.system(size: 96))
                .foregroundStyle(.tint)
                .padding(48)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

            VStack(spacing: 4) {
                Text(playback.currentTrackTitle ?? "—")
                    .font(.title2.bold())
                Text("Sample track")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    SimplePlayerView(playback: PlaybackService(
        player: PreviewAudioPlayer(),
        nowPlaying: PreviewNowPlayingPublisher()
    ))
}

private final class PreviewAudioPlayer: AudioPlayerProtocol {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 180
    var didFinishCallback: (() -> Void)?
    func load(url _: URL) throws {}
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
}

private final class PreviewNowPlayingPublisher: NowPlayingPublisher {
    func update(title _: String, artist _: String, album _: String,
                artwork _: UIImage?, duration _: TimeInterval,
                elapsed _: TimeInterval, isPlaying _: Bool) {}
    func clear() {}
}
