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

    /// The run-out starts halfway up the bar, not at its top edge. Anchored at
    /// the edge, the material was still at full strength on the exact line
    /// where the bar ended, and that step was visible no matter how long the
    /// run-out got.
    func testTheRunOutStartsAtTheBarsMidline() {
        XCTAssertEqual(
            ScrollEdgeEffect.solidHeight(hasTrack: false),
            BottomBarMetrics.screenBottomInset + BottomBarMetrics.tabBarHeight / 2
        )
    }

    /// The midline that matters is the topmost element's, and with a track
    /// loaded that is the collapsed pill rather than the bar.
    func testALoadedTrackMovesTheMidlineUpToTheCollapsedPlayer() {
        XCTAssertEqual(
            ScrollEdgeEffect.solidHeight(hasTrack: true),
            BottomBarMetrics.tabBarTopOffset
                + BottomBarMetrics.playerTabGap
                + PlayerCard.collapsedHeight / 2
        )
    }

    /// The band is the solid part plus the run-out — nothing else, so a change
    /// to either shows up in the total rather than being absorbed.
    func testTheBandIsTheSolidPartPlusTheRunOut() {
        for hasTrack in [true, false] {
            XCTAssertEqual(
                ScrollEdgeEffect.height(hasTrack: hasTrack),
                ScrollEdgeEffect.solidHeight(hasTrack: hasTrack) + ScrollEdgeEffect.fade
            )
        }
    }

    /// The run-out has to finish clear of the bar, or the top of the band would
    /// cut across the bar itself rather than above it.
    func testTheRunOutFinishesAboveTheBar() {
        XCTAssertGreaterThan(
            ScrollEdgeEffect.height(hasTrack: false),
            BottomBarMetrics.tabBarTopOffset
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
        XCTAssertEqual(stops.last?.color, Color.black.opacity(ScrollEdgeEffect.peak))
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
        // It reaches `peak`, not 1 — see that constant for why the material is
        // deliberately never applied at full strength.
        XCTAssertEqual(stops[stops.count - 2].location, 0.25, accuracy: 0.0001)
        XCTAssertEqual(stops[stops.count - 2].color, Color.black.opacity(ScrollEdgeEffect.peak))
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

        // t = 0.25 -> 6t⁵ - 15t⁴ + 10t³ = 0.103515625, then scaled by `peak`.
        XCTAssertEqual(stops[1].color, Color.black.opacity(0.103515625 * ScrollEdgeEffect.peak))
        // t = 0.5 is the one point where all three curves agree.
        XCTAssertEqual(stops[2].color, Color.black.opacity(0.5 * ScrollEdgeEffect.peak))
    }

    /// **The material is never applied at full strength.** Measured, full
    /// strength darkened a plain white region by 4% while the blur contributed
    /// nothing there — a band that only darkens is the overlay the HIG rules
    /// out. A stop reaching 1 here would be that state returning.
    func testTheMaterialIsCappedBelowFullStrength() {
        let peaks = ScrollEdgeEffect.maskStops(fadeFraction: 0.3)
            .dropLast()                       // the appended solid remainder
            .map(\.color)

        XCTAssertEqual(peaks.last, Color.black.opacity(ScrollEdgeEffect.peak))
        XCTAssertLessThan(ScrollEdgeEffect.peak, 1)
        XCTAssertGreaterThan(ScrollEdgeEffect.peak, 0)
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

    // **A test was deleted here, and this note is why.**
    //
    // `testTheRealFadeStaysASmallPartOfTheBand` asserted the run-out was under
    // 0.35 of the band, then — when that failed on the first retune — under
    // 0.5, restated as a "design relationship". It was not one either time. It
    // was the arithmetic of whatever `fade` happened to be, dressed up as a
    // requirement, and the second version failed on the very next retune too.
    //
    // There is no rule that the run-out must be shorter than the solid part.
    // The solid part only has to cover the bar, and that *is* pinned, by
    // `testTheRunOutFinishesAboveTheBar`. A bound that has to be rewritten
    // every time a designer changes their mind is measuring the designer.
}
