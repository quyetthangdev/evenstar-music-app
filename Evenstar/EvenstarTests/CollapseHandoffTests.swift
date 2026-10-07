import XCTest
import SwiftUI
@testable import Evenstar

/// Cuối cú thu: thẻ co mềm, không nảy, vào đúng viên kính, mặt thẻ thành
/// **kính** ở đoạn cuối, hàng mini hiện dần, rồi nhường cho accessory (spec,
/// Phần 1, chốt 2026-10-07).
///
/// Lỗi QA trên máy (iPhone 12, Release, sau `fbc0837`): thẻ thu khít lên viên
/// kính rồi đứng chết và mờ đi — "mất hiệu ứng đàn hồi, cứng". Bản trước nữa
/// thì tệ theo cách khác: thẻ đặc đứng ~300ms trên viên kính rồi nhảy màu.
///
/// Các nhóm test ở đây ghim những phần **không phụ thuộc đồng hồ**: cửa sổ
/// kính, lò xo hình học của cú thu (hỏi thẳng `CollapseSpring` bằng
/// `Spring.value`, không chạy animation), sàn phần dư, các cờ của
/// `PlayerExpansion`, và việc thẻ thật nối chúng lại đúng — kể cả chốt cú
/// morph. Cú chạm sàn **vẽ ra** thật được đo từng khung ở
/// `CollapseLandingFrameTests`.
@MainActor
final class CollapseHandoffTests: XCTestCase {

    // MARK: - Cửa sổ kính

    func testTheSurfaceIsOpaqueWhileTheCardIsMoreThanTwiceTheCapsule() {
        for height: CGFloat in [844, 300, 120, 96] {
            XCTAssertEqual(PlayerCard.collapseGlass(cardHeight: height, capsuleHeight: 48), 0,
                           "card \(height)pt")
        }
    }

    func testTheSurfaceIsGlassOnceTheCardIsWithinAQuarterOfTheCapsule() {
        for height: CGFloat in [60, 55, 48] {
            XCTAssertEqual(PlayerCard.collapseGlass(cardHeight: height, capsuleHeight: 48), 1,
                           "card \(height)pt")
        }
        // Tuyến tính ở giữa: 2× → 1,25×, nửa đường là 1,625×.
        XCTAssertEqual(PlayerCard.collapseGlass(cardHeight: 48 * 1.625, capsuleHeight: 48),
                       0.5, accuracy: 0.0001)
    }

    /// Spec: thẻ thành kính khi **còn lớn hơn** viên kính một chút, không phải
    /// lúc đã khít.
    func testTheGlassIsCompleteWhileTheCardIsStillVisiblyLarger() {
        XCTAssertGreaterThan(PlayerCard.collapseGlassStartRatio, PlayerCard.collapseGlassEndRatio)
        XCTAssertGreaterThanOrEqual(PlayerCard.collapseGlassEndRatio, 1.2)
        XCTAssertLessThanOrEqual(PlayerCard.collapseGlassStartRatio, 2.5,
                                 "càng sớm, viên kính hệ thống càng lâu lộ ra xuyên qua thẻ")
    }

    func testNoCapsuleHeightMeansNoGlass() {
        XCTAssertEqual(PlayerCard.collapseGlass(cardHeight: 48, capsuleHeight: 0), 0)
    }

    // MARK: - Lò xo hình học của cú thu

    /// Thẻ không bao giờ nhỏ hơn hay thấp hơn viên kính: hình học không bao giờ
    /// vọt qua đích — với mọi vận tốc thả tay — và cho tới lúc kết thúc nó **là**
    /// lò xo (`Spring.value`). Lò xo không nảy, nên nó kết thúc khi đã lắng.
    func testTheGeometryNeverPassesItsTarget() {
        let spring = BottomBarStyle.collapseSpring
        for velocity in [0, 3, 8, BottomBarStyle.maxSettleVelocity, -4] {
            let geometry = CollapseSpring(spring: spring, initialVelocity: velocity)
            let label = "v \(velocity)"
            var time = 0.0
            while let g = geometry.fraction(at: time) {
                XCTAssertLessThan(g, 1, label)
                XCTAssertEqual(g, spring.value(target: 1.0, initialVelocity: velocity, time: time),
                               accuracy: 1e-12, label)
                time += 0.001
            }
            // Và chính lò xo cũng không vọt qua — cái chốt dừng-ở-đích chỉ là
            // lưới an toàn ở đây.
            var probe = 0.0
            while probe < 2 {
                XCTAssertLessThanOrEqual(spring.value(target: 1.0, initialVelocity: velocity, time: probe),
                                         1 + 1e-9, "the spring itself overshot, \(label)")
                probe += 0.001
            }
            XCTAssertLessThan(time, 1, "the geometry has to finish, \(label)")
        }
    }

