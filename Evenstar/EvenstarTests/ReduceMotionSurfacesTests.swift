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

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.fire = nil
        try await super.tearDown()
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

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        try await super.tearDown()
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
    /// rather than against a taste — the old tab bar's tint
    /// separated the current destination from the others by 1.0 against 0.6
    /// and nothing else. A momentary dim has to be at least that visible,
    /// and must stop short of the range that reads as disabled.
    func testTheReducedPressIsStillVisibleAndNotADisabledLook() {
        BottomBarStyle.reduceMotion = true

        XCTAssertLessThan(BottomBarStyle.pressedOpacity, 0.6)
        XCTAssertGreaterThan(BottomBarStyle.pressedOpacity, 0.35)
    }

    /// The transport kick's three tracks all lose their displacement together.
    /// Asserted on `kickPeak` because that is the only thing the keyframes read
    /// — there is no second copy of these numbers left in the file to disagree
    /// with it.
    ///
    /// **The dim is deliberately not asserted here any more.** It used to be a
    /// fourth field on `Kick`, and a review round found that fatal rather than
    /// untidy: every track of that animator fires on `trigger`, the completed
    /// command, so the dim arrived after the finger had left and not at all for
    /// a press dragged off the button. It lives on `isPressed` now, and
    /// `TransportPressDimTests` below is what pins it.
    func testTheTransportKickLosesEveryDisplacement() {
        let skip: TransportButtonStyle = .transportSkip(trigger: 0, direction: 1)
        let toggle: TransportButtonStyle = .transportToggle(trigger: 0)

        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(skip.kickPeak.offset, 7)
        XCTAssertEqual(skip.kickPeak.scaleX, 1.12)
        XCTAssertEqual(skip.kickPeak.scaleY, 0.92)
        XCTAssertEqual(toggle.kickPeak.scaleX, 1.08)

        BottomBarStyle.reduceMotion = true
        for style in [skip, toggle] {
            XCTAssertEqual(style.kickPeak.offset, 0)
            XCTAssertEqual(style.kickPeak.scaleX, 1)
            XCTAssertEqual(style.kickPeak.scaleY, 1)
        }
    }
}

/// **The dim that answers the finger, on the pixels, with no command ever
/// sent.**
///
/// This is the case the shipped version got wrong and nothing could see: the
/// press is held and `trigger` never changes, which is a finger resting on the
/// button, and — if it is lifted somewhere else — a press dragged off it. The
/// halo is switched off in this mode and the kick only fires on the command, so
/// if the dim is not on `isPressed` there is nothing on screen at all.
///
/// It renders `TransportButtonStyle.Interaction` directly rather than a
/// `Button`. `ButtonStyleConfiguration` cannot be constructed and a real button
/// cannot be held pressed from a unit-test process, so the style's pressed frame
/// is unreachable any other way — which is why that type is internal and takes a
/// plain `Bool`.
@MainActor
final class TransportPressDimTests: XCTestCase {

    private enum Harness {
        @MainActor static var press: ((Bool) -> Void)?
    }

    private struct Probe: View {
        @State private var pressed = false

        var body: some View {
            // `trigger: 0`, and it never changes for the life of the probe.
            // Everything this test sees therefore came from `isPressed`.
            TransportButtonStyle.Interaction(
                label: Color.blue.frame(width: 20, height: 20),
                isPressedFromButton: pressed,
                style: .transportSkip(trigger: 0, direction: 1)
            )
            .frame(width: 60, height: 40)
            .background(Color.white)
            .onAppear { Harness.press = { pressed = $0 } }
        }
    }

    private var saved = false
    private var window: UIWindow?
    private var host: UIViewController?

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.press = nil
        try await super.tearDown()
    }

    /// How blue the block's centre is, 0 for white and 255 for solid blue.
    private func centre() throws -> Int {
        let view = try XCTUnwrap(host?.view)
        let grab = try XCTUnwrap(
            LivePixels.grab(view, CGSize(width: 60, height: 40)),
            "CALayer.render produced nothing"
        )
        let p = (20 * grab.width + 30) * 4
        return Int(grab.data[p + 2]) - Int(grab.data[p])
    }

    /// Holds the button down for `0.4s`, then lets go for another `0.4s`, and
    /// reports how blue the centre got at its extremes in each half.
    private func trace(reduceMotion: Bool) throws -> (held: Int, released: Int) {
        BottomBarStyle.reduceMotion = reduceMotion
        Harness.press = nil
        let (window, host) = LivePixels.host(Probe())
        self.window = window
        self.host = host

        let press = try XCTUnwrap(Harness.press)

        press(true)
        var held = 255
        for _ in 0..<40 {
            LivePixels.pump(0.01)
            held = min(held, try centre())
        }

        press(false)
        var released = 0
        for _ in 0..<40 {
            LivePixels.pump(0.01)
            released = max(released, try centre())
        }
        return (held, released)
    }

    /// **Reduced: contact dims the glyph, and letting go restores it.**
    ///
    /// A solid 20pt blue block reads 255; at `pressedOpacity`'s 0.45 over white
    /// it reads about 115. 200 sits between the two with room on either side and
    /// is the same threshold `TransportKickPixelTests` uses.
    func testAHeldPressDimsTheGlyphWithNoCommandSentWhenMotionIsReduced() throws {
        let (held, released) = try trace(reduceMotion: true)

        XCTAssertLessThan(held, 200, "a held press drew no dim at all; centre bottomed at \(held)")
        XCTAssertGreaterThan(released, 200, "the dim never came back after release; centre peaked at \(released)")
    }

    /// **Full: the same press changes nothing**, because `pressedOpacity` is 1
    /// there and the kick is still the answer. Without this half, a dim that had
    /// leaked into the unreduced mode — which would change how the app looks for
    /// everyone — would go unnoticed.
    func testTheSamePressDoesNotDimWithTheSettingOff() throws {
        let (held, released) = try trace(reduceMotion: false)

        XCTAssertGreaterThan(held, 200, "the glyph dimmed with Reduce Motion off; centre bottomed at \(held)")
        XCTAssertGreaterThan(released, 200, "the glyph never returned to full strength; centre peaked at \(released)")
    }
}

