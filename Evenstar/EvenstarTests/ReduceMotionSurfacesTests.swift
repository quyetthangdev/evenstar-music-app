import XCTest
import SwiftUI
@testable import Evenstar

/// **The four surfaces B4 changed, measured on the frames in between.**
///
/// `ReduceMotionTests` pins the constants. Nothing in that file can see the
/// thing this one is about: with Reduce Motion on, every surface here ends
/// exactly where it ended before — same selected tab, same button, same row —
/// and what changed is only what happened on the way. A test that renders a
/// final state cannot tell the two modes apart at all, and would be green
/// against a branch that was never written.
///
/// So the technique is different, and it is the one part of this file worth
/// reading before the tests. `ImageRenderer` — which
/// `ReduceMotionTests.isBlueAtTheUnrecededEdge(progress:)` uses — builds a fresh
/// render from the view *value*, so it always draws the destination. Instead
/// the view goes into a real `UIWindow`, the animation is started, the run loop
/// is let tick, and `CALayer.render(in:)` takes the pixels **as they stand at
/// that instant**. Sampling that a few dozen times over the length of an
/// animation gives a trace of what was actually on screen.
///
/// Every claim below is asserted in both directions, and the second direction
/// is not a formality: "nothing moved" is what a broken probe reports too. Each
/// pair is written so that a probe which had stopped seeing anything fails the
/// Reduce-Motion-off half.
@MainActor
private enum LivePixels {

    /// The top-left `size` of the hierarchy as it stands right now, one pixel
    /// per point, `[R, G, B, A]` per pixel.
    ///
    /// **`layoutIfNeeded()` first, and it is the whole reason this works.** In a
    /// unit-test process the window is not attached to a scene, so nothing
    /// drives a display pass: SwiftUI re-evaluates bodies and interpolates
    /// animations exactly as `SwiftUIAnimationTransactionEvidenceTests` records,
    /// but the CALayer tree is never brought up to date on its own. Measured
    /// while building this file — without the forced layout, a wash animated
    /// from one slot to the next left the blue layer at its *starting* frame for
    /// the entire run, and the trace came back as thirteen identical samples. It
    /// is not that the capture was stale; the layer had genuinely never moved.
    /// With the layout forced, the same trace reads 4…35, 4…36, 6…38, 10…41,
    /// 15…47, 22…54, 29…60, 35…67, 40…71, 43…74, 44…75.
    ///
    /// The flip is not cosmetic either. A bare `CGContext` has its origin at the
    /// bottom left and `CALayer.render(in:)` draws in the layer's own
    /// coordinates, so without it row 0 would be the bottom of the view.
    ///
    /// A context smaller than the view clips rather than scales, which is why
    /// every probe in this file is anchored at the top left: it keeps the grab
    /// to the few thousand pixels that are being asked about rather than the
    /// 390×844 the window has to be.
    static func grab(_ view: UIView, _ size: CGSize) -> (width: Int, height: Int, data: [UInt8])? {
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }

        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        view.layer.render(in: context)
        return (width, height, data)
    }

    /// Puts `view` on screen pinned to the top left of a phone-sized window.
    ///
    /// **The window has to be a plausible size**, which is not fussiness. A
    /// window sized to the probe itself still inherits the screen's safe-area
    /// insets, and SwiftUI lays the content out inside them: measured on a
    /// 60×40 window, a 20pt block that belongs at (20, 10) came out at (20, 44)
    /// — off the bottom of its own window, and every capture came back blank
    /// white. `ignoresSafeArea` plus a real window size puts the probe where the
    /// arithmetic in each test says it is.
    ///
    /// `isHidden = false` is load-bearing rather than tidy: SwiftUI does not
    /// drive an animation for a window nobody is showing, and every trace in
    /// this file would come back as samples of the destination.
    static func host<V: View>(_ view: V) -> (UIWindow, UIViewController) {
        let root = view
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
        let host = UIHostingController(rootView: root)
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return (window, host)
    }

    /// Lets the display link tick for `seconds`.
    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

// MARK: - Việc 1 — the tab bar's selection wash