    /// Co đều, không nảy: quãng còn lại chỉ giảm.
    func testTheCollapseShrinksMonotonically() {
        let spring = BottomBarStyle.collapseSpring
        for velocity in [0, 3, BottomBarStyle.maxSettleVelocity] {
            var previous = 0.0
            var time = 0.0
            while time < 1 {
                let f = spring.value(target: 1.0, initialVelocity: velocity, time: time)
                XCTAssertGreaterThanOrEqual(f, previous - 1e-12, "it went backwards at \(time)s, v \(velocity)")
                previous = f
                time += 0.001
            }
        }
    }

    /// Phán quyết: tới nơi ~0,45–0,5s (trong 1pt trên trọn quãng 796pt), và từ
    /// lúc chạm/thả tới hết cú mờ trao chỗ ≲ 0,7s. Thẻ trao chỗ khi hình học
    /// kết thúc (`completion` của nó), tức `settlingTime`.
    func testItArrivesInAboutHalfASecondAndHandsOverWithinPointSeven() {
        let spring = BottomBarStyle.collapseSpring
        var arrival = 0.0
        while 1 - spring.value(target: 1.0, initialVelocity: 0, time: arrival) > 1.0 / 796 { arrival += 0.001 }
        XCTAssertGreaterThanOrEqual(arrival, 0.43, "arrives in \(arrival)s")
        XCTAssertLessThanOrEqual(arrival, 0.52, "arrives in \(arrival)s")
        for velocity in [0, 3, BottomBarStyle.maxSettleVelocity] {
            let geometry = CollapseSpring(spring: spring, initialVelocity: velocity)
            let handoffEnd = geometry.settlingTime + 0.15
            print("[collapse] v \(velocity): handoff starts \(String(format: "%.0f", geometry.settlingTime * 1000))ms,"
                  + " ends \(String(format: "%.0f", handoffEnd * 1000))ms; tap arrives in 1pt at"
                  + " \(String(format: "%.0f", arrival * 1000))ms")
            XCTAssertLessThanOrEqual(handoffEnd, 0.7, "v \(velocity)")
            XCTAssertGreaterThanOrEqual(geometry.settlingTime, arrival * 0.8,
                                        "the handoff waits for the card to arrive, v \(velocity)")
        }
    }

    // MARK: - Hàng mini hiện dần ở đoạn cuối

    func testTheMiniRowAppearsOnlyAsTheCardNearsThePill() {
        XCTAssertEqual(PlayerCard.miniRowFadeIn(progress: 1), 0)
        XCTAssertEqual(PlayerCard.miniRowFadeIn(progress: 0.5), 0)
        XCTAssertEqual(PlayerCard.miniRowFadeIn(progress: PlayerCard.miniRowFadeStart), 0)
        XCTAssertEqual(PlayerCard.miniRowFadeIn(progress: PlayerCard.miniRowFadeEnd), 1)
        XCTAssertEqual(PlayerCard.miniRowFadeIn(progress: 0), 1)
        var previous = 0.0
        for p in stride(from: 1.0, through: 0, by: -0.01) {
            let o = PlayerCard.miniRowFadeIn(progress: p)
            XCTAssertGreaterThanOrEqual(o, previous)
            previous = o
        }
    }