/// **The play/pause glyph swaps without changing size when motion is reduced.**
///
/// This is the hole `symbolReplace()` closes, on the pixels, in the control it
/// mattered most for. With the setting on, tapping play/pause used to scale the
/// glyph down to about half its height and scale the replacement back up — a
/// scale animation on the app's most-tapped button, under the setting whose
/// whole purpose is removing them.
///
/// **A version of this class was written and deleted a round earlier, and the
/// reason it was deleted was wrong.** The justification was that no edit to
/// `TransportButtonStyle` could make it red — true, and generalised to "no edit
/// anywhere", which was not. Swapping the transition is such an edit, and it is
/// the one that fixes the thing. The test earns its place now: take the branch
/// out of `symbolReplace()` and the first of these two goes red.
///
/// The measurement is the glyph's row span. Ink cannot be used — a press fires
/// `TapHalo` with the setting off and the dim takes ink away with it on —
/// and neither moves where the glyph's edges are.
@MainActor
final class TransportSymbolSwapTests: XCTestCase {

    private enum Harness {
        @MainActor static var flip: (() -> Void)?
        /// Lifts the finger. See `tap(reduceMotion:)` for why the anchor needs
        /// this and never worked without it.
        @MainActor static var release: (() -> Void)?
    }

    /// The label exactly as `MiniPlayerChrome` writes it, rendered through the
    /// style that wraps it, with the press flipping in the same transaction the
    /// symbol does — which is what a real tap does.
    private struct Probe: View {
        @State private var playing = false
        @State private var pressed = false

        var body: some View {
            TransportButtonStyle.Interaction(
                label: Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .symbolReplace()
                    .frame(width: 32, height: 32),
                isPressedFromButton: pressed,
                style: .transportToggle(trigger: 0)
            )
            .frame(width: 60, height: 60)
            .background(Color.white)
            .onAppear {
                Harness.flip = {
                    playing.toggle()
                    pressed = true
                }
                Harness.release = { pressed = false }
            }
        }
    }

