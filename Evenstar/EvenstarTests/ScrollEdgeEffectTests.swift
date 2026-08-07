import XCTest
import SwiftUI
@testable import Evenstar

/// The hand-rolled scroll edge effect's geometry.
///
/// The band itself can only be judged by eye — whether it reads as a soft
/// separation or as a haze is not a number. What *is* a number, and what breaks
/// silently, is the arithmetic underneath: a band that stops short of the
/// collapsed player, or a mask whose stops run past the end of the gradient.
final class ScrollEdgeEffectTests: XCTestCase {

    // MARK: - Height

    /// The whole point of deriving it from `BottomBarMetrics` rather than
    /// writing a number: the band has to cover what the bar actually occupies.
    func testTheBandCoversTheBarAndItsRunOut() {
        XCTAssertEqual(
            ScrollEdgeEffect.height(hasTrack: false),
            BottomBarMetrics.tabBarTopOffset + ScrollEdgeEffect.fade
        )
    }

    /// A loaded track puts the collapsed pill above the bar, and the pill needs
    /// the same separation the bar does — this is the case a fixed height would
    /// get wrong, leaving the pill sitting on sharp content.
    func testALoadedTrackExtendsTheBandOverTheCollapsedPlayer() {
        XCTAssertEqual(
            ScrollEdgeEffect.height(hasTrack: true),
            BottomBarMetrics.tabBarTopOffset
                + BottomBarMetrics.playerTabGap
                + PlayerCard.collapsedHeight
                + ScrollEdgeEffect.fade
        )
    }

    func testTheBandIsTallerWithATrackThanWithout() {
        XCTAssertGreaterThan(
            ScrollEdgeEffect.height(hasTrack: true),
            ScrollEdgeEffect.height(hasTrack: false)
        )
    }

    // MARK: - The mask

    /// Transparent at the very top and fully opaque by the bottom. Either end
    /// wrong is the difference between a soft band and a grey slab.
    func testTheMaskRunsFromClearAtTheTopToSolidAtTheBottom() {
        let stops = ScrollEdgeEffect.maskStops(fadeFraction: 0.25)

        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.first?.color, Color.black.opacity(0))
        XCTAssertEqual(stops.last?.location, 1)
        XCTAssertEqual(stops.last?.color, Color.black)
    }

    /// Locations must never decrease. An out-of-order stop list does not fail
    /// to compile and does not crash — it renders a band with a seam in it.
    func testStopLocationsNeverGoBackwards() {
        for fraction in [0.05, 0.25, 0.5, 1.0] {
            let locations = ScrollEdgeEffect.maskStops(fadeFraction: fraction).map(\.location)

            XCTAssertEqual(
                locations, locations.sorted(),
                "stops out of order at fadeFraction \(fraction)"
            )
        }
    }

    /// The fade occupies exactly the fraction it is given, and the remainder of
    /// the band is solid — that split is what makes the run-out sit above the
    /// bar rather than across it.
    func testTheFadeEndsWhereItIsToldTo() {
        let stops = ScrollEdgeEffect.maskStops(fadeFraction: 0.25, samples: 4)

        // The last sampled fade stop, before the solid remainder is appended.
        //
        // `.opacity(1)` rather than `.black`: smoothstep(1) is exactly 1, so
        // the colour is fully opaque — but `Color` compares how it was built,
        // not what it renders, and `Color.black.opacity(1) != Color.black`.
        XCTAssertEqual(stops[stops.count - 2].location, 0.25, accuracy: 0.0001)
        XCTAssertEqual(stops[stops.count - 2].color, Color.black.opacity(1))
    }

    /// **Smootherstep, not linear and not smoothstep.** A straight ramp reaches
    /// full opacity with its slope unchanged, and that discontinuity reads as a
    /// horizontal line. Smoothstep fixes the slope but leaves the *second*
    /// derivative jumping, which still read as abrupt on screen.
    ///
    /// The quarter point separates all three: linear 0.25, smoothstep 0.15625,
    /// smootherstep 0.103515625. Asserting the exact value is what makes a
    /// silent revert to either of the others fail here.
    func testTheRampEasesRatherThanRisingStraight() {
        let stops = ScrollEdgeEffect.maskStops(fadeFraction: 1, samples: 4)

        // t = 0.25 -> 6t⁵ - 15t⁴ + 10t³ = 0.103515625.
        XCTAssertEqual(stops[1].color, Color.black.opacity(0.103515625))
        // t = 0.5 is the one point where all three curves agree.
        XCTAssertEqual(stops[2].color, Color.black.opacity(0.5))
    }

    /// A band shorter than the fade would put a stop past 1.0, which is not a
    /// valid gradient. Clamping keeps the mask well-formed instead.
    func testAFadeLongerThanTheBandIsClamped() {
        let locations = ScrollEdgeEffect.maskStops(fadeFraction: 4).map(\.location)

        XCTAssertEqual(locations.max(), 1)
        XCTAssertEqual(locations, locations.sorted())
    }

    func testANegativeFractionDoesNotProduceNegativeLocations() {
        let locations = ScrollEdgeEffect.maskStops(fadeFraction: -1).map(\.location)

        XCTAssertNil(locations.first { $0 < 0 })
    }

    /// The real call site's fraction, at both bar heights: the fade must stay a
    /// run-out rather than swallowing the band. Anything approaching 1 here
    /// would mean the whole band is ramp and nothing is at full strength, which
    /// is the state where content passes under the bar unprotected.
    ///
    /// **The bound was 0.35 and is now stated as a relationship instead.** 0.35
    /// was an arithmetic consequence of the first fade length, not a
    /// requirement — and that length was wrong: the transition read as an edge,
    /// and lengthening it is what fixed it. A bound that fails whenever the
    /// fade is retuned is a bound that tests the tuning rather than the design.
    ///
    /// What the design actually requires is that the full-strength region below
    /// the fade is at least as tall as the fade itself, so the bar always sits
    /// on fully-blurred content. That is `fraction <= 0.5`, and it stays true
    /// whatever the fade is set to next.
    func testTheFullStrengthRegionIsNeverShorterThanTheFade() {
        for hasTrack in [true, false] {
            let fraction = ScrollEdgeEffect.fade / ScrollEdgeEffect.height(hasTrack: hasTrack)

            XCTAssertLessThanOrEqual(
                fraction, 0.5,
                "the fade is taller than the solid part it runs out of (hasTrack: \(hasTrack))"
            )
            XCTAssertGreaterThan(fraction, 0)
        }
    }
}
