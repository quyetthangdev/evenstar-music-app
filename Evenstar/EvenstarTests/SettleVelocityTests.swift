import XCTest
import SwiftUI
@testable import Evenstar

/// `PlayerCard.settleVelocity` — the finger's speed at release, converted into
/// the units a SwiftUI spring takes as its initial velocity.
///
/// Three conversions live in one expression: a sign flip, points-to-progress,
/// and progress-to-remaining. Each is invisible when wrong. A sign error makes
/// every flick launch the card backwards for a few frames; a missing division
/// makes fast and slow releases indistinguishable again, which is the whole
/// thing this was added to fix. None of it shows up in a build, and none of it
/// shows up in a screenshot — a still frame cannot hold a velocity.
/// `@MainActor` like every other test class here. The helpers under test are
/// statics on a `View`, which `InferIsolatedConformances` makes main-actor
/// isolated, so a nonisolated test cannot call them under Swift 6. Nothing
/// about how these run changes — `XCTestCase` already runs them on the main
/// thread; the annotation only writes that down.
@MainActor
final class SettleVelocityTests: XCTestCase {

    /// A phone-sized drag range, so the numbers below read like real ones.
    private let travel: CGFloat = 750

    // MARK: - Sign

    /// Flicking up opens the card, and `progress` grows upward while
    /// `velocity.height` is positive *downward*. The negation is the whole test.
    func testFlickingUpTowardOpenGivesPositiveVelocity() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: -1500,   // upward
            travel: travel,
            from: 0.4,
            to: 1
        )

        XCTAssertGreaterThan(velocity, 0, "an upward flick must push toward the open state")
    }

    func testFlickingDownTowardClosedGivesPositiveVelocity() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: 1500,    // downward
            travel: travel,
            from: 0.6,
            to: 0
        )

        XCTAssertGreaterThan(
            velocity, 0,
            "a downward flick is also moving toward its target, so relative to that target it is positive"
        )
    }

    /// Released moving *away* from where it is going — a slow drag that has not
    /// passed the halfway point but is drifting the other way. The spring should
    /// be told so, and pull it back.
    func testMovingAwayFromTheTargetGivesNegativeVelocity() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: 400,     // downward, but the card is going up
            travel: travel,
            from: 0.7,
            to: 1
        )

        XCTAssertLessThan(velocity, 0)
    }

    // MARK: - Magnitude

    /// The whole point: a hard flick and a gentle release must not produce the
    /// same animation.
    func testAHarderFlickGivesAFasterSpring() {
        let gentle = PlayerCard.settleVelocity(
            verticalVelocity: -200, travel: travel, from: 0.5, to: 1
        )
        let hard = PlayerCard.settleVelocity(
            verticalVelocity: -2000, travel: travel, from: 0.5, to: 1
        )

        XCTAssertGreaterThan(hard, gentle * 2, "ten times the finger speed must read as much more than the same")
    }

    /// Both divisions, checked against a number worked out by hand.
    ///
    /// 1500 points per second over 750 points of travel is 2 progress per
    /// second. With half the range left to cover, that is 4 remainders per
    /// second.
    func testTheConversionMatchesTheArithmetic() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: -1500, travel: travel, from: 0.5, to: 1
        )

        XCTAssertEqual(velocity, 4, accuracy: 0.0001)
    }

    /// The same finger speed with less distance left is a larger relative
    /// velocity — this is the division that turns "progress per second" into
    /// "remainders per second", and dropping it would make both cases equal.
    func testLessDistanceLeftMeansAHigherRelativeVelocity() {
        let farOut = PlayerCard.settleVelocity(
            verticalVelocity: -1500, travel: travel, from: 0.2, to: 1
        )
        let nearlyThere = PlayerCard.settleVelocity(
            verticalVelocity: -1500, travel: travel, from: 0.8, to: 1
        )

        XCTAssertGreaterThan(nearlyThere, farOut)
    }

    // MARK: - The edges

    func testAViolentFlickIsClamped() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: -8000, travel: travel, from: 0.98, to: 1
        )

        XCTAssertEqual(velocity, BottomBarStyle.maxSettleVelocity, accuracy: 0.0001)
    }

    func testAViolentFlickTheOtherWayIsClampedToo() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: 8000, travel: travel, from: 0.98, to: 1
        )

        XCTAssertEqual(velocity, -BottomBarStyle.maxSettleVelocity, accuracy: 0.0001)
    }

    /// Released exactly at the destination. The remainder is zero and the
    /// division is undefined; the answer is that a spring with nowhere to go has
    /// no use for a speed.
    func testNothingLeftToTravelGivesZero() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: -1500, travel: travel, from: 1, to: 1
        )

        XCTAssertEqual(velocity, 0)
    }

    /// `travel` is `max(..., 1)` at its call site today, but a zero here must
    /// not produce infinity if that ever changes.
    func testZeroTravelGivesZero() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: -1500, travel: 0, from: 0.5, to: 1
        )

        XCTAssertEqual(velocity, 0)
    }

    /// A release with no movement at all — a tap that dragged past the minimum
    /// distance and stopped. Nothing to hand over.
    func testAStillFingerGivesZero() {
        let velocity = PlayerCard.settleVelocity(
            verticalVelocity: 0, travel: travel, from: 0.5, to: 1
        )

        XCTAssertEqual(velocity, 0)
    }
}