    private var saved = false
    private var window: UIWindow?
    private var host: UIViewController?

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.flip = nil
        Harness.release = nil
        try await super.tearDown()
    }

    /// Row span of the drawn glyph, and how much ink it is made of. The second
    /// is only used to say the glyph *changed*.
    private func shape() throws -> (span: Int, ink: Int) {
        let view = try XCTUnwrap(host?.view)
        let grab = try XCTUnwrap(
            LivePixels.grab(view, CGSize(width: 60, height: 60)),
            "CALayer.render produced nothing"
        )
        var top = Int.max
        var bottom = -1
        var ink = 0
        for row in 0..<grab.height {
            for column in 0..<grab.width {
                let value = Int(grab.data[(row * grab.width + column) * 4 + 1])
                ink += 255 - value
                if value < 200 {
                    top = min(top, row)
                    bottom = max(bottom, row)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(bottom, 0, "no glyph was drawn at all")
        return (bottom - top, ink)
    }

    private func tap(reduceMotion: Bool) throws -> (rest: Int, trough: Int, changed: Bool) {
        window?.isHidden = true
        BottomBarStyle.reduceMotion = reduceMotion
        Harness.flip = nil
        Harness.release = nil
        let (window, host) = LivePixels.host(Probe())
        self.window = window
        self.host = host

        LivePixels.pump(0.5)
        let before = try shape()

        let flip = try XCTUnwrap(Harness.flip)
        flip()
        var spans: [Int] = []
        for _ in 0..<40 {
            LivePixels.pump(0.01)
            spans.append(try shape().span)
        }

        // **The finger comes off before `after` is read, and the anchor below
        // is worthless without it.**
        //
        // `flip()` does two things, because a real tap does two things: it
        // swaps the symbol *and* holds the button down. Holding it down is what
        // the span measurement above needs — the scale it is watching for
        // happens under the finger.
        //
        // But `after` was being read with the finger still down, and in the
        // reduced mode a held press is `pressedOpacity` = 0.45 over the whole
        // glyph. That dim alone moves ink by far more than the 5% the anchor
        // asks for, so the anchor answered "yes, it changed" whether or not any
        // symbol had swapped. Proven, not suspected: deleting `playing.toggle()`
        // from the harness — so no swap happens anywhere — left the reduced test
        // **green**. The guard written to catch a harness that had stopped
        // flipping anything was the one thing in the class that could not catch
        // it.
        //
        // Released and settled, both readings are the same button in the same
        // resting state, and the only thing left that can move ink is which
        // glyph is drawn.
        try XCTUnwrap(Harness.release)()
        LivePixels.pump(0.6)
        let after = try shape()

        // "The glyph changed" is measured against a `pause.fill` being visibly
        // more ink than a `play.fill` — 15% more, measured. This is the anchor:
        // a harness that had stopped flipping anything would satisfy every
        // other assertion in this class trivially.
        let changed = abs(after.ink - before.ink) > before.ink / 20
        return (before.span, try XCTUnwrap(spans.min()), changed)
    }

    /// **Reduced: the glyph never changes size**, and it still becomes the other
    /// glyph.
    func testTheGlyphSwapsWithoutScalingWhenMotionIsReduced() throws {
        let (rest, trough, changed) = try tap(reduceMotion: true)

        XCTAssertTrue(changed, "the symbol never actually swapped")
        XCTAssertEqual(
            trough, rest,
            "the glyph still scaled: \(trough) rows at its smallest against \(rest) at rest"
        )
    }

    /// **Full: it still scales, exactly as it always has.** The mode that was to
    /// stay untouched, and the half that says the probe can see a scaling glyph
    /// at all.
    func testTheGlyphStillScalesWithTheSettingOff() throws {
        let (rest, trough, changed) = try tap(reduceMotion: false)

        XCTAssertTrue(changed, "the symbol never actually swapped")
        XCTAssertLessThanOrEqual(
            trough, rest - 4,
            "the replace effect stopped scaling with Reduce Motion off: \(trough) against \(rest)"
        )
    }
}

/// **Every symbol swap in the app goes through `symbolReplace()`.**
///
/// One mechanism is only one mechanism while nothing bypasses it, and a bypass
/// is invisible: a bare `.contentTransition(.symbolEffect(.replace))` compiles,
/// looks ordinary, and reintroduces the scale on one control. **Five production
/// sites in five files, plus two in the one demo file** — seven sites across six
/// files — were converted; this is what stops the eighth from being written.
///
/// It reads the source rather than the running app, which is unusual here and is
/// the point — the claim is about code that exists, not about one view's pixels.
///
/// **Reading it with `contains(".contentTransition(.symbolEffect(")` was not
/// enough, and the ways it was not enough are all ordinary.** Each of these
/// compiles, reintroduces the scale, and got past that check:
///
/// ```swift
/// .contentTransition(
///     .symbolEffect(.replace)
/// )
/// .contentTransition( .symbolEffect(.replace) )
/// .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
/// ```
///
/// The third is the worst of the three and the likeliest to be written: it is
/// the per-site duplicated branch `symbolReplace()` exists to prevent, and it is
/// **the exact form `symbolReplace()` itself is written in** at
/// `BottomBarStyle.swift`, so it is what copy-pasting the helper's own body
/// produces.
///
/// So the check balances parentheses instead of matching a spelling: any
/// `.contentTransition(…)` whose argument mentions `symbolEffect` anywhere is an
/// offender, however it is laid out. `symbolReplace()`'s own body is spelled
/// `contentTransition(` with no leading dot — it is a method on `View`, called
/// on `self` — so the one file allowed to write this call still does not report
/// itself, and it is not excluded by name.
@MainActor
final class SymbolReplaceCoverageTests: XCTestCase {

    /// True when `code` contains a `.contentTransition(…)` whose argument
    /// mentions `symbolEffect`.
    ///
    /// A paren balance rather than a regex: the argument can itself contain
    /// parentheses (`.symbolEffect(.replace)` has two levels, and a ternary adds
    /// no closing bracket to anchor on), and a regex that handles one nesting
    /// depth is a regex that a second one gets past — which is the whole reason
    /// this function exists at all.
    ///
    /// It answers about the *argument*, not the whole line, so a `symbolEffect`
    /// used as a plain `.symbolEffect(.bounce)` modifier somewhere else on the
    /// same chain is not swept up. That modifier is a different thing: it plays
    /// an effect on a symbol that is not changing, and nothing in this branch
    /// touches it.
    private func callsReplaceTransitionDirectly(_ code: String) -> Bool {
        var search = code.startIndex
        while let hit = code.range(of: ".contentTransition", range: search..<code.endIndex) {
            search = hit.upperBound

            // Swift lets a space sit between the name and its `(`, and that
            // spelling was one of the ones that got through before.
            var open = hit.upperBound
            while open < code.endIndex, code[open].isWhitespace {
                open = code.index(after: open)
            }
            guard open < code.endIndex, code[open] == "(" else { continue }

            var depth = 0
            var argument = ""
            var i = open
            while i < code.endIndex {
                let character = code[i]
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                argument.append(character)
                i = code.index(after: i)
            }

            if argument.contains("symbolEffect") { return true }
        }
        return false
    }

    /// **The detector can fail.**
    ///
    /// Without this the walk below is a walk with no detector in it, and it
    /// passes for exactly the reason the old `contains` check passed: nothing
    /// it looks for is ever there. The four positives are the four real
    /// spellings that got past that check; the two negatives are the two shapes
    /// that must keep not tripping it, one of them `symbolReplace()`'s own body.
    func testTheBypassDetectorCatchesEverySpellingThatCompiles() {
        let bypasses = [
            ".contentTransition(.symbolEffect(.replace))",
            ".contentTransition(\n    .symbolEffect(.replace)\n)",
            ".contentTransition( .symbolEffect(.replace) )",
            ".contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))"
        ]
        for bypass in bypasses {
            XCTAssertTrue(
                callsReplaceTransitionDirectly(bypass),
                "this bypass compiles and would go unseen:\n\(bypass)"
            )
        }

        XCTAssertFalse(
            callsReplaceTransitionDirectly(
                "contentTransition(BottomBarStyle.reduceMotion ? .opacity : .symbolEffect(.replace))"
            ),
            "symbolReplace()'s own body must not report itself"
        )
        XCTAssertFalse(
            callsReplaceTransitionDirectly(".contentTransition(.numericText()).symbolEffect(.bounce)"),
            "a content transition that is not the symbol one, next to an unrelated symbol effect"
        )
    }

    func testNoProductionSiteCallsTheReplaceTransitionDirectly() throws {
        // …/Evenstar/EvenstarTests/ThisFile.swift → …/Evenstar/Evenstar
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Evenstar")

        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil),
            "could not walk \(app.path)"
        )
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }

        // The walk found the app at all. Without this the loop below is a loop
        // over nothing and passes for the wrong reason.
        XCTAssertGreaterThan(files.count, 20, "only found \(files.count) source files under \(app.path)")

        var offenders: [String] = []
        var adopters = 0
        for file in files {
            // Comment lines are dropped first, and that is not tidiness: the
            // helper's own doc quotes the call it replaces, and `BottomBarStyle`
            // would otherwise report itself. Excluding the file instead would
            // leave the one file that *can* write this call unwatched.
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")

            if callsReplaceTransitionDirectly(code) {
                offenders.append(file.lastPathComponent)
            }
            if code.contains(".symbolReplace()") { adopters += 1 }
        }

        XCTAssertEqual(offenders, [], "these call the replace transition directly instead of symbolReplace()")
        // The helper is actually in use, so "no offenders" cannot be satisfied
        // by there being no symbol swaps left in the app.
        //
        // Five *files*, not five sites: four production files and the demo
        // file (which has two calls). `adopters` counts files, because a file
        // that stopped calling the helper is the shape of regression this is
        // watching for. Was six until `FloatingTabBar`, an adopter, was deleted.
        XCTAssertGreaterThanOrEqual(adopters, 5, "only \(adopters) files call symbolReplace()")
    }
}

