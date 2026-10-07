import XCTest
import UIKit
@testable import Evenstar

/// `AccessoryCapsule`: tìm view chứa viên kính của hệ thống **bằng hình học** —
/// tổ tiên cao nhất của neo còn đúng khung hàng accessory — và luôn hiện lại
/// nó, trên mọi lối ra (spec, Phần 1, bổ sung 2026-10-07).
///
/// Cây view ở đây là cây giả, dựng theo đúng hình dáng đo được trên iOS 26
/// (vòng 9): neo → vật chủ của neo → … → view chứa viên kính, cùng khung
/// (21, 705, 348, 48) → một view cha cao hơn của thanh tab. Không tên lớp nào.
@MainActor
final class AccessoryCapsuleTests: XCTestCase {
    private let pill = CGRect(x: 21, y: 705, width: 348, height: 48)
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    /// cửa sổ → thanh tab (cả màn) → dải dưới (0, 705, 390, 139) → viên kính
    /// (khung hàng) → vật chủ nội dung SwiftUI (khung hàng, `HostingBoundary`)
    /// → neo (khung hàng).
    private struct Tree {
        let window: UIWindow
        let strip: UIView
        let container: UIView
        let host: UIView
        let anchor: UIView
    }

    /// Vật chủ nội dung SwiftUI: chuỗi responder của nó không đi lên view cha
    /// mà rẽ sang một responder của SwiftUI — đo được trên iOS 26:
    /// `UIKitTabBarBottomAccessory.next` là `UIKitKeyPressResponder`, không
    /// phải `_UITabAccessoryContainer`. Ranh giới mà `container(of:)` dựa vào.
    final class HostingBoundary: UIView {
        private let hosting = UIResponder()
        override var next: UIResponder? { hosting }
    }

    private func makeTree(inWindow: Bool = true) -> Tree {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let tabBar = UIView(frame: window.bounds)
        let strip = UIView(frame: CGRect(x: 0, y: 705, width: 390, height: 139))
        let container = UIView(frame: CGRect(x: 21, y: 0, width: 348, height: 48))
        let host = HostingBoundary(frame: container.bounds)
        let anchor = UIView(frame: host.bounds)
        host.addSubview(anchor)
        container.addSubview(host)
        strip.addSubview(container)
        tabBar.addSubview(strip)
        window.addSubview(tabBar)
        if inWindow {
            window.isHidden = false
            self.window = window
        }
        return Tree(window: window, strip: strip, container: container, host: host, anchor: anchor)
    }

    // MARK: - Tìm

    func testItFindsTheTopmostAncestorWithTheRowsFrame() {
        let tree = makeTree()
        XCTAssertEqual(tree.anchor.convert(tree.anchor.bounds, to: nil), pill)
        XCTAssertTrue(AccessoryCapsule.container(of: tree.anchor) === tree.container)
    }

    func testHalfAPointOfRoundingStillMatches() {
        let tree = makeTree()
        tree.host.frame = tree.host.frame.insetBy(dx: 0.3, dy: 0.3)
        tree.anchor.frame = tree.host.bounds
        XCTAssertTrue(AccessoryCapsule.container(of: tree.anchor) === tree.container)
    }

    /// Hình dáng khác — neo không còn đúng khung cha nó — thì không có gì để
    /// ẩn: thẻ không nảy.
    func testWhenTheParentIsAlreadyBiggerThereIsNothingToHide() {
        let tree = makeTree()
        tree.anchor.frame = tree.host.bounds.insetBy(dx: 10, dy: 4)
        XCTAssertNil(AccessoryCapsule.container(of: tree.anchor))
    }

    /// Cùng cỡ mà lệch chỗ không phải cùng khung: neo lệch 6pt trong vật chủ
    /// của nó thì không tổ tiên nào trùng khung neo.
    func testTheSameSizeSomewhereElseIsNotTheSameFrame() {
        let tree = makeTree()
        tree.anchor.frame.origin.y = 6
        XCTAssertNil(AccessoryCapsule.container(of: tree.anchor))
    }

    /// Chuỗi cùng khung đi tới tận gốc: không có thanh tab nào bao quanh.
    func testAChainThatNeverMeetsABiggerParentFindsNothing() {
        let root = UIView(frame: pill)
        let host = UIView(frame: root.bounds)
        let anchor = UIView(frame: host.bounds)
        host.addSubview(anchor)
        root.addSubview(host)
        XCTAssertNil(AccessoryCapsule.container(of: anchor))
    }

