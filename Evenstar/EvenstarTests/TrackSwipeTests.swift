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
}