/// **The wash must not cross the bar when motion is reduced.**
///
/// The claim is spatial, so the probe is spatial: find the column that lies in
/// the gap between two neighbouring slots' washes — a column no wash covers in
/// *either* resting state — and watch it for the whole length of a tab change.
/// A wash that slides from one slot to the next has to pass through it. A wash
/// that fades out where it is and fades in where it is never touches it.
///
/// The gap is measured rather than computed: the two resting renders are
/// differenced, which gives the two washes' extents without this file needing
/// to know `selectionInset`, the slot arithmetic, or how wide a label is.
@MainActor
final class TabSelectionWashTravelTests: XCTestCase {

    private enum Harness {
        @MainActor static var select: ((LibraryTab) -> Void)?
    }

    /// The production bar, with the one line of `FloatingTabBar.select(_:)` a
    /// test can reach restated: that method is private and needs a touch, and
    /// what it does is write the binding inside
    /// `withAnimation(BottomBarStyle.selection)`.
    private struct Bar: View {
        @State private var selection: LibraryTab = .songs
        @State private var isSearching = false
        @State private var query = ""
        @State private var isEditing = false
        @State private var isMinimised = false

        var body: some View {
            FloatingTabBar(
                selection: $selection,
                isSearching: $isSearching,
                query: $query,
                isEditing: $isEditing,
                isMinimised: $isMinimised,
                hasTrack: true,
                onOpenSearch: {},
                onCloseSearch: { _ in },
                onRestore: {}
            )
            .background(Color.white)
            .onAppear {
                Harness.select = { tab in
                    withAnimation(BottomBarStyle.selection) { selection = tab }
                }
            }
        }
    }

    /// 3pt into the wash, which is 5pt in from the top of a 54pt bar. Above the
    /// glyph-over-label stack, so no ink but the wash's own is ever sampled.
    private static let sampleRow = 8

    /// Long enough for a tab change to be **completely** finished.
    ///
    /// Measured rather than picked: 0.6s was not, and this test failed
    /// intermittently by up to 6/255 at a wash edge because of it.
    /// `BottomBarStyle.selection` is a 0.38s spring, and its own doc records it
    /// overshooting to 106.3% and taking a further third of a second to come
    /// back down — so a resting sample needs the far side of ~0.71s, not the
    /// near side of it.
    private static let settlingTime: TimeInterval = 1.0
    private static let barWidth: CGFloat = 390

