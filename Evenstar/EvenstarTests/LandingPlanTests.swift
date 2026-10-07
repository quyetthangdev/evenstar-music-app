import XCTest
import SwiftUI
@testable import Evenstar

/// **Cú chạm sàn cuối cú thu: nén rồi giãn, một dao động, một cú nảy** (vòng
/// sửa 6) — `LandingPlan`. Mọi thứ ở đây là phép tính thuần trên đúng lịch mà
/// thẻ chạy; ảnh dựng thật ở `CollapseLandingFrameTests`.
@MainActor
final class LandingPlanTests: XCTestCase {

    /// iPhone 12: mép trên viên kính ~710pt từ đỉnh màn hình.
    private let travel: CGFloat = 710

    private func plan(afterDrag: Bool, velocity: Double, span: Double) -> LandingPlan {
        LandingPlan(spring: BottomBarStyle.collapseSpring(afterDrag: afterDrag),
                    initialVelocity: velocity, span: span, travel: travel)
    }

    /// Cú thu thường ngày (kéo thẻ mở xuống tới 0,9 rồi buông 1900pt/s).
    private var everyday: LandingPlan {
        plan(afterDrag: true,
             velocity: PlayerCard.settleVelocity(verticalVelocity: 1900, travel: travel, from: 0.9, to: 0),
             span: 0.9)
    }

    private var scenarios: [(String, LandingPlan)] {
        [("everyday", everyday),
         ("tap", plan(afterDrag: false, velocity: 0, span: 1)),
         ("release from open, still", plan(afterDrag: true, velocity: 0, span: 1)),
         ("hard flick", plan(afterDrag: true, velocity: BottomBarStyle.maxSettleVelocity, span: 1)),
         ("short", plan(afterDrag: true, velocity: 0, span: 0.15)),
         ("tiny", plan(afterDrag: true, velocity: 0, span: 0.02))]
    }

    /// Các nửa chu kỳ của dao động sau lúc chạm — không cắt ở `duration`, để
    /// đếm cả những nửa đã tắt: (lúc đỉnh, độ lệch đỉnh có dấu).
    private func halfCycles(_ plan: LandingPlan) -> [(time: Double, swing: Double)] {
        var lobes: [(time: Double, swing: Double)] = []
        var time = plan.impact + 0.0002
        while time < plan.impact + 1.5 {
            let s = plan.swingIgnoringEnd(at: time)
            if s != 0 {
                if let last = lobes.last, (last.swing > 0) == (s > 0) {
                    if abs(s) > abs(last.swing) { lobes[lobes.count - 1] = (time, s) }
                } else {
                    lobes.append((time, s))
                }
            }
            time += 0.0002
        }
        return lobes
    }

    /// Thứ một nửa chu kỳ vẽ ra ở mép của nó: đáy khi nén, mép trên khi giãn.
    private func drawn(_ swing: Double) -> CGFloat {
        swing >= 0 ? CGFloat(swing)
            : CGFloat(-swing) * BottomBarStyle.stretchToSquash / CGFloat(LandingPlan.halfCycleRatio)
    }

    // MARK: - Hai pha

    /// Nén: đáy võng (≥ sàn), hai bên nở, mép trên **đúng** ở mép trên viên
    /// kính. Giãn: mép trên vươn lên, đáy **đúng** ở sàn, hai bên về đúng bề
    /// ngang. Không mép nào bao giờ đi vào trong — ở từng mili giây.
    func testSquashThenStretchWithEveryEdgeOutwardAtEveryMillisecond() {
        for (name, plan) in scenarios {
            var time = 0.0
            while time <= plan.duration + 0.05 {
                let e = plan.edges(at: time)
                XCTAssertGreaterThanOrEqual(e.top, 0, "\(name) at \(time)s")
                XCTAssertGreaterThanOrEqual(e.bottom, 0, "\(name) at \(time)s")
                XCTAssertGreaterThanOrEqual(e.side, 0, "\(name) at \(time)s")
                if plan.swing(at: time) > 0 {
                    XCTAssertEqual(e.top, 0, "the top stays at the capsule top while squashing, \(name)")
                } else if plan.swing(at: time) < 0 {
                    XCTAssertEqual(e.bottom, 0, "the bottom stays on the floor while stretching, \(name)")
                    XCTAssertEqual(e.side, 0, "the sides are back at the capsule width while stretching, \(name)")
                }
                time += 0.001
            }
        }
    }

