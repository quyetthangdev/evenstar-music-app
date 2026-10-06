import XCTest
import SwiftUI
@testable import Evenstar

/// Cuối cú thu: thẻ thành **kính**, **lún quá chỗ ~10pt rồi nảy lại**, rồi mới
/// nhường cho accessory — như Apple Music.
///
/// Lỗi QA trên máy (iPhone 12, Release, sau `fbc0837`): thẻ thu khít lên viên
/// kính rồi đứng chết và mờ đi — "mất hiệu ứng đàn hồi, cứng". Bản trước nữa
/// thì tệ theo cách khác: thẻ đặc đứng ~300ms trên viên kính rồi nhảy màu.
///
/// Các nhóm test ở đây ghim những phần **không phụ thuộc đồng hồ**: đường cong
/// cửa sổ kính, phép đổi cú vọt qua ra điểm, chính lò xo của cú thu (hỏi thẳng
/// `CollapseSpring` bằng `Spring.value`, không chạy animation), các cờ của
/// `PlayerExpansion`, và việc thẻ thật nối chúng lại đúng. Cú lún **vẽ ra**
/// thật — mép thẻ, chiều cao, độ trong — được đo từng khung ở
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

    // MARK: - Cú vọt qua đổi ra điểm

    func testNothingMovesUntilTheLandingPassesZero() {
        XCTAssertEqual(PlayerCard.landingOffset(overshoot: 0, travel: 710), 0)
        XCTAssertEqual(PlayerCard.landingOffset(overshoot: -0.3, travel: 710), 0)
    }

    /// Độ dốc 1 ở 0: ngay sau khi chạm đích, mép trên thẻ đi tiếp đúng tốc độ
    /// nó đang đi — `travel` điểm cho mỗi đơn vị `progress`.
    func testTheTopEdgeKeepsItsSpeedAcrossTheTarget() {
        let tiny = 0.0005
        let offset = PlayerCard.landingOffset(overshoot: tiny, travel: 710)
        XCTAssertEqual(offset / CGFloat(tiny * 710), 1, accuracy: 0.001)
    }

    func testTheLandingIsCapped() {
        var previous: CGFloat = 0
        for overshoot in stride(from: 0.0, through: 0.2, by: 0.005) {
            let offset = PlayerCard.landingOffset(overshoot: overshoot, travel: 710)
            XCTAssertGreaterThanOrEqual(offset, previous, "monotonic")
            XCTAssertLessThanOrEqual(offset, PlayerCard.landingCap)
            previous = offset
        }
        XCTAssertGreaterThan(previous, PlayerCard.landingCap - 0.5, "a deep overshoot reaches the cap")
    }

    // MARK: - Lò xo của cú thu

    /// Dựng lại đúng đường cong mà `BottomBarStyle.collapse` giao cho thẻ, và
    /// đi nó từng mili giây.
    private struct Run {
        /// Thời điểm hình học chạm đích, tức lúc nó kết thúc.
        var crossing: Double?
        /// Phần vọt qua sâu nhất của `landing`, đơn vị phần quãng đường.
        var deepest = 0.0
        var deepestAt = 0.0
        /// Lúc `landing` quay về trên đích sau cú lún.
        var back: Double?
        /// Lúc `landing` coi như lắng — thẻ về nghỉ.
        var settled = 0.0
        /// Phần lệch còn lại ở lúc ấy.
        var residual = 0.0
        var geometryEverPassedTarget = false
        var formsDisagreedBeforeTheCrossing = false
    }

    private func run(afterDrag: Bool, velocity: Double) -> Run {
        let spring = BottomBarStyle.collapseSpring(afterDrag: afterDrag)
        let geometry = CollapseSpring(spring: spring, initialVelocity: velocity, stopsAtTarget: true)
        let landing = CollapseSpring(spring: spring, initialVelocity: velocity, stopsAtTarget: false)
        var out = Run()
        var time = 0.0
        while let f = landing.fraction(at: time) {
            if let g = geometry.fraction(at: time) {
                if g > 1 { out.geometryEverPassedTarget = true }
                if abs(g - f) > 1e-12 { out.formsDisagreedBeforeTheCrossing = true }
            } else if out.crossing == nil {
                out.crossing = time
            }
            if f - 1 > out.deepest { out.deepest = f - 1; out.deepestAt = time }
            out.residual = abs(f - 1)
            out.settled = time
            time += 0.001
        }
        // Lúc quay về hỏi thẳng lò xo, vì cú đáp có thể đã coi là lắng ngay
        // trước đó — phần còn lệch đã dưới `settleEpsilon`.
        time = out.deepestAt
        while time < 2 {
            if spring.value(target: 1.0, initialVelocity: velocity, time: time) <= 1 {
                out.back = time
                break
            }
            time += 0.001
        }
        return out
    }

    /// iPhone 12: mép trên viên kính ~710pt từ đỉnh màn hình.
    private let travel: CGFloat = 710

    private func landingPoints(_ run: Run, from start: Double) -> CGFloat {
        PlayerCard.landingOffset(overshoot: run.deepest * start, travel: travel)
    }

    func testTheGeometryStopsAtItsTargetAndNeverPastIt() {
        for afterDrag in [false, true] {
            for velocity in [0, 3, 8, BottomBarStyle.maxSettleVelocity, -4] {
                let r = run(afterDrag: afterDrag, velocity: velocity)
                XCTAssertFalse(r.geometryEverPassedTarget, "afterDrag \(afterDrag) v \(velocity)")
                XCTAssertNotNil(r.crossing, "the geometry has to arrive, afterDrag \(afterDrag) v \(velocity)")
                XCTAssertFalse(r.formsDisagreedBeforeTheCrossing,
                               "the two forms are one spring until the geometry stops")
            }
        }
    }

    /// Cú lún bắt đầu **đúng** lúc hình học chạm đích — không có khoảng đứng
    /// nào giữa hai thứ để đoán.
    func testTheLandingStartsExactlyWhereTheGeometryStops() throws {
        let r = run(afterDrag: true, velocity: 3)
        let crossing = try XCTUnwrap(r.crossing)
        let spring = BottomBarStyle.collapseSpring(afterDrag: true)
        let landing = CollapseSpring(spring: spring, initialVelocity: 3, stopsAtTarget: false)
        let justAfter = try XCTUnwrap(landing.fraction(at: crossing + 0.001))
        XCTAssertGreaterThanOrEqual(justAfter, 1)
        XCTAssertLessThan(justAfter - 1, 0.001, "and it starts from the target, not from a jump")
    }

    /// Cú chạm (`collapse()`, lúc bài về nil): trọn quãng, từ đứng yên.
    func testATapCollapseLandsAboutTenPointsDown() {
        let r = run(afterDrag: false, velocity: 0)
        let points = landingPoints(r, from: 1)
        XCTAssertGreaterThanOrEqual(points, 8, "\(points)pt")
        XCTAssertLessThanOrEqual(points, 12, "\(points)pt")
    }

    /// Cú thu thường ngày: vuốt thẻ đang mở xuống một đoạn rồi buông theo đà.
    func testAnEverydayDragReleaseLandsAboutTenPointsDown() {
        let start = 0.9
        let velocity = PlayerCard.settleVelocity(verticalVelocity: 1900, travel: travel,
                                                 from: start, to: 0)
        let r = run(afterDrag: true, velocity: velocity)
        let points = landingPoints(r, from: start)
        XCTAssertGreaterThanOrEqual(points, 8, "\(points)pt at relative velocity \(velocity)")
        XCTAssertLessThanOrEqual(points, 12, "\(points)pt at relative velocity \(velocity)")
    }

    /// Apple Music: lún ~132–200ms, nảy về tới ~500ms. Spec: "roughly 300 ms".
    func testTheDipAndReturnTakeRoughlyThreeHundredMilliseconds() throws {
        for afterDrag in [false, true] {
            let r = run(afterDrag: afterDrag, velocity: 0)
            let crossing = try XCTUnwrap(r.crossing)
            let back = try XCTUnwrap(r.back)
            let lobe = back - crossing
            XCTAssertGreaterThanOrEqual(lobe, 0.25, "afterDrag \(afterDrag): \(lobe)s")
            XCTAssertLessThanOrEqual(lobe, 0.40, "afterDrag \(afterDrag): \(lobe)s")
            XCTAssertLessThan(r.deepestAt - crossing, lobe / 2,
                              "down fast, back slower — the deepest point is in the first half")
        }
    }

    func testAHarderFlickLandsDeeperButNeverPastTheCap() {
        let gentle = landingPoints(run(afterDrag: true, velocity: 0), from: 1)
        let hard = landingPoints(run(afterDrag: true, velocity: BottomBarStyle.maxSettleVelocity), from: 1)
        XCTAssertGreaterThan(hard, gentle + 2)
        XCTAssertLessThanOrEqual(hard, PlayerCard.landingCap)
    }

    /// Cú chạm từ một thẻ gần như đã đóng thì gần như không lún — đà tỉ lệ với
    /// quãng còn lại, như một vật thật.
    func testAShortCollapseBarelyDips() {
        let points = landingPoints(run(afterDrag: true, velocity: 0), from: 0.1)
        XCTAssertLessThan(points, 2)
    }

    /// Thẻ chỉ về nghỉ — và nhường cho accessory — khi cú nảy đã lắng tới mức
    /// một cú trao tay không còn lộ ra thành cú nhích: từ đó trở đi lò xo
    /// không bao giờ lệch quá nửa điểm nữa.
    func testTheHandoffWaitsUntilTheBounceHasSettled() throws {
        for afterDrag in [false, true] {
            for velocity in [0, 3, BottomBarStyle.maxSettleVelocity] {
                let r = run(afterDrag: afterDrag, velocity: velocity)
                let label = "afterDrag \(afterDrag) v \(velocity)"
                XCTAssertGreaterThan(r.settled, r.deepestAt + 0.1, "well into the return, \(label)")
                XCTAssertLessThan(r.settled, 0.75, "and it does not hang on for ever, \(label)")
                let spring = BottomBarStyle.collapseSpring(afterDrag: afterDrag)
                var worst = 0.0
                var time = r.settled
                while time < 2 {
                    worst = max(worst, abs(spring.value(target: 1.0, initialVelocity: velocity, time: time) - 1))
                    time += 0.001
                }
                XCTAssertLessThan(CGFloat(worst) * travel, 0.5, label)
            }
        }
    }

    func testTheCurvesHandedToTheCardAreThoseSprings() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = false

        let curves = BottomBarStyle.collapse(initialVelocity: 4, afterDrag: true)
        let spring = BottomBarStyle.collapseSpring(afterDrag: true)
        XCTAssertEqual(curves.geometry,
                       Animation(CollapseSpring(spring: spring, initialVelocity: 4, stopsAtTarget: true)))
        XCTAssertEqual(curves.landing,
                       Animation(CollapseSpring(spring: spring, initialVelocity: 4, stopsAtTarget: false)))
        XCTAssertEqual(BottomBarStyle.collapseSpring(afterDrag: false),
                       Spring(duration: 0.36, bounce: BottomBarStyle.landingBounce),
                       "a tap keeps the tempo of `expand`")
        XCTAssertEqual(spring, Spring(duration: 0.42, bounce: BottomBarStyle.landingBounce),
                       "a release keeps the tempo of `settle`")
    }

    /// Giảm chuyển động: không lún, không vận tốc — nhánh phẳng của chính lối
    /// vào ấy, cho cả hai nửa.
    func testWithReduceMotionThereIsNoLandingAtAll() {
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = true

        let release = BottomBarStyle.collapse(initialVelocity: 9, afterDrag: true)
        XCTAssertEqual(release.geometry, .easeInOut(duration: 0.29))
        XCTAssertEqual(release.landing, release.geometry)
        let tap = BottomBarStyle.collapse(afterDrag: false)
        XCTAssertEqual(tap.geometry, .easeInOut(duration: 0.26))
        XCTAssertEqual(tap.landing, tap.geometry)
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

    /// Kéo accessory lên rồi thả: cú thả rơi về 0, `PlayerCard.handle` gọi
    /// `morph(to: 0…)`. Suốt lò xo **và** cú nảy, thẻ đang thu và accessory
    /// vẫn ẩn; chỉ khi cú nảy lắng thẻ mới về nghỉ.
    ///
    /// 0,4s nằm giữa hai mốc với biên rộng cả hai phía: hình học chạm đích ở
    /// ~0,26s, cú nảy lắng ở ~0,65s (`settle` 0.42, bounce 0.22). Bản trước
    /// về nghỉ theo `completion` của hình học, tức đã nghỉ ở mốc này.
    func testAReleaseThatFallsBackRestsOnlyAfterTheBounce() throws {
        let expansion = try mountRestingCard(reduceMotion: false)

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

        RunLoop.main.run(until: released.addingTimeInterval(0.4))
        XCTAssertFalse(expansion.isCardResting, "the geometry has arrived but the bounce is still running")
        XCTAssertFalse(expansion.showsAccessoryContent)

        let deadline = Date().addingTimeInterval(3)
        while !expansion.isCardResting, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(expansion.isCardResting)
        XCTAssertFalse(expansion.isCollapsing)
        XCTAssertTrue(expansion.showsAccessoryContent)
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
