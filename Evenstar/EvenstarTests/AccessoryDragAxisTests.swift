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
}
