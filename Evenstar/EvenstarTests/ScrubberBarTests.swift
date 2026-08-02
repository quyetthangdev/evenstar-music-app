import XCTest
import SwiftUI
@testable import Evenstar

final class ScrubberBarTests: XCTestCase {

    // MARK: - fillFraction

    func testFillFractionIsProportional() {
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: 120), 0.25, accuracy: 0.0001)
    }

    func testFillFractionClampsOutOfRangePositions() {
        XCTAssertEqual(ScrubberBar.fillFraction(position: -5, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.fillFraction(position: 500, duration: 120), 1, accuracy: 0.0001)
    }

    func testFillFractionIsZeroForUnusableDuration() {
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: .infinity), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.fillFraction(position: .nan, duration: 120), 0, accuracy: 0.0001)
    }

    // MARK: - time(forX:width:duration:)

    func testTimeAtEdgesMapsToStartAndEnd() {
        XCTAssertEqual(ScrubberBar.time(forX: 0, width: 200, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 200, width: 200, duration: 120), 120, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: 120), 60, accuracy: 0.0001)
    }

    func testTimeClampsBeyondEitherEndAndSurvivesZeroWidthOrDuration() {
        XCTAssertEqual(ScrubberBar.time(forX: -40, width: 200, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 900, width: 200, duration: 120), 120, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 0, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: 0), 0, accuracy: 0.0001)
    }
}
