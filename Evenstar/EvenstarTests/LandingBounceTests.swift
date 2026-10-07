import XCTest
import SwiftUI
@testable import Evenstar

/// Cú hạ cánh như Apple Music (spec, Phần 1, bổ sung 2026-10-07): tới viên
/// thuốc ~300ms, cả thẻ lún cứng ~8pt sâu nhất ~50ms sau đó, về lại chỗ nghỉ
/// ~230ms sau lúc chạm — đúng một nhịp. Hỏi thẳng `LandingBounce`, không chạy
/// animation; cú lún **vẽ ra** thật được đo ở `CollapseFrameTests`.
final class LandingBounceTests: XCTestCase {
    /// iPhone 12: màn 390×844, viên kính (21, 705, 348, 48) — tâm thẻ đi 307pt.
    private let anchor = PlayerAnchor(frame: CGRect(x: 21, y: 705, width: 348, height: 48),
                                      screen: CGSize(width: 390, height: 844))

    private func tap() throws -> LandingBounce {
        try XCTUnwrap(LandingBounce(initialVelocity: 0, span: 1, centerTravel: Double(anchor.centerTravel)))
    }

    private func peak(of bounce: LandingBounce) -> (time: Double, depth: Double) {
        stride(from: 0.0, through: bounce.duration + 0.2, by: 0.0005)
            .map { (time: $0, depth: bounce.offset(at: $0)) }
            .max { $0.depth < $1.depth }!
    }

    func testTheCentreTravelsWhatTheCardFrameSays() {
        XCTAssertEqual(anchor.centerTravel, 307, accuracy: 0.5)
    }

    func testATapArrivesInAboutThreeHundredMillisecondsAndSinksAboutEightPoints() throws {
        let bounce = try tap()
        let deepest = peak(of: bounce)
        print(String(format: "[landing] arrival %.0fms, deepest %.2fpt at %.0fms (+%.0fms), back at %.0fms (+%.0fms), v %.0fpt/s",
                     bounce.arrival * 1000, deepest.depth, deepest.time * 1000,
                     (deepest.time - bounce.arrival) * 1000, bounce.duration * 1000,
                     (bounce.duration - bounce.arrival) * 1000, bounce.velocity))
        XCTAssertEqual(bounce.arrival, 0.30, accuracy: 0.03, "Apple reaches the pill ~300ms in")
        XCTAssertEqual(deepest.depth, 8, accuracy: 1, "Apple sinks ~8pt")
        XCTAssertEqual(deepest.depth, bounce.depth, accuracy: 0.05)
        XCTAssertEqual(deepest.time - bounce.arrival, 0.05, accuracy: 0.012, "deepest ~50ms after arrival")
        XCTAssertEqual(bounce.duration - bounce.arrival, 0.23, accuracy: 0.015, "back at rest ~230ms after arrival")
        XCTAssertEqual(bounce.duration, 0.53, accuracy: 0.04, "Apple is still again at ~530ms")
    }

    /// Đúng một nhịp: trước khi chạm và sau khi về, độ lún đúng bằng 0; giữa
    /// hai mốc chỉ đi xuống rồi đi lên, không bao giờ lên quá chỗ nghỉ.
    func testThereIsExactlyOneBounceAndItEndsExactlyAtRest() throws {
        let bounce = try tap()
        XCTAssertEqual(bounce.offset(at: 0), 0)
        XCTAssertEqual(bounce.offset(at: bounce.arrival - 0.001), 0)
        XCTAssertEqual(bounce.offset(at: bounce.duration), 0, "exactly at rest when the bounce ends")
        for time in stride(from: bounce.duration, through: bounce.duration + 1, by: 0.01) {
            XCTAssertEqual(bounce.offset(at: time), 0, "a second overshoot at \(time)s")
        }
        let deepest = peak(of: bounce).time
        var previous = 0.0
        for time in stride(from: bounce.arrival, to: bounce.duration, by: 0.002) {
            let depth = bounce.offset(at: time)
            XCTAssertGreaterThanOrEqual(depth, 0, "rose above rest at \(time)s")
            defer { previous = depth }
            guard abs(time - deepest) > 0.002 else { continue }
            if time < deepest {
                XCTAssertGreaterThanOrEqual(depth, previous - 1e-9, "went back up early at \(time)s")
            } else {
                XCTAssertLessThanOrEqual(depth, previous + 1e-9, "sank again at \(time)s")
            }
        }
    }

