import XCTest
import SwiftUI
@testable import Evenstar

/// **Cú chạm sàn cuối cú thu, như một vật rơi** (vòng sửa 5): thẻ chạm sàn,
/// phồng, bật lên những cung parabol thấp dần trong khi cú phồng giữ làm lề,
/// rồi xẹp — `LandingPlan`. Mọi thứ ở đây là phép tính thuần trên đúng lịch mà
/// thẻ chạy; ảnh dựng thật ở `CollapseLandingFrameTests`.
@MainActor
final class LandingPlanTests: XCTestCase {

    /// iPhone 12: mép trên viên kính ~710pt từ đỉnh màn hình.
    private let travel: CGFloat = 710

    private func plan(afterDrag: Bool, velocity: Double, span: Double) -> LandingPlan {
        LandingPlan(spring: BottomBarStyle.collapseSpring(afterDrag: afterDrag),
                    initialVelocity: velocity, span: span, travel: travel)
    }

    /// Cú thu thường ngày (kéo thẻ mở xuống tới 0,9 rồi buông 1900pt/s) và cú chạm.
    private var everyday: LandingPlan {
        plan(afterDrag: true,
             velocity: PlayerCard.settleVelocity(verticalVelocity: 1900, travel: travel, from: 0.9, to: 0),
             span: 0.9)
    }
    private var tap: LandingPlan { plan(afterDrag: false, velocity: 0, span: 1) }

    private var scenarios: [(String, LandingPlan)] {
        [("everyday", everyday), ("tap", tap),
         ("release from open, still", plan(afterDrag: true, velocity: 0, span: 1)),
         ("hard flick", plan(afterDrag: true, velocity: BottomBarStyle.maxSettleVelocity, span: 1)),
         ("short", plan(afterDrag: true, velocity: 0, span: 0.15)),
         ("tiny", plan(afterDrag: true, velocity: 0, span: 0.02))]
    }

    // MARK: - Nhịp nảy

    /// "~5, rồi ~2, rồi ~1": mỗi nhịp 0,4 nhịp trước.
    func testTheBouncesAreFiveTwoAndUnderOnePointForAnEverydayCollapse() {
        let apexes = everyday.bounces.map(\.apex)
        XCTAssertEqual(apexes.count, 3)
        XCTAssertEqual(apexes[0], 5, accuracy: 0.001)
        XCTAssertEqual(apexes[1], 2, accuracy: 0.001)
        XCTAssertEqual(apexes[2], 0.8, accuracy: 0.001)
    }

    func testEveryBounceIsLowerThanTheOneBefore() {
        for (name, plan) in scenarios {
            for (earlier, later) in zip(plan.bounces, plan.bounces.dropFirst()) {
                XCTAssertLessThan(later.apex, earlier.apex, name)
                XCTAssertEqual(later.start, earlier.start + earlier.duration, accuracy: 1e-9,
                               "bounces follow each other with no gap, \(name)")
            }
        }
    }

    /// Trọng lực: mỗi cung là một parabol — đi được 3/4 chiều cao trong 1/4 đầu
    /// thời gian (nhanh sát sàn), đỉnh ở giữa (chậm lại ở đỉnh) — và cùng một
    /// trọng lực cho mọi nhịp, nên thời gian tỉ lệ với căn bậc hai chiều cao.
    func testEachBounceIsAGravityArc() {
        let plan = everyday
        for bounce in plan.bounces {
            let quarter = plan.lift(at: bounce.start + bounce.duration / 4)
            let middle = plan.lift(at: bounce.start + bounce.duration / 2)
            XCTAssertEqual(quarter / bounce.apex, 0.75, accuracy: 0.01)
            XCTAssertEqual(middle, bounce.apex, accuracy: 0.01)
            // Vận tốc sát sàn lớn hơn hẳn vận tốc gần đỉnh.
            let step = 0.005
            let nearFloor = plan.lift(at: bounce.start + step) - plan.lift(at: bounce.start)
            let nearApex = plan.lift(at: bounce.start + bounce.duration / 2)
                - plan.lift(at: bounce.start + bounce.duration / 2 - step)
            XCTAssertGreaterThan(nearFloor, nearApex * 4)
        }
        let first = plan.bounces[0], second = plan.bounces[1]
        XCTAssertEqual(second.duration / first.duration,
                       Double((second.apex / first.apex).squareRoot()), accuracy: 0.001)
        XCTAssertEqual(first.duration, BottomBarStyle.dropFirstBounceDuration, accuracy: 0.001)
    }

    // MARK: - Lề: viên kính luôn nằm trọn

    /// Ở mọi mili giây: đáy thẻ (phồng xuống, rồi bị nhấc lên) không bao giờ lên
    /// trên đáy viên kính, và khi thẻ đang bay thì còn dư ít nhất `dropMargin`.
    /// Mép trên đi lên cùng thẻ; hai bên chỉ nở ra.
    func testTheCapsuleStaysInsideTheCardAtEveryMillisecond() {
        for (name, plan) in scenarios {
            var time = 0.0
            while time <= plan.duration + 0.05 {
                let swell = plan.swell(at: time)
                let lift = plan.lift(at: time)
                XCTAssertGreaterThanOrEqual(lift, 0, name)
                XCTAssertGreaterThanOrEqual(swell.bottom - lift, 0, "bottom inside at \(time)s, \(name)")
                if lift > 0 {
                    XCTAssertGreaterThanOrEqual(swell.bottom - lift, BottomBarStyle.dropMargin - 0.0001,
                                                "less than the margin at \(time)s, \(name)")
                }
                XCTAssertGreaterThanOrEqual(swell.top + lift, 0, name)
                XCTAssertGreaterThanOrEqual(swell.side, 0, name)
                time += 0.001
            }
        }
    }