    private var saved = false
    private var window: UIWindow?
    private var host: UIViewController?

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.select = nil
        super.tearDown()
    }

    private func mount(reduceMotion: Bool) {
        window?.isHidden = true
        BottomBarStyle.reduceMotion = reduceMotion
        Harness.select = nil
        let (window, host) = LivePixels.host(Bar())
        self.window = window
        self.host = host
    }

    /// Luminance along `sampleRow`, one entry per column.
    private func row() throws -> [Int] {
        let view = try XCTUnwrap(host?.view)
        let grab = try XCTUnwrap(
            LivePixels.grab(view, CGSize(width: Self.barWidth, height: BottomBarMetrics.tabBarHeight)),
            "CALayer.render produced nothing"
        )
        let start = Self.sampleRow * grab.width * 4
        return (0..<grab.width).map { column in
            let p = start + column * 4
            // Greyscale ink over a white ground, so any channel answers; the
            // green channel is the one `Color.primary` darkens most evenly.
            return Int(grab.data[p + 1])
        }
    }

    /// The column exactly between the Songs wash and the Albums wash.
    ///
    /// Found by differencing the two resting rows: a column belongs to one
    /// wash if it is materially darker in that state than in the other. The
    /// midpoint of the two runs is a column neither wash reaches, which is what
    /// makes "the wash was here" mean "the wash travelled".
    private func gapColumn() throws -> Int {
        let select = try XCTUnwrap(Harness.select)

        select(.songs)
        LivePixels.pump(Self.settlingTime)
        let songs = try row()

        select(.albums)
        LivePixels.pump(Self.settlingTime)
        let albums = try row()

        let onSongs = (0..<songs.count).filter { songs[$0] < albums[$0] - 5 }
        let onAlbums = (0..<songs.count).filter { albums[$0] < songs[$0] - 5 }

        let right = try XCTUnwrap(onSongs.max(), "no wash found under Songs")
        let left = try XCTUnwrap(onAlbums.min(), "no wash found under Albums")
        XCTAssertLessThan(right, left, "the two washes overlap; there is no gap to watch")
        return (right + left) / 2
    }

    /// Every luminance the gap column took while the selection moved from
    /// Songs to Albums, sampled every 10ms for 0.5s — longer than either
    /// mode's curve, overshoot included.
    private func gapDuringTabChange() throws -> (rest: Int, trace: [Int]) {
        let column = try gapColumn()
        let select = try XCTUnwrap(Harness.select)

        select(.songs)
        LivePixels.pump(Self.settlingTime)
        let rest = try row()[column]

        select(.albums)
        var trace: [Int] = []
        for _ in 0..<50 {
            LivePixels.pump(0.01)
            trace.append(try row()[column])
        }
        return (rest, trace)
    }

    /// **The one that fails if the wash still slides.** With the setting on,
    /// the gap between the two slots must stay exactly as bright as it is at
    /// rest, at every frame of the change.
    func testTheWashNeverCrossesTheGapBetweenTwoTabsWhenMotionIsReduced() throws {
        mount(reduceMotion: true)

        let (rest, trace) = try gapDuringTabChange()
        let darkest = try XCTUnwrap(trace.min())

        XCTAssertGreaterThan(
            darkest, rest - 5,
            "the wash darkened the gap to \(darkest) against a resting \(rest); trace \(trace)"
        )
    }

    /// **And with the setting off it does slide**, which is what says the probe
    /// can see a travelling wash at all. Without this half, a capture that had
    /// silently stopped working would report the feature as implemented.
    func testTheWashStillCrossesThatSameGapWithTheSettingOff() throws {
        mount(reduceMotion: false)

        let (rest, trace) = try gapDuringTabChange()
        let darkest = try XCTUnwrap(trace.min())

        XCTAssertLessThan(
            darkest, rest - 5,
            "the wash never reached the gap; trace \(trace) against a resting \(rest)"
        )
    }

    /// **The first tab change of a session that launched with the setting
    /// already on**, which is the one ordering the structural branch could get
    /// wrong.
    ///
    /// `RootView` publishes the flag from `.onChange(of:initial:true)`, and
    /// `SwiftUIOnChangeOrderingEvidenceTests` measures that SwiftUI runs that
    /// action *after* the first `body` of every view below it. So the bar's
    /// first evaluation reads `false` and builds the travelling structure, even
    /// for the user the setting is for. `BottomBarStyle.reduceMotion`'s doc
    /// calls that harmless, and its argument is about curves: `withAnimation`
    /// re-reads the constant when it fires. B4 put a *structure* behind the same
    /// flag, and that argument does not cover a structure — so it is measured
    /// rather than assumed.
    ///
    /// The sequence here is exactly the app's: build with the flag off, publish
    /// it, then change tab. The change is the first render that can see the new
    /// value, so it is both the switch of structure and the switch of selection
    /// in one transaction.
    func testTheFirstTabChangeAfterTheFlagArrivesDoesNotTravelEither() throws {
        mount(reduceMotion: false)

        let column = try gapColumn()
        let select = try XCTUnwrap(Harness.select)
        select(.songs)
        LivePixels.pump(Self.settlingTime)
        let rest = try row()[column]

        BottomBarStyle.reduceMotion = true
        select(.albums)

        var trace: [Int] = []
        for _ in 0..<50 {
            LivePixels.pump(0.01)
            trace.append(try row()[column])
        }
        let darkest = try XCTUnwrap(trace.min())

        XCTAssertGreaterThan(
            darkest, rest - 5,
            "the first change after the flag arrived still crossed the gap: \(darkest) against \(rest); trace \(trace)"
        )
    }

    /// The wash still says which tab is current in the reduced mode, and says
    /// it in exactly the same place, with exactly the same ink.
    ///
    /// This is the half that stops "does not travel" being satisfied by "is not
    /// drawn". Both modes are rendered at rest for each of the four tabs and
    /// compared column by column along the wash's own row.
    func testAtRestTheTwoModesAreIndistinguishable() throws {
        func restingRows() throws -> [[Int]] {
            let select = try XCTUnwrap(Harness.select)
            return try LibraryTab.pillTabs.map { tab in
                select(tab)
                LivePixels.pump(Self.settlingTime)
                return try row()
            }
        }

        mount(reduceMotion: false)
        let full = try restingRows()

        mount(reduceMotion: true)
        let reduced = try restingRows()

        for (index, tab) in LibraryTab.pillTabs.enumerated() {
            let difference = zip(full[index], reduced[index]).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThanOrEqual(
                difference, 2,
                "the bar looks different on \(tab.rawValue) with the setting on, by \(difference)"
            )
        }

        // The probe can tell two tabs apart — otherwise the comparison above is
        // a comparison of four identical blank rows.
        XCTAssertNotEqual(full[0], full[1])
    }
}

