import SwiftUI

/// Nội dung của `tabViewBottomAccessory`. Viên kính là của hệ thống.
///
/// Ba việc:
/// - vẽ hàng mini player trùng khít hàng mà `PlayerCard` vẽ ở `progress` 0;
/// - báo khung của mình lên `PlayerExpansion`, để thẻ biết bung ra từ đâu — và
///   môi trường chữ hệ thống đặt cho nó, để hàng của thẻ vẽ y như thế — và
///   mang neo để thẻ tìm được viên kính của hệ thống (`AccessoryCapsule`);
/// - nhận chạm và cú kéo lên trên vùng thông tin bài, rồi chuyển sang thẻ;
///   cú vuốt ngang trên cùng vùng ấy đổi bài (`TrackSwipe`). Nút play/next nằm
///   ngoài vùng ấy, nên bấm nút không bao giờ thành kéo, và đứng yên khi vuốt.
///
/// Ẩn đi (opacity 0) khi thẻ rời trạng thái nghỉ: lúc ấy chính thẻ đang vẽ
/// hàng này, ở đúng chỗ này. Hiện lại khi thẻ về nghỉ — khi thẻ đã tới đúng
/// viên kính và hai hàng trùng khít — và nằm dưới tấm thẻ đang mờ đi.
/// Không sớm hơn: suốt đoạn cuối cú thu thẻ là kính trong suốt, nên một hàng
/// nằm dưới sẽ hiện xuyên qua. Xem `PlayerExpansion.showsAccessoryContent`.
struct MiniPlayerAccessory: View {
    let playback: PlaybackService
    let expansion: PlayerExpansion

    /// Chỉ đọc để ẩn ⏭ khi thu nhỏ — xem Global Constraints của plan.
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    /// Hệ thống đặt hai giá trị này cho nội dung accessory, khác với phần còn
    /// lại của app; thẻ phải vẽ hàng mini theo đúng chúng — xem
    /// `AccessoryTextStyle`.
    @Environment(\.imageScale) private var imageScale
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Cú kéo hiện tại đi về đâu; `nil` khi không kéo hoặc chưa khoá trục.
    @State private var route: AccessoryDragRoute?