    /// Cú nén đến trước, cú giãn sau — một đường cong, nửa dương rồi nửa âm.
    func testTheSquashComesFirstAndTheStretchFollowsOnTheSameCurve() throws {
        for (name, plan) in scenarios where plan.squashPeak > 1 {
            let lobes = halfCycles(plan)
            XCTAssertGreaterThanOrEqual(lobes.count, 2, name)
            XCTAssertGreaterThan(lobes[0].swing, 0, "first the squash, \(name)")
            XCTAssertLessThan(lobes[1].swing, 0, "then the stretch, \(name)")
            XCTAssertLessThan(lobes[0].time, lobes[1].time, name)
        }
    }

    /// Phán quyết: nén ~5–7pt đáy + ~1,5–2pt mỗi bên, giãn ~5–7pt mép trên —
    /// với cú thu thường ngày. Số cho báo cáo được in ra.
    func testAnEverydayLandingSquashesAndStretchesFiveToSevenPoints() throws {
        for (name, plan) in scenarios {
            let lobes = halfCycles(plan)
            let squash = plan.edges(at: lobes.first?.time ?? 0)
            let stretch = lobes.count > 1 ? plan.edges(at: lobes[1].time) : .none
            print("[squash] \(name): impact \(String(format: "%.0f", plan.impact * 1000))ms,"
                  + " squash \(String(format: "%.2f", squash.bottom))pt (sides \(String(format: "%.2f", squash.side))pt)"
                  + " at \(String(format: "%.0f", (lobes.first?.time ?? 0) * 1000))ms,"
                  + " stretch \(String(format: "%.2f", stretch.top))pt"
                  + " at \(String(format: "%.0f", (lobes.count > 1 ? lobes[1].time : 0) * 1000))ms,"
                  + " done \(String(format: "%.0f", plan.duration * 1000))ms")
        }
        let plan = everyday
        let lobes = halfCycles(plan)
        let squash = plan.edges(at: lobes[0].time), stretch = plan.edges(at: lobes[1].time)
        XCTAssertGreaterThanOrEqual(squash.bottom, 5)
        XCTAssertLessThanOrEqual(squash.bottom, 7)
        XCTAssertGreaterThanOrEqual(squash.side, 1.5)
        XCTAssertLessThanOrEqual(squash.side, 2.1)
        XCTAssertGreaterThanOrEqual(stretch.top, 5)
        XCTAssertLessThanOrEqual(stretch.top, 7)
    }

    /// Đúng **một** cú nảy thấy được: sau cú nén và cú giãn, mọi nửa chu kỳ còn
    /// lại vẽ ra dưới 0,5pt ở mọi mép — kể cả cú búng mạnh nhất.
    func testExactlyOnePerceptibleBounce() {
        for (name, plan) in scenarios {
            let lobes = halfCycles(plan)
            for lobe in lobes.dropFirst(2) {
                XCTAssertLessThan(drawn(lobe.swing), 0.5,
                                  "a further half-cycle shows \(drawn(lobe.swing))pt, \(name)")
            }
            if lobes.count > 2 {
                print("[squash] \(name): third half-cycle \(String(format: "%.2f", drawn(lobes[2].swing)))pt")
            }
        }
    }

    // MARK: - Liền mạch và trần

