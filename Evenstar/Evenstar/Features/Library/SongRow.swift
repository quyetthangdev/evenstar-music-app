import SwiftUI

/// One row in any list of songs, local or Drive.
///
/// Takes `any Playable` rather than `Track` so the two lists are the same row
/// *by construction* instead of by two people writing similar code. Everything
/// it reads — title, artist, artwork path — is a protocol member; a `DriveTrack`
/// simply reports `nil` artwork and gets the placeholder, exactly as an untagged
/// local file does.
struct SongRow: View {
    let track: any Playable

    /// Shown under the title in place of the artist.
    ///
    /// For Drive tracks the artist is the `MetadataPlaceholder` string until the
    /// ID3-over-the-network đợt lands — which is to say, for now, always. A row
    /// of "Unknown Artist" tells the user nothing, so the Drive list passes the
    /// folder name instead. Local lists pass nothing and get the artist.
    var subtitle: String?

    /// Bài này không có file trên máy đang chạy.
    ///
    /// Mặc định `false`, nên `DriveSongsList` và `JamendoSongsList` không phải
    /// đổi một chữ: một `DriveTrack` hay `JamendoTrack` là URL mạng, và "có
    /// trên máy này" không có nghĩa gì với chúng.
    ///
    /// Nhãn chữ chứ không chỉ làm mờ, và đó không phải trang trí: độ mờ một
    /// mình không đọc được bằng VoiceOver, và cũng không phân biệt được với
    /// một hàng đang bị vô hiệu vì lý do khác.
    var isAbsent: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(relativePath: track.artworkRelativePath, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                if isAbsent {
                    Label("Không có trên máy này", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(subtitle ?? track.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isAbsent ? 0.55 : 1)
    }
}
