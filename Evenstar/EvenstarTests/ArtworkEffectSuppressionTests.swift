import XCTest
import SwiftUI
@testable import Evenstar

/// **The three platform facts F1's suppression is built on**, measured on
/// harnesses that import no line of `PlayerCard`.
///
/// Same division of labour, and the same reason, as
/// `SwiftUIAnimationTransactionEvidenceTests` in `ReduceMotionTests.swift`:
/// this project has reasoned wrongly about SwiftUI internals often enough that
/// a design resting on one is not worth building until a harness has been made
/// to say it out loud.
///
/// The three claims, all load-bearing for `ArtworkEffects`:
///
///   1. A `View`'s `body` is **not** re-evaluated per frame while SwiftUI
///      animates. So "is the card moving?" cannot be answered from inside
///      `body`, and a value read there is the animation's *target*, never what
///      is on screen. The signal has to be an explicit flag, and anything that
///      must follow the pixels has to be an `Animatable`.
///   2. `.opacity(0)` leaves the subtree in the tree and still evaluates it;
///      `if false` does not. So the suppression has to remove the material,
///      not dim it.
///   3. Forking a view between "modifier applied" and "modifier not applied"
///      mid-animation **destroys the in-flight animation** of everything inside
///      the fork. That is why the `.mask` stays applied at all times and only
///      its content changes, while the `.overlay`'s content — which is not the
///      artwork itself — is free to come and go.
@MainActor
final class ArtworkEffectEvidenceTests: XCTestCase {

    private enum Trace {
        @MainActor static var interpolated: [Double] = []
        @MainActor static var bodyRuns = 0
        @MainActor static var probeRuns = 0
        @MainActor static var go: (() -> Void)?

        @MainActor static func reset() {
            interpolated = []
            bodyRuns = 0
            probeRuns = 0
            go = nil
        }
    }

    /// Records what SwiftUI actually wrote, frame by frame — the presented
    /// value, as opposed to what `body` was handed.
    private struct Recorder: ViewModifier, Animatable {
        var value: Double
        var animatableData: Double {
            get { value }
            set {
                value = newValue
                Trace.interpolated.append(newValue)
            }
        }
        func body(content: Content) -> some View { content.opacity(value) }
    }

    private var window: UIWindow?

    private func host(_ root: some View) {
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        self.window = window
    }

    /// Lets the display link tick. Nothing about an animation happens without
    /// it — see the identical note in `SwiftUIAnimationTransactionEvidenceTests`.
    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func between(_ values: [Double]) -> [Double] {
        values.filter { $0 > 0.0001 && $0 < 0.9999 }
    }

    override func setUp() async throws {
        try await super.setUp()
        Trace.reset()
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        Trace.reset()
        try await super.tearDown()
    }

    // MARK: - 1. `body` does not run per frame

    private struct BodyCountHarness: View {
        @State private var value: Double = 1

        var body: some View {
            Trace.bodyRuns += 1
            return Color.blue
                .modifier(Recorder(value: value))
                .onAppear {
                    Trace.go = { withAnimation(.easeInOut(duration: 0.3)) { value = 0 } }
                }
        }
    }

    /// The premise of the whole design: a body that ran per frame could simply
    /// test `progress`, and no flag would be needed.
    ///
    /// The two numbers have to be read together. `interpolated` proves the
    /// animation really ran, and `bodyRuns` proves `body` saw exactly one of
    /// its frames. Either alone would be satisfied by an animation that never
    /// started.
    func testBodyIsEvaluatedOnceWhileSwiftUIDrivesManyFrames() throws {
        host(BodyCountHarness())
        let go = try XCTUnwrap(Trace.go)
        Trace.interpolated = []
        Trace.bodyRuns = 0

        go()
        pump(0.7)

        XCTAssertFalse(
            between(Trace.interpolated).isEmpty,
            "the animation did not run; trace: \(Trace.interpolated)"
        )
        XCTAssertEqual(
            Trace.bodyRuns, 1,
            "body ran \(Trace.bodyRuns) times for one animated change"
        )
    }

    // MARK: - 2. `.opacity(0)` keeps the subtree; `if` removes it

