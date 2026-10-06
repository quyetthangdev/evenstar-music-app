import CoreGraphics

/// Kích thước hàng mini player, dùng chung cho **hai** nơi vẽ nó: nội dung
/// accessory (`MiniPlayerAccessory`) và thẻ player ở `progress` 0.
///
/// Hai nơi phải trùng khít từng điểm. Ở khung đầu cú bung, thẻ phủ đúng lên
/// accessory rồi accessory ẩn đi; lệch một điểm là thấy nhảy.
enum MiniPlayerMetrics {
    static let artworkSide: CGFloat = 30
    /// Viên kính cao 48, bán kính 24. Ở mép trên ô bìa (y = 9) đường cong đã
    /// lùi vào ~5,3pt, nên lề 12 cho khe hẹp nhất ~6,7pt. Chỉnh trên máy thật.
    static let artworkLeadingInset: CGFloat = 12
    static let artworkTitleGap: CGFloat = 10
    static let trailingInset: CGFloat = 14
    static let buttonSize: CGFloat = 32
    static let buttonGap: CGFloat = 4
    /// Chữ bắt đầu sau ô bìa và khe hở.
    static var titleLeadingInset: CGFloat { artworkLeadingInset + artworkSide + artworkTitleGap }
}