    /// …kể cả khi gốc ấy là một cửa sổ cỡ đúng bằng hàng: không bao giờ ẩn
    /// một cửa sổ.
    func testItNeverReturnsAWindow() {
        let window = UIWindow(frame: pill)
        let host = UIView(frame: window.bounds)
        let anchor = UIView(frame: host.bounds)
        host.addSubview(anchor)
        window.addSubview(host)
        XCTAssertNil(AccessoryCapsule.container(of: anchor))
    }

    /// Một bản iOS sau cho view chứa viên kính khung **lớn hơn** hàng: tổ tiên
    /// cao nhất còn đúng khung hàng khi ấy là vật chủ nội dung của chính ta.
    /// Ẩn nó là ẩn chữ, để viên kính đứng yên lộ ra suốt cú lún — nên không
    /// tìm thấy gì, và thẻ co mềm.
    func testWhenTheGlassContainerOutgrowsTheRowOnlyOurOwnContentMatchesSoNothingIsFound() {
        let tree = makeTree()
        tree.container.frame = CGRect(x: 17, y: -4, width: 356, height: 56)
        tree.host.frame.origin = CGPoint(x: 4, y: 4)
        XCTAssertEqual(tree.anchor.convert(tree.anchor.bounds, to: nil), pill)
        XCTAssertNil(AccessoryCapsule.container(of: tree.anchor))
    }

    /// Không thấy ranh giới vật chủ nào dưới view tìm được thì không biết nó
    /// có phải của hệ thống không: không ẩn.
    func testWithoutAHostingBoundaryBelowItNothingIsFound() {
        let tree = makeTree()
        let plainHost = UIView(frame: tree.host.frame)
        tree.host.removeFromSuperview()
        tree.anchor.removeFromSuperview()
        plainHost.addSubview(tree.anchor)
        tree.container.addSubview(plainHost)
        XCTAssertNil(AccessoryCapsule.container(of: tree.anchor))
    }

    func testAnEmptyAnchorFindsNothing() {
        let tree = makeTree()
        tree.anchor.frame = .zero
        XCTAssertNil(AccessoryCapsule.container(of: tree.anchor))
    }

    // MARK: - Ẩn và hiện