    /// Liền vận tốc: cú lún bắt đầu với đúng vận tốc của tâm thẻ lúc chạm đích.
    func testTheBounceStartsAtTheCardsOwnSpeed() throws {
        let bounce = try tap()
        let approach = LandingBounce.approachSpring
        let fraction = approach.velocity(target: 1.0, initialVelocity: 0, time: bounce.arrival)
        XCTAssertEqual(bounce.velocity, fraction * Double(anchor.centerTravel), accuracy: 1)
        let h = 0.0005
        let start = (bounce.offset(at: bounce.arrival + h) - bounce.offset(at: bounce.arrival)) / h
        XCTAssertEqual(start, bounce.velocity, accuracy: bounce.velocity * 0.05)
        // …và hình học thật sự tới đích ở đó: lò xo tiếp cận chạm 1 lần đầu.
        XCTAssertLessThan(approach.value(target: 1.0, initialVelocity: 0, time: bounce.arrival - 0.001), 1)
        XCTAssertGreaterThanOrEqual(approach.value(target: 1.0, initialVelocity: 0, time: bounce.arrival), 1)
    }

    /// Một cú búng lún sâu hơn một chút, và không bao giờ quá `maxDepth`.
    func testAFlickSinksDeeperButNeverPastTheCap() throws {
        let tapDepth = try tap().depth
        let flick = try XCTUnwrap(LandingBounce(initialVelocity: 3, span: 1, centerTravel: Double(anchor.centerTravel)))
        XCTAssertGreaterThan(flick.depth, tapDepth)
        let hard = try XCTUnwrap(LandingBounce(initialVelocity: 18, span: 1, centerTravel: Double(anchor.centerTravel)))
        XCTAssertEqual(hard.depth, LandingBounce.maxDepth, accuracy: 0.01)
        XCTAssertLessThanOrEqual(peak(of: hard).depth, LandingBounce.maxDepth + 0.01)
        XCTAssertEqual(LandingBounce.maxDepth, 12)
    }

    /// Thả gần viên thuốc: quãng ngắn, vận tốc nhỏ — lún ít, không lún ngược.
    func testAShortCollapseSinksLittle() throws {
        let short = try XCTUnwrap(LandingBounce(initialVelocity: 0, span: 0.05, centerTravel: Double(anchor.centerTravel)))
        XCTAssertLessThan(short.depth, 1)
        XCTAssertGreaterThanOrEqual(short.depth, 0)
        XCTAssertNil(LandingBounce(initialVelocity: 0, span: 0, centerTravel: 307))
        XCTAssertNil(LandingBounce(initialVelocity: 0, span: 1, centerTravel: 0))
    }

    /// Từ lúc chạm (hay nhấc tay) tới hết cú trao tay: không quá ~0,8s, kể cả
    /// cú hiện lại của viên kính.
    func testTheWholeLandingAndHandoffFitInPointEight() throws {
        for velocity in [0.0, 3, 18] {
            let bounce = try XCTUnwrap(LandingBounce(initialVelocity: velocity, span: 1,
                                                     centerTravel: Double(anchor.centerTravel)))
            let end = bounce.handoff + BottomBarStyle.capsuleReturnDuration + BottomBarStyle.collapseHandoffDuration
            // Cú trao tay bắt đầu khi thẻ đã về trong nửa điểm, và lúc nó xong
            // thẻ đã về hẳn.
            XCTAssertLessThanOrEqual(bounce.offset(at: bounce.handoff), LandingBounce.restTolerance)
            XCTAssertLessThan(bounce.handoff, bounce.duration)
            XCTAssertLessThanOrEqual(bounce.duration, bounce.handoff + BottomBarStyle.capsuleReturnDuration,
                                     "still sinking when the handoff fade begins, v \(velocity)")
            print(String(format: "[landing] v %.0f: arrival %.0fms, handoff from %.0fms, still %.0fms, handoff ends %.0fms, depth %.1fpt",
                         velocity, bounce.arrival * 1000, bounce.handoff * 1000, bounce.duration * 1000,
                         end * 1000, bounce.depth))
            XCTAssertLessThanOrEqual(end, 0.8, "v \(velocity)")
        }
    }

