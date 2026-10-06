import SwiftUI

/// Nội dung của `tabViewBottomAccessory`. Viên kính là của hệ thống.
///
/// Ba việc:
/// - vẽ hàng mini player trùng khít hàng mà `PlayerCard` vẽ ở `progress` 0;
/// - báo khung của mình lên `PlayerExpansion`, để thẻ biết bung ra từ đâu;
/// - nhận chạm và cú kéo lên trên vùng thông tin bài, rồi chuyển sang thẻ.
///   Nút play/next nằm ngoài vùng ấy, nên bấm nút không bao giờ thành kéo.
///
/// Ẩn đi (opacity 0) khi thẻ rời trạng thái nghỉ: lúc ấy chính thẻ đang vẽ
/// hàng này, ở đúng chỗ này.
struct MiniPlayerAccessory: View {
    let playback: PlaybackService
    let expansion: PlayerExpansion

    /// Chỉ đọc để ẩn ⏭ khi thu nhỏ — xem Global Constraints của plan.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @State private var axis: AccessoryDragAxis?
    @State private var drivesCard = false

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: 0) {
            info
            Spacer(minLength: MiniPlayerMetrics.artworkTitleGap)
            MiniPlayerControls(playback: playback, showsNext: !isInline)
        }
        .padding(.trailing, MiniPlayerMetrics.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(expansion.isCardResting ? 1 : 0)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            expansion.reportAccessoryFrame(frame, isInline: isInline)
        }
    }

    private var info: some View {
        HStack(spacing: MiniPlayerMetrics.artworkTitleGap) {
            ArtworkThumbnail(relativePath: playback.currentTrack?.artworkRelativePath,
                             size: MiniPlayerMetrics.artworkSide)
            MiniPlayerTitle(playback: playback)
        }
        .padding(.leading, MiniPlayerMetrics.artworkLeadingInset)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { expansion.requestExpand() }
        .gesture(drag)
        .contextMenu {
            Button(role: .destructive) {
                playback.stop()
            } label: {
                Label("Dừng phát", systemImage: "stop.fill")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { expansion.requestExpand() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: AccessoryDragAxis.lockDistance, coordinateSpace: .global)
            .onChanged { value in
                if axis == nil {
                    axis = AccessoryDragAxis.resolve(value.translation)
                    // Chỉ một cú kéo **lên** mới lái thẻ. Kéo xuống thì không
                    // làm gì (Review Focus 3); kéo ngang để dành cho Task 13.
                    drivesCard = axis == .vertical && value.translation.height < 0
                }
                guard drivesCard else { return }
                expansion.accessoryDragChanged(translationHeight: value.translation.height)
            }
            .onEnded { value in
                defer {
                    axis = nil
                    drivesCard = false
                }
                guard drivesCard else { return }
                expansion.accessoryDragEnded(
                    predictedTranslationHeight: value.predictedEndTranslation.height,
                    verticalVelocity: value.velocity.height
                )
            }
    }
}