    func testHidingHidesThatViewAndRestoringBringsItsAlphaBack() {
        let tree = makeTree()
        tree.container.alpha = 0.9
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        XCTAssertTrue(capsule.hide())
        XCTAssertTrue(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 0)
        XCTAssertEqual(tree.strip.alpha, 1, "only the capsule, never the tab bar")
        capsule.restore()
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 0.9, accuracy: 1e-6)
        capsule.restore()
        XCTAssertEqual(tree.container.alpha, 0.9, accuracy: 1e-6, "restoring twice is harmless")
    }

    func testWithoutAnAnchorInAWindowNothingIsHidden() {
        let capsule = AccessoryCapsule()
        XCTAssertFalse(capsule.hide(), "no anchor yet")
        let tree = makeTree(inWindow: false)
        tree.anchor.removeFromSuperview()
        capsule.attach(tree.anchor)
        XCTAssertFalse(capsule.hide(), "an anchor that left the window")
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 1)
    }

    /// Tìm lại mỗi lần: hệ thống dựng lại viên kính thì lần ẩn sau trúng view
    /// mới, không phải view cũ đã rời màn hình.
    func testItLooksAgainEveryTime() {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        capsule.hide()
        capsule.restore()
        let rebuilt = UIView(frame: tree.container.frame)
        tree.container.removeFromSuperview()
        tree.strip.addSubview(rebuilt)
        rebuilt.addSubview(tree.host)
        XCTAssertTrue(capsule.hide())
        XCTAssertEqual(rebuilt.alpha, 0)
        XCTAssertEqual(tree.container.alpha, 1)
        capsule.restore()
    }

    // MARK: - Chạm trong lúc ẩn

    private func blocker(in tree: Tree) -> AccessoryCapsule.Blocker? {
        tree.strip.subviews.compactMap { $0 as? AccessoryCapsule.Blocker }.first
    }

    private var pillCentre: CGPoint { CGPoint(x: pill.midX, y: pill.midY) }

    /// Viên kính ở `alpha` 0 thì UIKit không cho nó nhận chạm; một lớp trong
    /// suốt nhận thay, và cú chạm mở lại thẻ — không rơi xuống hàng thư viện.
    func testWhileHiddenATapOnThePillStillReachesTheCapsule() throws {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        var taps = 0
        capsule.onTap = { taps += 1 }
        capsule.attach(tree.anchor)
        XCTAssertTrue(tree.window.hitTest(pillCentre, with: nil)?.isDescendant(of: tree.container) == true)
        capsule.hide()
        let cover = try XCTUnwrap(blocker(in: tree), "no stand-in for the hidden capsule")
        XCTAssertTrue(tree.window.hitTest(pillCentre, with: nil) === cover,
                      "a tap on the hidden pill would fall through to whatever is underneath")
        XCTAssertEqual(cover.frame, tree.container.frame)
        XCTAssertEqual(cover.alpha, 1)
        XCTAssertTrue(cover.accessibilityElementsHidden)
        XCTAssertFalse(cover.isAccessibilityElement)
        XCTAssertTrue(cover.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true)
        cover.handleTap()
        XCTAssertEqual(taps, 1)

        capsule.restore()
        XCTAssertNil(blocker(in: tree))
        XCTAssertTrue(tree.window.hitTest(pillCentre, with: nil)?.isDescendant(of: tree.container) == true,
                      "after restoring, the capsule takes its taps again")
    }

    /// `PlayerExpansion` nối cú chạm ấy với `requestExpand()`.
    func testATapWhileHiddenAsksTheCardToExpand() throws {
        let expansion = PlayerExpansion()
        let tree = hiddenCapsule(in: expansion)
        try XCTUnwrap(blocker(in: tree)).handleTap()
        XCTAssertEqual(expansion.intent?.kind, .expand)
    }

    /// Hiện lại chỉ gỡ cú mờ của chính nó, không gỡ animation khác của hệ
    /// thống trên viên kính (thanh tab đang thu nhỏ…).
    func testRestoringLeavesTheSystemsOtherAnimationsAlone() {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        let move = CABasicAnimation(keyPath: "position.y")
        move.duration = 10
        tree.container.layer.add(move, forKey: "position")
        capsule.hide()
        XCTAssertNotNil(tree.container.layer.animation(forKey: AccessoryCapsule.fadeKey), "our own fade")
        capsule.restore()
        XCTAssertNotNil(tree.container.layer.animation(forKey: "position"))
        XCTAssertNil(tree.container.layer.animation(forKey: AccessoryCapsule.fadeKey))
    }

    /// `"opacity"` là khoá UIKit đặt cho **mọi** animation `alpha`, của hệ
    /// thống cũng vậy (accessory đang được dỡ đi…). Hiện lại chỉ gỡ cú mờ của
    /// chính ta, theo khoá riêng.
    func testRestoringLeavesTheSystemsOwnOpacityAnimationAlone() {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        capsule.hide()
        let system = CABasicAnimation(keyPath: "opacity")
        system.duration = 10
        tree.container.layer.add(system, forKey: "opacity")
        capsule.restore()
        XCTAssertNotNil(tree.container.layer.animation(forKey: "opacity"))
        XCTAssertEqual(tree.container.alpha, 1)
    }

    /// Hệ thống đã đổi `alpha` trong lúc ẩn — đó không còn là số ta đặt, nên
    /// không ép nó về.
    func testRestoringLeavesAnAlphaTheSystemChangedAlone() throws {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        capsule.hide()
        tree.container.alpha = 0.4
        capsule.restore()
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 0.4, accuracy: 1e-6)
        XCTAssertNil(blocker(in: tree), "the stand-in goes regardless")

        capsule.hide()
        tree.container.alpha = 0.4
        var done = false
        capsule.restore(fadingIn: 0.05) { done = true }
        XCTAssertTrue(done, "nothing of ours to fade in: call back at once")
        XCTAssertEqual(tree.container.alpha, 0.4, accuracy: 1e-6)
    }

    /// Viên kính đã rời cửa sổ (hệ thống dỡ accessory): để yên nó.
    func testRestoringLeavesAViewThatLeftTheWindowAlone() {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        capsule.hide()
        tree.container.removeFromSuperview()
        capsule.restore()
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 0)
    }

    // MARK: - Mọi lối ra đều hiện lại

    private func hiddenCapsule(in expansion: PlayerExpansion) -> Tree {
        let tree = makeTree()
        expansion.capsule.attach(tree.anchor)
        XCTAssertTrue(expansion.capsule.hide())
        XCTAssertEqual(tree.container.alpha, 0)
        return tree
    }

    func testHandingOverRestoresIt() {
        let expansion = PlayerExpansion()
        expansion.leaveRest()
        expansion.commitCollapse()
        let tree = hiddenCapsule(in: expansion)
        expansion.arriveAtRest()
        XCTAssertFalse(expansion.capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 1)
        XCTAssertNil(blocker(in: tree))
    }

    /// Một chuyển động mới — chạm hay kéo accessory giữa cú hạ cánh, mở lại.
    func testANewMotionRestoresIt() {
        let expansion = PlayerExpansion()
        expansion.leaveRest()
        expansion.commitCollapse()
        let tree = hiddenCapsule(in: expansion)
        expansion.leaveRest()
        XCTAssertEqual(tree.container.alpha, 1)
        XCTAssertNil(blocker(in: tree))

        expansion.commitCollapse()
        XCTAssertTrue(expansion.capsule.hide())
        expansion.accessoryDragChanged(translationHeight: -80)
        XCTAssertEqual(tree.container.alpha, 1, "a drag on the accessory")
        XCTAssertNil(blocker(in: tree))
    }

    func testLeavingTheForegroundRestoresIt() {
        let expansion = PlayerExpansion()
        let tree = hiddenCapsule(in: expansion)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(tree.container.alpha, 1)
        XCTAssertNil(blocker(in: tree))
        XCTAssertTrue(expansion.capsule.hide())
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(tree.container.alpha, 1)
        XCTAssertNil(blocker(in: tree))
    }

    func testDeallocationRestoresIt() {
        let tree = makeTree()
        var capsule: AccessoryCapsule? = AccessoryCapsule()
        capsule?.attach(tree.anchor)
        XCTAssertEqual(capsule?.hide(), true)
        XCTAssertEqual(tree.container.alpha, 0)
        capsule = nil
        // Hẹn trên main actor từ `deinit`: chạy ở lượt kế.
        let deadline = Date().addingTimeInterval(1)
        while tree.container.alpha != 1, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(tree.container.alpha, 1)
        XCTAssertNil(blocker(in: tree))
    }

    /// Giải phóng `PlayerExpansion` — test nào cũng làm, hàng trăm lần — không
    /// được làm sập tiến trình (vòng 9: `isolated deinit` đã làm thế).
    func testReleasingManyExpansionsIsSafe() {
        for _ in 0..<200 {
            let expansion = PlayerExpansion()
            _ = expansion.capsule.isHidden
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    /// Chốt cuối: một `completion` không bao giờ nổ cũng không giữ viên kính
    /// ẩn quá `watchdog`.
    func testTheWatchdogRestoresItIfNothingElseDoes() {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        capsule.hide()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(capsule.isHidden, "not before the watchdog")
        let deadline = Date().addingTimeInterval(1.5)
        while capsule.isHidden, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 1)
        XCTAssertNil(blocker(in: tree))
    }

    /// Hiện lại dần cho cú trao tay: `completion` chạy khi đã hiện hẳn — và chạy
    /// ngay khi không có gì để hiện, để cú trao tay không bao giờ bị kẹt.
    func testFadingBackInCallsBackOnceVisible() {
        let tree = makeTree()
        let capsule = AccessoryCapsule()
        capsule.attach(tree.anchor)
        capsule.hide()
        var done = false
        capsule.restore(fadingIn: 0.05) { done = true }
        XCTAssertNil(blocker(in: tree), "the capsule takes its taps back as it starts fading in")
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(tree.container.alpha, 1, "the model value is already back")
        let deadline = Date().addingTimeInterval(1)
        while !done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(done)

        var immediate = false
        capsule.restore(fadingIn: 0.05) { immediate = true }
        XCTAssertTrue(immediate, "nothing hidden: call back at once")
    }
}
