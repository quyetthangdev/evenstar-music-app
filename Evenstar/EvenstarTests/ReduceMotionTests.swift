import XCTest
import SwiftUI
@testable import Evenstar

/// `BottomBarStyle`'s Reduce Motion branch.
///
/// Every constant in that type now answers a flag, and nothing about that is
/// visible in a build: a wrong branch compiles, a missing branch compiles, and
/// a constant that quietly kept its spring compiles best of all. The failure it
/// produces is one nobody on the team can see — the whole point of the setting
/// is that the people it is for are not the people writing the code — so it has
/// to be pinned here or it is not pinned anywhere.
///
/// The flat durations are asserted as literals rather than derived. They came
/// from measuring each spring (see the table in `BottomBarStyle.swift`); a test
/// that recomputed them would agree with a mistake in the same way twice.
@MainActor
final class ReduceMotionTests: XCTestCase {

    /// The flag is process-global by design, so a test that flipped it and left
    /// would change the answers of every test that ran after it.
    private var saved = false

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        super.tearDown()
    }

    // MARK: - The springs that flatten

    /// Each of these describes a real displacement, so each gets a duration
    /// curve in place of its spring.
    func testEverySpringConstantFlattens() {
        BottomBarStyle.reduceMotion = false

        XCTAssertEqual(BottomBarStyle.morph, .spring(duration: 0.36, bounce: 0.24))
        XCTAssertEqual(BottomBarStyle.selection, .spring(duration: 0.38, bounce: 0.34))
        XCTAssertEqual(BottomBarStyle.content, .spring(duration: 0.34, bounce: 0.20))
        XCTAssertEqual(BottomBarStyle.settle, .spring(duration: 0.42, bounce: 0.14))
        XCTAssertEqual(BottomBarStyle.expand, .spring(duration: 0.52, bounce: 0.12))
        XCTAssertEqual(BottomBarStyle.queue, .spring(Spring(duration: 0.31, bounce: 0)))
        XCTAssertEqual(
            BottomBarStyle.queueContentSlide,
            .spring(Spring(duration: 0.20, bounce: 0))
        )

        BottomBarStyle.reduceMotion = true

        XCTAssertEqual(BottomBarStyle.morph, .easeInOut(duration: 0.20))
        XCTAssertEqual(BottomBarStyle.selection, .easeInOut(duration: 0.18))
        XCTAssertEqual(BottomBarStyle.content, .easeInOut(duration: 0.20))
        XCTAssertEqual(BottomBarStyle.settle, .easeInOut(duration: 0.29))
        XCTAssertEqual(BottomBarStyle.expand, .easeInOut(duration: 0.37))
        XCTAssertEqual(BottomBarStyle.queue, .easeInOut(duration: 0.29))
        XCTAssertEqual(BottomBarStyle.queueContentSlide, .easeInOut(duration: 0.19))
    }

    /// The branch has to *do* something. Asserted separately from the literals
    /// above so that a future retune of one spring — which would rightly change
    /// a literal — cannot land it on its own flat value without saying so.
    func testTheFlatBranchIsNeverTheSpring() {
        BottomBarStyle.reduceMotion = false
        let sprung = [
            BottomBarStyle.morph,
            BottomBarStyle.selection,
            BottomBarStyle.content,
            BottomBarStyle.settle,
            BottomBarStyle.expand,
            BottomBarStyle.queue,
            BottomBarStyle.queueContentSlide,
        ]

        BottomBarStyle.reduceMotion = true
        let flat = [
            BottomBarStyle.morph,
            BottomBarStyle.selection,
            BottomBarStyle.content,
            BottomBarStyle.settle,
            BottomBarStyle.expand,
            BottomBarStyle.queue,
            BottomBarStyle.queueContentSlide,
        ]

        for (full, reduced) in zip(sprung, flat) {
            XCTAssertNotEqual(full, reduced)
        }
    }

    // MARK: - The curves that deliberately do not change

    /// Six constants are already duration curves driving a fade or a 5pt swell
    /// — there is no displacement in them to remove, and shortening them would
    /// only break the phase relationships the `queue*` doc comments were
    /// measured to establish.
    ///
    /// This test exists to make that a decision rather than an oversight. If a
    /// later change gives one of them a real reduced variant, this failing is
    /// the correct outcome and the line comes out.
    func testTheAlreadyFlatCurvesAreUnchanged() {
        BottomBarStyle.reduceMotion = false
        let full = [
            BottomBarStyle.press,
            BottomBarStyle.control,
            BottomBarStyle.queueContentIn,
            BottomBarStyle.queueContentOut,
            BottomBarStyle.queueTitleOut,
            BottomBarStyle.queueTitleIn,
        ]

        BottomBarStyle.reduceMotion = true
        let reduced = [
            BottomBarStyle.press,
            BottomBarStyle.control,
            BottomBarStyle.queueContentIn,
            BottomBarStyle.queueContentOut,
            BottomBarStyle.queueTitleOut,
            BottomBarStyle.queueTitleIn,
        ]

        XCTAssertEqual(full, reduced)

        // And they are still the measured curves, delays included: the delays
        // are staging, not motion, and dropping one would put two blocks of
        // text on screen at once in the reduced mode only.
        XCTAssertEqual(BottomBarStyle.press, .easeOut(duration: 0.09))
        XCTAssertEqual(BottomBarStyle.control, .easeOut(duration: 0.15))
        XCTAssertEqual(BottomBarStyle.queueContentIn, .easeOut(duration: 0.13))
        XCTAssertEqual(BottomBarStyle.queueContentOut, .easeIn(duration: 0.10))
        XCTAssertEqual(BottomBarStyle.queueTitleOut, .easeIn(duration: 0.06).delay(0.04))
        XCTAssertEqual(BottomBarStyle.queueTitleIn, .easeOut(duration: 0.10).delay(0.13))
    }

    // MARK: - The velocity hand-off

    /// The reason `settle(initialVelocity:)` exists is that a violent flick and
    /// a gentle release must not produce the same animation. Reduced, they must
    /// — a hand-off of momentum is the sensation being removed, so the velocity
    /// is dropped rather than flattened around.
    func testReducedSettleIgnoresItsVelocityEntirely() {
        BottomBarStyle.reduceMotion = true

        let still = BottomBarStyle.settle(initialVelocity: 0)
        let gentle = BottomBarStyle.settle(initialVelocity: 1.5)
        let violent = BottomBarStyle.settle(initialVelocity: BottomBarStyle.maxSettleVelocity)
        let backwards = BottomBarStyle.settle(initialVelocity: -6)

        XCTAssertEqual(still, gentle)
        XCTAssertEqual(gentle, violent)
        XCTAssertEqual(violent, backwards)
    }

    /// …and the answer it gives is the same curve `settle` gives, so a card
    /// released mid-drag and a card told where to be share one vocabulary.
    func testReducedSettleIsTheFlatSettle() {
        BottomBarStyle.reduceMotion = true

        XCTAssertEqual(BottomBarStyle.settle(initialVelocity: 9), BottomBarStyle.settle)
        XCTAssertEqual(BottomBarStyle.settle(initialVelocity: 9), .easeInOut(duration: 0.29))
    }

    /// The guard on the other side: with the setting off, the velocity must
    /// still reach the spring. A branch that swallowed it in both modes would
    /// pass every assertion above.
    func testFullSettleStillCarriesItsVelocity() {
        BottomBarStyle.reduceMotion = false

        let still = BottomBarStyle.settle(initialVelocity: 0)
        let violent = BottomBarStyle.settle(initialVelocity: BottomBarStyle.maxSettleVelocity)

        XCTAssertNotEqual(still, violent)
        XCTAssertEqual(
            violent,
            .interpolatingSpring(
                duration: 0.42,
                bounce: 0.14,
                initialVelocity: BottomBarStyle.maxSettleVelocity
            )
        )
    }
}

