import CoreGraphics

/// Hình học của thẻ player, suy ra từ **khung accessory** mà hệ thống đặt.
///
/// Thay cho `collapsedSideMargin`, `collapsedBottomOffset` và `collapsedHeight`
/// cũ, vốn tự tính chỗ viên pill từ `BottomBarMetrics`. Chỗ ấy giờ là của hệ
/// thống, nên ta chỉ đọc lại nó. Mọi con số là toạ độ màn hình vật lý: cùng hệ
/// toạ độ thẻ dựng hình (thẻ `.ignoresSafeArea()`), và cùng hệ với
/// `.frame(in: .global)` mà accessory báo lên.
///
/// **Vị trí thẻ và quãng kéo nằm chung một chỗ.** Lỗi "thẻ trôi khỏi ngón tay"
/// đã tái phát hai lần khi hai thứ này được tính ở hai nơi.
struct PlayerAnchor: Equatable {
    let frame: CGRect
    let screen: CGSize

    var leadingMargin: CGFloat { frame.minX }
    var trailingMargin: CGFloat { screen.width - frame.maxX }
    var bottomOffset: CGFloat { screen.height - frame.maxY }
    var collapsedHeight: CGFloat { frame.height }
    var collapsedCornerRadius: CGFloat { frame.height / 2 }

    /// Quãng mép trên của thẻ đi từ `progress` 0 tới 1, cũng chính là
    /// `frame.minY`. Cả cú kéo trên thẻ lẫn trên accessory chia cho số này.
    var dragTravel: CGFloat { Self.dragTravel(for: frame) }

    static func dragTravel(for frame: CGRect) -> CGFloat { max(frame.minY, 1) }

    func cardFrame(progress: Double) -> CGRect {
        let p = CGFloat(min(max(progress, 0), 1))
        let leading = leadingMargin * (1 - p)
        let trailing = trailingMargin * (1 - p)
        let height = collapsedHeight + (screen.height - collapsedHeight) * p
        let bottom = screen.height - bottomOffset * (1 - p)
        return CGRect(x: leading, y: bottom - height,
                      width: screen.width - leading - trailing, height: height)
    }

    /// Khung dùng khi accessory chưa từng được đo, ví dụ chạm một bài lúc chưa
    /// có bài nào: accessory và cú bung xuất hiện cùng một lượt.
    ///
    /// Số đo trên iPhone 17, iOS 26.0, vị trí `.expanded` (spike 2026-10-06):
    /// lề 20, cao 48, đáy cách mép màn 91.
    static func fallbackFrame(screen: CGSize) -> CGRect {
        CGRect(x: 20, y: screen.height - 91 - 48, width: screen.width - 40, height: 48)
    }

    /// Khung đo được nếu nó có thật và nằm trong màn hình; ngược lại là
    /// `fallbackFrame`.
    static func resolve(measured: CGRect, screen: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: screen)
        guard measured.width > 0, measured.height > 0, bounds.contains(measured) else {
            return fallbackFrame(screen: screen)
        }
        return measured
    }
}
