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

    /// **Smoothstep, not linear.** A straight ramp reaches full opacity with
    /// its slope unchanged, and that discontinuity reads as a horizontal line
    /// across the screen. Halfway along the fade the two curves agree, so the
    /// quarter point is where they separate: linear would be 0.25.
    func testTheRampEasesRatherThanRisingStraight() {
        let stops = ScrollEdgeEffect.maskStops(fadeFraction: 1, samples: 4)

        // t = 0.25 -> 3t² - 2t³ = 0.15625, well below the linear 0.25.
        XCTAssertEqual(stops[1].color, Color.black.opacity(0.15625))
        // t = 0.5 is the one point where smoothstep and linear agree.
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
    /// would mean the whole band is ramp and nothing is at full strength.
    func testTheRealFadeStaysASmallPartOfTheBand() {
        for hasTrack in [true, false] {
            let fraction = ScrollEdgeEffect.fade / ScrollEdgeEffect.height(hasTrack: hasTrack)

            XCTAssertLessThan(fraction, 0.35, "fade dominates the band (hasTrack: \(hasTrack))")
            XCTAssertGreaterThan(fraction, 0)
        }
    }
}
