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

    /// The `async` overrides throughout this file are what carry the class's
    /// `@MainActor` into setup and teardown, and that is the whole reason they
    /// are `async` — nothing here awaits anything.
    ///
    /// The synchronous `setUp()`/`tearDown()` are nonisolated, and an override
    /// cannot add isolation the declaration it overrides does not have, so the
    /// `@MainActor` on each class here reaches every test method and stops at
    /// those two. That matters because `BottomBarStyle.reduceMotion` and
    /// `UIWindow` are both main-actor. XCTest also offers `async` versions, and
    /// those the compiler does let a `@MainActor` class isolate, so the access
    /// becomes checked rather than assumed. `MainActor.assumeIsolated` was the
    /// first attempt and does not work here: inside these overrides `self` is
    /// *task*-isolated, and handing it to a main-actor closure is the data race
    /// the compiler is describing rather than a formality to wave through.
    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        try await super.tearDown()
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
        XCTAssertEqual(BottomBarStyle.expand, .spring(duration: 0.36, bounce: 0.12))
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
        XCTAssertEqual(BottomBarStyle.expand, .easeInOut(duration: 0.26))
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
        // 0.10 → 0.033, qua hai bước. Hằng số 0.10 mâu thuẫn với chính phép đo
        // ghi ngay trên nó trong `BottomBarStyle` — "hai tới ba khung", tức
        // 0.033–0.05 giây ở 60fps; 0.10 là sáu khung. Đưa về 0.05 rồi nhìn
        // thật: ba khung vẫn còn đọc ra là nán lại, nên xuống 0.033 — hai
        // khung, đầu nhanh của khoảng đo, và là sàn.
        XCTAssertEqual(BottomBarStyle.queueContentOut, .easeIn(duration: 0.033))
        XCTAssertEqual(BottomBarStyle.queueTitleOut, .easeIn(duration: 0.06).delay(0.04))
        XCTAssertEqual(BottomBarStyle.queueTitleIn, .easeOut(duration: 0.10).delay(0.13))
    }

    // MARK: - Nhịp rụng của các tab, và bậc thu nhỏ của chrome

    /// Tab bên phải rời đi **trước**, và quay lại **sau**.
    ///
    /// Viên nang thu về phía trái, nên mép clip chạm tab phải trước. Cho nó mờ
    /// trước là cho cú mờ đi cùng chiều với cú clip. Bung ra thì ngược lại.
    ///
    /// Không có chốt này thì đảo hai chiều vẫn biên dịch, vẫn chạy, và sóng
    /// chạy ngược — thứ chỉ nhìn mới thấy.
    func testTheRightmostTabLeavesFirstAndReturnsLast() {
        let step = FloatingTabBar.tabCascadeStep
        XCTAssertEqual(step, 0.03, accuracy: 0.001)

        // Bốn tab, bậc 0…3. Thu: phải nhất (chỉ số 3) chạy ngay.
        let collapsingDelays = (0..<4).map { Double(3 - $0) * step }
        XCTAssertEqual(collapsingDelays.last, 0, "tab phải nhất không đợi ai")
        XCTAssertEqual(collapsingDelays.first, 3 * step, "tab trái nhất đợi lâu nhất")

        // Bung: đảo lại.
        let expandingDelays = (0..<4).map { Double($0) * step }
        XCTAssertEqual(expandingDelays.first, 0, "bung thì tab trái nhất tới trước")
        XCTAssertNotEqual(collapsingDelays, expandingDelays,
                          "hai chiều phải khác nhau — đó là cả điểm của nó")
    }

    /// Toàn dãy ngắn hơn hẳn đường cong nó cưỡi lên.
    ///
    /// 4 tab × 0.03 = 0.09s so với `content` 0.34s. Dài hơn thì tab cuối còn
    /// nằm đó khi viên nang đã đóng gần hết, và đợt sóng đọc ra thành bốn cú
    /// rời rạc.
    func testTheCascadeIsShorterThanTheCurveItRidesOn() {
        BottomBarStyle.reduceMotion = false
        let cascade = Double(LibraryTab.pillTabs.count - 1) * FloatingTabBar.tabCascadeStep
        XCTAssertLessThan(cascade, 0.34 / 3,
                          "dãy \(cascade)s phải ngắn hơn nhiều so với content 0.34s")
    }

    /// **Không tab nào đứng yên**, kể cả tab trái nhất.
    ///
    /// Bản đầu tỉ lệ thẳng theo chỉ số nên tab đầu nhận đúng 0 — và tab đầu là
    /// tab sống lâu nhất trong cú thu, vì viên nang clip từ phải sang. Thứ nhìn
    /// được lâu nhất lại đứng im, nên cú trượt gần như không tồn tại.
    func testEveryTabDriftsIncludingTheLeftmost() {
        BottomBarStyle.reduceMotion = false
        let base = FloatingTabBar.tabCascadeBaseFraction
        XCTAssertGreaterThan(base, 0, "tab trái nhất phải đi một quãng thật")
        XCTAssertLessThan(base, 1, "nhưng vẫn ít hơn tab phải nhất — hàng phải hội tụ")
    }

    /// Quãng trượt trái là chuyển động thật, nên giảm chuyển động bỏ nó.
    func testTheLeftwardDriftGoesToZeroWhenMotionIsReduced() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(FloatingTabBar.tabCascadeShift, 18, accuracy: 0.001)
        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(FloatingTabBar.tabCascadeShift, 0,
                       "quãng đường phải biến mất, không chỉ ngắn đi")
    }

    /// Nhưng **độ trễ** thì ở lại — nó là dàn cảnh, không phải chuyển động.
    ///
    /// Cùng lập luận với `queueTitleOut`: bỏ dàn cảnh đi không làm ai dễ nhìn
    /// hơn, nó chỉ làm bốn tab biến mất cùng lúc thành một mảng.
    func testTheCascadeTimingSurvivesReducedMotion() {
        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(FloatingTabBar.tabCascadeStep, 0.03, accuracy: 0.001)
    }

    /// Bậc thu nhỏ của chrome: có thật, và không xuống dưới ngưỡng chạm.
    ///
    /// Ba khối này là toàn bộ cách điều khiển app khi danh sách đang cuộn. Nút
    /// tìm cao 54pt; ngưỡng HIG là 44pt, nên hệ số không được kéo nó xuống dưới
    /// đó. 0.94 cho 50.8pt.
    func testTheCollapsedChromeShrinksButStaysTappable() {
        BottomBarStyle.reduceMotion = false
        let scale = BottomBarStyle.collapsedChromeScale
        XCTAssertEqual(scale, 0.94, accuracy: 0.001)
        XCTAssertLessThan(scale, 1, "phải thật sự nhỏ đi")
        XCTAssertGreaterThanOrEqual(BottomBarMetrics.tabBarHeight * scale, 44,
                                    "không được xuống dưới ngưỡng chạm HIG")
    }

    func testTheChromeShrinkGoesToZeroWhenMotionIsReduced() {
        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(BottomBarStyle.collapsedChromeScale, 1)
    }

    // MARK: - The distances that go to zero

    /// `recedeScale` is not a curve, it is a *distance*.
    ///
    /// **Nhánh thường giờ cũng là 1, và đó là một quyết định có số đo đứng
    /// sau** — xem doc của chính hằng số ấy. Cú thu nhỏ nền cắt cụt đáy danh
    /// sách trong lúc morph rồi trả lại chiều cao đầy trong một khung; đo trên
    /// video, dải y≈812–828 đi từ 7,27 lên 38,72 giữa hai khung liên tiếp.
    ///
    /// Test này vì thế đổi từ "hai nhánh khác nhau" sang "cả hai đều không
    /// thu nhỏ gì". Nó vẫn có việc để làm: nếu ai dựng lại chiều sâu ấy thì
    /// phải đi qua đây và đọc lý do nó bị bỏ, thay vì đổi một con số rồi phát
    /// hành lại đúng cú nháy cũ.
    func testNeitherBranchScalesTheContentBehindThePlayer() {
        BottomBarStyle.reduceMotion = false
        XCTAssertEqual(BottomBarStyle.recedeScale, 1)

        BottomBarStyle.reduceMotion = true
        XCTAssertEqual(BottomBarStyle.recedeScale, 1)
    }

    /// The constant is not the claim. The claim is that the screen behind the
    /// player does not move — so this renders the **production modifier** and
    /// looks at pixels.
    ///
    /// An earlier version of this test restated
    /// `1 - (1 - recedeScale) * progress` in the test body and asserted on
    /// that, which is a test of a copy: change the real `scaleEffect` in
    /// `RecedeBehindPlayer` and it stays green. This plan has already caught
    /// that defect once, in `SwiftUIOnChangeOrderingEvidenceTests`' own
    /// warning.
    ///
    /// `RecedeBehindPlayer` is `private` and stays private — the access level
    /// is not widened for the test's sake. The public entry point
    /// `recedesBehindPlayer(_:)` is what the app calls and is what is called
    /// here.
    ///
    /// The probe: a 100pt blue square centred in a 200pt red field. Receded by
    /// 0.92 it spans 54…146, so the column at x = 52 is red; unreceded it
    /// spans 50…150 and that same column is blue. One pixel answers the whole
    /// question, and it answers it about whatever transform the modifier
    /// actually applies rather than about arithmetic retyped here.
    func testTheContentBehindThePlayerNeverShrinksWhenMotionIsReduced() throws {
        BottomBarStyle.reduceMotion = true

        // Every progress, because a drag visits all of them and Reduce Motion
        // must not depend on which one it is interrupted at.
        for step in 0...10 {
            let progress = Double(step) / 10
            XCTAssertTrue(
                try isBlueAtTheUnrecededEdge(progress: progress),
                "the content shrank at progress \(progress) with Reduce Motion on"
            )
        }
    }

    /// …và với **thiết lập tắt** thì giờ cũng vậy.
    ///
    /// **Test này từng khẳng định điều ngược lại**, và nó đúng cho tới ngày
    /// 2026-08-19: nó ghim rằng nhánh thường *phải* thu nhỏ, đích danh để bắt
    /// "một nhánh làm phẳng cả hai chế độ". Cú thu nhỏ ấy đã bị bỏ, có số đo
    /// đứng sau — nó cắt cụt đáy danh sách trong lúc morph rồi trả lại chiều
    /// cao đầy trong một khung, dải y≈812–828 đi từ 7,27 lên 38,72 giữa hai
    /// khung liên tiếp trên máy thật. Xem doc của `BottomBarStyle.recedeScale`.
    ///
    /// Nên cái test này canh giờ đổi chiều: nó canh rằng lớp nội dung **không
    /// bao giờ** bị thu nhỏ, ở cả hai chế độ, ở mọi `progress`. Vẫn là một
    /// phép đo trên pixel của chính modifier sản phẩm, không phải trên một bản
    /// chép lại số học — nên dựng lại cú thu nhỏ bằng bất cứ đường nào cũng
    /// làm nó đỏ, và người làm việc ấy sẽ đọc được vì sao nó đã bị bỏ.
    func testTheContentBehindThePlayerNeverShrinksWithTheSettingOffEither() throws {
        BottomBarStyle.reduceMotion = false

        for step in 0...10 {
            let progress = Double(step) / 10
            XCTAssertTrue(
                try isBlueAtTheUnrecededEdge(progress: progress),
                "lớp nội dung bị thu nhỏ ở progress \(progress) khi Giảm chuyển động tắt"
            )
        }
    }

    /// Renders `recedesBehindPlayer(_:)` and reports whether the square still
    /// reaches the column only an unreceded square reaches.
    private func isBlueAtTheUnrecededEdge(progress: Double) throws -> Bool {
        let expansion = PlayerExpansion()
        expansion.progress = progress

        let probe = Color.blue
            .frame(width: 100, height: 100)
            .recedesBehindPlayer(expansion)
            .frame(width: 200, height: 200)
            .background(Color.red)

        let renderer = ImageRenderer(content: probe)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage, "ImageRenderer produced nothing")

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Draw the whole image shifted so that the pixel of interest — 52pt
        // across, halfway down — is the one that lands in the 1×1 context.
        context.draw(
            image,
            in: CGRect(x: -52, y: -100, width: CGFloat(image.width), height: CGFloat(image.height))
        )

        XCTAssertGreaterThan(Int(pixel[0]) + Int(pixel[2]), 100, "sampled neither red nor blue")
        return pixel[2] > pixel[0]
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

        // **The anchor, and this test ran without one.**
        //
        // "The two runs agree" is satisfied by four functions that all return
        // zero, or by three that were deleted and one that was stubbed. It says
        // the modes match; it does not say what they match *on*. Its sibling
        // `ReorderTuningFlatDurationTests` names this exact hole in its own doc
        // — "comparing two production values to each other says they agree;
        // only the literal says which number they agree on" — and then supplies
        // the literals. These are the literals for this one.
        //
        // One value from each of the four functions, chosen where the arithmetic
        // is doing something rather than passing something through:
        XCTAssertEqual(BottomBarStyle.maxSettleVelocity, 18, accuracy: 1e-9)
        // The collapsed card pays the full 10pt to disambiguate a tap; the open
        // one pays 2, because the tap it protects cannot fire past 0.5.
        XCTAssertEqual(PlayerCard.dragThreshold(progress: 0), 10)
        XCTAssertEqual(PlayerCard.dragThreshold(progress: 1), 2)
        // The threshold comes back out of the travel, and the clamp holds a
        // sideways-recognised drag at 0 instead of flipping its sign.
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: 37, threshold: 10), 27)
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: -37, threshold: 10), -27)
        XCTAssertEqual(PlayerCard.dragOffset(translationHeight: 2, threshold: 10), 0)
        // 420pt/s upward over 803pt of travel is 0.523 progress/s, and the
        // remaining distance from 0 to 1 is 1, so the spring is handed 0.523.
        XCTAssertEqual(
            PlayerCard.settleVelocity(verticalVelocity: -420, travel: 803, from: 0, to: 1),
            420.0 / 803.0,
            accuracy: 1e-9
        )
        // …and a flick fast enough to exceed the cap is capped, not obeyed.
        XCTAssertEqual(
            PlayerCard.settleVelocity(verticalVelocity: -3000, travel: 803, from: 0.95, to: 1),
            BottomBarStyle.maxSettleVelocity,
            accuracy: 1e-9
        )
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

    // `async` only to inherit the class's isolation: see the first `setUp` above.
    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        window?.isHidden = true
        window = nil
        try await super.tearDown()
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
        XCTAssertEqual(expansion.animation, .spring(duration: 0.36, bounce: 0.12))
    }
}