    /// Bìa + tên bài đã đi bao xa theo cú vuốt ngang (đã qua rubber band). Chỉ
    /// lệch phần **vẽ**: `offset` không đổi khung của ai, nên khung báo lên
    /// `PlayerExpansion`, neo viên kính và `AccessoryTextStyle` không biết gì.
    @State private var swipeTravel: CGFloat = 0
    /// Bề rộng vùng thông tin bài — ngưỡng 30% và quãng trượt ra quy theo nó.
    @State private var infoWidth: CGFloat = 0
    /// Đáy cú mờ chéo của Giảm chuyển động.
    @State private var swipeDimmed = false
    /// Một cú đổi bài đang bay: cú vuốt mới bị bỏ qua tới khi nó xong.
    @State private var swipeLanding = false
    /// Nhịp haptic mỗi lần vuốt đổi được bài.
    @State private var swipeCommits = 0

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
            MiniPlayerControls(playback: playback, showsNext: !isInline)
        }
        .padding(.trailing, MiniPlayerMetrics.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Neo để tìm viên kính của hệ thống — xem `AccessoryCapsule`. Mang đúng
        // khung hàng.
        .background(AccessoryCapsuleAnchor(capsule: expansion.capsule))
        .opacity(expansion.showsAccessoryContent ? 1 : 0)
        // Bật tắt, không bao giờ mờ dần, dù lượt cập nhật có mang animation
        // nào: hàng này thế chỗ hàng y hệt của thẻ trong một lượt — xem
        // `BottomBarStyle.collapseHandoff`. Mờ dần thì giữa chừng hai hàng
        // chồng nhau hoặc cùng nhạt — một nhịp chớp.
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
        .onChange(of: AccessoryTextStyle(imageScale: imageScale, typeSize: typeSize), initial: true) { _, style in
            expansion.reportAccessoryTextStyle(style)
        }
        .onChange(of: expansion.isCardResting) { _, resting in
            if resting { expansion.reportAccessoryFrame(lastFrame, isInline: lastIsInline) }
        }
        .onChange(of: dragIsLive) { _, live in
            // Sau một cú thả bình thường thì vô hại: cú thả đã được gửi, và
            // `cancelAccessoryDrag()` không gửi lần hai.
            guard !live else { return }
            expansion.cancelAccessoryDrag()
            // Cú vuốt bị huỷ thì nảy về như một cú thả chưa đủ xa.
            if route == .trackSwipe { finishSwipe(.cancel) }
            route = nil
        }
        // Accessory bị dỡ giữa cú kéo (bài về nil) cũng là một cú huỷ — và
        // giữa cú hạ cánh thì viên kính phải hiện lại.
        .onDisappear {
            expansion.cancelAccessoryDrag()
            expansion.capsule.restore()
        }
    }

    /// Vùng thông tin bài **trải tới sát cụm nút**: vuốt ở khoảng trống sau
    /// một tên bài ngắn vẫn đổi bài, và nội dung trượt ra tới mép cụm nút chứ
    /// không bị cắt ngay sau chữ. Khe trước cụm nút là `padding` thay cho
    /// `Spacer(minLength:)` cũ — cùng bề rộng chừa cho chữ
    /// (`MiniPlayerMetrics.titleWidth`), nên chữ cắt ở đúng chỗ cũ và hàng vẫn
    /// trùng khít hàng của thẻ.
    private var info: some View {
        HStack(spacing: MiniPlayerMetrics.artworkTitleGap) {
            ArtworkThumbnail(relativePath: playback.currentTrack?.artworkRelativePath,
                             size: MiniPlayerMetrics.artworkSide)
            MiniPlayerTitle(playback: playback)
        }
        .offset(x: TrackSwipe.slide(travel: swipeTravel, reduceMotion: BottomBarStyle.reduceMotion))
        .opacity(swipeDimmed ? TrackSwipe.dimmedOpacity : TrackSwipe.opacity(travel: swipeTravel, width: infoWidth))
        .padding(.leading, MiniPlayerMetrics.artworkLeadingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Chữ nhật, không bo: rẻ, không vẽ ngoài màn hình (xem
        // `PlayerCardClipShapeTests`). Nội dung trượt ra biến ở mép viên kính
        // và ở khe trước cụm nút.
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { infoWidth = $0 }
        .padding(.trailing, MiniPlayerMetrics.artworkTitleGap)
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
        .sensoryFeedback(.impact(weight: .light), trigger: swipeCommits)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: AccessoryDragAxis.lockDistance, coordinateSpace: .global)
            .updating($dragIsLive) { _, live, _ in live = true }
            .onChanged { value in
                if route == nil {
                    // Chỉ một cú kéo **lên** mới lái thẻ; kéo xuống thì không
                    // làm gì (Review Focus 3); ngang thì đổi bài.
                    route = AccessoryDragRoute.resolve(
                        value.translation,
                        swipeAllowed: expansion.showsAccessoryContent && !swipeLanding
                    )
                }
                switch route {
                case .card:
                    expansion.accessoryDragChanged(translationHeight: value.translation.height)
                case .trackSwipe:
                    swipeTravel = TrackSwipe.displayedOffset(
                        translation: value.translation.width,
                        canGoNext: playback.canGoNext,
                        canGoPrevious: playback.canGoPrevious
                    )
                case .ignored, nil:
                    break
                }
            }
            .onEnded { value in
                defer { route = nil }
                switch route {
                case .card:
                    expansion.accessoryDragEnded(
                        predictedTranslationHeight: value.predictedEndTranslation.height,
                        verticalVelocity: value.velocity.height
                    )
                case .trackSwipe:
                    finishSwipe(TrackSwipe.outcome(
                        translation: value.translation.width,
                        predictedTranslation: value.predictedEndTranslation.width,
                        width: infoWidth,
                        canGoNext: playback.canGoNext,
                        canGoPrevious: playback.canGoPrevious
                    ))
                case .ignored, nil:
                    break
                }
            }
    }

    /// Chưa đủ xa: nảy về. Đủ: bài cũ trượt hẳn ra, bài đổi khi nó đã khuất,
    /// bài mới trượt vào từ phía đối diện. Giảm chuyển động: không trượt — nội
    /// dung mờ xuống, bài đổi ở đáy cú mờ, rồi hiện lại.
    private func finishSwipe(_ outcome: TrackSwipe.Outcome) {
        guard outcome != .cancel else {
            withAnimation(BottomBarStyle.settle) { swipeTravel = 0 }
            return
        }
        swipeLanding = true
        if BottomBarStyle.reduceMotion {
            withAnimation(.easeOut(duration: TrackSwipe.fadeDuration)) {
                swipeDimmed = true
            } completion: {
                if TrackSwipe.commit(outcome, on: playback) { swipeCommits += 1 }
                swipeTravel = 0
                withAnimation(.easeIn(duration: TrackSwipe.fadeDuration)) {
                    swipeDimmed = false
                } completion: {
                    swipeLanding = false
                }
            }
            return
        }
        let exit = (outcome == .next ? -1 : 1) * max(infoWidth, 1)
        withAnimation(.easeIn(duration: TrackSwipe.exitDuration)) {
            swipeTravel = exit
        } completion: {
            guard TrackSwipe.commit(outcome, on: playback) else {
                // Bài cuối hết giữa cú trượt: không còn bài để tới — về chỗ cũ.
                withAnimation(BottomBarStyle.settle) { swipeTravel = 0 } completion: { swipeLanding = false }
                return
            }
            swipeCommits += 1
            // Nhảy sang phía đối diện, ngoài mọi animation — đang khuất sau
            // mép cắt nên không ai thấy cú nhảy.
            var jump = Transaction(animation: nil)
            jump.disablesAnimations = true
            withTransaction(jump) { swipeTravel = -exit }
            // Lượt sau, khi cú nhảy đã được vẽ. Cùng lượt thì SwiftUI chỉ thấy
            // `exit → 0` và bài mới trượt vào từ phía bài cũ vừa ra.
            DispatchQueue.main.async {
                withAnimation(BottomBarStyle.settle) { swipeTravel = 0 } completion: { swipeLanding = false }
            }
        }
    }
}
