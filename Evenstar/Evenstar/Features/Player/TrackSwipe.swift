import CoreGraphics

/// Cú vuốt ngang trên mini player: trái là bài tiếp, phải là bài trước.
///
/// Quyết theo vị trí **dự đoán** lúc thả chứ không theo vị trí hiện tại, nên
/// một cú búng ngắn mà nhanh vẫn đổi bài, giống cú thả thẻ player.
enum TrackSwipe {
    enum Outcome: Equatable {
        case next
        case previous
        case cancel
    }

    /// Phần bề ngang phải vượt qua để đổi bài.
    static let commitFraction: CGFloat = 0.3
    /// Nội dung chỉ đi theo ngón tay chừng này khi không có bài để tới.
    static let rubberBandFactor: CGFloat = 0.25

    static func outcome(translation: CGFloat, predictedTranslation: CGFloat, width: CGFloat,
                        canGoNext: Bool, canGoPrevious: Bool) -> Outcome {
        let threshold = width * commitFraction
        let reach = abs(predictedTranslation) > abs(translation) ? predictedTranslation : translation
        if reach <= -threshold { return canGoNext ? .next : .cancel }
        if reach >= threshold { return canGoPrevious ? .previous : .cancel }
        return .cancel
    }

    static func displayedOffset(translation: CGFloat, canGoNext: Bool, canGoPrevious: Bool) -> CGFloat {
        let blocked = translation < 0 ? !canGoNext : !canGoPrevious
        return blocked ? translation * rubberBandFactor : translation
    }
}