    /// Theo thời gian của cú chạm: hàng chưa hiện trong nửa đầu cú thu, bắt đầu
    /// hiện khi thẻ còn vài lần viên kính, và hiện hẳn trước khi thẻ tới nơi.
    func testTheMiniRowFadesInOverTheLastPartOfTheCollapse() {
        let spring = BottomBarStyle.collapseSpring
        func time(reaching p: Double) -> Double {
            var t = 0.0
            while 1 - spring.value(target: 1.0, initialVelocity: 0, time: t) > p { t += 0.001 }
            return t
        }
        let start = time(reaching: PlayerCard.miniRowFadeStart)
        let end = time(reaching: PlayerCard.miniRowFadeEnd)
        let settle = CollapseSpring(spring: spring, initialVelocity: 0).settlingTime
        print("[collapse] mini row fades in from \(String(format: "%.0f", start * 1000))ms"
              + " to \(String(format: "%.0f", end * 1000))ms; handoff at \(String(format: "%.0f", settle * 1000))ms")
        XCTAssertGreaterThan(start, 0.15, "the row should not appear early in the collapse")
        XCTAssertLessThan(end, settle, "and should be fully there before the handoff")
        XCTAssertGreaterThan(end - start, 0.08, "a fade, not a cut")
    }

    // MARK: - Sàn: cú thu cắt ngang một cú bung còn sớm

    /// Thứ vẽ ra là `(1 − k)·span + R(t)`: phần của cú thu cộng phần dư của cú
    /// bung còn đang chạy. Âm là thẻ thấp hơn viên kính.
    private func lowestDrawn(afterDrag: Bool, interruptAt elapsed: Double, floored: Bool) -> Double {
        let expand = try! XCTUnwrap(BottomBarStyle.expandCurves.geometrySpring)
        let residual = CollapseSpring.Residual(spring: expand, initialVelocity: 0, delta: 1, elapsed: elapsed)
        let geometry = CollapseSpring(spring: BottomBarStyle.collapseSpring,
                                      initialVelocity: 0,
                                      span: 1, residuals: floored ? [residual] : [])
        var lowest = Double.infinity
        var time = 0.0
        while time < 2 {
            let ours = geometry.fraction(at: time).map { 1 - $0 } ?? 0
            lowest = min(lowest, ours + residual.value(after: time))
            time += 0.001
        }
        return lowest
    }

    func testACollapseRightAfterAnExpandNeverTakesTheCardBelowTheCapsule() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = false