    /// Lúc chạm, đáy bắt đầu võng đúng ở vận tốc mép trên vừa có — đà của cú
    /// thu chuyển nguyên vào cú nén (dưới `squashKnee`).
    func testTheSquashStartsAtTheArrivalSpeed() {
        let spring = BottomBarStyle.collapseSpring(afterDrag: true)
        let velocity = PlayerCard.settleVelocity(verticalVelocity: 1900, travel: travel, from: 0.9, to: 0)
        let plan = everyday
        XCTAssertLessThan(plan.squashPeak, BottomBarStyle.squashKnee, "the everyday landing is below the knee")
        let arrival = spring.velocity(target: 1.0, initialVelocity: velocity, time: plan.impact) * 0.9 * Double(travel)
        let step = 0.0002
        let sagSpeed = Double(plan.edges(at: plan.impact + step).bottom) / step
        XCTAssertEqual(sagSpeed / arrival, 1, accuracy: 0.05,
                       "the bottom starts at \(sagSpeed)pt/s against an arrival of \(arrival)pt/s")
        // …và trước lúc chạm, không mép nào động.
        XCTAssertEqual(plan.edges(at: plan.impact - 0.001), .none)
    }

    /// Cú búng mạnh hơn nén và giãn nhiều hơn, nhưng không quá trần.
    func testAHarderLandingSquashesMoreButStaysUnderTheCap() {
        let gentle = plan(afterDrag: true, velocity: 0, span: 1)
        let hard = plan(afterDrag: true, velocity: BottomBarStyle.maxSettleVelocity, span: 1)
        XCTAssertGreaterThan(hard.squashPeak, gentle.squashPeak)
        XCTAssertLessThanOrEqual(hard.squashPeak, BottomBarStyle.squashCap)
        var time = 0.0
        while time < hard.duration {
            let e = hard.edges(at: time)
            XCTAssertLessThanOrEqual(max(e.bottom, e.top), BottomBarStyle.squashCap + 0.001)
            time += 0.001
        }
    }

    /// Không có bước nhảy: từng mili giây, mọi mép chỉ đổi theo vận tốc của
    /// chính dao động (dưới ~3pt/ms ngay cả lúc nảy mạnh nhất).
    func testNothingJumps() {
        for (name, plan) in scenarios {
            var previous = plan.edges(at: 0)
            var time = 0.001
            while time <= plan.duration + 0.01 {
                let now = plan.edges(at: time)
                XCTAssertLessThan(abs(now.top - previous.top), 3, "top jumped at \(time)s, \(name)")
                XCTAssertLessThan(abs(now.bottom - previous.bottom), 3, "bottom jumped at \(time)s, \(name)")
                previous = now
                time += 0.001
            }
        }
    }

    // MARK: - Kết thúc

    /// Đúng ở nghỉ từ `duration` trở đi, và cú cắt ở `duration` dưới
    /// `squashSettle`.
    func testItEndsExactlyAtRest() {
        for (name, plan) in scenarios {
            for time in [plan.duration, plan.duration + 0.001, plan.duration + 1] {
                XCTAssertEqual(plan.edges(at: time), .none, name)
            }
            let before = plan.edges(at: plan.duration - 0.0005)
            XCTAssertLessThan(max(before.top, before.bottom, before.side), BottomBarStyle.squashSettle + 0.01, name)
        }
    }

    /// Trao chỗ sau cú nảy, tổng tới hết cú mờ ≲ 0,9s.
    func testTheHandoffComesAfterTheBounceWithinNineTenthsOfASecond() {
        for (name, plan) in scenarios {
            let lobes = halfCycles(plan)
            if lobes.count > 1, plan.squashPeak > 1 {
                XCTAssertGreaterThan(plan.duration, lobes[1].time, "after the stretch, \(name)")
            }
            XCTAssertLessThanOrEqual(plan.duration + 0.15, 0.9, "\(name) hands over at \(plan.duration + 0.15)s")
        }
    }
}

private extension LandingPlan {
    /// Dao động không bị cắt ở `duration` — để đếm cả những nửa chu kỳ đã tắt.
    func swingIgnoringEnd(at time: Double) -> Double {
        let zeta = BottomBarStyle.squashDamping
        let damped = Double.pi / BottomBarStyle.squashHalfCycle
        let omega = damped / (1 - zeta * zeta).squareRoot()
        let tau = time - impact
        guard tau > 0 else { return 0 }
        return launchSpeed / damped * exp(-zeta * omega * tau) * sin(damped * tau)
    }
}