    /// Hai lò xo đúng như đã chọn, và cú lún dùng chính `Spring` của SwiftUI —
    /// so với nghiệm giải tích e^(−ζωt)·sin(ω_d·t)/ω_d để chắc `value(target: 0…)`
    /// đúng là đáp ứng xung.
    func testTheSpringsAreTheChosenOnesAndTheBounceIsAnImpulseResponse() {
        XCTAssertEqual(LandingBounce.approachSpring, Spring(duration: 0.6, bounce: 0.33))
        XCTAssertEqual(LandingBounce.spring, Spring(duration: 0.29, bounce: 0.22))
        let zeta = 1 - 0.22, omega = 2 * Double.pi / 0.29, damped = omega * (1 - zeta * zeta).squareRoot()
        for time in stride(from: 0.0, to: 0.25, by: 0.01) {
            let analytic = exp(-zeta * omega * time) * sin(damped * time) / damped
            XCTAssertEqual(LandingBounce.spring.value(target: 0.0, initialVelocity: 1, time: time), analytic,
                           accuracy: 1e-4, "t \(time)")
        }
    }

    /// Cú thu có hạ cánh dùng lò xo tiếp cận, dừng ở lần chạm đích đầu
    /// (`CollapseSpring`) — thẻ không bao giờ nhỏ hơn viên thuốc.
    @MainActor
    func testTheLandingCollapseIsTheApproachSpringStoppingAtItsFirstArrival() throws {
        let curves = BottomBarStyle.landingCollapse(initialVelocity: 4)
        XCTAssertEqual(curves.collapseSpring, LandingBounce.approachSpring)
        XCTAssertEqual(curves.initialVelocity, 4)
        XCTAssertEqual(curves.geometry,
                       Animation(CollapseSpring(spring: LandingBounce.approachSpring, initialVelocity: 4)))
        let geometry = CollapseSpring(spring: LandingBounce.approachSpring, initialVelocity: 0)
        let bounce = try tap()
        for time in stride(from: 0.0, through: 1.0, by: 0.002) {
            guard let fraction = geometry.fraction(at: time) else {
                XCTAssertGreaterThanOrEqual(time, bounce.arrival - 0.002, "stopped before arriving")
                return
            }
            XCTAssertLessThan(fraction, 1, "the card went past the pill at \(time)s")
        }
        XCTFail("the approach never stopped")
    }

    /// Cửa sổ kính của cú hạ cánh (4× → 1,25×) không là một cú cắt, và xong
    /// trước khi thẻ chạm đích.
    func testTheGlassWindowOfALandingIsAboutSeventyMilliseconds() throws {
        let bounce = try tap()
        let approach = LandingBounce.approachSpring
        func when(ratio: Double) -> Double {
            let height = 48 * ratio
            let progress = Double((CGFloat(height) - 48) / (844 - 48))
            var time = 0.0
            while 1 - approach.value(target: 1.0, initialVelocity: 0, time: time) > progress { time += 0.0005 }
            return time
        }
        let start = when(ratio: PlayerCard.landingGlassStartRatio)
        let end = when(ratio: PlayerCard.collapseGlassEndRatio)
        print(String(format: "[landing] glass %.0f → %.0fms, arrival %.0fms", start * 1000, end * 1000, bounce.arrival * 1000))
        XCTAssertGreaterThanOrEqual(end - start, 0.06)
        XCTAssertLessThan(end, bounce.arrival)
        XCTAssertEqual(PlayerCard.collapseGlass(cardHeight: 48 * 4, capsuleHeight: 48,
                                                startRatio: PlayerCard.landingGlassStartRatio), 0)
        XCTAssertEqual(PlayerCard.collapseGlass(cardHeight: 48 * 1.25, capsuleHeight: 48,
                                                startRatio: PlayerCard.landingGlassStartRatio), 1)
    }
}
