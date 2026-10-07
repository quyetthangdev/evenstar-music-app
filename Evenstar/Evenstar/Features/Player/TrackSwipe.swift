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

    // MARK: - Hình

    /// Nội dung mờ đi chừng này khi đã trượt trọn một bề ngang.
    static let maxFade: Double = 0.6
    /// Độ mờ ở đáy cú mờ chéo của Giảm chuyển động — bài đổi ở đây.
    static let dimmedOpacity: Double = 0.15
    /// Bài cũ trượt hẳn ra trong chừng này, rồi bài mới vào trên `settle`.
    static let exitDuration: Double = 0.16
    /// Mỗi nửa cú mờ chéo của Giảm chuyển động.
    static let fadeDuration: Double = 0.12

    /// Nội dung lệch bao nhiêu. Giảm chuyển động: không trượt chút nào, chỉ mờ.
    static func slide(travel: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : travel
    }

    /// Mờ theo quãng đã đi, dừng ở `1 - maxFade` sau một bề ngang. Đứng yên
    /// thì rõ hẳn, kể cả trước khi vùng thông tin bài được đo (`width` 0).
    static func opacity(travel: CGFloat, width: CGFloat) -> Double {
        guard travel != 0 else { return 1 }
        guard width > 0 else { return 1 - maxFade }
        return 1 - Double(min(abs(travel) / width, 1)) * maxFade
    }

    // MARK: - Đổi bài

    /// Đổi bài cho một cú vuốt đã quyết. `false` khi không đổi gì.
    ///
    /// Hỏi lại `canGoNext`/`canGoPrevious` ở đây chứ không tin quyết định lúc
    /// thả: bài đổi **sau** cú trượt ra, và trong ~0,16s ấy bài cuối có thể đã
    /// hết. `next()` ở cuối hàng đợi khi tắt repeat dừng phát — cú vuốt không
    /// bao giờ được gọi nó ở đó. Không cái nào tăng `explicitSelections`, nên
    /// vuốt đổi bài không bung player.
    @MainActor
    static func commit(_ outcome: Outcome, on playback: PlaybackService) -> Bool {
        switch outcome {
        case .next:
            guard playback.canGoNext else { return false }
            playback.next()
            return true
        case .previous:
            guard playback.canGoPrevious else { return false }
            playback.stepBack()
            return true
        case .cancel:
            return false
        }
    }
}

