import XCTest
import SwiftUI
import SwiftData
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

    // MARK: - The distances that go to zero

    /// `recedeScale` is not a curve, it is a *distance*, and reducing motion
    /// has to take the distance out rather than travel it differently.
    func testTheRecedeScaleFlattensToNoScaleAtAll() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(BottomBarStyle.recedeScale, 0.92)

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(BottomBarStyle.recedeScale, 1)
    }

    /// The constant is not the claim. The claim is that the screen behind the
    /// player does not move, so the assertion is on the expression
    /// `RecedeBehindPlayer` actually applies — at every `progress`, because a
    /// drag visits all of them and Reduce Motion must not depend on which one.
    func testTheContentBehindThePlayerNeverShrinksWhenMotionIsReduced() {
        BottomBarStyle.reduceMotion = true

        for step in 0...20 {
            let progress = Double(step) / 20
            let scale = 1 - (1 - BottomBarStyle.recedeScale) * progress
            XCTAssertEqual(scale, 1, accuracy: 1e-12, "at progress \(progress)")
        }
    }

    /// …and with the setting off it still recedes, all the way to 0.92 at full
    /// screen. A branch that flattened both modes would pass the test above.
    func testTheContentBehindThePlayerStillRecedesWithTheSettingOff() {
        BottomBarStyle.reduceMotion = false

        XCTAssertEqual(1 - (1 - BottomBarStyle.recedeScale) * 0, 1, accuracy: 1e-12)
        XCTAssertEqual(1 - (1 - BottomBarStyle.recedeScale) * 1, 0.92, accuracy: 1e-12)
    }

    // MARK: - The drag path, which must not change at all

    /// **The non-negotiable one.** Reduce Motion is aimed at animation, not at
    /// direct manipulation: while a finger is on the card, the card following
    /// it is *feedback*, and every system sheet keeps doing it with the
    /// setting on. Taking it away would not make the app more accessible, it
    /// would leave the user unable to close the player.
    ///
    /// The gesture's arithmetic is four pure functions, so "the drag path did
    /// not change" is a statement that can be asserted rather than eyeballed:
    /// every one of them must give the same answer in both modes. A reduced
    /// branch introduced into any of them — a smaller threshold, a swallowed
    /// velocity, a scaled-down offset — fails here.
    ///
    /// What this cannot see is the gesture handler itself, which needs a
    /// touch to run. `drag(...).onChanged` is unchanged by B3 and writes
    /// `dragDelta` outside every transaction exactly as it did before; that
    /// half is pinned by review of the diff, not by this test.
    func testEveryPieceOfTheDragArithmeticIgnoresReduceMotion() {
        let translations: [CGFloat] = [-400, -37, -10, -2, 0, 2, 10, 37, 400]
        let progresses: [Double] = [0, 0.05, 0.49, 0.5, 0.51, 0.95, 1]
        let velocities: [CGFloat] = [-3000, -420, 0, 420, 3000]

        func answers() -> [Double] {
            var out: [Double] = [Double(BottomBarStyle.maxSettleVelocity)]
            for progress in progresses {
                let threshold = PlayerCard.dragThreshold(progress: progress)
                out.append(Double(threshold))
                for translation in translations {
                    out.append(Double(PlayerCard.dragOffset(
                        translationHeight: translation,
                        threshold: threshold
                    )))
                }
                for velocity in velocities {
                    out.append(PlayerCard.settleVelocity(
                        verticalVelocity: velocity,
                        travel: 803,
                        from: progress,
                        to: progress > 0.5 ? 1 : 0
                    ))
                }
            }
            return out
        }

        BottomBarStyle.reduceMotion = false
        let full = answers()

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(full, answers())
    }

    // MARK: - The fade that replaces the card's morph

    /// A morph worth hiding gets hidden…
    func testTheFullTravelNeedsTheFade() {
        XCTAssertTrue(PlayerCard.morphNeedsFade(from: 0, to: 1))
        XCTAssertTrue(PlayerCard.morphNeedsFade(from: 1, to: 0))
        XCTAssertTrue(PlayerCard.morphNeedsFade(from: 0.62, to: 1))
        XCTAssertTrue(PlayerCard.morphNeedsFade(from: 0.44, to: 0))
    }

    /// …and a move nobody can see does not, which is the half that stops the
    /// whole player blinking every time a row in the queue is tapped:
    /// `explicitSelections` calls `expand()` on an already-expanded card.
    func testAMoveNobodyCanSeeIsNotWorthAFade() {
        XCTAssertFalse(PlayerCard.morphNeedsFade(from: 1, to: 1))
        XCTAssertFalse(PlayerCard.morphNeedsFade(from: 0, to: 0))
        XCTAssertFalse(PlayerCard.morphNeedsFade(from: 0.995, to: 1))
        XCTAssertFalse(PlayerCard.morphNeedsFade(from: 0.01, to: 0))
    }

    /// The threshold has to be small enough that it can only ever skip the
    /// fade for a move of a few points. On the ~800pt travel of an iPhone 17
    /// this is 16pt; anything an order of magnitude larger would start
    /// letting real morphs through unfaded.
    func testTheFadeThresholdStaysSmallEnoughToOnlySkipInvisibleMoves() {
        XCTAssertLessThanOrEqual(PlayerCard.morphFadeMinimumTravel, 0.05)
        XCTAssertGreaterThan(PlayerCard.morphFadeMinimumTravel, 0)
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

/// **The wiring for the card's own morph.** `PlayerCard` is rendered for real
/// and made to open by the one path a test can reach without a finger:
/// `explicitSelections`, which is what a tapped row increments and what
/// `onChange(of: playback.explicitSelections)` turns into `expand()`.
///
/// What it can observe is `PlayerExpansion`, which the test owns: the card
/// writes both the destination and the curve into it from inside
/// `morph(to:curve:)`, so the object is a direct readout of which branch ran.
/// `settled`, `dragDelta` and `cardOpacity` are private `@State` and stay
/// unobservable — this class cannot tell you the card *looks* right, only that
/// the branch it took is the branch the setting asks for.
///
/// The distinction that matters is in `animation`, not in `progress`. Both
/// modes end at 1; the reduced one gets there with `nil`, meaning nothing
/// between here and there is interpolated, which is the whole feature.
@MainActor
final class PlayerCardReducedMorphWiringTests: XCTestCase {

    private var saved = false
    private var window: UIWindow?

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Renders a card that is collapsed and has a track, then plays a track
    /// the way a tapped row does.
    private func openThePlayer(reduceMotion: Bool) throws -> PlayerExpansion {
        BottomBarStyle.reduceMotion = reduceMotion

        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)
        let playback = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        let expansion = PlayerExpansion()

        let host = UIHostingController(
            rootView: PlayerCard(playback: playback, minimised: 0, expansion: expansion)
                .environment(library)
                .environment(playback)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        self.window = window

        // The card starts collapsed, and `onChange` cannot have fired yet.
        XCTAssertEqual(expansion.progress, 0)

        playback.play(track, in: [track])
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        return expansion
    }

    /// With the setting on, the card is *told* where to be and nothing is
    /// interpolated on the way. A `nil` here is the geometry jump; anything
    /// else means the 750pt travel is still being animated and B3 did not
    /// happen.
    func testOpeningWithReduceMotionOnHandsOverNoAnimationAtAll() throws {
        let expansion = try openThePlayer(reduceMotion: true)

        XCTAssertEqual(expansion.progress, 1)
        XCTAssertNil(
            expansion.animation,
            "the reduced morph handed over \(String(describing: expansion.animation))"
        )
    }

    /// And with it off, the same tap still animates the whole travel on
    /// `expand`. Without this the test above would pass against a card that
    /// had simply stopped animating for everybody.
    func testOpeningWithReduceMotionOffStillHandsOverTheExpandSpring() throws {
        let expansion = try openThePlayer(reduceMotion: false)

        XCTAssertEqual(expansion.progress, 1)
        XCTAssertEqual(expansion.animation, .spring(duration: 0.52, bounce: 0.12))
    }
}

/// **What SwiftUI does with transactions** — the three behaviours B3's
/// cross-fade is built on, measured instead of reasoned about.
///
/// Everything below runs on `Harness`, declared in this file. None of it
/// imports a line of `PlayerCard`, and a green run here says nothing about the
/// player; what it says is whether the mechanism the player's
/// `fadeMorph(to:)` leans on is the mechanism SwiftUI has. Same division of
/// labour as `SwiftUIOnChangeOrderingEvidenceTests` below, and here for the
/// same reason: this project has been wrong about SwiftUI internals often
/// enough, and corrected by measurement often enough, that a comment claiming
/// one is not worth writing without a harness under it.
///
/// The three claims, all of them load-bearing:
///
///   1. `withAnimation` really does drive intermediate values — so a fade
///      written this way actually fades.
///   2. `withTransaction(Transaction(animation: nil))` drives **none** — so
///      the geometry change in `morph(to:curve:)` is a jump and not a fast
///      interpolation. The whole point of the feature is that the jump is
///      never on screen.
///   3. Clearing a value to 0 without animation and animating it back to 1
///      **in the same update** does fade, from 0.
///
/// The third is here because reasoning got it wrong first. The prediction was
/// that SwiftUI only ever sees the value a state variable ends an update
/// holding, so the pair would collapse into "1 to 1" and no fade would run —
/// which would have forced a two-phase implementation with a `completion`, a
/// cancellation token, and a window in which `cardOpacity` sits at 0 in state
/// and a dropped completion leaves the player invisible for good. The trace
/// this class prints says otherwise, and `PlayerCard` is the smaller, safer
/// shape because of it. Written down so nobody re-derives the wrong version
/// from first principles later.
///
/// The recorder is an `Animatable` `ViewModifier`, and the two traces mean
/// different things. `interpolated` is what SwiftUI wrote into
/// `animatableData` — an animation, frame by frame. `rendered` is every value
/// its `body` was actually evaluated with, animated or not. A change with no
/// animation shows up in the second and not the first, which is precisely the
/// distinction claim 2 needs.
@MainActor
final class SwiftUIAnimationTransactionEvidenceTests: XCTestCase {

    private enum Trace {
        @MainActor static var interpolated: [Double] = []
        @MainActor static var rendered: [Double] = []
        @MainActor static var apply: ((Double, Animation?) -> Void)?
        @MainActor static var dip: ((Animation) -> Void)?

        @MainActor static func reset() {
            interpolated = []
            rendered = []
        }
    }

    private struct Recorder: ViewModifier, Animatable {
        var value: Double
        var animatableData: Double {
            get { value }
            set {
                value = newValue
                Trace.interpolated.append(newValue)
            }
        }
        func body(content: Content) -> some View {
            Trace.rendered.append(value)
            return content.opacity(value)
        }
    }

    private struct Harness: View {
        @State private var value: Double = 1

        var body: some View {
            Color.blue
                .modifier(Recorder(value: value))
                .onAppear {
                    Trace.apply = { target, animation in
                        if let animation {
                            withAnimation(animation) { value = target }
                        } else {
                            withTransaction(Transaction(animation: nil)) { value = target }
                        }
                    }
                    // Both writes in one synchronous scope, which is the
                    // shape `PlayerCard.morph(to:curve:)` has.
                    Trace.dip = { animation in
                        withTransaction(Transaction(animation: nil)) { value = 0 }
                        withAnimation(animation) { value = 1 }
                    }
                }
        }
    }

    private var window: UIWindow?

    override func setUp() {
        super.setUp()
        Trace.reset()
        Trace.apply = nil
        Trace.dip = nil

        let host = UIHostingController(rootView: Harness())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        self.window = window
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Lets the display link tick. Nothing about an animation happens without
    /// this — a test that only laid out would see the final value and call it
    /// a snap.
    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Values strictly between the two ends: the evidence that something was
    /// interpolated rather than assigned.
    private func between(_ values: [Double]) -> [Double] {
        values.filter { $0 > 0.0001 && $0 < 0.9999 }
    }

    func testWithAnimationDrivesIntermediateValues() throws {
        let apply = try XCTUnwrap(Trace.apply)
        Trace.reset()

        apply(0, .easeInOut(duration: 0.2))
        pump(0.3)

        XCTAssertFalse(
            between(Trace.interpolated).isEmpty,
            "nothing was interpolated; trace: \(Trace.interpolated)"
        )
        XCTAssertEqual(Trace.rendered.last ?? -1, 0, accuracy: 0.001)
    }

    /// The claim the geometry jump rests on. If this goes red, the reduced
    /// morph is not a jump-while-invisible any more — it is a very fast
    /// version of exactly the motion the setting exists to remove, and the
    /// feature is back to "changed the curve".
    ///
    /// Note what the two traces say together, because either alone would be
    /// weak: `interpolated` comes back **empty**, and `rendered` ends at the
    /// new value. The write landed and was drawn; SwiftUI simply rebuilt the
    /// modifier from it rather than animating `animatableData` toward it.
    func testANilAnimationTransactionDrivesNoIntermediateValueAtAll() throws {
        let apply = try XCTUnwrap(Trace.apply)
        Trace.reset()

        apply(0, nil)
        pump(0.3)

        XCTAssertTrue(
            Trace.interpolated.isEmpty,
            "a nil-animation transaction interpolated; trace: \(Trace.interpolated)"
        )
        XCTAssertTrue(
            between(Trace.rendered).isEmpty,
            "a nil-animation transaction drew a value in between; trace: \(Trace.rendered)"
        )
        XCTAssertEqual(Trace.rendered.last ?? -1, 0, accuracy: 0.001)
    }

    /// **The one that was predicted to fail.** Clearing the value to 0 with no
    /// animation and animating it back to 1 in the same synchronous scope
    /// fades, from 0 — SwiftUI does not collapse the pair into the value the
    /// update ends on.
    ///
    /// This is `PlayerCard.morph(to:curve:)`'s whole mechanism, so the trace
    /// is asserted in three ways rather than one: it starts at 0, it passes
    /// through the middle, and it ends at 1.
    func testClearingAndRestoringInOneUpdateStillFadesFromZero() throws {
        let dip = try XCTUnwrap(Trace.dip)
        Trace.reset()

        dip(.easeInOut(duration: 0.2))
        pump(0.3)

        XCTAssertEqual(Trace.interpolated.first ?? -1, 0, accuracy: 0.001)
        XCTAssertFalse(
            between(Trace.interpolated).isEmpty,
            "the fade did not run; trace: \(Trace.interpolated)"
        )
        XCTAssertEqual(Trace.interpolated.last ?? -1, 1, accuracy: 0.001)
    }
}

/// The arithmetic behind the flat-duration table in `BottomBarStyle.swift`,
/// re-run against Apple's own `Spring` rather than trusted from a comment.
///
/// The table's seven `t(98%)` figures and its two overshoot figures were
/// measured once, by hand, and written down. B3 found a third figure in the
/// same block wrong by a factor of ten — the second undershoot was quoted as
/// "four hundredths of a percent even for the bounciest" when the bounciest is
/// `selection` at four *tenths*, and six hundredths is `morph`'s number. A
/// prose figure nothing executes is exactly the kind that can be wrong for
/// months, so the block now has a harness.
///
/// The springs are restated here as literals rather than read from
/// `BottomBarStyle`, whose `…Full` constants are private. That is the right
/// way round anyway: this class asks whether the *table* is true of the
/// springs it names, and `testEverySpringConstantFlattens` above is what pins
/// the file to those same springs.
@MainActor
final class SpringSettlingEvidenceTests: XCTestCase {

    /// Name, duration, bounce, and the flat duration the table derives.
    private let springs: [(name: String, duration: Double, bounce: Double, flat: Double)] = [
        ("morph", 0.36, 0.24, 0.20),
        ("selection", 0.38, 0.34, 0.18),
        ("content", 0.34, 0.20, 0.20),
        ("settle", 0.42, 0.14, 0.29),
        ("expand", 0.52, 0.12, 0.37),
        ("queue", 0.31, 0, 0.29),
        ("queueContentSlide", 0.20, 0, 0.19),
    ]

    /// 1ms sampling, the interval the table says it was built at.
    private func samples(_ spring: Spring, upTo end: TimeInterval = 4) -> [(t: Double, v: Double)] {
        stride(from: 0, through: end, by: 0.001).map { time in
            let value: Double = spring.value(target: 1.0, time: time)
            return (time, value)
        }
    }

    /// Every flat duration is the time its own spring first crosses 98%,
    /// rounded to the hundredth. This is the whole derivation, executed.
    func testEachFlatDurationIsItsSpringsFirstCrossingOf98Percent() {
        for spring in springs {
            let crossing = samples(Spring(duration: spring.duration, bounce: spring.bounce))
                .first { $0.v >= 0.98 }?.t
            guard let crossing else {
                return XCTFail("\(spring.name) never reached 98%")
            }
            XCTAssertEqual(
                (crossing * 100).rounded() / 100,
                spring.flat,
                accuracy: 1e-9,
                "\(spring.name) crosses 98% at \(crossing)"
            )
        }
    }

    /// "None of the seven dips back under 98% afterwards." The claim the
    /// corrected figure supports, asserted rather than described.
    func testNoSpringDipsBackUnder98PercentAfterCrossingIt() {
        for spring in springs {
            let after = samples(Spring(duration: spring.duration, bounce: spring.bounce))
                .drop { $0.v < 0.98 }
            XCTAssertFalse(after.isEmpty, "\(spring.name) never reached 98%")
            for sample in after {
                XCTAssertGreaterThanOrEqual(
                    sample.v, 0.98,
                    "\(spring.name) fell back to \(sample.v) at t=\(sample.t)"
                )
            }
        }
    }

    /// The two figures the comment now quotes, and the ordering that makes
    /// `selection` the worst case: the trough depth is a function of the
    /// damping ratio alone, so it ranks by bounce and `morph` cannot be the
    /// bounciest anything.
    func testTheSecondUndershootIsFourTenthsOfAPercentForTheBounciest() {
        func trough(duration: Double, bounce: Double) -> Double {
            let all = samples(Spring(duration: duration, bounce: bounce))
            guard let peak = all.max(by: { $0.v < $1.v })?.t else { return 1 }
            return all.filter { $0.t > peak }.map(\.v).min() ?? 1
        }

        // `selection`, the bounciest of the seven.
        XCTAssertEqual(trough(duration: 0.38, bounce: 0.34), 0.995994, accuracy: 5e-6)
        // `morph`, whose 0.0644% was the number the comment used to quote
        // against `selection`.
        XCTAssertEqual(trough(duration: 0.36, bounce: 0.24), 0.999356, accuracy: 5e-6)

        // Ten times apart, which is the size of the error that was there.
        XCTAssertEqual(
            (1 - trough(duration: 0.38, bounce: 0.34))
                / (1 - trough(duration: 0.36, bounce: 0.24)),
            6.2,
            accuracy: 0.5
        )
    }

    /// The harness itself, checked against the two overshoot figures the same
    /// comment block already carried. If this class disagreed with those, it
    /// would be the class that was wrong.
    func testTheHarnessReproducesTheOvershootsAlreadyInTheComment() {
        func peak(duration: Double, bounce: Double) -> Double {
            samples(Spring(duration: duration, bounce: bounce)).map(\.v).max() ?? 0
        }

        XCTAssertEqual(peak(duration: 0.36, bounce: 0.24), 1.025, accuracy: 5e-4)
        XCTAssertEqual(peak(duration: 0.38, bounce: 0.34), 1.063, accuracy: 5e-4)
    }
}

/// What SwiftUI does with `.onChange(of:initial:true)` — **not** what this app
/// does with it.
///
/// **Read this before trusting a green run here.** Every view in this class is
/// declared in this file. Nothing below imports a single line of the app's
/// wiring: delete the `.onChange` from `RootView`, flip it to `initial: false`,
/// or replace its body with a hardcoded constant, and all three of these still
/// pass. They cannot tell you the app is wired up, and a reader who takes them
/// for that will ship a build where Reduce Motion does nothing.
///
/// `ReduceMotionRootViewWiringTests` below is the one that fails when the app
/// breaks. This class answers a different and narrower question: *is the
/// SwiftUI behaviour the design leans on actually the behaviour SwiftUI has?*
/// Two claims in `RootView` and `BottomBarStyle.reduceMotion` depend on it —
/// that `initial: true` fires at all, and that it fires after the first `body`
/// evaluation rather than before, which is why "the first evaluation of every
/// body captures the default" is written down as harmless. This project has
/// been wrong about SwiftUI often enough, and corrected by measurement often
/// enough, that those are measured rather than reasoned about.
///
/// So: this class going red means an assumption about SwiftUI expired. It
/// going green means nothing whatever about `RootView`.
@MainActor
final class SwiftUIOnChangeOrderingEvidenceTests: XCTestCase {

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

    /// **SwiftUI fires an `initial: true` action on the first render** — on
    /// `Harness` below, which is declared in this file. The app's use of the
    /// same modifier is pinned in `ReduceMotionRootViewWiringTests`, not here.
    ///
    /// Worth measuring because `RootView` would be wrong in an invisible way
    /// without this behaviour: correct for anyone who toggles the setting
    /// mid-session, wrong for everyone who launched with it already on — which
    /// is everyone the feature is for.
    func testSwiftUIFiresAnInitialTrueActionOnTheFirstRenderOfALocalHarness() {
        render(flag: true)

        XCTAssertTrue(
            Trace.events.contains("onChange true"),
            "onChange(initial: true) did not run on first render; got \(Trace.events)"
        )
    }

    /// **SwiftUI runs the action after the first `body` evaluation, not
    /// before** — measured on `Harness` below, not on `RootView`.
    ///
    /// This is the ordering two comments in the app assert without being able
    /// to prove it themselves: the first evaluation of every body below the
    /// root reads the flag's default, and the flag is only right from the
    /// action onward. Both call that harmless — nothing animates on the first
    /// frame, `withAnimation` reads the constant when it fires, and a
    /// `.animation(_:value:)` cannot fire until its value changes, which needs
    /// the body that built it to run again — but "harmless" is only worth
    /// writing down if the ordering it describes is the real one. If this goes
    /// red, those two comments need rewriting, and the app may need a seed
    /// value; nothing about `RootView` itself has broken.
    func testSwiftUIRunsTheActionAfterTheFirstBodyEvaluationOfALocalHarness() {
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

    /// SwiftUI hands the action the current value rather than a placeholder —
    /// again on `Harness`, so the same render with the flag off reports
    /// `false`.
    func testSwiftUIHandsTheActionTheLocalHarnessesCurrentValue() {
        render(flag: false)

        XCTAssertTrue(
            Trace.events.contains("onChange false"),
            "trace: \(Trace.events)"
        )
    }
}

/// **The wiring.** `RootView` is rendered for real here, and this is the only
/// class in this file that fails when the app stops respecting Reduce Motion.
///
/// What it costs: an in-memory `ModelContainer` and the seven services
/// `EvenstarApp` injects, because `RootView` will not build without them. That
/// is a lot of setup for two assertions, and it is worth it — everything
/// cheaper than this turned out to be a test of code written inside the test.
/// The class above is the cautionary example.
///
/// Reduce Motion is injected through `\._accessibilityReduceMotion`. The public
/// `\.accessibilityReduceMotion` is get-only, so there is no supported way to
/// write it; the underscored pair is what the public getter reads, and it is
/// declared in SwiftUICore's `.swiftinterface` rather than being a symbol
/// prised out of the binary. If a future SDK renames it this file stops
/// compiling, which is the loud kind of failure — the alternative was leaving
/// the app's one accessibility invariant untested.
@MainActor
final class ReduceMotionRootViewWiringTests: XCTestCase {

    private var saved = false

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        super.tearDown()
    }

    /// Everything `EvenstarApp.body` supplies, with the two I/O boundaries
    /// mocked. `RootView` reads `PlaybackService` itself; the rest are read by
    /// the screens inside its `TabView`, and a missing one is a crash on
    /// render rather than a compile error, so they are all here.
    private func renderRootView(reduceMotion injected: Bool) throws {
        let container = try ModelContainer(
            for: Track.self, PlaybackState.self, DriveFolder.self, DriveTrack.self, JamendoTrack.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let library = LibraryService(context: ModelContext(container))
        let playback = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )

        let root = RootView()
            .environment(library)
            .environment(ImportService(library: library, metadataReader: MockMetadataReader()))
            .environment(playback)
            .environment(DriveLibraryService(library: library))
            .environment(JamendoLibraryService(library: library))
            .environment(LibraryStore())
            .environment(SearchResultsStore())
            .modelContainer(container)
            .environment(\._accessibilityReduceMotion, injected)

        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Put it away again. The action under test has already run by here, and
        // a visible window left standing outlives this test in a process that
        // runs 470-odd others.
        window.isHidden = true
    }

    /// Rendering `RootView` with Reduce Motion on must leave the flag on.
    ///
    /// The flag is seeded to the *opposite* value first, so the assertion
    /// cannot be satisfied by the default. This is the test that goes red if
    /// the `.onChange` is deleted from `RootView`, if it is flipped to
    /// `initial: false` — both leave the seeded `false` standing — or if the
    /// `@Environment` read is replaced by anything that does not track the
    /// setting.
    func testRenderingRootViewPublishesReduceMotionOn() throws {
        BottomBarStyle.reduceMotion = false

        try renderRootView(reduceMotion: true)

        XCTAssertTrue(
            BottomBarStyle.reduceMotion,
            "RootView rendered with Reduce Motion on but left BottomBarStyle.reduceMotion false"
        )
    }

    /// And the other direction, seeded the other way.
    ///
    /// On its own the test above would pass against a body that assigned `true`
    /// unconditionally. This one is what makes the pair say "publishes the
    /// setting" rather than "writes a constant".
    func testRenderingRootViewPublishesReduceMotionOff() throws {
        BottomBarStyle.reduceMotion = true

        try renderRootView(reduceMotion: false)

        XCTAssertFalse(
            BottomBarStyle.reduceMotion,
            "RootView rendered with Reduce Motion off but left BottomBarStyle.reduceMotion true"
        )
    }
}
