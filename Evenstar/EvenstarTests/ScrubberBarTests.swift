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
        // Discriminates `duration > 0`: without it, 30 / 0 is +infinity, which
        // clamps to 1, not 0.
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: 0), 0, accuracy: 0.0001)
        // Documentation only — this cannot discriminate `duration.isFinite`.
        // Any finite position over +infinity is ±0 under IEEE-754, and NaN is
        // already rejected by `duration > 0`, so no input to *this* function
        // distinguishes the guard's presence. The case that genuinely requires
        // it lives in `time(forX:width:duration:)`, where a fraction times an
        // infinite duration is infinite rather than zero — see
        // `testTimeClampsBeyondEitherEndAndSurvivesZeroWidthOrDuration`.
        XCTAssertEqual(ScrubberBar.fillFraction(position: 30, duration: .infinity), 0, accuracy: 0.0001)
        // Discriminates `position.isFinite`: without it, NaN / 120 is NaN and
        // every comparison against it fails.
        XCTAssertEqual(ScrubberBar.fillFraction(position: .nan, duration: 120), 0, accuracy: 0.0001)
    }

    // MARK: - time(forX:width:duration:)

    func testTimeAtEdgesMapsToStartAndEnd() {
        XCTAssertEqual(ScrubberBar.time(forX: 0, width: 200, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 200, width: 200, duration: 120), 120, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: 120), 60, accuracy: 0.0001)
        // A second, different width. Every other assertion here uses 200, so an
        // implementation that hardcoded 200 and ignored `width` entirely would
        // pass all of them; this one returns 60 against such a stub instead of
        // the correct 30, and fails.
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 400, duration: 120), 30, accuracy: 0.0001)
    }

    func testTimeClampsBeyondEitherEndAndSurvivesZeroWidthOrDuration() {
        XCTAssertEqual(ScrubberBar.time(forX: -40, width: 200, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 900, width: 200, duration: 120), 120, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 0, duration: 120), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: 0), 0, accuracy: 0.0001)
        // Discriminates `duration.isFinite`. Unlike `fillFraction`, this
        // function multiplies by the duration instead of dividing by it, so
        // without the guard the midpoint of the bar yields 0.5 * .infinity =
        // +infinity — an infinite seek target handed to `onSeek` — and this
        // assertion fails.
        XCTAssertEqual(ScrubberBar.time(forX: 100, width: 200, duration: .infinity), 0, accuracy: 0.0001)
    }
}