/// **A `.symbolEffect(.replace)` content transition does not read the
/// transaction it happens in.** SF Symbols times it; nothing around it can.
///
/// Evidence, in the shape of `SwiftUIAnimationTransactionEvidenceTests` and for
/// the same reason: a production decision rests on this, and reasoning about it
/// was not good enough. `TransportButtonStyle.Interaction` applies
/// `.animation(_:value: isPressed)` over the whole label, and one caller's label
/// is `Image(systemName: isPlaying ? …)` carrying that effect, with `isPlaying`
/// flipping in the same touch-down transaction. If an ancestor's animation
/// reached the effect, the unreduced mode would stop being identical to what
/// shipped, and Reduce Motion would gain a scale-based symbol effect through the
/// change meant to remove scale.
///
/// **Not a test of Evenstar's code.** It is the platform assumption `symbolReplace()`
/// and the note at `TransportButtonStyle`'s `.animation` both rest on. If a
/// future iOS lets the surrounding transaction drive the effect, this fails and
/// those two stop being true on the same day.
///
/// **Two claims, and an earlier version of this file only had the first — then
/// stated it as if it were both.** The curve cannot reach the effect; the
/// off-switch can. Writing "no ancestor reaches it" was wrong, and it was wrong
/// in the direction that mattered, because `disablesAnimations` reaching it is
/// what makes the scale closable at all.
///
/// Five runs of one swap. The measurement is the glyph's row span, which the
/// effect collapses to about half and restores — 15 rows at rest, 7 at the
/// trough, on frame 20-21 of a 10ms sampling:
///
///   - `bare` — nothing around it.
///   - `withAnimation` — a 1.2s `withAnimation` around the state change.
///   - `ancestorTransaction` — a 1.2s `.transaction` above the image.
///   - `disabled` — `.transaction { $0.disablesAnimations = true }` above it.
///   - `opacityTransition` — `.contentTransition(.opacity)`, which is the
///     branch `symbolReplace()` takes when motion is reduced.
///
/// The first three have to agree: a 1.2s retiming would put the trough past
/// frame 60. The last two have to *not* collapse at all — span 15 throughout —
/// which is the half that says the fix has something to act on.
///
/// ─────────────────────────────────────────────────────────────────────────
/// THE ±3 FRAME BUDGET IS KNOWN-TIGHT. READ THIS BEFORE TRUSTING A GREEN RUN.
/// ─────────────────────────────────────────────────────────────────────────
/// The comparison is index-based: it asks which *sample* the trough landed on,
/// and allows the five runs to differ by ±3. That budget is **one sample above
/// the drift this harness shows on its own** — trough index moves by as much as
/// 2 across same-configuration runs on the same machine, with nothing changed
/// between them. So ±3 leaves roughly one sample of headroom, which at 10ms
/// sampling means a real retiming of ±30–36ms could pass here unremarked.
///
/// That matters more than a loose budget usually would, because this class is
/// the **sole** evidence for a claim quoted in three production comments —
/// `BottomBarStyle.symbolReplace()`, `TransportButtonStyle.Interaction.body`,
/// and `TransportSymbolSwapTests` — all of which say, on this test's authority,
/// that an ancestor's animation cannot reach a symbol replace transition. A
/// green run here is good evidence that the effect is not being retimed by
/// *seconds*, which is what the 1.2s drives are testing and what the claim
/// actually rests on. It is weak evidence about tens of milliseconds.
///
/// Left as it is, deliberately, and this note is the alternative to a bad fix.
/// Tightening the budget makes the class flaky; the real repair is to stop
/// comparing sample indices and compare elapsed *time* to the trough, measured
/// against a clock rather than against a pump count — which is a rewrite of the
/// harness, not a number change, and belongs to its own round. Until then:
/// treat a green run as ruling out a large retiming, not a small one.
@MainActor
final class SymbolReplaceTransactionEvidenceTests: XCTestCase {

