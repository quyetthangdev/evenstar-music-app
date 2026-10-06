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
/// hàng này, ở đúng chỗ này. Hiện lại khi thẻ về nghỉ — sau cú lún và nảy ở
/// cuối cú thu, khi hai hàng đã trùng khít — và nằm dưới tấm thẻ đang mờ đi.
/// Không sớm hơn: suốt đoạn cuối cú thu thẻ là kính trong suốt, nên một hàng
/// nằm dưới sẽ hiện xuyên qua. Xem `PlayerExpansion.showsAccessoryContent`.
struct MiniPlayerAccessory: View {
    let playback: PlaybackService
    let expansion: PlayerExpansion

    /// Chỉ đọc để ẩn ⏭ khi thu nhỏ — xem Global Constraints của plan.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @State private var axis: AccessoryDragAxis?
    @State private var drivesCard = false

    /// `true` suốt một cú kéo, và SwiftUI tự trả nó về `false` khi cú kéo
    /// **kết thúc hoặc bị huỷ**. Chỉ cái thứ hai mới cần tới nó: `onEnded`
    /// không nổ cho cú kéo bị huỷ. Xem `PlayerExpansion.cancelAccessoryDrag()`.
    @GestureState private var dragIsLive = false

    /// Khung và vị trí đo được gần nhất, giữ lại để báo lại khi thẻ về nghỉ.
    ///
    /// `onGeometryChange` chỉ nổ khi khung **đổi**, và `PlayerExpansion` bỏ qua
    /// mọi lần báo lúc thẻ không nghỉ. Chạm một bài lúc chưa có gì phát thì
    /// accessory mọc ra và thẻ rời nghỉ cùng một lượt, nên lần đo đầu tiên của
    /// accessory rơi đúng vào lúc bị bỏ qua — và không bao giờ nổ lại, vì khung
    /// không đổi nữa. Không báo lại thì mọi cú bung về sau dùng khung dự phòng.
    @State private var lastFrame: CGRect = .zero
    @State private var lastIsInline = false

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: 0) {
            info
            Spacer(minLength: MiniPlayerMetrics.artworkTitleGap)
            MiniPlayerControls(playback: playback, showsNext: !isInline)
        }
        .padding(.trailing, MiniPlayerMetrics.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(expansion.showsAccessoryContent ? 1 : 0)
        // Bật tắt, không bao giờ mờ dần, dù lượt cập nhật có mang animation
        // nào. Thẻ về nghỉ bên trong `BottomBarStyle.collapseHandoff`, và cú
        // mờ ấy là của **thẻ**: hàng này phải đặc sẵn dưới nó. Mờ cả hai cùng
        // lúc thì giữa chừng chữ của hai hàng cùng nhạt — một nhịp chớp.
        .animation(nil, value: expansion.showsAccessoryContent)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            lastFrame = frame
            lastIsInline = isInline
            expansion.reportAccessoryFrame(frame, isInline: isInline)
        }
        .onChange(of: isInline) { _, inline in
            lastIsInline = inline
            expansion.reportAccessoryFrame(lastFrame, isInline: inline)
        }
        .onChange(of: expansion.isCardResting) { _, resting in
            if resting { expansion.reportAccessoryFrame(lastFrame, isInline: lastIsInline) }
        }
        .onChange(of: dragIsLive) { _, live in
            // Sau một cú thả bình thường thì vô hại: cú thả đã được gửi, và
            // `cancelAccessoryDrag()` không gửi lần hai.
            guard !live else { return }
            expansion.cancelAccessoryDrag()
            axis = nil
            drivesCard = false
        }
        // Accessory bị dỡ giữa cú kéo (bài về nil) cũng là một cú huỷ.
        .onDisappear { expansion.cancelAccessoryDrag() }
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
            .updating($dragIsLive) { _, live, _ in live = true }
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
