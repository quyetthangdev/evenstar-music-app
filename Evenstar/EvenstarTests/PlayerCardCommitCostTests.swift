import XCTest
import SwiftUI
import QuartzCore
@testable import Evenstar

/// **What one update of `PlayerCard` costs, and which part of it costs that.**
///
/// The device trace this exists to explain is an `Animation Hitches` recording
/// of 24s of opening and closing the player on an iPhone 12, Release, cold:
/// the **commit** phase has a median of 16.06ms against a 16.67ms budget and
/// blows it on 42% of frames, while the app's own code is 0.14% of main-thread
/// time and libobjc + CoreFoundation + malloc are ~38%. That is the signature
/// of building and throwing away objects every frame inside SwiftUI, not of a
/// slow function in this project — so nothing here profiles Evenstar's own
/// symbols. It measures the one thing the trace says is the bottleneck: the
/// wall-clock cost of bringing the layer tree up to date after a change.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT THE PROBE MEASURES, AND WHY IT IS `layoutIfNeeded` AND NOT A PUMP
/// ─────────────────────────────────────────────────────────────────────────
/// `LivePixels` in `ReduceMotionSurfacesTests` already established the fact
/// this whole file rests on, and it was established by measurement rather than
/// reasoning: **in a unit-test process the run loop advances SwiftUI's
/// interpolation but never brings the `CALayer` tree up to date.** Its doc
/// records a wash animation whose layer sat at its starting frame for thirteen
/// consecutive samples until `layoutIfNeeded()` was forced.
///
/// That separation is what makes a probe possible at all. Pumping the run loop
/// costs whatever SwiftUI's own bookkeeping costs; the layer-tree update — the
/// commit — happens only where this file asks for it, so it can be timed:
///
///   1. `idle(until:)` spends the idle part of a frame the way the app spends
///      it — running the run loop, which is what advances the animation.
///      Untimed.
///   2. optional state writes, timed separately (the drag path).
///   3. `setNeedsLayout` + `layoutIfNeeded` + `CATransaction.flush()`, timed.
///      That is the span from "the state has changed" to "the layer tree is
///      updated and handed to the render server".
///
/// Step 3 forces a layout every sample rather than waiting for one to be
/// needed, so what it reports is the **marginal cost of one update pass**, not
/// what an idle card costs. That is the right quantity for a ranking — it is
/// what a frame of a morph pays — but it is not an idle-cost measurement and
/// must not be read as one.
///
/// ─────────────────────────────────────────────────────────────────────────
/// THE SIMULATOR IS NOT THE DEVICE, AND THIS FILE ONLY CLAIMS AN ORDERING
/// ─────────────────────────────────────────────────────────────────────────
/// The absolute milliseconds below are a Mac's, on a simulator, in Debug, with
/// no display link and no GPU pipeline of the kind the device trace measured.
/// They will not reproduce 16.06ms and are not meant to. What survives the move
/// is the *ordering* — which layer of the card costs more than which — and the
/// only assertions in this file are ordering assertions with wide margins.
///
/// ─────────────────────────────────────────────────────────────────────────
/// A HARNESS THAT MEASURES NOTHING REPORTS EVERYTHING AS CHEAP
/// ─────────────────────────────────────────────────────────────────────────
/// The failure mode is not a wrong number, it is a uniform number: a probe that
/// had stopped seeing the update would report every configuration as equally
/// fast and every switched-off component as free. `PlayerCardCommitCostControlTests`
/// is what stands against that, and it is the first class here for that reason.
/// Three views are swept through the same morph on the same probe — a single
/// coloured rectangle, a stack of gradients and a masked material, and the real
/// card — and the probe has to separate all three. If it cannot, every other
/// number in this file is meaningless and that class is the one that says so.
@MainActor
private enum CommitProbe {

