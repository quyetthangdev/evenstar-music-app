import XCTest
import SwiftUI
@testable import Evenstar

/// `PlayerCard.dragOffset` and `PlayerCard.dragThreshold` — the two halves of
/// the stutter at the start of a swipe.
///
/// `DragGesture.Value.translation` is measured from touch-down, not from the
/// moment the gesture recognised, so the first `onChanged` already carries the
/// whole `minimumDistance`. Left alone that is a dead zone followed by a jump,
/// and the reported symptom — "it hesitates at the start, every time" — is
/// exactly those two together.
///
/// None of this is visible in a screenshot. A still frame has no dead zone.
/// `@MainActor` like every other test class here. The helpers under test are
/// statics on a `View`, which `InferIsolatedConformances` makes main-actor
/// isolated, so a nonisolated test cannot call them under Swift 6. Nothing
/// about how these run changes — `XCTestCase` already runs them on the main
/// thread; the annotation only writes that down.
@MainActor
final class DragOffsetTests: XCTestCase {

    // MARK: - The threshold

    /// Open, the tap that a threshold protects is guarded off and cannot fire,
    /// so there is nothing to pay for.
    func testTheThresholdIsSmallWhileTheCardIsOpen() {
        XCTAssertLessThanOrEqual(PlayerCard.dragThreshold(progress: 1), 2)
    }

    /// Collapsed, the pill's tap-to-expand is live and must not be stolen.
    func testTheThresholdIsLargeWhileTheCardIsCollapsed() {
        XCTAssertGreaterThanOrEqual(PlayerCard.dragThreshold(progress: 0), 10)
    }

    /// Never zero: at zero the gesture recognises on touch-down and competes
    /// with the transport buttons inside the expanded card.
    func testTheThresholdIsNeverZero() {
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            XCTAssertGreaterThan(PlayerCard.dragThreshold(progress: progress), 0)
        }
    }

    // MARK: - The compensation

    /// The frame the gesture recognises on. Without this the card jumps the
    /// whole threshold in one frame.
    func testTravelExactlyAtTheThresholdProducesNoMovement() {
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: 10, threshold: 10), 0)
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: -10, threshold: 10), 0)
    }

    func testTravelBeyondTheThresholdIsReducedByIt() {
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: 60, threshold: 10), 50)
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: -60, threshold: 10), -50)
    }

    /// **The sign must survive.** `minimumDistance` measures two-dimensional
    /// distance, so a mostly-sideways drag can recognise with a vertical
    /// component smaller than the threshold. Subtracting blindly would flip it
    /// and send the card the opposite way to the finger.
    func testASmallVerticalComponentIsFlattenedRatherThanReversed() {
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: 3, threshold: 10), 0)
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: -3, threshold: 10), 0)
    }

    func testTheSignIsNeverInverted() {
        for height in stride(from: -40.0, through: 40.0, by: 1) {
            let offset = PlayerCard.dragOffset(
                translationHeight: CGFloat(height), threshold: 10
            )
            if height > 0 { XCTAssertGreaterThanOrEqual(offset, 0) }
            if height < 0 { XCTAssertLessThanOrEqual(offset, 0) }
        }
    }

    func testAStationaryFingerProducesNoMovement() {
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: 0, threshold: 10), 0)
    }

    /// Continuity at the moment of recognition is the whole point: the movement
    /// has to grow from zero, not start somewhere.
    func testMovementGrowsContinuouslyFromTheThreshold() {
        let atThreshold = PlayerCard.dragOffset(translationHeight: 10, threshold: 10)
        let justPast = PlayerCard.dragOffset(translationHeight: 10.5, threshold: 10)

        XCTAssertEqual(atThreshold, 0)
        XCTAssertEqual(justPast, 0.5, accuracy: 0.0001)
    }
}
