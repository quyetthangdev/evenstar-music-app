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

    // MARK: - Xoay màn hình lúc thẻ mở

    /// iPhone 17 nằm ngang, và khung accessory hệ thống đặt ở đó.
    private let landscape = CGSize(width: 874, height: 402)
    private let landscapeAccessory = CGRect(x: 120, y: 330, width: 634, height: 48)

    /// Khung chụp lúc rời nghỉ là khung **dọc** (y 735). Ghép nó với cỡ màn
    /// ngang thì viên thuốc ở y 735 trên một màn cao 402 — cú thu đáp ra ngoài
    /// màn hình. Chưa có khung mới nào thì dùng khung dự phòng của màn mới.
    func testRotatingWhileOpenReanchorsOnTheNewScreen() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.screenSize = landscape
        XCTAssertEqual(e.anchorFrame, PlayerAnchor.fallbackFrame(screen: landscape))
        XCTAssertTrue(CGRect(origin: .zero, size: landscape).contains(e.anchorFrame),
                      "the pill would land off-screen at \(e.anchorFrame)")
    }

    /// Accessory báo khung mới **sau** khi cỡ màn đổi: lấy nó, cả vị trí inline.
    func testAFrameReportedAfterTheRotationBecomesTheAnchor() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.screenSize = landscape
        e.reportAccessoryFrame(landscapeAccessory, isInline: true)
        XCTAssertEqual(e.anchorFrame, landscapeAccessory)
        XCTAssertTrue(e.anchorIsInline)
    }

    /// …hoặc **trước**: thứ tự hai lần báo không được định trước.
    func testAFrameReportedJustBeforeTheRotationIsUsedOnceTheScreenChanges() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.reportAccessoryFrame(landscapeAccessory, isInline: false)
        XCTAssertEqual(e.anchorFrame, expanded, "same screen: still the frame captured at rest")
        e.screenSize = landscape
        XCTAssertEqual(e.anchorFrame, landscapeAccessory)
    }

    /// Xoay về: neo về đúng khung chụp lúc rời nghỉ, kể cả khi accessory báo
    /// khung dọc trước lúc cỡ màn kịp đổi.
    func testRotatingBackRestoresTheAnchorCapturedAtRest() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.screenSize = landscape
        e.reportAccessoryFrame(landscapeAccessory, isInline: true)
        e.reportAccessoryFrame(expanded, isInline: false)
        XCTAssertTrue(CGRect(origin: .zero, size: landscape).contains(e.anchorFrame),
                      "a portrait frame on a landscape screen")
        e.screenSize = screen
        XCTAssertEqual(e.anchorFrame, expanded)
        XCTAssertFalse(e.anchorIsInline)
        e.screenSize = landscape
        XCTAssertTrue(CGRect(origin: .zero, size: landscape).contains(e.anchorFrame))
        e.reportAccessoryFrame(landscapeAccessory, isInline: true)
        XCTAssertEqual(e.anchorFrame, landscapeAccessory)
    }

    /// Quãng kéo đi theo neo mới: cú kéo trên accessory chia cho mép trên của
    /// viên thuốc trên màn **hiện tại**.
    func testTheDragTravelFollowsTheNewAnchor() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        e.screenSize = landscape
        e.reportAccessoryFrame(landscapeAccessory, isInline: false)
        e.accessoryDragChanged(translationHeight: -100)
        let expected = Double((100 - AccessoryDragAxis.lockDistance) / landscapeAccessory.minY)
        XCTAssertEqual(e.accessoryDragDelta, expected, accuracy: 0.0001)
    }

    /// Lúc nghỉ, xoay màn không đụng tới neo: lần rời nghỉ sau chụp lại.
    func testRotatingAtRestChangesNothingUntilTheNextLeave() {
        let e = make()
        e.reportAccessoryFrame(expanded, isInline: false)
        e.leaveRest()
        e.arriveAtRest()
        e.screenSize = landscape
        XCTAssertEqual(e.anchorFrame, expanded)
        e.reportAccessoryFrame(landscapeAccessory, isInline: false)
        e.leaveRest()
        XCTAssertEqual(e.anchorFrame, landscapeAccessory)
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
