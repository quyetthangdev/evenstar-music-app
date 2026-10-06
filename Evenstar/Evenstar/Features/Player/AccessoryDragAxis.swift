import CoreGraphics

/// Trục mà một cú kéo trên mini player khoá vào, quyết **một lần** sau
/// `lockDistance` rồi giữ tới khi nhấc tay.
///
/// Dọc lái thẻ player, ngang đổi bài. Khoá một lần vì một ngón tay trượt chéo
/// giữa chừng không được nhảy từ "đang bung player" sang "đang đổi bài".
enum AccessoryDragAxis: Equatable {
    case vertical
    case horizontal

    /// Cũng là `minimumDistance` của `DragGesture` trên accessory, và là ngưỡng
    /// mà `PlayerCard.dragOffset` trừ đi để thẻ không giật một đoạn lúc bắt đầu.
    static let lockDistance: CGFloat = 10

    /// `nil` khi ngón tay chưa đi đủ `lockDistance`. Hoà thì nghiêng về ngang.
    static func resolve(_ translation: CGSize) -> AccessoryDragAxis? {
        guard hypot(translation.width, translation.height) >= lockDistance else { return nil }
        return abs(translation.height) > abs(translation.width) ? .vertical : .horizontal
    }
}