/// How the flag gets from Settings → Accessibility into `BottomBarStyle`.
///
/// `RootView` reads `@Environment(\.accessibilityReduceMotion)` and pushes it
/// down from an `.onChange(of:initial:true)` action. Two things about that are
/// assumptions about SwiftUI rather than about this app, and this project has
/// been wrong about SwiftUI often enough — and been corrected by measurement
/// often enough — that they are measured here instead of reasoned about.
@MainActor
final class ReduceMotionWiringTests: XCTestCase {

    /// What SwiftUI did, in the order it did it.
    private enum Trace {
        @MainActor static var events: [String] = []
        @MainActor static func record(_ event: String) { events.append(event) }
    }

    private struct Leaf: View {
        var body: some View {
            Trace.record("leaf body")
            return Color.clear
        }
    }

    private struct Harness: View {
        let flag: Bool
        var body: some View {
            Trace.record("root body")
            return Leaf()
                .onChange(of: flag, initial: true) { _, isOn in
                    Trace.record("onChange \(isOn)")
                }
        }
    }

    /// Renders `Harness` for real — a hosting controller in a window, laid out
    /// — because none of this happens without a render pass.
    private func render(flag: Bool) {
        Trace.events = []
        let host = UIHostingController(rootView: Harness(flag: flag))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    /// **`initial: true` fires on the first render.** Without this the app
    /// would look correct to anyone who toggles the setting while it is running
    /// and be wrong for everyone who launched with it already on — which is
    /// everyone the feature is for.
    func testInitialTrueFiresOnTheFirstRender() {
        render(flag: true)

        XCTAssertTrue(
            Trace.events.contains("onChange true"),
            "onChange(initial: true) did not run on first render; got \(Trace.events)"
        )
    }

    /// **The action runs after the first `body` evaluation, not before.**
    ///
    /// This is the ordering the comments in `RootView` and
    /// `BottomBarStyle.reduceMotion` assert: the first evaluation of every body
    /// below the root reads the flag's default, and the flag is only correct
    /// from the action onward. It is documented as harmless — nothing animates
    /// on the first frame, `withAnimation` reads the constant when it fires,
    /// and a `.animation(_:value:)` cannot fire until its value changes, which
    /// needs the body that built it to run again — but "harmless" is only worth
    /// writing down if the ordering it describes is the real one.
    func testTheActionRunsAfterTheFirstBodyEvaluation() {
        render(flag: true)

        guard let action = Trace.events.firstIndex(of: "onChange true") else {
            return XCTFail("no onChange in \(Trace.events)")
        }
        guard let rootBody = Trace.events.firstIndex(of: "root body") else {
            return XCTFail("no root body in \(Trace.events)")
        }
        guard let leafBody = Trace.events.firstIndex(of: "leaf body") else {
            return XCTFail("no leaf body in \(Trace.events)")
        }

        XCTAssertLessThan(rootBody, action, "trace: \(Trace.events)")
        XCTAssertLessThan(leafBody, action, "trace: \(Trace.events)")
    }

    /// The value handed over is the current one, not a placeholder — the same
    /// render with the flag off must report `false`.
    func testTheActionReceivesTheValueItWasGiven() {
        render(flag: false)

        XCTAssertTrue(
            Trace.events.contains("onChange false"),
            "trace: \(Trace.events)"
        )
    }
}
