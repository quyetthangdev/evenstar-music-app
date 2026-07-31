import SwiftUI

struct MiniPlayerBar: View {
    let playback: PlaybackService

    var body: some View {
        if let current = playback.currentTrack {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    ArtworkThumbnail(relativePath: current.artworkRelativePath, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(current.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    Button {
                        playback.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(playback.queueIndex >= playback.queue.count - 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
        }
    }
}