    private struct Probe: View {
        var body: some View {
            Trace.probeRuns += 1
            return Rectangle().fill(.ultraThinMaterial)
        }
    }

    private struct PresenceHarness: View {
        let dimmed: Bool

        var body: some View {
            Color.red.overlay {
                if dimmed {
                    Probe().opacity(0)
                } else {
                    EmptyView()
                }
            }
        }
    }

    /// `PlayerCard` ~1449 says a material costs the same at opacity 0.01 as at
    /// 1, and that line is a measurement. This is the structural half of it,
    /// which is the half the fix rests on: at opacity 0 the material is still
    /// built and still in the tree, so there is something left to cost
    /// anything. Taking the branch away is the only thing that removes it.
    func testAMaterialAtOpacityZeroIsStillBuiltAndAnIfRemovesIt() {
        host(PresenceHarness(dimmed: true))
        let dimmed = Trace.probeRuns
        window?.isHidden = true
        window = nil

        Trace.probeRuns = 0
        host(PresenceHarness(dimmed: false))
        let absent = Trace.probeRuns

        XCTAssertGreaterThan(dimmed, 0, "the material at opacity 0 was never built")
        XCTAssertEqual(absent, 0, "the removed branch was built \(absent) times")
    }

    // MARK: - 3. Forking a modifier on and off destroys the animation inside it

    private struct ForkHarness: View {
        let forks: Bool
        @State private var wide = false
        @State private var masked = true

        private var probe: some View {
            Color.blue
                .modifier(Recorder(value: wide ? 0 : 1))
                .frame(width: wide ? 300 : 40, height: 40)
        }

        var body: some View {
            Group {
                if masked {
                    probe.mask(Color.white)
                } else {
                    probe
                }
            }
            .onAppear {
                Trace.go = {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        wide = true
                        if forks { masked = false }
                    }
                }
            }
        }
    }

    // MARK: - 3b. An `Animatable` wrapper does not freeze what it wraps

    private struct WrapperHarness: View {
        @State private var wide = false
        @State private var outer: Double = 1

        var body: some View {
            Color.blue
                .modifier(Recorder(value: wide ? 0 : 1))
                .frame(width: wide ? 300 : 40, height: 40)
                .modifier(Wrapper(value: outer))
                .onAppear {
                    Trace.go = {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            wide = true
                            outer = 0
                        }
                    }
                }
        }
    }

    /// A modifier whose own `body` is re-run on every frame of an animation,
    /// which is exactly what `ArtworkEffects` is.
    private struct Wrapper: ViewModifier, Animatable {
        var value: Double
        var animatableData: Double {
            get { value }
            set { value = newValue }
        }
        func body(content: Content) -> some View {
            content.overlay { if value > 0.5 { Color.clear } }
        }
    }

    /// The other half of the fork measurement, and the half that says the fix
    /// is safe: wrapping the artwork in an `Animatable` modifier that is itself
    /// animating, and whose `body` therefore rebuilds an overlay and a mask
    /// every frame, leaves the animation *inside* it running. A stable modifier
    /// is not a fork.
    func testAnAnimatableWrapperLeavesTheAnimationInsideItRunning() throws {
        host(WrapperHarness())
        let go = try XCTUnwrap(Trace.go)
        Trace.interpolated = []

        go()
        pump(0.7)

        XCTAssertFalse(
            between(Trace.interpolated).isEmpty,
            "the wrapped view never animated; trace: \(Trace.interpolated)"
        )
    }

    // MARK: - 4. Which curve one `Animatable` runs on when two states move it

    private struct DualHarness: View {
        @State private var shape: Double = 1
        @State private var reveal: Double = 1

        var body: some View {
            Color.blue
                .modifier(Recorder(value: shape * reveal))
                .onAppear {
                    Trace.go = {
                        withAnimation(.linear(duration: 1.0)) { shape = 0 }
                        withAnimation(.linear(duration: 0.1)) { reveal = 0 }
                    }
                }
        }
    }

    /// Both writes land in one update and both move the same `animatableData`,
    /// so SwiftUI has to pick one curve for it. Which one it picks decided
    /// whether the suppression could also cover the *closing* half of the
    /// morph: a fast curve on the reveal would take the two layers off the
    /// screen in 0.1s and leave the rest of the close free, where the morph's
    /// own curve gives them the whole close and saves nothing.
    ///
    /// It picks the morph's. So the close keeps both layers, and
    /// `PlayerCard.artworkEffectsAreInert(shapeProgress:)` only ever says yes
    /// at the collapsed end.
    ///
    /// Linear curves, so the answer is a number and not a judgement: 0.3s into
    /// a 0.1s fade the value would be 0; 0.3s into a 1.0s one it is still
    /// around 0.7. Both bounds are asserted — an upper one alone would be
    /// satisfied by an animation that never started.
    func testALaterFasterCurveDoesNotSpeedUpAPairedAnimatable() throws {
        host(DualHarness())
        let go = try XCTUnwrap(Trace.go)
        Trace.interpolated = []

        go()
        pump(0.3)

        let last = try XCTUnwrap(Trace.interpolated.last)
        XCTAssertGreaterThan(
            last, 0.5,
            "the fast curve won after all, and the close could be suppressed too; "
                + "trace tail: \(Trace.interpolated.suffix(5))"
        )
        XCTAssertLessThan(
            last, 0.95,
            "nothing moved at all; trace tail: \(Trace.interpolated.suffix(5))"
        )
    }

    /// The constraint the note at `PlayerCard` ~1934 states as "with no view
    /// inserted or removed mid-morph to pop", measured on the specific shape
    /// this task wanted to use: taking a `.mask` *off* the artwork while the
    /// artwork is mid-morph.
    ///
    /// The control run — same harness, same animation, only the fork removed —
    /// is what stops this passing because nothing was animating at all.
    func testForkingAModifierOnAndOffMidAnimationDestroysTheAnimationInsideIt() throws {
        host(ForkHarness(forks: false))
        let steady = try XCTUnwrap(Trace.go)
        Trace.interpolated = []
        steady()
        pump(0.7)
        let control = between(Trace.interpolated).count
        window?.isHidden = true
        window = nil

        host(ForkHarness(forks: true))
        let forking = try XCTUnwrap(Trace.go)
        Trace.interpolated = []
        forking()
        pump(0.7)
        let forked = between(Trace.interpolated).count

        XCTAssertGreaterThan(control, 0, "the control run never animated at all")
        XCTAssertEqual(
            forked, 0,
            "the forked run animated \(forked) intermediate values; if this is "
                + "green the `.mask` could be taken off entirely"
        )
    }
}