// MARK: - Việc 2 — the tap halo

/// **The halo does not bloom when motion is reduced.**
///
/// Sampled at the centre of the disc, which is inside it at every scale the
/// keyframes visit, so this is the most sensitive point there is: if any part
/// of the pulse runs, this sees it.
@MainActor
final class TapHaloReducedTests: XCTestCase {

    private enum Harness {
        @MainActor static var fire: (() -> Void)?
    }

    private struct Probe: View {
        @State private var trigger = 0

        var body: some View {
            Color.clear
                .frame(width: 40, height: 40)
                .tapHalo(trigger: trigger)
                .background(Color.white)
                .onAppear { Harness.fire = { trigger += 1 } }
        }
    }

    private var saved = false
    private var window: UIWindow?
    private var host: UIViewController?

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.fire = nil
        super.tearDown()
    }

    /// The darkest the centre of the disc ever got over the halo's full 0.52s
    /// of keyframes.
    private func darkestCentre(reduceMotion: Bool) throws -> Int {
        BottomBarStyle.reduceMotion = reduceMotion
        Harness.fire = nil
        let (window, host) = LivePixels.host(Probe())
        self.window = window
        self.host = host

        let fire = try XCTUnwrap(Harness.fire)
        fire()

        var darkest = 255
        for _ in 0..<60 {
            LivePixels.pump(0.01)
            let grab = try XCTUnwrap(
                LivePixels.grab(host.view, CGSize(width: 40, height: 40)),
                "CALayer.render produced nothing"
            )
            let p = (20 * grab.width + 20) * 4
            darkest = min(darkest, Int(grab.data[p + 1]))
        }
        return darkest
    }

    /// With the setting on, the ground under the button stays white for the
    /// whole length of the pulse the halo would have run.
    func testTheHaloNeverBloomsWhenMotionIsReduced() throws {
        XCTAssertGreaterThan(
            try darkestCentre(reduceMotion: true), 250,
            "something bloomed under the button with Reduce Motion on"
        )
    }

    /// And with it off the same probe sees it, which is what makes the
    /// assertion above mean anything.
    func testTheHaloStillBloomsWithTheSettingOff() throws {
        XCTAssertLessThan(
            try darkestCentre(reduceMotion: false), 250,
            "the halo did not bloom at all with Reduce Motion off"
        )
    }
}

// MARK: - Việc 3 — the two button styles

/// **The press constants, and the threshold they have to clear.**
@MainActor
final class PressFeedbackConstantsTests: XCTestCase {