        for afterDrag in [false, true] {
            for elapsed in [0, 0.016, 0.05, 0.1, 0.15, 0.2, 0.3, 0.5] {
                XCTAssertGreaterThanOrEqual(
                    lowestDrawn(afterDrag: afterDrag, interruptAt: elapsed, floored: true),
                    -CollapseSpring.residualTolerance,
                    "afterDrag \(afterDrag), expand interrupted at \(elapsed)s"
                )
            }
        }
    }

    /// Đối chứng: không có sàn thì đúng là thẻ xuống dưới viên kính — test
    /// trên không xanh vì kịch bản vô hại.
    func testWithoutTheFloorTheSameCollapseWouldSquashTheCard() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = false

        // Với lò xo thu không nảy (0,34s), cú thu bắt ngay sau cú mở vẫn chạy
        // nhanh hơn phần dư của cú mở một quãng: đo được ~−0,007, tức thẻ thấp
        // hơn viên kính ~5pt trên 796pt. Nhỏ hơn thời lò xo có nảy, nhưng là thật.
        let lowest = lowestDrawn(afterDrag: false, interruptAt: 0, floored: false)
        XCTAssertLessThan(lowest, -0.005, "the unfloored tap collapse right after a tap open only reached \(lowest)")
    }

    /// Trường hợp thường — không cú nào đang bay — không đổi một bit.
    func testWithNothingInFlightTheCollapseIsUntouched() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = false

        let curves = BottomBarStyle.collapse(initialVelocity: 2, afterDrag: true)
        XCTAssertEqual(curves.flooring(span: 0.7, residuals: []).geometry, curves.geometry)
        XCTAssertNil(curves.geometrySpring, "a collapse leaves no negative residual to record")
        XCTAssertNotNil(BottomBarStyle.expandCurves.geometrySpring)
        XCTAssertNotNil(BottomBarStyle.settleCurves(initialVelocity: 3).geometrySpring)
        XCTAssertEqual(BottomBarStyle.expandCurves.geometry, BottomBarStyle.expand, "expand itself is unchanged")
        XCTAssertEqual(BottomBarStyle.settleCurves(initialVelocity: 3).geometry,
                       BottomBarStyle.settle(initialVelocity: 3))
    }

    func testTheCurvesHandedToTheCardAreThoseSprings() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = false

        let curves = BottomBarStyle.collapse(initialVelocity: 4, afterDrag: true)
        let spring = BottomBarStyle.collapseSpring
        XCTAssertEqual(curves.geometry,
                       Animation(CollapseSpring(spring: spring, initialVelocity: 4)))
        XCTAssertEqual(curves.collapseSpring, spring)
        XCTAssertEqual(curves.initialVelocity, 4)
        XCTAssertEqual(BottomBarStyle.collapse(afterDrag: false).collapseSpring, spring,
                       "a tap and a release share one tempo")
        XCTAssertEqual(spring, Spring(duration: 0.34, bounce: 0), "no bounce")
    }

    /// Giảm chuyển động: không vận tốc — nhánh phẳng của chính lối vào ấy.
    func testWithReduceMotionTheCollapseIsTheFlatCurve() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = true

        let release = BottomBarStyle.collapse(initialVelocity: 9, afterDrag: true)
        XCTAssertEqual(release.geometry, .easeInOut(duration: 0.29))
        XCTAssertNil(release.collapseSpring)
        let tap = BottomBarStyle.collapse(afterDrag: false)
        XCTAssertEqual(tap.geometry, .easeInOut(duration: 0.26))
        XCTAssertNil(tap.collapseSpring)
    }

    // MARK: - Các cờ của `PlayerExpansion`

    private func make() -> PlayerExpansion {
        let e = PlayerExpansion()
        e.screenSize = CGSize(width: 390, height: 844)
        return e
    }

    func testAtRestTheAccessoryShowsItsContent() {
        XCTAssertTrue(make().showsAccessoryContent)
    }

    func testLeavingRestHidesTheAccessorysContent() {
        let e = make()
        e.leaveRest()
        XCTAssertFalse(e.showsAccessoryContent)
    }

    /// Ngược với `fbc0837`: thẻ giờ là kính trong suốt suốt đoạn cuối và lún
    /// lệch khỏi viên kính, nên hàng của accessory **không** được hiện sớm —
    /// nó sẽ lộ xuyên qua thành hai dòng chữ lệch nhau.
    func testCommittingACollapseKeepsTheAccessorysContentHiddenUntilRest() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        XCTAssertTrue(e.isCollapsing)
        XCTAssertFalse(e.isCardResting)
        XCTAssertFalse(e.showsAccessoryContent)
    }

    func testArrivingAtRestEndsTheCollapseAndShowsTheAccessory() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        e.arriveAtRest()
        XCTAssertFalse(e.isCollapsing)
        XCTAssertTrue(e.isCardResting)
        XCTAssertTrue(e.showsAccessoryContent)
    }

    func testTheSurfaceIsOpaqueWhileOpeningAndGlassOnlyWhenCollapsingOrResting() {
        let e = make()
        XCTAssertTrue(e.cardSurfaceIsGlass, "at rest — the card is invisible there anyway")
        e.leaveRest()
        XCTAssertFalse(e.cardSurfaceIsGlass, "opening: opaque from the first frame")
        e.commitCollapse()
        XCTAssertTrue(e.cardSurfaceIsGlass)
        e.arriveAtRest()
        XCTAssertTrue(e.cardSurfaceIsGlass,
                      "still glass while the card fades out over the accessory — no grey flash")
    }

    /// Chạm accessory giữa cú thu: thẻ chưa về nghỉ nên `leaveRest()` bỏ qua
    /// phần chụp khung, nhưng cú thu phải bị huỷ — thẻ đặc lại ngay.
    func testExpandingAgainMidCollapseMakesTheCardOpaqueAgain() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        e.leaveRest()
        XCTAssertFalse(e.isCollapsing)
        XCTAssertFalse(e.cardSurfaceIsGlass)
        XCTAssertFalse(e.showsAccessoryContent)
    }

    func testADragOnTheAccessoryMidCollapseMakesTheCardOpaqueAgain() {
        let e = make()
        e.leaveRest()
        e.commitCollapse()
        e.accessoryDragChanged(translationHeight: -100)
        XCTAssertFalse(e.isCollapsing)
        XCTAssertFalse(e.cardSurfaceIsGlass)
        XCTAssertFalse(e.showsAccessoryContent)
    }

    // MARK: - Nối dây: thẻ thật

    private var window: UIWindow?
    private var savedReduceMotion = false

    override func setUp() async throws {
        try await super.setUp()
        savedReduceMotion = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = savedReduceMotion
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    /// Thẻ nghỉ, có bài sẵn (khôi phục phiên trước: chọn bài **trước** khi
    /// gắn view, nên `explicitSelections` không mở thẻ).
    private func mountRestingCard(reduceMotion: Bool) throws -> PlayerExpansion {
        BottomBarStyle.reduceMotion = reduceMotion
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack()
        try library.insert(track)
        let playback = PlaybackService(
            player: MockAudioPlayer(),
            nowPlaying: MockNowPlayingPublisher(),
            library: library
        )
        playback.play(track, in: [track])
        let expansion = PlayerExpansion()
        let host = UIHostingController(
            rootView: PlayerCard(playback: playback, expansion: expansion)
                .environment(library)
                .environment(playback)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(expansion.isCardResting)
        return expansion
    }

    /// Hai mốc của một cú thu sau cú thả tay không vận tốc, tính bằng chính lò
    /// xo ấy: lúc thẻ đã gần tới (98% quãng), và lúc hình học kết thúc — thẻ
    /// trao chỗ. Không phụ thuộc quãng: lò xo đo theo phần quãng đường.
    private func releaseMilestones() throws -> (near: Double, rest: Double) {
        let spring = BottomBarStyle.collapseSpring
        var near = 0.0
        while spring.value(target: 1.0, initialVelocity: 0, time: near) < 0.98 { near += 0.001 }
        let rest = CollapseSpring(spring: spring, initialVelocity: 0).settlingTime
        XCTAssertGreaterThan(rest - near, 0.15, "the two milestones are too close to tell apart by waiting")
        return (near, rest)
    }

    private func waitForRest(_ expansion: PlayerExpansion) {
        let deadline = Date().addingTimeInterval(3)
        while !expansion.isCardResting, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Kéo accessory lên rồi thả: cú thả rơi về 0, `PlayerCard.handle` gọi
    /// `morph(to: 0…)`. Suốt cú thu thẻ đang thu và accessory vẫn ẩn; chỉ khi
    /// hình học kết thúc thẻ mới về nghỉ.
    ///
    /// Mốc kiểm tra là **giữa** lúc thẻ đã gần tới (98%, ~0,32s) và lúc hình học
    /// kết thúc (~0,54s), tính từ lò xo chứ không gõ tay — biên ~0,11s cả hai
    /// phía.
    func testAReleaseThatFallsBackRestsOnlyOnceTheCardHasArrived() throws {
        let expansion = try mountRestingCard(reduceMotion: false)
        let milestones = try releaseMilestones()

        expansion.accessoryDragChanged(translationHeight: -120)
        XCTAssertFalse(expansion.showsAccessoryContent)
        expansion.accessoryDragEnded(predictedTranslationHeight: -120, verticalVelocity: 0)
        let released = Date()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(expansion.progress, 0, "the card settled on the collapse target")
        XCTAssertFalse(expansion.isCardResting)
        XCTAssertTrue(expansion.isCollapsing)
        XCTAssertTrue(expansion.cardSurfaceIsGlass)
        XCTAssertFalse(expansion.showsAccessoryContent, "hidden under the translucent card")

        RunLoop.main.run(until: released.addingTimeInterval((milestones.near + milestones.rest) / 2))
        XCTAssertFalse(expansion.isCardResting, "the card is nearly there but has not arrived")
        XCTAssertFalse(expansion.showsAccessoryContent)

        waitForRest(expansion)
        XCTAssertTrue(expansion.isCardResting)
        XCTAssertFalse(expansion.isCollapsing)
        XCTAssertTrue(expansion.showsAccessoryContent)
    }

    // MARK: - Một `completion` cũ không được về nghỉ giữa cú thu mới

    /// Đường (a) của review: thu, rồi giữa cú thu kéo accessory lên một chút
    /// và thả — cú thu thứ hai. `completion` của cú thứ nhất vẫn nổ ở mốc lắng
    /// **của nó**, lúc cú thứ hai còn đang bay.
    ///
    /// Mốc kiểm tra: giữa lúc cú thứ nhất kết thúc (`rest₁`) và lúc cú thứ hai
    /// kết thúc (`0,35 + rest₂`), cả hai tính từ lò xo của cú thu.
    ///
    /// Đo được: trên simulator iOS 26 đường này **xanh cả khi tháo chốt** —
    /// `completion` của cú thứ nhất không nổ giữa cú thứ hai ở đây. Đường (b)
    /// ngay dưới thì đỏ khi tháo chốt. Giữ cả hai: chốt không dựa vào việc
    /// SwiftUI gọi hay không gọi một `completion` bị cắt ngang lúc nào.
    func testAStaleCompletionDoesNotRestTheCardDuringALaterCollapse() throws {
        let expansion = try mountRestingCard(reduceMotion: false)
        let milestones = try releaseMilestones()

        expansion.accessoryDragChanged(translationHeight: -120)
        expansion.accessoryDragEnded(predictedTranslationHeight: -120, verticalVelocity: 0)
        let first = Date()

        RunLoop.main.run(until: first.addingTimeInterval(0.25))
        expansion.accessoryDragChanged(translationHeight: -70)
        RunLoop.main.run(until: first.addingTimeInterval(0.35))
        expansion.accessoryDragEnded(predictedTranslationHeight: -70, verticalVelocity: 0)

        let second = try releaseMilestones()
        RunLoop.main.run(until: first.addingTimeInterval((milestones.rest + 0.35 + second.rest) / 2))
        XCTAssertFalse(expansion.isCardResting,
                       "the first collapse's completion rested the card in the middle of the second")
        XCTAssertFalse(expansion.showsAccessoryContent)

        waitForRest(expansion)
        XCTAssertTrue(expansion.isCardResting, "and the second collapse still rests the card")
    }

    /// Đường (b) của review: thu, mở lại giữa chừng (chạm accessory), rồi thu
    /// lần nữa bằng một cú kéo xuống. Hai `completion` cũ — của cú thu đầu và
    /// của cú mở — đều nổ trong cú thu thứ hai, và với `settled == 0` lúc ấy,
    /// một phép hỏi trạng thái hiện tại sẽ gật đầu với cả hai.
    func testReopeningMidCollapseAndCollapsingAgainRestsOnlyAtTheEnd() throws {
        let expansion = try mountRestingCard(reduceMotion: false)
        let milestones = try releaseMilestones()

        expansion.accessoryDragChanged(translationHeight: -120)
        expansion.accessoryDragEnded(predictedTranslationHeight: -120, verticalVelocity: 0)
        let first = Date()

        RunLoop.main.run(until: first.addingTimeInterval(0.3))
        expansion.requestExpand()
        RunLoop.main.run(until: first.addingTimeInterval(0.6))
        XCTAssertEqual(expansion.progress, 1, "the tap reopened the card")
        expansion.accessoryDragChanged(translationHeight: 700)
        expansion.accessoryDragEnded(predictedTranslationHeight: 800, verticalVelocity: 0)

        // Cú thu đầu kết thúc ở `rest`; cú thu thứ hai bắt đầu ở 0,6s và kết
        // thúc ở 0,6 + `rest` hoặc muộn hơn (sàn phần dư của cú mở bị cắt
        // ngang kéo dài nó). Kiểm ở giữa: sau `completion` cũ, trước
        // `completion` thật.
        let second = try releaseMilestones()
        RunLoop.main.run(until: first.addingTimeInterval((milestones.rest + 0.6 + second.rest) / 2))
        XCTAssertFalse(expansion.isCardResting,
                       "a stale completion rested the card in the middle of the last collapse")

        waitForRest(expansion)
        XCTAssertTrue(expansion.isCardResting)
    }

    /// Giảm chuyển động: nhánh ấy về nghỉ ngay, nên accessory hiện và thẻ ẩn
    /// trong cùng lượt — không cú lún, không cú hoà sang kính, không trạng
    /// thái "đang thu" nào treo lại.
    func testWithReduceMotionTheReleaseArrivesAtRestImmediately() throws {
        let expansion = try mountRestingCard(reduceMotion: true)

        expansion.accessoryDragChanged(translationHeight: -120)
        expansion.accessoryDragEnded(predictedTranslationHeight: -120, verticalVelocity: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertTrue(expansion.isCardResting)
        XCTAssertFalse(expansion.isCollapsing)
        XCTAssertTrue(expansion.showsAccessoryContent)
    }
}
