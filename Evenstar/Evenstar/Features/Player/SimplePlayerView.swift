import SwiftUI

struct SimplePlayerView: View {
    let playback: PlaybackService

    @State private var draggingPosition: TimeInterval?

    var body: some View {
        VStack(spacing: 24) {
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
                Text(playback.currentMetadata?.title ?? "—")
                    .font(.title2.bold())
                Text(playback.currentMetadata?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            scrubber

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

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { draggingPosition ?? playback.position },
                    set: { draggingPosition = $0 }
                ),
                in: 0...max(playback.duration, 0.001),
                onEditingChanged: { editing in
                    if !editing, let target = draggingPosition {
                        playback.seek(to: target)
                        draggingPosition = nil
                    }
                }
            )

            HStack {
                Text(formatTime(draggingPosition ?? playback.position))
                Spacer()
                Text("-" + formatTime(max(0, playback.duration - (draggingPosition ?? playback.position))))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.horizontal)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
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