    /// Puts `view` on screen in a phone-sized window.
    ///
    /// Copied from `LivePixels.host` rather than shared, and the reason is
    /// visibility rather than taste: that type is `private` to
    /// `ReduceMotionSurfacesTests.swift`, and widening it would be an edit to a
    /// file this round is not allowed to touch. Its two load-bearing details
    /// are kept exactly, because both were arrived at by measurement there —
    /// **a plausible window size** (a window sized to the probe inherits the
    /// screen's safe-area insets and lays the content out off its own bottom
    /// edge) and **`isHidden = false`** (SwiftUI does not drive an animation
    /// for a window nobody is showing, which would flatten every curve here to
    /// its destination).
    static func host<V: View>(_ view: V) -> (UIWindow, UIViewController) {
        let host = UIHostingController(rootView: view)
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

    /// Lets the run loop tick — used only to settle a mount, never inside a
    /// measured span.
    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// One update and commit, in seconds.
    ///
    /// `CATransaction.flush()` after the layout, not instead of it. The layout
    /// is what makes SwiftUI produce the frame at all (see this file's header);
    /// the flush is what commits the resulting layer changes rather than
    /// leaving them for whenever the run loop next gets a turn — which, inside
    /// a measured span that never runs the run loop, would be never.
    static func commit(_ view: UIView) -> Double {
        let start = CACurrentMediaTime()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        CATransaction.flush()
        return CACurrentMediaTime() - start
    }

    /// Burns wall-clock time **without** running the run loop.
    ///
    /// **Not what the sweep uses, and the reason is a measurement.** This was
    /// the first design: keep the run loop out of the idle part of a frame so
    /// nothing could quietly commit behind the probe. It produced a control
    /// that could not tell a single `Color` from a six-layer stack of gradients
    /// and masked material — 6.751ms against 5.783ms, with the *rectangle*
    /// ahead. Every sample was a no-op: with no run loop the animation never
    /// advances, so by the time `commit` is called nothing has changed and
    /// there is nothing to update.
    ///
    /// Which is the same fact `LivePixels` records from the other side. The run
    /// loop is what advances SwiftUI's interpolation; `layoutIfNeeded` is what
    /// brings the layer tree up to date. A probe needs both, and it needs them
    /// in that order — so the sweep pumps, and measures the layout that follows.
    ///
    /// Kept because it is the honest record of why the sweep looks the way it
    /// does, and because it is what a reader will otherwise propose.
    static func spin(until deadline: CFTimeInterval) {
        while CACurrentMediaTime() < deadline {}
    }

    /// Advances the animation to `deadline` and returns.
    ///
    /// `RunLoop.main.run(until:)` with the remaining time, so the frame's idle
    /// budget is spent the way the app spends it: letting the display link and
    /// the timers fire. Nothing here is timed.
    static func idle(until deadline: CFTimeInterval) {
        let remaining = deadline - CACurrentMediaTime()
        guard remaining > 0 else { return }
        RunLoop.main.run(until: Date().addingTimeInterval(remaining))
    }

    struct Frame {
        /// Seconds spent inside the state writes for this frame. 0 on the tap
        /// path, which writes nothing.
        var write: Double
        /// Seconds spent bringing the layer tree up to date.
        var commit: Double
        var total: Double { write + commit }
    }

    /// Sweeps `frames` simulated display frames, timing each one.
    ///
    /// The deadlines are computed from one fixed start, not accumulated from
    /// each frame's end, so a configuration that costs more does not stretch
    /// its own timeline: every sweep samples the same 0…`frames`/60 seconds of
    /// the same animation, and a slow one simply falls behind and does fewer
    /// idle spins. That is what keeps two configurations comparable sample for
    /// sample.
    static func sweep(
        _ view: UIView,
        frames: Int,
        frameSeconds: Double = 1.0 / 60.0,
        write: (Int) -> Void = { _ in }
    ) -> [Frame] {
        var out: [Frame] = []
        out.reserveCapacity(frames)
        let start = CACurrentMediaTime()
        for index in 0..<frames {
            idle(until: start + Double(index) * frameSeconds)
            let t0 = CACurrentMediaTime()
            write(index)
            let t1 = CACurrentMediaTime()
            out.append(Frame(write: t1 - t0, commit: commit(view)))
        }
        return out
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func ms(_ seconds: Double) -> String {
        String(format: "%.3f", seconds * 1000)
    }

    /// Prints, and also appends to a file in the app's own Documents directory.
    ///
    /// `print` alone is not enough to work with: a test bundle's stdout does
    /// not reach the `.xcresult`, so a table printed from here is visible in
    /// Xcode and nowhere else. The file is the copy that can be read back after
    /// a headless `xcodebuild` run. It costs nothing anyone measures — every
    /// call site is outside a timed span.
    static func log(_ line: String) {
        print(line)
        let url = FileLocation.absoluteURL(forRelative: "commit-cost-measurements.txt")
        let text = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// The state the harness views hand back so a test can drive them.
@MainActor
private enum Drive {
    /// Writes `PlayerCard.minimised` — the only input to the real card a test
    /// can write from outside. See `PlayerCardTapVersusDragCostTests` for what
    /// it does and does not stand for.
    static var minimised: ((Double) -> Void)?
    /// Starts a control view's morph.
    static var morph: (() -> Void)?
}

// MARK: - The three views the control compares

/// A single rectangle that grows the way the card does. The floor.
private struct TrivialMorph: View {
    @State private var progress: Double = 0

    var body: some View {
        Color.blue
            .frame(width: 348 + (390 - 348) * progress,
                   height: 54 + (874 - 54) * progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.bottom, 79 * (1 - progress))
            .onAppear {
                Drive.morph = { withAnimation(BottomBarStyle.expand) { progress = 1 } }
            }
    }
}

/// The same growth carrying the *kinds* of layer the card carries — a
/// seven-stop gradient rebuilt from `progress`, a masked `.ultraThinMaterial`,
/// and a tint ramp — but none of its content, geometry or state.
///
/// The middle rung of the control. Without it, "the card is slower than a
/// rectangle" would be satisfied by a probe that only measured how many views
/// there are.
private struct LayeredMorph: View {
    @State private var progress: Double = 0

    private var stops: [Gradient.Stop] {
        let span = 0.25 * progress
        let start = 1 - span
        return (0...6).map { step in
            let t = Double(step) / 6
            let eased = t * t * (3 - 2 * t)
            return Gradient.Stop(color: .white.opacity(1 - eased), location: start + span * t)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .orange, location: 0),
                    .init(color: .orange, location: 0.75),
                    .init(color: .orange.opacity(0.55), location: 0.87),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(progress)

            Color.purple
                .overlay {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.30),
                                    .init(color: .white.opacity(0.55), location: 0.52),
                                    .init(color: .white, location: 0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(progress)
                }
                .mask(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 348 + (390 - 348) * progress,
               height: 54 + (874 - 54) * progress)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, 79 * (1 - progress))
        .onAppear {
            Drive.morph = { withAnimation(BottomBarStyle.expand) { progress = 1 } }
        }
    }
}

/// The real card, with the one input a test can write exposed.
private struct CardHarness: View {
    let playback: PlaybackService
    let library: LibraryService
    let expansion: PlayerExpansion
    @State private var minimised: Double = 0

    var body: some View {
        PlayerCard(playback: playback, minimised: minimised, expansion: expansion)
            .environment(library)
            .environment(playback)
            .onAppear { Drive.minimised = { minimised = $0 } }
    }
}

// MARK: - Mounting a real card

/// Everything a `PlayerCard` needs to be the card the device trace recorded:
/// a track **with a cover on disk**, so `hasArtwork` is true and the layers it
/// gates — the dissolve mask, the frosted overlay, the tint ramp — are all
/// live. A coverless card takes a different and much cheaper path through
/// `artworkView` and `background`, and measuring that one would answer a
/// question nobody asked.
@MainActor
private struct CardRig {
    let library: LibraryService
    let playback: PlaybackService
    let expansion: PlayerExpansion
    let track: Track
    let window: UIWindow
    let host: UIViewController

    /// Written once per process; `ArtworkStore` caches the decode by path, so
    /// every mount after the first gets the same picture without touching the
    /// disk again.
    static let coverPath: String = {
        let relative = "covers/commit-cost-harness.jpg"
        let url = FileLocation.absoluteURL(forRelative: relative)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
        let image = renderer.image { context in
            UIColor(red: 0.85, green: 0.25, blue: 0.15, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            UIColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 300, width: 600, height: 300))
        }
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url)
        return relative
    }()

    static func make(background: Color? = nil) throws -> CardRig {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(artworkRelativePath: Self.coverPath)
        try library.insert(track)
        let playback = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        let expansion = PlayerExpansion()
        Drive.minimised = nil

        let card = CardHarness(playback: playback, library: library, expansion: expansion)
        let (window, host): (UIWindow, UIViewController)
        if let background {
            // `ignoresSafeArea`, or the ground stops at the safe-area inset and
            // the first 59 rows of every capture are the hosting controller's
            // own white — which reads as "the card's top edge is row 0" at
            // every sample, measured.
            (window, host) = CommitProbe.host(ZStack { background.ignoresSafeArea(); card })
        } else {
            (window, host) = CommitProbe.host(card)
        }

        return CardRig(
            library: library, playback: playback, expansion: expansion,
            track: track, window: window, host: host
        )
    }

    /// Settles the mount: lets `.task` finish decoding the cover and lets the
    /// first, one-off costs (font loading, first decode, first material) land
    /// somewhere other than the measurement.
    func warmUp() {
        CommitProbe.pump(0.35)
        for _ in 0..<10 { _ = CommitProbe.commit(host.view) }
    }

    /// Opens the player exactly the way a tapped library row does — one state
    /// change, inside `expand()`'s spring. There is no other way in: `settled`
    /// and `dragDelta` are `private @State`, and `PlayerExpansion` publishes
    /// outward only.
    func tapToOpen() {
        playback.play(track, in: [track])
    }
}

// MARK: - Việc 1 — the control

/// **The probe can tell three views apart, so it is measuring something.**
///
/// The ordering has to hold in both places it can fail. A probe that had
/// stopped seeing the update entirely reports all three as equal; a probe that
/// only counted views would rank `LayeredMorph` — six layers — beside the card,
/// which is hundreds. Neither survives all three comparisons below.
@MainActor
final class PlayerCardCommitCostControlTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        Drive.minimised = nil
        Drive.morph = nil
        try await super.tearDown()
    }

    private static let frames = 40

    private func sweepControl<V: View>(_ view: V) -> [CommitProbe.Frame] {
        window?.isHidden = true
        Drive.morph = nil
        let (window, host) = CommitProbe.host(view)
        self.window = window
        CommitProbe.pump(0.3)
        for _ in 0..<10 { _ = CommitProbe.commit(host.view) }
        Drive.morph?()
        return CommitProbe.sweep(host.view, frames: Self.frames)
    }

    private func sweepCard() throws -> [CommitProbe.Frame] {
        window?.isHidden = true
        let rig = try CardRig.make()
        window = rig.window
        rig.warmUp()
        rig.tapToOpen()
        return CommitProbe.sweep(rig.host.view, frames: Self.frames)
    }

    func testTheProbeSeparatesARectangleFromALayerStackFromTheRealCard() throws {
        let trivial = sweepControl(TrivialMorph())
        let layered = sweepControl(LayeredMorph())
        let card = try sweepCard()

        func report(_ name: String, _ frames: [CommitProbe.Frame]) -> Double {
            let total = frames.reduce(0) { $0 + $1.commit }
            CommitProbe.log("[control] \(name): total \(CommitProbe.ms(total))ms over \(frames.count) frames, "
                  + "median \(CommitProbe.ms(CommitProbe.median(frames.map(\.commit))))ms, "
                  + "max \(CommitProbe.ms(frames.map(\.commit).max() ?? 0))ms")
            return total
        }

        let trivialTotal = report("Color", trivial)
        let layeredTotal = report("gradients + masked material", layered)
        let cardTotal = report("PlayerCard", card)

        // Wide margins, deliberately: the claim is an ordering, and a threshold
        // tight enough to be interesting is a threshold tight enough to be
        // flaky on a loaded machine. A 2x separation is far beyond the run to
        // run spread measured here (under 15%) and far below the separations
        // actually observed.
        XCTAssertGreaterThan(
            layeredTotal, trivialTotal * 2,
            "the probe cannot separate six composited layers from one flat colour: "
            + "\(CommitProbe.ms(layeredTotal))ms against \(CommitProbe.ms(trivialTotal))ms"
        )
        XCTAssertGreaterThan(
            cardTotal, layeredTotal * 2,
            "the probe cannot separate the whole card from a six-layer stand-in: "
            + "\(CommitProbe.ms(cardTotal))ms against \(CommitProbe.ms(layeredTotal))ms"
        )
        // And the floor is a floor. Without this, all three could be the same
        // large constant — the run loop's own overhead, say — and the two
        // ratios above would still be satisfiable by noise.
        XCTAssertGreaterThan(
            trivialTotal, 0,
            "the probe measured no time at all for a view that is definitely animating"
        )
    }
}