    /// Lề ở đỉnh từng nhịp — số cho báo cáo, và cận dưới cho nó.
    func testTheMarginAtEachApexIsAtLeastHalfAPoint() {
        for (name, plan) in scenarios {
            for bounce in plan.bounces {
                let apexTime = bounce.start + bounce.duration / 2
                let margin = plan.swell(at: apexTime).bottom - plan.lift(at: apexTime)
                print("[drop] \(name): apex \(String(format: "%.2f", bounce.apex))pt at "
                      + "\(String(format: "%.0f", apexTime * 1000))ms, margin \(String(format: "%.2f", margin))pt")
                XCTAssertGreaterThanOrEqual(margin, BottomBarStyle.dropMargin - 0.0001, name)
            }
        }
    }

    // MARK: - Cú phồng

    /// Đỉnh phồng giữ dáng của vòng sửa 3–4: ~6–7pt mỗi mép cho cú thu thường
    /// ngày, và giữ nguyên suốt mọi nhịp nảy.
    func testTheSwellKeepsItsLookAndHoldsThroughTheBounces() throws {
        let plan = everyday
        let perEdge = PlayerCard.landingSwell(growth: plan.peakGrowth).bottom
        XCTAssertGreaterThanOrEqual(perEdge, 6)
        XCTAssertLessThanOrEqual(perEdge, 7)
        let last = try XCTUnwrap(plan.bounces.last)
        var time = plan.launch
        while time < last.start + last.duration {
            XCTAssertEqual(plan.growth(at: time), plan.peakGrowth, accuracy: 0.0001, "at \(time)s")
            time += 0.001
        }
    }

    /// Thẻ chỉ bật lên khi cú phồng đã tới đỉnh — lúc chạm, chưa có lề nào.
    func testTheCardSquashesBeforeItLeavesTheFloor() {
        for (name, plan) in scenarios {
            XCTAssertGreaterThanOrEqual(plan.launch, plan.impact, name)
            var time = 0.0
            while time < plan.launch {
                XCTAssertEqual(plan.lift(at: time), 0, "lifted before launch at \(time)s, \(name)")
                time += 0.001
            }
        }
        let plan = everyday
        XCTAssertEqual(plan.growth(at: plan.impact), 0, accuracy: 0.6, "the swell starts from nothing at impact")
    }

    /// Cú thu ngắn thì cú phồng nhỏ, và các nhịp bị chặn theo — không bao giờ
    /// ngược lại.
    func testAShortCollapseBouncesLowerOrNotAtAll() throws {
        let short = plan(afterDrag: true, velocity: 0, span: 0.15)
        let perEdge = PlayerCard.landingSwell(growth: short.peakGrowth).bottom
        let first = try XCTUnwrap(short.bounces.first)
        XCTAssertLessThanOrEqual(first.apex, perEdge - BottomBarStyle.dropMargin + 0.0001)
        XCTAssertLessThan(first.apex, BottomBarStyle.dropApex)
        XCTAssertTrue(plan(afterDrag: true, velocity: 0, span: 0.02).bounces.isEmpty,
                      "a tiny collapse has no room for a bounce")
    }

    // MARK: - Kết thúc

    func testItEndsExactlyAtRest() {
        for (name, plan) in scenarios {
            for time in [plan.duration, plan.duration + 0.001, plan.duration + 1] {
                XCTAssertEqual(plan.lift(at: time), 0, name)
                XCTAssertEqual(plan.swell(at: time), .init(top: 0, bottom: 0, side: 0), name)
            }
            XCTAssertEqual(plan.lift(at: plan.deflateStart), 0, "the last bounce has landed before the deflate, \(name)")
        }
    }

    /// Không có bước nhảy nào: từng mili giây, cú phồng và cú nảy chỉ đổi theo
    /// vận tốc của chính chúng. Ngưỡng cú phồng là 2pt/ms vì ngay sau lúc chạm
    /// nó lớn lên đúng bằng vận tốc mép trên vừa có — với cú búng mạnh nhất
    /// ~1,3pt/ms (đo được), liền mạch chứ không phải một bước.
    func testNothingJumps() {
        for (name, plan) in scenarios {
            var previous = (plan.swell(at: 0).bottom, plan.lift(at: 0))
            var time = 0.001
            while time <= plan.duration + 0.01 {
                let now = (plan.swell(at: time).bottom, plan.lift(at: time))
                XCTAssertLessThan(abs(now.0 - previous.0), 2, "swell jumped at \(time)s, \(name)")
                XCTAssertLessThan(abs(now.1 - previous.1), 0.5, "lift jumped at \(time)s, \(name)")
                previous = now
                time += 0.001
            }
        }
    }

    /// Phán quyết: trao chỗ sau nhịp nảy cuối, tổng tới hết cú mờ ≲ 1,1s.
    func testTheHandoffComesAfterTheLastBounceWithinAboutOnePointOneSeconds() {
        for (name, plan) in scenarios {
            let handoffEnd = plan.duration + 0.15
            print("[drop] \(name): impact \(String(format: "%.0f", plan.impact * 1000))ms,"
                  + " launch \(String(format: "%.0f", plan.launch * 1000))ms,"
                  + " bounces \(plan.bounces.map { String(format: "%.2f", $0.apex) }),"
                  + " deflate \(String(format: "%.0f", plan.deflateStart * 1000))ms,"
                  + " handoff ends \(String(format: "%.0f", handoffEnd * 1000))ms")
            XCTAssertGreaterThanOrEqual(plan.duration, plan.deflateStart, name)
            XCTAssertLessThanOrEqual(handoffEnd, 1.1, name)
        }
    }
}
