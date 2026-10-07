import XCTest
@testable import Evenstar

final class TrackSwipeTests: XCTestCase {
    private let width: CGFloat = 234

    func testPastThirtyPercentLeftIsNext() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -80, predictedTranslation: -80, width: width,
                                          canGoNext: true, canGoPrevious: true), .next)
    }

    func testPastThirtyPercentRightIsPrevious() {
        XCTAssertEqual(TrackSwipe.outcome(translation: 80, predictedTranslation: 80, width: width,
                                          canGoNext: true, canGoPrevious: true), .previous)
    }

    func testAShortSlowSwipeCancels() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -30, predictedTranslation: -40, width: width,
                                          canGoNext: true, canGoPrevious: true), .cancel)
    }

    /// Một cú búng ngắn nhưng nhanh: dự đoán quá ngưỡng thì vẫn đổi bài.
    func testAShortFastFlickCommits() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -30, predictedTranslation: -200, width: width,
                                          canGoNext: true, canGoPrevious: true), .next)
    }

    /// Review Focus 4: ở cuối hàng đợi không bao giờ gọi `next()`, vì khi tắt
    /// repeat nó dừng phát.
    func testNoNextNeverCommitsNext() {
        XCTAssertEqual(TrackSwipe.outcome(translation: -200, predictedTranslation: -400, width: width,
                                          canGoNext: false, canGoPrevious: true), .cancel)
    }

    func testNoPreviousNeverCommitsPrevious() {
        XCTAssertEqual(TrackSwipe.outcome(translation: 200, predictedTranslation: 400, width: width,
                                          canGoNext: true, canGoPrevious: false), .cancel)
    }

    func testTheContentFollowsTheFingerWhenThereIsSomewhereToGo() {
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: -60, canGoNext: true, canGoPrevious: true), -60)
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: 60, canGoNext: true, canGoPrevious: true), 60)
    }

    func testTheContentRubberBandsWhenThereIsNowhereToGo() {
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: -60, canGoNext: false, canGoPrevious: true),
                       -60 * TrackSwipe.rubberBandFactor)
        XCTAssertEqual(TrackSwipe.displayedOffset(translation: 60, canGoNext: true, canGoPrevious: false),
                       60 * TrackSwipe.rubberBandFactor)
    }

    // MARK: - Presentation

    func testTheContentSlidesWithTheFinger() {
        XCTAssertEqual(TrackSwipe.slide(travel: -60, reduceMotion: false), -60)
    }

    /// Giảm chuyển động: không trượt, chỉ mờ.
    func testReduceMotionNeverSlides() {
        XCTAssertEqual(TrackSwipe.slide(travel: -60, reduceMotion: true), 0)
        XCTAssertEqual(TrackSwipe.slide(travel: 200, reduceMotion: true), 0)
    }

    func testTheContentFadesWithDistance() {
        XCTAssertEqual(TrackSwipe.opacity(travel: 0, width: width), 1)
        XCTAssertEqual(TrackSwipe.opacity(travel: -width / 2, width: width), 1 - TrackSwipe.maxFade / 2, accuracy: 1e-9)
        XCTAssertEqual(TrackSwipe.opacity(travel: width / 2, width: width), 1 - TrackSwipe.maxFade / 2, accuracy: 1e-9)
    }

    func testTheFadeStopsAtOneWidth() {
        XCTAssertEqual(TrackSwipe.opacity(travel: -3 * width, width: width), 1 - TrackSwipe.maxFade, accuracy: 1e-9)
    }

    /// Trước lần đo đầu tiên `width` là 0 — hàng đứng yên không được mờ.
    func testAtRestTheContentIsFullyOpaqueEvenBeforeItIsMeasured() {
        XCTAssertEqual(TrackSwipe.opacity(travel: 0, width: 0), 1)
    }

    func testAZeroWidthDoesNotDivideByZero() {
        XCTAssertEqual(TrackSwipe.opacity(travel: 10, width: 0), 1 - TrackSwipe.maxFade, accuracy: 1e-9)
    }
}