// MARK: - Việc 2 — the curve, and the axis it is plotted against

@MainActor
final class PlayerCardCommitCostTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        Drive.minimised = nil
        try await super.tearDown()
    }

    private static let frames = 40
    private static let repetitions = 9

    /// **The baseline: what one tapped open costs, frame by frame.**
    ///
    /// Nine mounts rather than nine morphs on one mount, because there is no
    /// way to close the card again from a test that does not also change what
    /// is drawn (`collapse()` runs only when `currentTrack` goes to `nil`, and
    /// a card with no track is invisible). A fresh rig per repetition is the
    /// only repeat that measures the same thing every time.
    ///
    /// ─────────────────────────────────────────────────────────────────────
    /// THE HEADLINE NUMBER IS A RATIO, BECAUSE MILLISECONDS DRIFT TOO MUCH
    /// ─────────────────────────────────────────────────────────────────────
    /// Measured on this machine, the summed median moved 151.3ms → 129.8ms
    /// between two runs of the *identical* build — 16.5% of run-to-run spread,
    /// which is more than several of the components this file is trying to
    /// rank contribute in the first place. A ranking built on raw milliseconds
    /// cannot tell a real 10% from a busy laptop.
    ///
    /// **The minimum was tried first and is worse, which is worth recording
    /// because it is the textbook answer.** Taking the fastest of nine
    /// observations per sample index gave totals of 71.7ms and 29.7ms on two
    /// runs — a factor of 2.4, against the median's 1.07. The reason is that
    /// the nine mounts are not nine observations of the same instant: the
    /// morph starts a frame or two earlier or later relative to the sweep
    /// depending on when `onChange(of: explicitSelections)` lands, so the
    /// minimum at each index tends to pick the one mount where nothing was
    /// happening yet. Minimum-of-N is the right estimator for N runs of
    /// identical work, and these are not that.
    ///
    /// So the ranking reads a **ratio measured inside the same process run**:
    /// the same `LayeredMorph` from the control class is swept alongside the
    /// card, moments apart, and the reported number is card ÷ layered. A busy
    /// machine inflates both and cancels.
    func testTheCostOfOneTappedOpen() throws {
        var byIndex: [[Double]] = Array(repeating: [], count: Self.frames)
        var cardTotals: [Double] = []
        var referenceTotals: [Double] = []

        for _ in 0..<Self.repetitions {
            window?.isHidden = true
            let rig = try CardRig.make()
            window = rig.window
            rig.warmUp()
            rig.tapToOpen()
            let frames = CommitProbe.sweep(rig.host.view, frames: Self.frames)
            for (index, frame) in frames.enumerated() { byIndex[index].append(frame.commit) }
            cardTotals.append(frames.reduce(0) { $0 + $1.commit })

            // The yardstick, mounted and swept the same way, immediately after
            // — so whatever the machine was doing during the card's sweep it
            // was still doing during this one.
            window?.isHidden = true
            Drive.morph = nil
            let (referenceWindow, referenceHost) = CommitProbe.host(LayeredMorph())
            window = referenceWindow
            CommitProbe.pump(0.3)
            for _ in 0..<10 { _ = CommitProbe.commit(referenceHost.view) }
            Drive.morph?()
            let referenceFrames = CommitProbe.sweep(referenceHost.view, frames: Self.frames)
            referenceTotals.append(referenceFrames.reduce(0) { $0 + $1.commit })
        }

        let curve = byIndex.map { CommitProbe.median($0) }
        CommitProbe.log("[baseline] per-frame commit, median of \(Self.repetitions) mounts, ms:")
        for (index, value) in curve.enumerated() {
            CommitProbe.log(String(format: "[baseline] frame %02d  t=%5.1fms  %@ms",
                                   index, Double(index) * 1000 / 60, CommitProbe.ms(value)))
        }

        let card = CommitProbe.median(cardTotals)
        let reference = CommitProbe.median(referenceTotals)
        CommitProbe.log("[baseline] TOTAL median \(CommitProbe.ms(card))ms over \(Self.frames) frames"
                        + "; reference \(CommitProbe.ms(reference))ms"
                        + String(format: "; RATIO %.3f", card / reference))

        XCTAssertGreaterThan(curve.reduce(0, +), 0, "the whole morph cost nothing")
        XCTAssertGreaterThan(reference, 0, "the yardstick measured nothing, so the ratio means nothing")
    }

    /// **Where the card actually is at each sample.**
    ///
    /// The curve above is indexed by time, and time is only a stand-in for
    /// `progress` unless somebody measures the map between them. This does,
    /// from pixels, so the ranking can be read against the card's travel rather
    /// than against a spring curve taken on trust.
    ///
    /// The card's own arithmetic gives the inversion, and its derivation is
    /// spelled out in `card(size:insets:)`: with `H` the full height, `C` the
    /// collapsed height and `B` the collapsed bottom offset,
    /// `top(p) = H − B(1−p) − C − (H−C)p`, which is linear in `p` with
    /// `top(1) = 0`. So `p = 1 − top / top(0)`, and `top(0) = H − B − C` comes
    /// from the app's own constants rather than a literal.
    ///
    /// **The resting edge is not read from pixels, and that is a finding rather
    /// than a shortcut.** The first attempt read it right after the tap, on the
    /// grounds that the spring cannot have moved anything yet. It came back
    /// blank, every time: `body` fades the whole card in with
    /// `.opacity(currentTrack == nil ? 0 : 1)` on `BottomBarStyle.settle`, so
    /// for the first frames of an open there is a card at the right place with
    /// nothing visible in it. That fade is also why the early samples below
    /// have no top edge to report at all.
    ///
    /// Black behind the card so "the card's top edge" is the first row that is
    /// not black — and black is the ground that makes a *partly* faded-in card
    /// detectable, since its shadow is black on black and contributes nothing.
    func testWhereTheCardIsAtEachSample() throws {
        window?.isHidden = true
        let rig = try CardRig.make(background: .black)
        window = rig.window
        rig.warmUp()

        let column = 195
        let height = 844
        func topEdge() -> Int? {
            let view = rig.host.view!
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let width = column + 1
            var data = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            view.layer.render(in: context)
            for row in 0..<height {
                let p = (row * width + column) * 4
                let luminance = Int(data[p]) + Int(data[p + 1]) + Int(data[p + 2])
                if luminance > 60 { return row }
            }
            return nil
        }

        let rest = Int(CGFloat(height)
                       - BottomBarMetrics.playerBottomOffset
                       - PlayerCard.collapsedHeight)

        rig.tapToOpen()
        var trace: [(Int, Int?)] = []
        let start = CACurrentMediaTime()
        for index in 0..<Self.frames {
            CommitProbe.idle(until: start + Double(index) / 60)
            trace.append((index, topEdge()))
        }

        CommitProbe.log("[travel] derived resting top edge \(rest)pt")
        for (index, top) in trace {
            let text = top.map {
                String(format: "top=%4dpt  progress≈%.3f", $0, 1 - Double($0) / Double(rest))
            } ?? "still fading in"
            CommitProbe.log(String(format: "[travel] frame %02d  t=%5.1fms  %@",
                                   index, Double(index) * 1000 / 60, text))
        }

        let seen = trace.compactMap(\.1)
        XCTAssertFalse(seen.isEmpty, "the card was never visible at all")
        let last = try XCTUnwrap(seen.last)
        XCTAssertLessThan(last, rest / 2, "the card never travelled; top edge \(last) against \(rest)")
        // The trace starts somewhere near the collapsed rest rather than at the
        // destination. Without this, a probe that only ever caught the last
        // frame would report a perfectly good-looking map.
        XCTAssertGreaterThan(
            try XCTUnwrap(seen.max()), rest / 2,
            "every visible sample was already most of the way open; the map covers nothing"
        )
    }
}