    private var saved = false

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        super.tearDown()
    }

    /// Both press scales go to 1 — no deformation left anywhere — and the
    /// opacity that replaces them appears only in the reduced mode.
    func testThePressScalesFlattenAndTheDimAppears() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(BottomBarStyle.pressedScale, 0.96)
        XCTAssertEqual(QueueToggleStyle.pressedScale, 0.9)
        XCTAssertEqual(BottomBarStyle.pressedOpacity, 1)

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(BottomBarStyle.pressedScale, 1)
        XCTAssertEqual(QueueToggleStyle.pressedScale, 1)
        XCTAssertEqual(BottomBarStyle.pressedOpacity, 0.45)
    }

    /// **The threshold the brief names: a press must still show.**
    ///
    /// Stated against a number the bar already stakes a readability claim on
    /// rather than against a taste — `FloatingTabBar.tint(isCurrent:)`
    /// separates the current destination from the other three by 1.0 against
    /// 0.6 and nothing else. A momentary dim has to be at least that visible,
    /// and must stop short of the range that reads as disabled.
    func testTheReducedPressIsStillVisibleAndNotADisabledLook() {
        BottomBarStyle.reduceMotion = true

        XCTAssertLessThan(BottomBarStyle.pressedOpacity, 0.6)
        XCTAssertGreaterThan(BottomBarStyle.pressedOpacity, 0.35)
    }

    /// The transport kick's three tracks all lose their displacement together,
    /// and the dim arrives in the same value. Asserted on `kickPeak` because
    /// that is the only thing the keyframes read — there is no second copy of
    /// these numbers left in the file to disagree with it.
    func testTheTransportKickLosesEveryDisplacementAndGainsTheDim() {
        let skip: TransportButtonStyle = .transportSkip(trigger: 0, direction: 1)
        let toggle: TransportButtonStyle = .transportToggle(trigger: 0)

        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(skip.kickPeak.offset, 7)
        XCTAssertEqual(skip.kickPeak.scaleX, 1.12)
        XCTAssertEqual(skip.kickPeak.scaleY, 0.92)
        XCTAssertEqual(skip.kickPeak.opacity, 1)
        XCTAssertEqual(toggle.kickPeak.scaleX, 1.08)

        BottomBarStyle.reduceMotion = true
        for style in [skip, toggle] {
            XCTAssertEqual(style.kickPeak.offset, 0)
            XCTAssertEqual(style.kickPeak.scaleX, 1)
            XCTAssertEqual(style.kickPeak.scaleY, 1)
            // Against a literal as well as against the shared constant. The
            // second assertion alone survived a mutation that took
            // `pressedOpacityFlat` to 1 — both sides moved together and the
            // peak claimed a dim of exactly nothing. Caught by the pixel test
            // next door; pinned here so it does not need to be.
            XCTAssertLessThan(style.kickPeak.opacity, 0.6)
            XCTAssertEqual(style.kickPeak.opacity, BottomBarStyle.pressedOpacity)
        }
    }
}

/// **The kick, on the pixels.** The constants above say what the peak is; this
/// says the keyframes are aimed at it.
///
/// A 20pt blue block in a 60×40 white field, thrown right by 7 and stretched to
/// 1.12. At rest it spans 20…40; kicked it reaches past 48. Column 45 is
/// therefore a column only a *moving* button reaches, and the centre of the
/// block is where a dim shows up.
@MainActor
final class TransportKickPixelTests: XCTestCase {

    private enum Harness {
        @MainActor static var fire: (() -> Void)?
    }

    private struct Probe: View {
        @State private var trigger = 0

        var body: some View {
            Button {} label: {
                Color.blue.frame(width: 20, height: 20)
            }
            .buttonStyle(.transportSkip(trigger: trigger, direction: 1))
            .frame(width: 60, height: 40)
            .background(Color.white)
            .onAppear { Harness.fire = { trigger += 1 } }
        }
    }