    enum Drive { case bare, withAnimation, ancestorTransaction, disabled, opacityTransition }

    private enum Harness {
        @MainActor static var flip: (() -> Void)?
    }

    /// The label exactly as `MiniPlayerChrome` and `NowPlayingContent` write it,
    /// with no button style anywhere near it — the claim is about the effect,
    /// not about Evenstar.
    private struct Probe: View {
        @State private var playing = false
        let drive: Drive

        var body: some View {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.title3)
                .contentTransition(
                    drive == .opacityTransition ? .opacity : .symbolEffect(.replace)
                )
                .frame(width: 32, height: 32)
                .modifier(Ancestor(drive: drive))
                .frame(width: 60, height: 60)
                .background(Color.white)
                .onAppear {
                    Harness.flip = {
                        if drive == .withAnimation {
                            SwiftUI.withAnimation(.easeInOut(duration: 1.2)) { playing.toggle() }
                        } else {
                            playing.toggle()
                        }
                    }
                }
        }
    }

    /// A separate modifier because `.transaction` has to be *above* the image in
    /// the chain to stand for the real arrangement, where the animation is
    /// applied by a button style wrapping a label it did not write.
    private struct Ancestor: ViewModifier {
        let drive: Drive

        @ViewBuilder
        func body(content: Content) -> some View {
            switch drive {
            case .ancestorTransaction:
                content.transaction { $0.animation = .easeInOut(duration: 1.2) }
            case .disabled:
                content.transaction { $0.disablesAnimations = true }
            default:
                content
            }
        }
    }

    private var window: UIWindow?
    private var host: UIViewController?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        host = nil
        Harness.flip = nil
        try await super.tearDown()
    }

    private func rowSpan() throws -> Int {
        let view = try XCTUnwrap(host?.view)
        let grab = try XCTUnwrap(
            LivePixels.grab(view, CGSize(width: 60, height: 60)),
            "CALayer.render produced nothing"
        )
        var top = Int.max
        var bottom = -1
        for row in 0..<grab.height {
            for column in 0..<grab.width
            where Int(grab.data[(row * grab.width + column) * 4 + 1]) < 200 {
                top = min(top, row)
                bottom = max(bottom, row)
                break
            }
        }
        XCTAssertGreaterThanOrEqual(bottom, 0, "no glyph was drawn at all")
        return bottom - top
    }

    /// 70 frames — long enough that a 1.2s retiming would still be on its way
    /// down at the end.
    private func swap(_ drive: Drive) throws -> (rest: Int, trough: Int, frame: Int) {
        window?.isHidden = true
        Harness.flip = nil
        let (window, host) = LivePixels.host(Probe(drive: drive))
        self.window = window
        self.host = host

        LivePixels.pump(0.5)
        let rest = try rowSpan()

        let flip = try XCTUnwrap(Harness.flip)
        flip()
        var spans: [Int] = []
        for _ in 0..<70 {
            LivePixels.pump(0.01)
            spans.append(try rowSpan())
        }
        let trough = try XCTUnwrap(spans.min())
        return (rest, trough, try XCTUnwrap(spans.firstIndex(of: trough)))
    }

    /// **The curve cannot reach it.**
    func testTheReplaceEffectIgnoresBothWithAnimationAndAnAncestorTransaction() throws {
        let bare = try swap(.bare)
        let animated = try swap(.withAnimation)
        let transacted = try swap(.ancestorTransaction)

        // It runs at all, and it is a *collapse* — otherwise the comparisons
        // below are readings of a glyph that never moved. A range rather than
        // `== 15`: the rest height is a `.title3` glyph rendered by SF Symbols,
        // and neither is this file's to promise. What matters is that it is a
        // couple of dozen rows and that the effect halves it.
        XCTAssertTrue((10...24).contains(bare.rest), "unexpected resting height \(bare.rest)")
        XCTAssertGreaterThanOrEqual(bare.rest - bare.trough, 4, "the symbol never collapsed")

        for (name, other) in [("withAnimation", animated), ("ancestorTransaction", transacted)] {
            XCTAssertLessThanOrEqual(
                abs(bare.trough - other.trough), 1,
                "\(name) changed how far the symbol collapsed: \(other.trough) against \(bare.trough)"
            )
            XCTAssertLessThanOrEqual(
                abs(bare.frame - other.frame), 3,
                "\(name) retimed the effect: bottomed out on frame \(other.frame) against \(bare.frame)"
            )
        }
    }

    /// **The off-switch can, and so can replacing the transition** — the two
    /// routes to taking the scale out, and the half the first version of this
    /// class was missing.
    ///
    /// `symbolReplace()` takes the second. The first is recorded because it is
    /// the reason the absolute in the old comment was wrong, and because it is
    /// the fallback if a transition ever has to stay `.symbolEffect`.
    func testTheEffectIsSuppressedByDisablingAnimationsAndByAnOpacityTransition() throws {
        let bare = try swap(.bare)
        let disabled = try swap(.disabled)
        let opacity = try swap(.opacityTransition)

        XCTAssertGreaterThanOrEqual(
            bare.rest - bare.trough, 4,
            "the symbol never collapsed even bare; there is nothing to suppress"
        )

        for (name, other) in [("disablesAnimations", disabled), ("opacity transition", opacity)] {
            XCTAssertEqual(
                other.trough, other.rest,
                "\(name) still collapsed the glyph, to \(other.trough) from \(other.rest)"
            )
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

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.fire = nil
        try await super.tearDown()
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

    /// Reduced: the button never reaches a column only a thrown button reaches.
    ///
    /// **And it does not dim either, which is the assertion this pair gained
    /// rather than lost.** `fire()` moves `trigger` and nothing else — no finger
    /// is on the button — so this is the command arriving on its own. A dim here
    /// would mean the acknowledgement was back on the completed tap, which is
    /// exactly the defect `TransportPressDimTests` was written for.
    func testTheKickNeitherTravelsNorDimsOnTheCommandWhenMotionIsReduced() throws {
        let (beyond, centre) = try trace(reduceMotion: true)

        XCTAssertLessThan(beyond, 20, "the button travelled: column 45 reached \(beyond)")
        XCTAssertGreaterThan(centre, 200, "the command dimmed the glyph on its own; centre bottomed at \(centre)")
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
    ///
    /// **Both sides come from production now.** `ReorderTuning.partSpring` used
    /// to be private and the spring was re-typed here as a literal, so this half
    /// asserted a property of a spring *this file* had built: changing
    /// `partFull` could not make it red. The spring is `internal` for exactly
    /// this — see its own note in `ReorderableStack.swift`.
    ///
    /// The flat durations are pinned to literals separately below. Comparing two
    /// production values to each other says they agree; only the literal says
    /// which number they agree on.
    func testBothFlatDurationsAreTheirSpringsFirstCrossingOf98Percent() throws {
        XCTAssertEqual(
            try flatDuration(of: ReorderTuning.partSpring),
            ReorderTuning.partFlatDuration, accuracy: 1e-9
        )
        XCTAssertEqual(
            try flatDuration(of: ReorderTuning.settleSpring),
            ReorderTuning.settleFlatDuration, accuracy: 1e-9
        )

        XCTAssertEqual(ReorderTuning.partFlatDuration, 0.14, accuracy: 1e-9)
        XCTAssertEqual(ReorderTuning.settleFlatDuration, 0.19, accuracy: 1e-9)
    }

    /// And both springs really do overshoot, so there is a bounce to remove.
    /// If either stopped overshooting, flattening it would be taking away
    /// nothing and the doc comments would be describing a bounce that is not
    /// there.
    func testBothSpringsOvershootTheirTarget() {
        let part = samples(ReorderTuning.partSpring).map(\.v).max() ?? 0
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

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        try await super.tearDown()
    }

    /// The rows making way keep their travel and lose their bounce.
    ///
    /// The literals stay literals here, and they are the only place the two
    /// numbers appear outside production: `ReorderTuningFlatDurationTests` now
    /// samples `ReorderTuning.partSpring` rather than a spring of its own, so
    /// without this pin nothing would say *which* spring both sides agree on.
    func testTheRowsMakingWayFlattenButKeepTheirTravel() {
        XCTAssertEqual(ReorderTuning.partResponse, 0.28, accuracy: 1e-9)
        XCTAssertEqual(ReorderTuning.partDampingRatio, 0.68, accuracy: 1e-9)

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

        // **The anchor, and it is what makes the comparison below mean
        // anything.** Two runs compared only to each other would be green if
        // `offset(at:)` had started returning zeros in both modes — the
        // arithmetic could stop working entirely and this would still pass.
        //
        // Worked from the source rather than recorded from a run: the finger
        // lands at y=27, which is `floor(27/54) = 0`, so `sourceIndex` is 0 and
        // `liftOriginY` 27. It moves to 147, so `dragOffset` is 120 and
        // `(120/54).rounded()` is 2 — `targetIndex` 2, two slots down and the
        // remaining 12pt short of a third. Row 0 is the lifted one and carries
        // the whole 120. Rows 1 and 2 lie between the source and the hole and
        // step one slot *up*, −54 each. Row 3 is past the hole and does not
        // move.
        let expected: [CGFloat] = [120, -54, -54, 0, 120, 2, 0]

        BottomBarStyle.reduceMotion = false
        let full = answers()
        XCTAssertEqual(full, expected)

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(answers(), expected)
    }
}

/// **With Reduce Motion off, the disabled tint still switches instantly.**
///
/// `Interaction.body` gained an `.animation(_:value: isPressed)` on this branch,
/// for the press dim. Its scope is the whole label, and `.foregroundStyle(isEnabled
/// ? .primary : .tertiary)` is inside that scope — so a change of `isEnabled`
/// arriving in the same update as a change of `isPressed` gets carried along on
/// `dimReturn`'s 0.20s.
///
/// That is not a hypothetical pairing, it is the ordinary one: tapping Next onto
/// the last track lifts the finger (`isPressed` → false) and runs the command
/// (`canGoNext` → false, so `isEnabled` → false) in one turn. Pre-branch the tint
/// switched in a frame. **Behaviour with the setting off was to be identical to
/// before the branch**, and a 0.20s tint fade is not identical.
///
/// **Measured with the setting off, and only there, deliberately.** With it on,
/// `pressedOpacity` is 0.45 and lifting the finger *is* meant to animate the glyph
/// back to full over `dimReturn` — a value that legitimately travels, which would
/// drown out the thing being measured. Off, `pressedOpacity` is 1, so the press
/// draws nothing at all and the only thing left that can move the pixel is the
/// tint.
@MainActor
final class TransportDisabledTintTests: XCTestCase {

    private enum Harness {
        @MainActor static var down: (() -> Void)?
        @MainActor static var up: (() -> Void)?
    }

    private struct Probe: View {
        @State private var enabled = true
        @State private var pressed = false

        var body: some View {
            // A bare `Rectangle()` and not a `Color`: an unfilled shape paints
            // itself with the current foreground style, which is the one thing
            // this test is looking at. `Color.blue` — what the sibling press-dim
            // probe uses — carries its own fill and would ignore the tint
            // entirely.
            //
            // `trigger: 0` for the life of the probe, so nothing here came from
            // the kick.
            TransportButtonStyle.Interaction(
                label: Rectangle().frame(width: 20, height: 20),
                isPressedFromButton: pressed,
                style: .transportSkip(trigger: 0, direction: 1)
            )
            .disabled(!enabled)
            .frame(width: 60, height: 40)
            .background(Color.white)
            .onAppear {
                Harness.down = { pressed = true }
                // One turn, both writes — a touch-up that also happens to be
                // the command that disables the button. Splitting them would
                // measure a pairing that does not occur.
                Harness.up = {
                    pressed = false
                    enabled = false
                }
            }
        }
    }

    private var saved = false
    private var window: UIWindow?
    private var host: UIViewController?

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        host = nil
        Harness.down = nil
        Harness.up = nil
        try await super.tearDown()
    }

    /// How dark the block's centre is: 255 for solid ink, 0 for white.
    private func centre() throws -> Int {
        let view = try XCTUnwrap(host?.view)
        let grab = try XCTUnwrap(
            LivePixels.grab(view, CGSize(width: 60, height: 40)),
            "CALayer.render produced nothing"
        )
        return 255 - Int(grab.data[(20 * grab.width + 30) * 4 + 1])
    }

    func testTheDisabledTintArrivesInOneFrameWithTheSettingOff() throws {
        BottomBarStyle.reduceMotion = false
        Harness.down = nil
        Harness.up = nil
        let (window, host) = LivePixels.host(Probe())
        self.window = window
        self.host = host

        LivePixels.pump(0.5)
        let whileEnabled = try centre()

        // Pressed and left to settle before the interesting moment, so the halo
        // this touch-down fires has expired and cannot be mistaken for the tint
        // moving. The halo is keyed on touch-*down* only, so lifting the finger
        // below fires no second one.
        try XCTUnwrap(Harness.down)()
        LivePixels.pump(0.6)

        try XCTUnwrap(Harness.up)()
        var samples: [Int] = []
        for _ in 0..<25 {
            LivePixels.pump(0.01)
            samples.append(try centre())
        }
        LivePixels.pump(0.6)
        let settled = try centre()

        // The anchor. Without it, a probe drawing nothing, or drawing the same
        // grey in both states, satisfies the real assertion trivially — every
        // sample would sit on top of a `settled` that means nothing.
        let gap = abs(whileEnabled - settled)
        XCTAssertGreaterThan(
            gap, 40,
            "the probe cannot tell the two tints apart: \(whileEnabled) enabled against \(settled) disabled"
        )

        // Every sample from the first frame after the lift onwards is already at
        // the disabled value. A fade would put the early ones up near
        // `whileEnabled` and walk them down; `dimReturn` is 0.20s, so 25 frames
        // covers the whole of it with room to spare.
        let worst = samples.map { abs($0 - settled) }.max() ?? 0
        XCTAssertLessThanOrEqual(
            worst, gap / 10,
            "the disabled tint faded in instead of switching: \(samples) settling at \(settled)"
        )
    }
}

/// **The queue transition: every distance goes, and the transition still
/// happens.**
///
/// The single largest motion in the app, and until this round the only large one
/// with no reduced path at all. Opening the queue shrank the full-bleed cover
/// (~402×874) onto `QueuePanel.headerArtwork`'s 60pt slot and flew it diagonally
/// to the top-left corner — about 6.7× horizontally and 14.6× vertically — while
/// the title block slid several hundred points behind it. `BottomBarStyle.queue`
/// had a flat branch the whole time; a flat branch swaps the curve and leaves
/// the *distance* exactly where it was, which is why the reduced mode still flew.
///
/// Five sites carried that transition, and one of them being gated is worth
/// nothing while the other four ride along. This pins the four that are numbers
/// — the fifth, the cover's own flight, is removed inside
/// `PlayerCard.setQueueFactor(to:)`, which is private to a view and reachable
/// only by rendering one.
///
/// **The other half is that the transition still happens**, which is the whole
/// difference between reducing motion and breaking a feature. The distances go
/// to zero; nothing that makes the queue *appear* is touched, and the assertions
/// below say so in the same breath.
@MainActor
final class QueueTransitionDistanceTests: XCTestCase {

    private var saved = false

    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        try await super.tearDown()
    }

    /// Reduced: all four distances are zero. Off: all four are the measured
    /// numbers they have always been, which is the half that says the setting
    /// off is untouched.
    func testEveryDistanceInTheQueueTransitionGoesToZero() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(QueuePanel.riseDistance, 55)
        XCTAssertEqual(QueuePanel.headerTextRise, 8)
        XCTAssertEqual(NowPlayingContent.queueBadgeScale, 0.7)

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(QueuePanel.riseDistance, 0)
        XCTAssertEqual(QueuePanel.headerTextRise, 0)
        // 1, not 0: a scale's "no distance" is unity. Asserting 0 here would
        // pin the badge to being invisible, which is the opposite of the
        // requirement.
        XCTAssertEqual(NowPlayingContent.queueBadgeScale, 1)
    }

    /// **The swap still has to happen.** Reduce Motion removes travel, scale and
    /// bounce; it does not remove the queue.
    ///
    /// Two things say so here. The four fade curves that make the panel and the
    /// two title blocks appear are identical in both modes — a fade is what HIG
    /// asks for, so there is nothing to take out of them — and the artwork's
    /// geometry at `queueFactor` 1 is still the header slot, unchanged, because
    /// `artworkGeometry` is pure arithmetic on that factor and reads no flag.
    /// The reduced path cuts the journey, not the destination.
    func testTheQueueStillOpensAndTheArtworkStillReachesTheHeaderSlot() {
        BottomBarStyle.reduceMotion = false
        let fadesFull = [
            BottomBarStyle.queueContentIn,
            BottomBarStyle.queueContentOut,
            BottomBarStyle.queueTitleIn,
            BottomBarStyle.queueTitleOut
        ]
        let openFull = Self.artworkAtFullyOpenQueue()

        BottomBarStyle.reduceMotion = true
        let fadesReduced = [
            BottomBarStyle.queueContentIn,
            BottomBarStyle.queueContentOut,
            BottomBarStyle.queueTitleIn,
            BottomBarStyle.queueTitleOut
        ]
        let openReduced = Self.artworkAtFullyOpenQueue()

        XCTAssertEqual(fadesFull, fadesReduced, "a fade is not travel and must survive the setting")
        XCTAssertEqual(openFull, openReduced, "the artwork's destination changed with the setting")

        // And the destination is the header slot itself, not merely the same in
        // both modes: two equal wrong answers would satisfy the line above.
        let slot = PlayerCard.queueThumbCentre(topInset: Self.topInset)
        XCTAssertEqual(openReduced.width, QueuePanel.headerArtwork, accuracy: 0.001)
        XCTAssertEqual(openReduced.height, QueuePanel.headerArtwork, accuracy: 0.001)
        XCTAssertEqual(openReduced.centre.x, slot.x, accuracy: 0.001)
        XCTAssertEqual(openReduced.centre.y, slot.y, accuracy: 0.001)
        // Rounded like a thumbnail rather than squared off like a full-bleed
        // cover — the shape half of "it arrived".
        XCTAssertEqual(openReduced.shapeProgress, 0, accuracy: 0.001)
    }

    private static let cardSize = CGSize(width: 402, height: 874)
    private static let topInset: CGFloat = 59

    /// The artwork's geometry with the card fully expanded and the queue fully
    /// open — the end state of the transition, in both modes.
    private static func artworkAtFullyOpenQueue() -> PlayerCard.ArtworkGeometry {
        PlayerCard.artworkGeometry(
            progress: 1,
            queueFactor: 1,
            cardSize: cardSize,
            fullBleed: true,
            artworkSide: cardSize.width,
            // 0, and it makes no difference: `artworkTop` is only read on the
            // `fullBleed == false` path, where the expanded centre is derived
            // from the artwork's own square. This is the full-bleed cover.
            artworkTop: 0,
            queueThumbCentre: PlayerCard.queueThumbCentre(topInset: topInset),
            queueThumbSide: QueuePanel.headerArtwork
        )
    }
}
