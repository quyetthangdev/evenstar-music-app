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

    /// Một tấm bìa **chưa từng được giải mã trong tiến trình này**, ở một
    /// đường dẫn riêng cho mỗi lần gọi.
    ///
    /// `coverPath` ở trên cố ý ấm: nó là `static let`, nên mọi lần mount sau
    /// lần đầu đều là một cú tra cache. Điều đó đúng cho việc xếp hạng chi phí
    /// commit, và **sai** cho bất cứ câu hỏi nào về việc bìa tới muộn — trên
    /// máy thật, mỗi lần đổi bài là một lượt giải mã thật.
    ///
    /// Trắng với một dải xanh lá ngang, chứ không phải hai mảng màu: dải ấy là
    /// thước đo. Bề dày của nó trên màn hình tỉ lệ thẳng với cỡ tấm bìa đang
    /// được vẽ, nên đọc dải là đọc được bìa đang to bằng bao nhiêu ở khung ấy.
    ///
    /// **Nền trắng, và bản đầu dùng nền đen là một lỗi đã đo được.** Mép thẻ
    /// được dò bằng "hàng sáng đầu tiên trên nền đen của cửa sổ", nên một tấm
    /// bìa đen làm hai thước đo lẫn vào nhau: sau khi thẻ mở hết, hàng sáng đầu
    /// tiên **chính là dải xanh**, và bảng in ra "mép thẻ 380pt" suốt phần đuôi
    /// — đó là dải, không phải mép. Trắng tách chúng ra.
    ///
    /// 1200×1200 chứ không phải 600: cú giải mã phải đủ chậm để tiếp đất *giữa*
    /// cú morph, vì đó là toàn bộ tình huống đang được đo.
    static func freshCover(_ name: String) -> String {
        let relative = "covers/cold-\(name).jpg"
        let url = FileLocation.absoluteURL(forRelative: relative)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let side: CGFloat = 1200
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor(red: 0, green: 1, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: side * 0.45, width: side, height: side * 0.10))
        }
        try? image.jpegData(compressionQuality: 0.95)?.write(to: url)
        return relative
    }

    /// - Parameter alreadyPlaying: chọn bài **trước khi** gắn view, nên lúc gắn
    ///   `currentTrack` đã khác nil. Cú mở sau đó là cú mở **ấm**: không có cú
    ///   hoà mờ `.opacity(currentTrack == nil ? 0 : 1)` trên `settle`, không có
    ///   `.task` giải mã chạy lại, chỉ còn đúng cú morph. `j1` §1 đo cú mở ấm
    ///   rẻ hơn cú mở lạnh 54%, và bất kỳ phép đo nào về *độ trong suốt* đều
    ///   phải chạy ở đây — trên đường lạnh, cú hoà mờ toàn thẻ nuốt trọn tín
    ///   hiệu và mọi thứ trông như đang rò rỉ nền.
    static func make(
        background: Color? = nil,
        cover: String? = nil,
        alreadyPlaying: Bool = false,
        artworkless: Bool = false
    ) throws -> CardRig {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(
            artworkRelativePath: artworkless ? nil : (cover ?? Self.coverPath)
        )
        try library.insert(track)
        let playback = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        let expansion = PlayerExpansion()
        Drive.minimised = nil

        if alreadyPlaying { playback.play(track, in: [track]) }

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

    /// Mỗi view được quét **ba** lần và lấy trung vị, không phải một.
    ///
    /// **Một lần quét là không đủ, và đó là số đo chứ không phải phòng xa.**
    /// Ngày 2026-08-19 test này đỏ hai lần trong hai lượt chạy suite đầy đủ, ở
    /// hai assertion khác nhau, trong khi chạy riêng nó xanh 4/4. Lần đỏ thứ
    /// hai trượt ngưỡng đúng **0,04ms** (10,253 so với 10,294). Cùng buổi, cột
    /// `layered` đo ra 11,4 / 13,3 / 14,0 / 15,3 / 43,9ms — trải **3,9 lần**,
    /// trên một view không ai chạm vào.
    ///
    /// Ghi chú ở phần assertion bên dưới nói "run to run spread ... under 15%",
    /// và con số ấy không đứng trên máy này, nhất là khi 500 test khác vừa chạy
    /// trước nó. Ngưỡng 2× thì giữ nguyên — nó đúng và nó là điều test này tồn
    /// tại để nói. Thứ được sửa là **cỡ mẫu**, đúng bài học `k1` §3 đã trả giá
    /// để học: 9 lần mount cho ra −42,9% cho một thay đổi mà 20 lần mount cho
    /// ra −1,9%.
    ///
    /// Ba lần, không phải mười: mỗi lần quét là 40 khung × 16,67ms ≈ 0,67s cho
    /// mỗi view, nên ba lần cho ba view đã là ~6s. Trung vị của ba đủ để một
    /// lần quét xui không quyết định kết quả, mà vẫn giữ test dưới mười giây.
    private func medianSweep(_ make: () throws -> [CommitProbe.Frame]) rethrows -> [CommitProbe.Frame] {
        var runs: [[CommitProbe.Frame]] = []
        for _ in 0..<3 { runs.append(try make()) }
        runs.sort { total(of: $0) < total(of: $1) }
        return runs[runs.count / 2]
    }

    private func total(of frames: [CommitProbe.Frame]) -> Double {
        frames.reduce(0) { $0 + $1.commit }
    }

    func testTheProbeSeparatesARectangleFromALayerStackFromTheRealCard() throws {
        let trivial = medianSweep { sweepControl(TrivialMorph()) }
        let layered = medianSweep { sweepControl(LayeredMorph()) }
        let card = try medianSweep { try sweepCard() }

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
        // flaky on a loaded machine.
        //
        // ── NGƯỠNG 2× ĐÃ HẠ XUỐNG 1,5×, VÀ ĐÂY LÀ SỐ ĐO ────────────────────
        // Câu cũ ở đây viết: "A 2x separation is far beyond the run to run
        // spread measured here (under 15%)". Đo lại ngày 2026-08-19 cho thấy
        // câu ấy sai, và test đỏ ba lần trong ba lượt chạy suite đầy đủ trong
        // khi chạy riêng thì xanh 4/4.
        //
        // Tỉ lệ `layered / trivial` đo được, cùng máy cùng buổi:
        //
        //   chạy riêng   2,71×  2,44×  2,50×  2,15×
        //   trong suite  1,99×  1,89×
        //
        // Đây **không** phải dao động mà là một cú nén có hệ thống, và cơ chế
        // đọc ra được từ chính các con số: `trivial` chỉ tốn 0,13ms mỗi khung,
        // nên một khoản phí *cộng* thêm dưới tải phồng nó lên theo tỉ lệ lớn
        // hơn `layered` nhiều lần. Mọi tỉ lệ giữa một số nhỏ và một số lớn đều
        // co lại khi có nền cộng vào. Tăng cỡ mẫu không chữa được một thiên
        // lệch — `medianSweep` vẫn được giữ vì nó chữa phần dao động thật, còn
        // phần nén này thì chỉ có ngưỡng mới chữa.
        //
        // 1,5× nằm dưới hẳn con số tệ nhất từng quan sát (1,89×) và vẫn phát
        // biểu đúng điều test này tồn tại để nói: ba view tách được khỏi nhau.
        // Cách hỏng mà nó canh — một bộ đo đã ngừng nhìn thấy sẽ báo cả ba
        // bằng nhau, tức tỉ lệ 1,0× — vẫn bị bắt, và bắt với biên rộng.
        XCTAssertGreaterThan(
            layeredTotal, trivialTotal * 1.5,
            "the probe cannot separate six composited layers from one flat colour: "
            + "\(CommitProbe.ms(layeredTotal))ms against \(CommitProbe.ms(trivialTotal))ms"
        )
        XCTAssertGreaterThan(
            cardTotal, layeredTotal * 1.5,
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
        // The map has to *span* travel, not just end at the destination.
        // Without this, a probe that only ever caught the last frame would
        // report a perfectly good-looking map.
        //
        // **Đo cái nhịp, không đo mốc nửa đường.** Bản cũ đòi
        // `seen.max() > rest / 2` — tức mẫu đầu tiên nhìn thấy được phải còn ở
        // nửa dưới quãng đường. Điều ấy đúng khi `expand` là 0.52s: `h1` ghi
        // thẻ hiện ra lần đầu ở 515pt, progress ≈ 0,26. Hạ `expand` xuống 0.40s
        // thì thẻ hiện ra lần đầu ở 325pt, progress ≈ 0,53, và assertion đỏ —
        // đúng, nhưng vì một tính chất nó không định canh.
        //
        // Thẻ hiện ra muộn *theo quãng đường* vì hai đồng hồ khác nhau: quãng
        // đường chạy trên `expand`, còn cú hoà mờ lúc thẻ xuất hiện chạy trên
        // `.animation(BottomBarStyle.settle, value: currentTrack == nil)`, và
        // chỉ cái thứ nhất được rút ngắn. Đó là một tính chất **thật** của cú
        // bung, đáng một test riêng nếu ai muốn ghim nó — không phải thứ để
        // đóng ké vào một bộ đo bản đồ vị trí.
        let highest = try XCTUnwrap(seen.max())
        let lowest = try XCTUnwrap(seen.min())
        let span = highest - lowest
        XCTAssertGreaterThan(
            span, rest / 4,
            "the visible samples all sat at the same place; the map covers nothing — "
            + "span \(span)pt over a travel of \(rest)pt"
        )
    }
}

/// **Khi cú giải mã bìa tiếp đất giữa cú morph, bìa xuất hiện ở cỡ nào?**
///
/// Người dùng báo: *"thỉnh thoảng như kiểu ảnh có sẵn, chỉ có player bung"* —
/// tấm bìa không lớn dần cùng tấm thẻ. Doc của `ArtworkStore.anyCachedImage`
/// đã gọi đúng tên triệu chứng ấy từ trước: *"it is the cover failing to grow
/// with the card"*, và cái lưới an toàn nó mô tả chỉ bắt được khi bài ấy đã
/// từng được giải mã ở **một cỡ nào đó** trong tiến trình. Bài chưa từng được
/// giải mã thì lưới rỗng.
///
/// Có **hai** cách hỏng khác nhau ở đây, và chúng dẫn tới hai bản sửa khác
/// hẳn nhau, nên phải tách được chúng trước khi sửa bất cứ gì:
///
/// 1. **Đứt gãy hình học.** `if source == .image` trong `artworkView` là một
///    `if` *cấu trúc*, và `loadArtwork` ghi `artwork` bằng một cú ghi `@State`
///    trần. Nếu SwiftUI chèn tấm `Image` vào cây với hình học **đích** thay vì
///    hình học đang được nội suy, thì bìa thật sự nhảy — và bản sửa là bỏ cái
///    `if` ấy đi.
/// 2. **Chỉ là tới muộn.** Nếu tấm `Image` được chèn vào và lớn lên đúng theo
///    thẻ, thì không có gì đứt gãy cả; bìa chỉ vắng mặt trong phần lớn cú
///    bung. Bản sửa khi ấy nằm ở chỗ khác hoàn toàn: rút ngắn cú giải mã, hoặc
///    làm cái lưới `anyCachedImage` bắt được nhiều hơn.
///
/// Test này **không** khẳng định cái nào đúng — nó in ra bảng để đọc. Assertion
/// duy nhất là assertion mà một bộ đo phải có: rằng nó nhìn thấy được thứ nó
/// đang đo.
@MainActor
final class PlayerCardColdArtworkArrivalTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    func testWhereTheCoverIsOnTheFrameItArrives() throws {
        window?.isHidden = true
        let rig = try CardRig.make(background: .black, cover: CardRig.freshCover("arrival"))
        window = rig.window

        let column = 195
        let height = 844

        /// Một lượt đọc cột `column`: mép trên tấm thẻ, và dải xanh của tấm bìa.
        ///
        /// Cùng một lần render cho cả ba con số, chứ không ba lần: hai lượt
        /// render cách nhau vài mili giây là hai khung khác nhau của một cú
        /// animation đang chạy, và so chúng với nhau là so hai thời điểm.
        func read() -> (cardTop: Int?, greenTop: Int?, greenBottom: Int?) {
            let view = rig.host.view!
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let width = column + 1
            var data = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return (nil, nil, nil) }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            view.layer.render(in: context)

            var cardTop: Int?
            var greenTop: Int?
            var greenBottom: Int?
            for row in 0..<height {
                let p = (row * width + column) * 4
                let r = Int(data[p]), g = Int(data[p + 1]), b = Int(data[p + 2])
                if cardTop == nil, r + g + b > 60 { cardTop = row }
                // JPEG ở chất lượng 0.95 vẫn làm mép dải nhoè, và tấm bìa còn
                // đi qua lớp sương với cú tan, nên "xanh" phải là một vùng chứ
                // không phải một giá trị: trội hẳn hai kênh kia là đủ để không
                // thứ gì khác trên tấm thẻ lọt vào.
                if g > 90, g > r * 2, g > b * 2 {
                    if greenTop == nil { greenTop = row }
                    greenBottom = row
                }
            }
            return (cardTop, greenTop, greenBottom)
        }

        // **Bơm run loop tường minh, không dùng `CommitProbe.idle(until:)`.**
        //
        // `idle(until:)` có `guard remaining > 0 else { return }`, và một lượt
        // `read()` render cả một context 196×844 nên tốn hơn 16,7ms. Deadline
        // `start + index/60` vì thế tụt lại ngay từ khung đầu và `idle` trả về
        // tức thì ở **mọi** lượt sau đó — run loop không bao giờ được chạy, nên
        // continuation của `loadArtwork` không bao giờ tiếp đất. Bản đầu của
        // test này chạy 150 mẫu, báo "bìa không hiện ở khung nào", rồi in ra
        // một dải xanh sáng rực ngay khi được `pump(1.5)`. Cùng cách hỏng mà
        // `spin(until:)` ở đầu file đã ghi lại, tới từ một cửa khác.
        //
        // Hệ quả: mốc thời gian phải **đo**, không suy ra từ chỉ số khung — một
        // mẫu ở đây dài hơn một khung màn hình.
        rig.tapToOpen()
        var trace: [(Double, (cardTop: Int?, greenTop: Int?, greenBottom: Int?))] = []
        let start = CACurrentMediaTime()
        for _ in 0..<90 {
            CommitProbe.pump(1.0 / 60)
            trace.append(((CACurrentMediaTime() - start) * 1000, read()))
        }

        for (index, row) in trace.enumerated().map({ ($0.offset, $0.element) }).map({ ($0.1.0, $0.1.1) }) {
            let card = row.cardTop.map { "\($0)pt" } ?? "chưa hiện"
            let green = row.greenTop.flatMap { top in
                row.greenBottom.map { "dải \(top)–\($0)pt, dày \($0 - top)pt" }
            } ?? "chưa có bìa"
            CommitProbe.log(String(format: "[arrival] t=%6.1fms  mép thẻ %@  %@",
                                   index, card, green))
        }

        let framesWithGreen = trace.filter { $0.1.greenTop != nil }
        CommitProbe.log("[arrival] bìa hiện ở \(framesWithGreen.count)/90 mẫu; "
              + "mẫu đầu tiên có bìa: t=\(framesWithGreen.first.map { String(format: "%.1f", $0.0) } ?? "không có")ms")

        // Chẩn đoán khi không thấy dải: để mọi thứ lắng hẳn rồi in trắc diện
        // màu của cả cột. Nếu dải có ở đây mà không có ở trên thì là cú giải mã
        // tới muộn; nếu không có ở đây nữa thì là ngưỡng màu sai.
        CommitProbe.pump(1.5)
        let view = rig.host.view!
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let width = column + 1
        var data = [UInt8](repeating: 0, count: width * height * 4)
        if let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            view.layer.render(in: context)
            for row in stride(from: 0, to: height, by: 20) {
                let p = (row * width + column) * 4
                CommitProbe.log("[arrival-profile] row \(row): "
                      + "r\(data[p]) g\(data[p + 1]) b\(data[p + 2])")
            }
        }

        // Bộ đo phải nhìn thấy được cả hai thứ nó đo, nếu không cả bảng ở trên
        // là một trang trắng có định dạng đẹp.
        XCTAssertFalse(
            trace.compactMap({ $0.1.cardTop }).isEmpty,
            "không đọc được mép thẻ ở khung nào"
        )
        XCTAssertFalse(
            framesWithGreen.isEmpty,
            "không đọc được tấm bìa ở khung nào — cú giải mã chưa bao giờ tiếp đất, "
            + "hoặc ngưỡng màu không bắt được dải xanh"
        )
        // ── KHẲNG ĐỊNH CHÍNH ─────────────────────────────────────────────────
        //
        // Đọc dải mốc ở một mẫu mà tấm thẻ **còn đang đi**, rồi so với chỗ dải
        // ấy nằm khi mọi thứ đã đứng yên. Bìa lớn lên cùng thẻ thì hai chỗ ấy
        // phải cách nhau; bìa đứng sẵn ở đích thì chúng trùng nhau.
        //
        // Số đo ngày 2026-08-19, cùng máy cùng buổi:
        //
        //   trước bản sửa   mép thẻ 120pt  dải 380–463pt   (đúng chỗ cuối cùng)
        //   sau bản sửa     mép thẻ 391pt  dải 531–583pt   (còn cách 152pt)
        //
        // 30pt là ngưỡng, không phải con số kỳ vọng: nó nằm dưới hẳn 152pt đo
        // được và trên hẳn 0pt của cách hỏng. Rộng như vậy vì mỗi mẫu ở đây tốn
        // 50–80ms — `read()` render cả một bitmap — nên cú morph 0,40s chỉ cho
        // khoảng bốn mẫu, và mẫu đầu tiên có bìa rơi vào đâu trong bốn mẫu ấy
        // thì tuỳ máy.
        let settledBandTop = try XCTUnwrap(
            trace.last(where: { $0.1.greenTop != nil })?.1.greenTop,
            "không có mẫu nào ở trạng thái nghỉ để lấy chỗ đứng cuối của dải"
        )
        let whileTravelling = trace.first { sample in
            guard let cardTop = sample.1.cardTop, sample.1.greenTop != nil else { return false }
            return cardTop > 30
        }
        let travelling = try XCTUnwrap(
            whileTravelling,
            "không bắt được mẫu nào vừa thấy bìa vừa thấy thẻ đang đi. Cú giải mã "
            + "tiếp đất sau khi thẻ đã mở xong, nên không có gì để so — máy quá "
            + "chậm cho phép đo này, chứ không phải mã sai."
        )
        let bandTopWhileTravelling = try XCTUnwrap(travelling.1.greenTop)
        XCTAssertGreaterThan(
            bandTopWhileTravelling - settledBandTop, 30,
            "tấm bìa không lớn lên cùng tấm thẻ: mép thẻ còn ở "
            + "\(travelling.1.cardTop.map(String.init) ?? "?")pt mà dải mốc đã ở "
            + "\(bandTopWhileTravelling)pt, trong khi chỗ đứng cuối của nó là "
            + "\(settledBandTop)pt. Bìa đang được vẽ ở hình học đích rồi để tấm "
            + "thẻ hé ra — xem chú thích ở `artworkView` về cái `if` cấu trúc."
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


/// **Tấm thẻ có trong suốt giữa cú morph không.**
///
/// Người dùng báo hai lần rằng khi thu nhỏ player, thanh tab và danh sách phía
/// sau nhìn xuyên qua được và bị làm mờ, rồi trả về nguyên trạng một phát khi
/// xong. Hai vòng chẩn đoán trước đó sai, và cả hai sai vì suy luận từ mã thay
/// vì đo — nên đây là phép đo.
///
/// Cách đo: đặt thẻ lên một nền **xanh lá thuần** (0,255,0), ép chế độ tối, rồi
/// đếm số hàng trong thân thẻ mà kênh green trội hẳn hai kênh kia. Mọi lớp của
/// thẻ đều là xám hoặc màu trội rút từ bìa, nên một hàng xanh trội chỉ có thể
/// là nền lọt qua.
///
/// Ba chi tiết của rig, mỗi cái sửa một phép đo đã hỏng trước đó:
///
/// - **`alreadyPlaying: true`.** Trên cú mở **lạnh**, `.opacity(currentTrack ==
///   nil ? 0 : 1)` hoà cả tấm thẻ vào trên `settle`, và cú hoà mờ ấy làm mọi
///   thứ trông như đang rò rỉ nền — bản đầu của phép đo này đọc ra 65% rò rỉ ở
///   giữa cú morph và con số ấy hoàn toàn là cú hoà mờ.
/// - **`artworkless: true`.** Bài **có** bìa thì tấm bìa tràn màn hình và đục
///   che mất lớp nền, nên độ trong suốt của nền không quan sát được. Bài trong
///   video người dùng quay là bài không bìa, và đó cũng là ca duy nhất đo được.
/// - **chế độ tối.** `systemGroupedBackground` ở chế độ sáng gần trắng nên nó
///   cho cả ba kênh cao, không tách được "nền lọt qua" khỏi "mặt thẻ vốn sáng".
///
/// Chỉ đo được chiều **mở**; `h1` §4.5 đã ghi vì sao chiều đóng không đo được
/// từ test. Cơ chế đối xứng, nên chiều mở là đại diện.
@MainActor
final class PlayerCardTranslucencyTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    func testTheCardIsOpaqueWhileItTravels() throws {
        window?.isHidden = true
        let rig = try CardRig.make(
            background: Color(red: 0, green: 1, blue: 0),
            alreadyPlaying: true,
            artworkless: true
        )
        window = rig.window
        rig.window.overrideUserInterfaceStyle = .dark
        rig.warmUp()

        let column = 195
        let height = 844

        func sample() -> (cardTop: Int?, leaking: Int, rows: Int) {
            let view = rig.host.view!
            view.setNeedsLayout()
            view.layoutIfNeeded()
            let width = column + 1
            var data = [UInt8](repeating: 0, count: width * height * 4)
            guard let ctx = CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return (nil, 0, 0) }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            view.layer.render(in: ctx)

            var top: Int?
            for row in 0..<height {
                let p = (row * width + column) * 4
                if data[p] > 20 || Int(data[p + 1]) < 200 || data[p + 2] > 20 { top = row; break }
            }
            guard let found = top else { return (nil, 0, 0) }
            var leaking = 0
            for row in found..<height {
                let p = (row * width + column) * 4
                let r = Int(data[p]), g = Int(data[p + 1]), b = Int(data[p + 2])
                if g > r + 40, g > b + 40 { leaking += 1 }
            }
            return (found, leaking, height - found)
        }

        rig.tapToOpen()
        var trace: [(Int?, Int, Int)] = []
        for _ in 0..<20 {
            CommitProbe.pump(1.0 / 60)
            trace.append(sample())
        }

        for row in trace {
            CommitProbe.log("[opaque] mép thẻ \(row.0.map(String.init) ?? "—")pt  "
                  + "rò rỉ \(row.1)/\(row.2) hàng")
        }

        // Mẫu giữa đường: thẻ đã rời hẳn viên thuốc nhưng chưa tới đích. Ở
        // trạng thái nghỉ thẻ **phải** trong — viên thuốc là một mặt sương, và
        // đó là chủ ý — nên mốc dưới 200pt loại đúng trạng thái ấy ra.
        let midway = trace.first { row in
            guard let top = row.0 else { return false }
            return top > 200 && top < 520
        }
        let sample = try XCTUnwrap(
            midway,
            "không bắt được mẫu nào ở giữa cú morph để chấm"
        )

        // Đo được ngày 2026-08-19, cùng máy cùng buổi, ở mép thẻ ~350pt:
        //
        //   lớp nền đọc `progress` của `body`   304/480 hàng  (63%)
        //   lớp nền đọc giá trị đang được vẽ     46/507 hàng   (9%)
        //
        // 25% là ngưỡng: dưới hẳn 63% của cách hỏng, trên hẳn 9% còn lại — phần
        // dư ấy là mép trên tấm thẻ, nơi lớp sương và cú bo góc chồng nhau, và
        // nó không phải thứ ai nhìn ra.
        let leakFraction = Double(sample.1) / Double(sample.2)
        XCTAssertLessThan(
            leakFraction, 0.25,
            """
            tấm thẻ trong suốt giữa cú morph: \(sample.1)/\(sample.2) hàng cho \
            thấy nền xuyên qua ở mép thẻ \(sample.0.map(String.init) ?? "?")pt. \
            Lớp nền đục đang đọc `progress` của `body` — vốn đã là giá trị đích \
            ngay từ khung đầu của một `withAnimation` — thay vì giá trị đang \
            được vẽ. Xem `CardSurface`.
            """
        )
    }
}
