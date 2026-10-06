import SwiftUI

/// Tên bài, một dòng. Khi bài đang kẹt thì dòng báo lỗi màu đỏ thay vào chỗ
/// ấy, vì đây là chỗ duy nhất trên màn thư viện báo được chuyện đó.
///
/// Một dòng ở **cả hai** vị trí của accessory. Spike 2026-10-06: hệ thống đổi
/// vị trí mà không kèm animation, nên bố cục nào đổi theo vị trí đều nhảy.
struct MiniPlayerTitle: View {
    let playback: PlaybackService

    var body: some View {
        if let current = playback.currentTrack {
            let line = PlayerSubtitle.collapsedLine(track: current,
                                                    error: playback.stalledPlaybackError)
            Text(line.isFailure ? line.text : current.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(line.isFailure ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
        }
    }
}

/// Play và next. Glyph trần, không `.glass`: accessory đã là kính, và kính lồng
/// trong kính là điều Apple khuyên tránh. Mini player của Apple Music cũng vậy.
///
/// `showsNext` false khi accessory thu nhỏ vào thanh tab: ⏭ mờ dần và co về 0,
/// như Apple Music (video 2026-10-06).
struct MiniPlayerControls: View {
    let playback: PlaybackService
    let showsNext: Bool

    @State private var playPauseTaps = 0
    @State private var nextTaps = 0

    var body: some View {
        HStack(spacing: MiniPlayerMetrics.buttonGap) {
            Button {
                playPauseTaps += 1
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .symbolReplace()
                    .frame(width: MiniPlayerMetrics.buttonSize, height: MiniPlayerMetrics.buttonSize)
                    .contentShape(Rectangle())
            }
            .sensoryFeedback(.impact(weight: .light), trigger: playPauseTaps)

            Button {
                nextTaps += 1
                playback.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .frame(width: MiniPlayerMetrics.buttonSize, height: MiniPlayerMetrics.buttonSize)
                    .contentShape(Rectangle())
            }
            .disabled(!playback.canGoNext)
            .sensoryFeedback(.impact(weight: .light), trigger: nextTaps)
            .frame(width: showsNext ? MiniPlayerMetrics.buttonSize : 0)
            .opacity(showsNext ? 1 : 0)
            .clipped()
            .allowsHitTesting(showsNext)
            .padding(.leading, showsNext ? 0 : -MiniPlayerMetrics.buttonGap)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: showsNext)
    }
}

/// Hàng mini player bên trong thẻ, ở `progress` 0. Không có ô bìa: thẻ tự vẽ
/// bìa để nó lớn liên tục suốt cú bung.
struct MiniPlayerRow: View {
    let playback: PlaybackService
    let showsNext: Bool

    var body: some View {
        HStack(spacing: 0) {
            MiniPlayerTitle(playback: playback)
            Spacer(minLength: MiniPlayerMetrics.artworkTitleGap)
            MiniPlayerControls(playback: playback, showsNext: showsNext)
        }
        .padding(.leading, MiniPlayerMetrics.titleLeadingInset)
        .padding(.trailing, MiniPlayerMetrics.trailingInset)
    }
}