/// **When the two artwork layers may be taken away, and why that is safe.**
///
/// The arithmetic behind the suppression, separated from the view chain for
/// the reason `artworkGeometry` and `dragOffset` are: a modifier chain cannot
/// be asserted against, and these are the numbers whose being wrong is
/// invisible in a build and nearly invisible on a screen.
@MainActor
final class ArtworkEffectStrengthTests: XCTestCase {

    /// The property the whole fix stands on. At strength 0 every stop sits at
    /// location 1, which is an opaque white mask — the dissolve draws nothing,
    /// so removing the frost beside it and collapsing this to an identity mask
    /// cannot be seen. If this stops being true, the suppression starts
    /// snapping a soft edge to a hard one at the first frame of every open.
    func testTheDissolveIsAnIdentityMaskAtStrengthZero() {
        let stops = PlayerCard.dissolveStops(progress: 0)

        XCTAssertFalse(stops.isEmpty)
        for stop in stops {
            XCTAssertEqual(
                stop.location, 1, accuracy: 0.0001,
                "a stop sat at \(stop.location) with nothing to dissolve"
            )
        }
    }

    /// And that it is a real dissolve everywhere else, so the test above is not
    /// green against a function that returned a flat mask at every input.
    func testTheDissolveSpansTheBottomOfThePictureAtFullStrength() {
        let stops = PlayerCard.dissolveStops(progress: 1)
        let locations = stops.map(\.location)

        XCTAssertEqual(locations.first ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(locations.last ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(locations, locations.sorted(), "the stops ran backwards")
    }

    /// The rule that decides whether a morph may drop the layers: only where
    /// they are already drawing nothing. Both ends are asserted, because a
    /// predicate that always said yes would pop the close and a predicate that
    /// always said no would leave the open exactly as slow as it was.
    func testTheLayersMayOnlyBeDroppedWhereTheyDrawNothing() {
        XCTAssertTrue(PlayerCard.artworkEffectsAreInert(shapeProgress: 0))
        XCTAssertTrue(PlayerCard.artworkEffectsAreInert(shapeProgress: 0.0001))
        XCTAssertFalse(PlayerCard.artworkEffectsAreInert(shapeProgress: 0.05))
        XCTAssertFalse(PlayerCard.artworkEffectsAreInert(shapeProgress: 1))
    }

    /// The threshold is a hair, not a fraction of the journey. A tap-to-open
    /// starts at exactly 0, so anything bigger than a rounding error is only
    /// there to swallow the drag's first pixel — and one big enough to swallow
    /// a visible amount of frost would be dropping the layers from a card the
    /// user can see them on.
    func testTheInertThresholdIsSmallerThanAnythingVisible() {
        XCTAssertLessThan(PlayerCard.artworkEffectInertThreshold, 0.01)
        XCTAssertGreaterThan(PlayerCard.artworkEffectInertThreshold, 0)
    }

    /// The number itself, against figures rather than against another copy of
    /// its own arithmetic.
    ///
    /// The cross-check below is the one that would have been written on its
    /// own, and on its own it is worth nothing: `artworkGeometry` calls this
    /// function, so mutating the function moves both sides of that comparison
    /// and it stays green through anything. Anchoring figures, for the reason
    /// `testEveryPieceOfTheDragArithmeticIgnoresReduceMotion` needed them.
    func testShapeProgressIsTheJourneyLessWhateverTheQueueHasTaken() {
        XCTAssertEqual(PlayerCard.shapeProgress(progress: 1, queueFactor: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(PlayerCard.shapeProgress(progress: 1, queueFactor: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(PlayerCard.shapeProgress(progress: 1, queueFactor: 0.4), 0.6, accuracy: 0.0001)
        XCTAssertEqual(PlayerCard.shapeProgress(progress: 0.5, queueFactor: 0.5), 0.25, accuracy: 0.0001)
        XCTAssertEqual(PlayerCard.shapeProgress(progress: 0, queueFactor: 0), 0, accuracy: 0.0001)
    }

    /// The three callers of `shapeProgress` — the mask, the corner radius, and
    /// the two suppression sites — have to be asking the same question, and the
    /// only way to keep them asking it is for there to be one copy of it. This
    /// goes red the day somebody writes the expression out again inside
    /// `artworkGeometry`, which is the only way they can drift.
    func testShapeProgressIsWhatTheArtworkGeometryActuallyCarries() {
        for progress in [0.0, 0.25, 0.5, 1.0] {
            for queueFactor in [0.0, 0.4, 1.0] {
                let geometry = PlayerCard.artworkGeometry(
                    progress: progress,
                    queueFactor: queueFactor,
                    cardSize: CGSize(width: 390, height: 844),
                    fullBleed: true,
                    artworkSide: 300,
                    artworkTop: 80,
                    queueThumbCentre: CGPoint(x: 44, y: 120),
                    queueThumbSide: 44
                )

                XCTAssertEqual(
                    geometry.shapeProgress,
                    PlayerCard.shapeProgress(progress: progress, queueFactor: queueFactor),
                    accuracy: 0.0001,
                    "progress \(progress), queueFactor \(queueFactor)"
                )
            }
        }
    }

    /// The queue's own slot is the case that would be missed by reading
    /// `progress` alone: fully expanded with the queue open, the artwork is a
    /// 44pt thumbnail, and the layers must already be gone. It is also the one
    /// place the suppression needs no flag at all — see `ArtworkEffects`.
    func testTheQueueSlotIsInertEvenAtFullExpansion() {
        XCTAssertTrue(
            PlayerCard.artworkEffectsAreInert(
                shapeProgress: PlayerCard.shapeProgress(progress: 1, queueFactor: 1)
            )
        )
        XCTAssertFalse(
            PlayerCard.artworkEffectsAreInert(
                shapeProgress: PlayerCard.shapeProgress(progress: 1, queueFactor: 0.5)
            )
        )
    }
}
