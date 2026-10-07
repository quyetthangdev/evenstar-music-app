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

/// Cú kéo trên accessory đi về đâu — quyết cùng lúc khoá trục, giữ tới khi
/// nhấc tay.
///
/// Một trạng thái thay cho cặp "trục" + "có lái thẻ không": hai nhánh loại trừ
/// nhau, nên không có tổ hợp nào mà một cú ngang vừa trượt bài vừa lái thẻ.
enum AccessoryDragRoute: Equatable {
    /// Kéo lên: thẻ player bám ngón tay (`PlayerExpansion.accessoryDragChanged`).
    case card
    /// Ngang: đổi bài (`TrackSwipe`). Không chạm vào `PlayerExpansion`.
    case trackSwipe
    /// Kéo xuống, hoặc ngang khi không được vuốt.
    case ignored

    /// `nil` khi ngón tay chưa đi đủ `AccessoryDragAxis.lockDistance`.
    ///
    /// `swipeAllowed` false khi hàng của accessory đang ẩn (thẻ rời nghỉ, chính
    /// thẻ đang vẽ hàng ấy) hay một cú đổi bài còn đang bay: cú ngang khi ấy bị
    /// bỏ qua, và không bao giờ rơi sang thẻ.
    static func resolve(_ translation: CGSize, swipeAllowed: Bool) -> AccessoryDragRoute? {
        switch AccessoryDragAxis.resolve(translation) {
        case nil: nil
        case .vertical: translation.height < 0 ? .card : .ignored
        case .horizontal: swipeAllowed ? .trackSwipe : .ignored
        }
    }
}