    private var saved = false
    private var window: UIWindow?
    private var host: UIViewController?

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.fire = nil
        super.tearDown()
    }

    /// How blue a pixel is, 0 for white and 255 for solid blue.
    private func blueness(_ grab: (width: Int, height: Int, data: [UInt8]), x: Int, y: Int) -> Int {
        let p = (y * grab.width + x) * 4
        return Int(grab.data[p + 2]) - Int(grab.data[p])
    }

    /// The bluest column 45 ever got, and the least blue the block's own centre
    /// ever got, over the whole kick.
    private func trace(reduceMotion: Bool) throws -> (beyond: Int, centre: Int) {
        BottomBarStyle.reduceMotion = reduceMotion
        Harness.fire = nil
        let (window, host) = LivePixels.host(Probe())
        self.window = window
        self.host = host

        let fire = try XCTUnwrap(Harness.fire)
        fire()

        var beyond = 0
        var centre = 255
        for _ in 0..<40 {
            LivePixels.pump(0.01)
            let grab = try XCTUnwrap(
                LivePixels.grab(host.view, CGSize(width: 60, height: 40)),
                "CALayer.render produced nothing"
            )
            beyond = max(beyond, blueness(grab, x: 45, y: 20))
            centre = min(centre, blueness(grab, x: 30, y: 20))
        }
        return (beyond, centre)
    }

    /// Reduced: the button never reaches a column only a thrown button
    /// reaches, and it dims instead.
    func testTheKickNeitherTravelsNorStretchesWhenMotionIsReduced() throws {
        let (beyond, centre) = try trace(reduceMotion: true)

        XCTAssertLessThan(beyond, 20, "the button travelled: column 45 reached \(beyond)")
        XCTAssertLessThan(centre, 200, "the button did not dim at all; centre bottomed at \(centre)")
    }

    /// Full: it travels, and it does not dim. Together with the pair above this
    /// says the two modes swapped one for the other rather than one of them
    /// having quietly stopped doing anything.
    func testTheKickStillTravelsAndDoesNotDimWithTheSettingOff() throws {
        let (beyond, centre) = try trace(reduceMotion: false)

        XCTAssertGreaterThan(beyond, 20, "the button never travelled; column 45 peaked at \(beyond)")
        XCTAssertGreaterThan(centre, 200, "the button dimmed with Reduce Motion off; centre \(centre)")
    }
}

// MARK: - Việc 4 — the reorder settle

/// `ReorderTuning`'s two flat durations, re-derived from the springs they
/// replace rather than trusted from the comments that quote them.
///
/// Same method and same harness shape as `SpringSettlingEvidenceTests`, which
/// does this for `BottomBarStyle`'s seven: the flat duration is the moment its
/// own spring first crosses 98% of the target, sampled at 1ms and rounded to
/// the hundredth.
@MainActor
final class ReorderTuningFlatDurationTests: XCTestCase {

    private func samples(_ spring: Spring) -> [(t: Double, v: Double)] {
        stride(from: 0, through: 4, by: 0.001).map { time in
            (time, spring.value(target: 1.0, time: time))
        }
    }

    private func flatDuration(of spring: Spring) throws -> Double {
        let crossing = try XCTUnwrap(
            samples(spring).first { $0.v >= 0.98 }?.t,
            "the spring never reached 98%"
        )
        return (crossing * 100).rounded() / 100
    }

    /// 0.14 and 0.19 are measurements, not choices.
    func testBothFlatDurationsAreTheirSpringsFirstCrossingOf98Percent() throws {
        XCTAssertEqual(
            try flatDuration(of: Spring(response: 0.28, dampingRatio: 0.68)),
            0.14, accuracy: 1e-9
        )
        XCTAssertEqual(
            try flatDuration(of: ReorderTuning.settleSpring),
            0.19, accuracy: 1e-9
        )
    }

    /// And both springs really do overshoot, so there is a bounce to remove.
    /// If either stopped overshooting, flattening it would be taking away
    /// nothing and the doc comments would be describing a bounce that is not
    /// there.
    func testBothSpringsOvershootTheirTarget() {
        let part = samples(Spring(response: 0.28, dampingRatio: 0.68)).map(\.v).max() ?? 0
        let settle = samples(ReorderTuning.settleSpring).map(\.v).max() ?? 0

        XCTAssertEqual(part, 1.054, accuracy: 5e-4)
        XCTAssertEqual(settle, 1.025, accuracy: 5e-4)
    }
}

/// The reorder list's own two constants, and the release that used to carry the
/// finger's momentum.
@MainActor
final class ReorderReducedMotionTests: XCTestCase {

    private var saved = false