// MARK: - Việc 3 — one state change against many

/// **The tap path against the drag path.**
///
/// The contradiction this answers: `SwiftUIAnimationTransactionEvidenceTests`
/// measured that a tapped morph runs `PlayerCard.body` **once** and lets
/// SwiftUI interpolate properties — so where do 16ms *per frame* come from?
/// Either the dynamic properties are re-evaluated every frame anyway, or the
/// expensive direction is the one the user **drags**, where
/// `DragGesture.onChanged` writes `@State` at ~250Hz (the number is this
/// project's own, at the head of `Features/Prototypes/PlayerMorphUIKitView.swift`)
/// and every write rebuilds the tree, three of every four rebuilds being
/// thrown away.
///
/// The six sweeps below run the same morph over the same frames on the same
/// probe, and differ only in how many times an input is written per frame, and
/// in whether the run loop gets a turn between the writes. The gaps between
/// them are the price of those extra rebuilds.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT IT MEASURED, SO THE SHAPE OF THE TABLE IS NOT A SURPRISE
/// ─────────────────────────────────────────────────────────────────────────
/// Measured here, medians of nine mounts over 40 frames:
///
///     tap, no writes                            141.7ms
///     1 write/frame                             189.6ms   1.34x
///     4 writes/frame, batched                   148.8ms   1.05x
///     4 writes/frame, run loop between          189.9ms   1.34x
///     4 large writes/frame, batched             150.3ms   1.06x
///     4 large writes/frame, run loop between    189.9ms   1.34x
///
/// **Four writes in a frame cost what one costs.** Whether they are batched or
/// each given their own pass of the run loop, and whatever the size of the
/// change, the frame lands on the same 1.34x. There is one update per frame,
/// not four — SwiftUI coalesces, and the write itself is only an
/// invalidation. The note at the head of `PlayerMorphUIKitView.swift` — "four
/// rebuilds of the view tree per display frame, three of them thrown away" —
/// does not describe what this measures.
///
/// The other half is the answer to the contradiction. A tap, where `body` runs
/// once and everything after it is interpolation, already costs 75% of what the
/// drag frame costs. Whatever is expensive is expensive with `body` sitting
/// still.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHAT `minimised` STANDS FOR, AND WHERE IT FALLS SHORT
/// ─────────────────────────────────────────────────────────────────────────
/// A real drag writes `dragDelta`, which is `private @State`. Nothing outside
/// the type can write it, and there is no way to deliver a touch to a
/// `DragGesture` from a unit-test process — so the drag is modelled with
/// `minimised`, the card's own `let` input, written from the harness above it.
/// Writing it produces a genuinely different `PlayerCard` value and therefore a
/// full `body` evaluation, which is the thing being counted.
///
/// It is **not** the same in one respect: `minimised` feeds fewer downstream
/// attributes than `progress` does, so more of the graph compares equal and is
/// skipped. Two amplitudes exist to bracket that — 0.002, a rebuild whose
/// results are nearly all discarded, and 0.5, which moves the card's margins
/// and bottom offset so layout is genuinely redone. They came out within 1% of
/// each other, which says the bracket is narrow and the penalty is the rebuild
/// itself rather than what the rebuild changes. The 1.34x is still a floor
/// rather than an estimate, but a floor with a measured ceiling close above it.
@MainActor
final class PlayerCardTapVersusDragCostTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        Drive.minimised = nil
        try await super.tearDown()
    }

    private static let frames = 40
    private static let repetitions = 9

    /// One configuration of the drag path.
    private struct Path {
        let name: String
        /// Writes per simulated display frame. 0 is the tap path.
        let writes: Int
        /// How far `minimised` moves on each write.
        let amplitude: Double
        /// Whether the run loop is serviced *between* the writes of one frame.
        ///
        /// This is the difference between four touches that arrive in one batch
        /// and four touches that each arrive in their own pass of the run loop,
        /// which is what 250Hz touch delivery against a 60Hz display actually
        /// looks like. Whether SwiftUI coalesces them is the question; with the
        /// run loop shut out it has no choice but to.
        let serviced: Bool
    }

    private func sweep(_ path: Path) throws -> (write: Double, commit: Double) {
        var writes: [Double] = []
        var commits: [Double] = []

        for _ in 0..<Self.repetitions {
            window?.isHidden = true
            let rig = try CardRig.make()
            window = rig.window
            rig.warmUp()
            rig.tapToOpen()

            var tick = 0
            let frames = CommitProbe.sweep(rig.host.view, frames: Self.frames) { _ in
                guard let write = Drive.minimised else { return }
                for _ in 0..<path.writes {
                    tick += 1
                    write(Double(tick % 2) * path.amplitude)
                    if path.serviced { RunLoop.main.run(until: Date()) }
                }
            }
            writes.append(frames.reduce(0) { $0 + $1.write })
            commits.append(frames.reduce(0) { $0 + $1.commit })
        }

        return (CommitProbe.median(writes), CommitProbe.median(commits))
    }

    func testOneStateChangePerMorphAgainstFourPerFrame() throws {
        let paths: [Path] = [
            .init(name: "tap — 1 state change for the whole morph", writes: 0, amplitude: 0, serviced: false),
            .init(name: "drag — 1 small write/frame", writes: 1, amplitude: 0.002, serviced: false),
            .init(name: "drag — 4 small writes/frame, batched", writes: 4, amplitude: 0.002, serviced: false),
            .init(name: "drag — 4 small writes/frame, run loop between", writes: 4, amplitude: 0.002, serviced: true),
            .init(name: "drag — 4 large writes/frame, batched", writes: 4, amplitude: 0.5, serviced: false),
            .init(name: "drag — 4 large writes/frame, run loop between", writes: 4, amplitude: 0.5, serviced: true)
        ]

        var results: [(Path, Double)] = []
        for path in paths {
            let result = try sweep(path)
            let total = result.write + result.commit
            results.append((path, total))
            CommitProbe.log("[tap-vs-drag] \(path.name): write \(CommitProbe.ms(result.write))ms"
                            + " + commit \(CommitProbe.ms(result.commit))ms"
                            + " = \(CommitProbe.ms(total))ms over \(Self.frames) frames")
        }

        let tapTotal = try XCTUnwrap(results.first?.1)
        for (path, total) in results.dropFirst() {
            CommitProbe.log(String(format: "[tap-vs-drag] %@ = %.2fx tap", path.name, total / tapTotal))
        }

        XCTAssertGreaterThan(tapTotal, 0, "the tap path cost nothing, so nothing here is comparable")
        // The writes reach the card. Without this the whole class could be six
        // measurements of the same configuration — the harness's own failure
        // mode, and one that would read as "the drag path is free".
        let loudest = try XCTUnwrap(results.last?.1)
        XCTAssertGreaterThan(
            loudest, tapTotal,
            "160 extra state writes cost nothing measurable; the harness is probably not writing at all"
        )
    }
}
