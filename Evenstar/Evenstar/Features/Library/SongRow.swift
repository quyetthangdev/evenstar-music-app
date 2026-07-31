import SwiftUI

struct SongRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(relativePath: track.artworkRelativePath, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