    override func setUp() {
        super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() {
        BottomBarStyle.reduceMotion = saved
        super.tearDown()
    }

    /// The rows making way keep their travel and lose their bounce.
    func testTheRowsMakingWayFlattenButKeepTheirTravel() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(ReorderTuning.part, .spring(response: 0.28, dampingFraction: 0.68))

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(ReorderTuning.part, .easeInOut(duration: 0.14))
        XCTAssertNotEqual(ReorderTuning.part, .spring(response: 0.28, dampingFraction: 0.68))
    }

    /// The touch background is deliberately untouched: it is an opacity going
    /// from 0 to 0.4, with no displacement in it to remove. If a later change
    /// gives it a reduced variant, this failing is the correct outcome.
    func testThePressBackgroundIsDeliberatelyUnchanged() {
        BottomBarStyle.reduceMotion = false
        let full = ReorderTuning.press
        BottomBarStyle.reduceMotion = true

        XCTAssertEqual(ReorderTuning.press, full)
        XCTAssertEqual(ReorderTuning.press, .easeOut(duration: 0.14))
    }

    /// **The release drops the velocity entirely**, the same trade
    /// `BottomBarStyle.settle(initialVelocity:)` makes: a hand-off of momentum
    /// is the sensation being removed, so a violent flick and a gentle release
    /// have to produce the identical animation.
    func testTheReleaseIgnoresBothItsDistanceAndItsVelocityWhenMotionIsReduced() {
        BottomBarStyle.reduceMotion = true

        let cases: [(CGFloat, CGFloat)] = [
            (0, 0), (0.2, 0), (54, 0), (54, 900), (-54, -2400), (300, 4000), (0.1, 4000),
        ]
        for (distance, velocity) in cases {
            XCTAssertEqual(
                ReorderModel.settleAnimation(distance: distance, velocity: velocity),
                ReorderTuning.settleFlat,
                "distance \(distance), velocity \(velocity) got its own curve"
            )
        }
        XCTAssertEqual(ReorderTuning.settleFlat, .easeInOut(duration: 0.19))
    }

    /// And with the setting off it still carries the momentum, clamp and all.
    /// Without this the assertions above would pass against a release that had
    /// stopped answering the finger for everyone.
    func testTheReleaseStillCarriesItsVelocityWithTheSettingOff() {
        BottomBarStyle.reduceMotion = false

        let gentle = ReorderModel.settleAnimation(distance: 54, velocity: 54)
        let violent = ReorderModel.settleAnimation(distance: 54, velocity: 5400)

        XCTAssertNotEqual(gentle, violent)
        XCTAssertEqual(
            gentle,
            .interpolatingSpring(ReorderTuning.settleSpring, initialVelocity: 1)
        )
        // The clamp, which is what stops a flick released a few points from its
        // destination from shooting past it.
        XCTAssertEqual(
            violent,
            .interpolatingSpring(ReorderTuning.settleSpring, initialVelocity: 14)
        )
        // A move too small to see keeps the plain spring, no velocity at all.
        XCTAssertEqual(
            ReorderModel.settleAnimation(distance: 0.4, velocity: 5400),
            .spring(ReorderTuning.settleSpring)
        )
    }

    /// **The drag itself must not change**, which is the same boundary
    /// `PlayerCard` drew: a row following the finger is direct manipulation,
    /// not an animation, and taking it away would leave the user unable to
    /// reorder anything. `offset(at:)` is the whole of what the finger drives,
    /// and it has to give the same answers in both modes.
    func testTheDragArithmeticIgnoresReduceMotion() {
        func answers() -> [CGFloat] {
            let model = ReorderModel()
            model.slot = 54
            model.adopt((0..<4).map { _ in UUID() })
            // Lift the first row and drag it 120pt down — two slots and a bit,
            // so the rounding at the midpoint is exercised rather than skirted.
            model.liftBegan(atY: 27)
            model.liftMoved(toY: 147)
            return (0..<4).map { model.offset(at: $0) }
                + [model.dragOffset, CGFloat(model.targetIndex), CGFloat(model.sourceIndex)]
        }

        BottomBarStyle.reduceMotion = false
        let full = answers()

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(full, answers())
    }
}