/// **What SwiftUI does with transactions** — the three behaviours B3's
/// cross-fade is built on, measured instead of reasoned about.
///
/// Everything below runs on `Harness`, declared in this file. None of it
/// imports a line of `PlayerCard`, and a green run here says nothing about the
/// player; what it says is whether the mechanism the player's
/// `morph(to:curve:)` leans on is the mechanism SwiftUI has. Same division of
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

    // `async` only to inherit the class's isolation: see the first `setUp` above.
    override func setUp() async throws {
        try await super.setUp()
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

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
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

    /// How much blue survives `.opacity(value)` over a red ground, 0…255.
    ///
    /// The same render-and-read-a-pixel technique
    /// `ReduceMotionTests.isBlueAtTheUnrecededEdge(progress:)` uses, for the
    /// same reason: what a modifier *does* is a question about pixels.
    /// The centre pixel of `ink` composited over a 40pt system-red ground,
    /// as `[R, G, B]`.
    ///
    /// System colours rather than pure primaries, deliberately: a pure ground
    /// has nothing in its other channels to subtract, so it cannot see the
    /// ghost a negative opacity paints. See
    /// `testViewOpacityClampsNegativesWhereColourOpacityDoesNot`, whose
    /// `ShapeStyle.opacity` half is the one that needs the channels.
    ///
    /// (This pointed at `testANegativeOpacityIsNotInvisibleButPaintsAnInvertedGhost`
    /// until that test was removed in B3's revert. The reasoning it carried
    /// survived into the test named above; only the name was left dangling.)
    private func pixel<Ink: View>(of ink: Ink) throws -> [Int] {
        let probe = ink
            .frame(width: 40, height: 40)
            .background(Color.red)

        let renderer = ImageRenderer(content: probe)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage, "ImageRenderer produced nothing")

        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(
            image,
            in: CGRect(x: -20, y: -20, width: CGFloat(image.width), height: CGFloat(image.height))
        )
        return [Int(bytes[0]), Int(bytes[1]), Int(bytes[2])]
    }

    func testWithAnimationDrivesIntermediateValues() throws {
        let apply = try XCTUnwrap(Trace.apply)
        Trace.reset()

        apply(0, .easeInOut(duration: 0.2))
        // 0.7, not 0.3, and the assertions below are untouched.
        //
        // This was 0.3 against a 0.2s curve — 0.1s of margin — and it flaked:
        // roughly one run in two, `rendered.last` came back at 0.0043 instead of
        // 0, i.e. the animation was still a hair off its target when the pump
        // returned. `RunLoop.run(until:)` gives no guarantee about how many
        // display links it services, so the margin has to be generous rather
        // than tight. 0.7 is what the sibling at
        // `testASecondFadeArrivingMidFadeIsNeverPartiallyVisible` already uses
        // for the same reason.
        //
        // The two `nil`-animation cases below keep 0.3: there is no curve there
        // to settle, and their claim is that nothing was interpolated at all.
        pump(0.7)

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
        // 0.7 chứ không phải 0.3, cùng lý do đã ghi ở
        // `testAClearedValueIsNeverDrawnAtItsOldOne`: `RunLoop.run(until:)`
        // không hứa phục vụ bao nhiêu display link, nên biên phải rộng tay chứ
        // không sát. Với 0.3 — gấp 1,5 lần một curve 0,2s — test này đỏ hai lần
        // trong các lượt chạy suite đầy đủ ngày 2026-08-19, ở 0,9973 và 0,9934
        // so với ngưỡng 1,0 ± 0,001, trong khi chạy riêng thì xanh 3/3. Đó là
        // run loop bị 500 test chạy trước bỏ đói, không phải cú hoà mờ hỏng.
        // Assertion không đổi một chữ: nó vẫn đòi curve chạy tới đúng 1,0.
        pump(0.7)

        XCTAssertEqual(Trace.interpolated.first ?? -1, 0, accuracy: 0.001)
        XCTAssertFalse(
            between(Trace.interpolated).isEmpty,
            "the fade did not run; trace: \(Trace.interpolated)"
        )
        XCTAssertEqual(Trace.interpolated.last ?? -1, 1, accuracy: 0.001)
    }

    /// One fade interrupted by a second one, `interruptAfter` seconds in.
    /// Returns the last value rendered before the interruption and everything
    /// rendered from the interruption onward.
    private func dipDuringDip(interruptAfter: TimeInterval) throws -> (before: Double, after: [Double]) {
        let dip = try XCTUnwrap(Trace.dip)
        Trace.reset()

        dip(.easeInOut(duration: 0.5))
        pump(interruptAfter)
        let mark = Trace.interpolated.count
        XCTAssertGreaterThan(mark, 0, "the first fade never started")
        let before = try XCTUnwrap(Trace.interpolated.last)

        dip(.easeInOut(duration: 0.5))
        pump(0.7)

        return (before, Array(Trace.interpolated[mark...]))
    }

    /// **A second morph arriving mid-fade, which is reachable in the app**:
    /// `collapse()` fires from `onChange(of: playback.currentTrack?.id)` and
    /// can land while an `expand()` fade is still running.
    ///
    /// The worry was that SwiftUI would treat the second dip as a no-op —
    /// state is already 1, so writing 0 and then 1 changes nothing that
    /// update — keep the animation already in flight, and leave the card at a
    /// *partial* opacity at the instant the geometry jumps. That would put the
    /// jump on screen, which is the one thing this feature exists to prevent.
    ///
    /// It does not happen, and the reason is worth having in writing because
    /// it is not what either prediction expected. SwiftUI's animations are
    /// **additive**: dropping the state by 1 while an animation is in flight
    /// moves the presented value down by a full 1.0 rather than being ignored.
    /// Measured at two different interruption points, the value at the moment
    /// of the second dip is `previous - 1.0` to three decimals — and since the
    /// running fade can never have presented more than 1, that difference is
    /// **always at or below 0**. Opacity clamps there, so the card is fully
    /// invisible at the instant the geometry jumps, at every interruption
    /// point, not just the two sampled here.
    ///
    /// What it costs is real but small, and it is a blank, not a jump: the
    /// recovery starts from below zero, so an interrupted morph stays
    /// invisible longer than a fresh one before it begins to show. Recorded
    /// rather than fixed — the fix is the two-phase version with a
    /// cancellation token, and that trades a longer blank for a state in which
    /// a dropped completion leaves the player invisible for good.
    func testASecondFadeArrivingMidFadeIsNeverPartiallyVisible() throws {
        for interruptAfter in [0.1, 0.3] {
            let (before, after) = try dipDuringDip(interruptAfter: interruptAfter)
            let first = try XCTUnwrap(after.first)

            XCTAssertLessThanOrEqual(
                first, 0,
                "interrupted at \(interruptAfter)s: the card was \(first) visible when the geometry jumped"
            )
            XCTAssertEqual(
                first, before - 1, accuracy: 0.001,
                "interrupted at \(interruptAfter)s: expected the additive drop; trace \(after)"
            )
            XCTAssertEqual(
                after.last ?? -1, 1, accuracy: 0.001,
                "interrupted at \(interruptAfter)s: did not recover to fully visible; trace \(after)"
            )
        }
    }

    /// **The last link of the argument, which was reasoning until round 2.**
    ///
    /// The chain is: the geometry jumps → the presented opacity at that
    /// instant is at or below 0 → therefore nothing of the card is on screen.
    /// The first two links are traced above. The third was assumed, and this
    /// closes it: `View.opacity` clamps a negative to fully transparent, so a
    /// presented `-0.915` renders as exactly the ground.
    ///
    /// **And a trap sitting right next to it, which this test exists as much
    /// to record as the clamp itself.** `ShapeStyle.opacity` —
    /// `Color.blue.opacity(x)`, the identically-named method on `Color` — does
    /// *not* clamp. It multiplies the colour's own alpha, and a negative alpha
    /// composites subtractively: `ground + a·(ink − ground)`, clamped per
    /// channel afterwards, which paints an inverted ghost. On this ground that
    /// is `[255, 56, 60]` coming out as `[255, 0, 0]`.
    ///
    /// The first version of this measurement used `Color.blue.opacity(v)` and
    /// concluded that a negative opacity paints a ghost in production. It does
    /// not: `cardOpacity` is applied with `View.opacity`, to a whole view tree,
    /// which is the clamping one. A `ClampedOpacity` modifier was written to
    /// fix the phantom defect, shipped into `PlayerCard`, and reverted once the
    /// probe was split in two — the mutation check caught it by **surviving**,
    /// which is the only reason it was caught at all.
    ///
    /// So the ordering of these assertions is the point: same value, same
    /// ground, two spellings, two different results.
    func testViewOpacityClampsNegativesWhereColourOpacityDoesNot() throws {
        let ground = try pixel(of: Color.blue.opacity(0))

        // `View.opacity` — what `PlayerCard` applies to `cardOpacity`.
        XCTAssertEqual(
            try pixel(of: Color.blue.frame(width: 40, height: 40).opacity(-0.915)),
            ground,
            "View.opacity did not clamp a negative; an interrupted morph would show its jump"
        )
        XCTAssertEqual(
            try pixel(of: Color.blue.frame(width: 40, height: 40).opacity(-1)),
            ground
        )

        // `ShapeStyle.opacity` — the same word, a different operation.
        //
        // **Two assertions on one value, and they are not the same assertion.**
        // The second is the claim — a negative alpha paints *something*, and
        // whatever it is, it is not the ground — and it says so without naming
        // a channel, so it survives any renderer. The first pins the exact
        // triple, and its job is different: `[255, 0, 0]` is quoted verbatim in
        // `PlayerCard.morph(to:curve:)`'s doc comment as a measurement, and a
        // measurement quoted in production prose with nothing executing it is
        // how the other findings in this round happened. Keeping only the
        // second would leave that number unpinned; keeping only the first would
        // make the claim hostage to a device's colour handling.
        XCTAssertEqual(try pixel(of: Color.blue.opacity(-0.915)), [255, 0, 0])
        XCTAssertNotEqual(try pixel(of: Color.blue.opacity(-0.915)), ground)

        // Above zero the two agree, so what differs above is the handling of
        // the sign and not the two spellings differing everywhere.
        XCTAssertEqual(
            try pixel(of: Color.blue.frame(width: 40, height: 40).opacity(0.5)),
            try pixel(of: Color.blue.opacity(0.5))
        )
    }

    /// **The precondition the interrupted-morph invariant depends on, and it
    /// is not written down anywhere else.**
    ///
    /// "The additive drop always lands at or below 0" holds because a running
    /// fade never presents *above* its target of 1. That is a property of the
    /// curve, not of the mechanism: `PlayerCard.morph(to:curve:)` takes any
    /// `Animation`, and a curve that overshoots would present above 1
    /// mid-flight, put the additive drop at a **positive** value, and show the
    /// geometry jump — the exact failure the feature exists to prevent.
    ///
    /// So: the two curves that can actually reach that call in reduced mode
    /// are measured here for overshoot, rather than trusted. The control at
    /// the end is a bouncy spring, which the same probe must catch overshooting
    /// — without it this test would pass against a harness that had stopped
    /// recording.
    func testTheCurvesTheReducedMorphRunsOnNeverPresentAboveTheirTarget() throws {
        let apply = try XCTUnwrap(Trace.apply)
        let saved = BottomBarStyle.reduceMotion
        defer { BottomBarStyle.reduceMotion = saved }
        BottomBarStyle.reduceMotion = true

        func peak(of animation: Animation) -> Double {
            apply(0, nil)
            pump(0.05)
            Trace.reset()
            apply(1, animation)
            pump(0.9)
            return Trace.interpolated.max() ?? .nan
        }

        // Every curve `morph(to:curve:)` can be handed with the setting on:
        // `expand()` and `collapse()` pass `BottomBarStyle.expand`, and the
        // drag's release passes `settle(initialVelocity:)` — whose reduced
        // branch drops the velocity, so the extremes are the same curve.
        for (name, animation) in [
            ("expand", BottomBarStyle.expand),
            ("settle(0)", BottomBarStyle.settle(initialVelocity: 0)),
            ("settle(max)", BottomBarStyle.settle(initialVelocity: BottomBarStyle.maxSettleVelocity)),
        ] {
            XCTAssertLessThanOrEqual(
                peak(of: animation), 1.0001,
                "\(name) presented above its target; an interrupted morph would show the jump"
            )
        }

        XCTAssertGreaterThan(
            peak(of: .spring(duration: 0.38, bounce: 0.34)), 1.0001,
            "the probe did not catch a spring overshooting, so it cannot catch one here either"
        )
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
        ("expand", 0.36, 0.12, 0.26),
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
            // `continue`, not `return XCTFail(…)`.
            //
            // `XCTFail` returns `Void`, so `return XCTFail(…)` is a legal way to
            // spell "fail and leave" — and it leaves the *method*, not the
            // iteration. The first spring that missed 98% therefore silently
            // skipped the other six, and the report would name one failure where
            // there might be seven. A table-driven test that stops at the first
            // row is a table-driven test in name only.
            guard let crossing else {
                XCTFail("\(spring.name) never reached 98%")
                continue
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

        // **6.2 times apart, and the prose used to say ten.**
        //
        // The ten is real but belongs elsewhere: it is the old *quoted* figure
        // ("four hundredths") against `selection`'s true 0.4006%. The two
        // constants themselves are 0.4006 / 0.0644 = 6.22 apart, which is what
        // this assertion has always executed — so for a while the comment block
        // written to fix a factor-of-ten error carried a second one, and the
        // prose and the assertion below disagreed. Corrected in both places;
        // `BottomBarStyle`'s block carries the same paragraph.
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

    // `async` only to inherit the class's isolation: see the first `setUp` above.
    override func setUp() async throws {
        try await super.setUp()
        saved = BottomBarStyle.reduceMotion
    }

    override func tearDown() async throws {
        BottomBarStyle.reduceMotion = saved
        try await super.tearDown()
    }

    /// Everything `EvenstarApp.body` supplies, with the two I/O boundaries
    /// mocked. `RootView` reads `PlaybackService` itself; the rest are read by
    /// the screens inside its `TabView`, and a missing one is a crash on
    /// render rather than a compile error, so they are all here.
    private func renderRootView(reduceMotion injected: Bool) throws {
        // Hai kho, như app — xem `InMemoryLibrary`.
        let container = try InMemoryLibrary.makeContainer()
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
