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
