import XCTest
@testable import Evenstar

@MainActor
final class PlayerExpansionTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)
    private let expanded = CGRect(x: 20, y: 735, width: 360, height: 48)

    private func make() -> PlayerExpansion {
        let e = PlayerExpansion()
        e.screenSize = screen
        return e
    }

    func testStartsAtRest() {
        let e = make()
        XCTAssertTrue(e.isCardResting)
        XCTAssertEqual(e.accessoryDragDelta, 0)
        XCTAssertNil(e.intent)
    }

    func testLeavingRestCapturesTheMeasuredFrame() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        XCTAssertFalse(e.isCardResting)
        XCTAssertEqual(e.anchorFrame, expanded)
    }

    /// Review Focus 1.
    func testLeavingRestBeforeAnyMeasurementUsesTheFallback() {
        let e = make()
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, PlayerAnchor.fallbackFrame(screen: screen))
    }

    /// Review Focus 2: trong lúc nội dung lùi lại, khung đo được đang co.
    func testFramesReportedAwayFromRestAreIgnored() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.reportAccessoryFrame(CGRect(x: 31, y: 743, width: 338, height: 45), isInline: false)
        e.arriveAtRest()
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, expanded)
    }

    /// Thẻ phải biết accessory đang ở vị trí nào lúc bung, để hàng mini player
    /// của nó ẩn ⏭ giống hệt accessory ở khung đầu.
    func testLeavingRestCapturesWhetherTheAccessoryWasInline() {
        let e = make()
        e.reportAccessoryFrame(CGRect(x: 84, y: 798, width: 234, height: 48), isInline: true)
        e.leaveRest()
        XCTAssertTrue(e.anchorIsInline)
    }

    func testLeavingRestTwiceKeepsTheFirstAnchor() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, expanded)
    }

    func testAnUpwardDragDrivesProgressOverTheAnchorsTravel() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        let expected = Double((100 - AccessoryDragAxis.lockDistance) / 735)
        XCTAssertTrue(e.accessoryDragging)
        XCTAssertFalse(e.isCardResting)
        XCTAssertEqual(e.accessoryDragDelta, expected, accuracy: 0.0001)
        XCTAssertEqual(e.progress, expected, accuracy: 0.0001)
    }

    /// Review Focus 3.
    func testADownwardDragClampsProgressAtZero() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: 60)
        XCTAssertEqual(e.progress, 0)
        XCTAssertLessThan(e.accessoryDragDelta, 0)
    }

    func testReleasingSendsThePredictedProgress() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        e.accessoryDragEnded(predictedTranslationHeight: -500, verticalVelocity: -900)
        guard case let .release(predicted, velocity)? = e.intent?.kind else {
            return XCTFail("expected a release intent")
        }
        XCTAssertEqual(predicted, Double((500 - AccessoryDragAxis.lockDistance) / 735), accuracy: 0.0001)
        XCTAssertEqual(velocity, -900)
    }

    func testTakingTheDragHandsOverTheDeltaAndClearsIt() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        let carried = e.takeAccessoryDrag()
        XCTAssertGreaterThan(carried, 0)
        XCTAssertEqual(e.accessoryDragDelta, 0)
        XCTAssertFalse(e.accessoryDragging)
    }

    func testArrivingAtRestWaitsForAnAccessoryDragToEnd() {
        let e = make()
        e.accessoryDragChanged(translationHeight: -100)
        e.arriveAtRest()
        XCTAssertFalse(e.isCardResting)
        _ = e.takeAccessoryDrag()
        e.arriveAtRest()
        XCTAssertTrue(e.isCardResting)
    }

    // MARK: - Cú kéo bị huỷ

    /// SwiftUI không gọi `onEnded` khi cú kéo bị huỷ. `cancelAccessoryDrag()`
    /// là đường thả thay thế; không có cú kéo nào thì nó không được làm gì.
    func testCancellingWithNoDragIsANoOp() {
        let e = make()
        e.requestExpand()
        let before = e.intent
        e.cancelAccessoryDrag()
        XCTAssertEqual(e.intent, before)
    }

    /// Cú thả bình thường đã gửi `.release`; lần reset trạng thái cử chỉ ngay
    /// sau đó không được gửi lần hai.
    func testCancellingAfterANormalReleaseIsANoOp() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        e.accessoryDragEnded(predictedTranslationHeight: -500, verticalVelocity: -900)
        let released = e.intent
        e.cancelAccessoryDrag()
        XCTAssertEqual(e.intent, released)
    }

    func testCancellingMidDragReleasesAtTheCurrentProgressWithNoVelocity() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        let current = e.accessoryDragDelta
        e.cancelAccessoryDrag()
        guard case let .release(predicted, velocity)? = e.intent?.kind else {
            return XCTFail("expected a release intent")
        }
        XCTAssertEqual(predicted, current, accuracy: 0.0001)
        XCTAssertEqual(velocity, 0)
    }

    /// Kẹp như `progress`: một cú kéo xuống huỷ giữa chừng không được báo một
    /// đích âm.
    func testCancellingADownwardDragReleasesAtZero() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: 60)
        e.cancelAccessoryDrag()
        guard case let .release(predicted, _)? = e.intent?.kind else {
            return XCTFail("expected a release intent")
        }
        XCTAssertEqual(predicted, 0)
    }

    func testCancellingAfterTheCardTookTheDragIsANoOp() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        e.accessoryDragEnded(predictedTranslationHeight: -500, verticalVelocity: -900)
        _ = e.takeAccessoryDrag()
        let afterTake = e.intent
        e.cancelAccessoryDrag()
        XCTAssertEqual(e.intent, afterTake)
    }

    /// Sau khi thẻ đã nhận cú thả, một cú kéo **mới** phải huỷ được như thường:
    /// cờ "đang chờ thả" không được kẹt lại.
    func testANewDragAfterATakenReleaseCanBeCancelled() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        e.accessoryDragEnded(predictedTranslationHeight: -500, verticalVelocity: -900)
        _ = e.takeAccessoryDrag()
        e.accessoryDragChanged(translationHeight: -50)
        let before = e.intent
        e.cancelAccessoryDrag()
        XCTAssertNotEqual(e.intent, before)
    }

    /// `onChange` chỉ nổ khi giá trị đổi; hai lần chạm liền nhau phải là hai
    /// ý định khác nhau.
    func testTwoExpandRequestsAreTwoDistinctIntents() {
        let e = make()
        e.requestExpand()
        let first = e.intent
        e.requestExpand()
        XCTAssertNotEqual(first, e.intent)
        XCTAssertEqual(e.intent?.kind, .expand)
    }
}
