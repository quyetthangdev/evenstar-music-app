import XCTest
@testable import Evenstar

final class AccessoryDragAxisTests: XCTestCase {
    func testNothingIsDecidedBeforeTheLockDistance() {
        XCTAssertNil(AccessoryDragAxis.resolve(CGSize(width: 3, height: -5)))
        XCTAssertNil(AccessoryDragAxis.resolve(.zero))
    }

    func testMostlyUpIsVertical() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: 4, height: -12)), .vertical)
    }

    func testMostlyDownIsAlsoVertical() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: -2, height: 15)), .vertical)
    }

    func testMostlySidewaysIsHorizontal() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: -14, height: 5)), .horizontal)
    }

    /// Đúng 45° thì nghiêng về ngang: kéo chéo không được làm thẻ hiện ra.
    func testAnExactDiagonalIsHorizontal() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: 10, height: -10)), .horizontal)
    }

    func testTheLockDistanceIsMeasuredAlongTheDiagonal() {
        XCTAssertEqual(AccessoryDragAxis.resolve(CGSize(width: 8, height: -8)), .horizontal,
                       "hypot(8, 8) ≈ 11.3 ≥ 10")
    }

    // MARK: - AccessoryDragRoute

    func testNoRouteBeforeTheLockDistance() {
        XCTAssertNil(AccessoryDragRoute.resolve(CGSize(width: 6, height: -3), swipeAllowed: true))
    }

    /// Kéo lên lái thẻ — y như trước khi có vuốt ngang.
    func testUpDrivesTheCard() {
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: 3, height: -14), swipeAllowed: true), .card)
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: 3, height: -14), swipeAllowed: false), .card)
    }

    func testDownDoesNothing() {
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: 3, height: 14), swipeAllowed: true), .ignored)
    }

    /// Ngang không bao giờ lái thẻ — nên không bao giờ dựng `accessoryDragging`,
    /// không rời nghỉ, không ẩn viên kính.
    func testSidewaysSwipesTheTrackAndNeverDrivesTheCard() {
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: -14, height: -4), swipeAllowed: true), .trackSwipe)
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: 14, height: 4), swipeAllowed: true), .trackSwipe)
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: 10, height: -10), swipeAllowed: true), .trackSwipe,
                       "chéo 45° lên trên vẫn là ngang, không bung thẻ")
    }

    /// Hàng đang ẩn (thẻ rời nghỉ) hoặc một cú đổi bài đang bay: cú ngang bị bỏ
    /// qua, và vẫn không rơi sang thẻ.
    func testSidewaysWhileNotAllowedIsIgnored() {
        XCTAssertEqual(AccessoryDragRoute.resolve(CGSize(width: -14, height: -4), swipeAllowed: false), .ignored)
    }
}
