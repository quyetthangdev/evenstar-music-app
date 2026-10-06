import XCTest
@testable import Evenstar

/// Hai khung dưới là **số đo thật** từ spike 2026-10-06 (iPhone 17, iOS 26.0):
/// accessory ở `.expanded` và ở `.inline`. Ca màn ngang là khung giả định với
/// hai lề khác nhau — đúng ca từng làm viên pill lệch khỏi chỗ.
final class PlayerAnchorTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)
    private let expanded = CGRect(x: 20, y: 735, width: 360, height: 48)
    private let inline = CGRect(x: 84, y: 798, width: 234, height: 48)

    func testAtRestTheCardSitsExactlyOnTheAccessory() {
        for frame in [expanded, inline] {
            let anchor = PlayerAnchor(frame: frame, screen: screen)
            XCTAssertEqual(anchor.cardFrame(progress: 0), frame)
        }
    }

    func testFullyOpenTheCardFillsTheScreen() {
        for frame in [expanded, inline] {
            let anchor = PlayerAnchor(frame: frame, screen: screen)
            XCTAssertEqual(anchor.cardFrame(progress: 1), CGRect(origin: .zero, size: screen))
        }
    }

    /// Lỗi "thẻ trôi khỏi ngón tay" đã tái phát hai lần: quãng chia ra
    /// `progress` khác quãng mép trên thật sự đi.
    func testDragTravelIsExactlyHowFarTheTopEdgeMoves() {
        for frame in [expanded, inline] {
            let anchor = PlayerAnchor(frame: frame, screen: screen)
            let moved = anchor.cardFrame(progress: 0).minY - anchor.cardFrame(progress: 1).minY
            XCTAssertEqual(anchor.dragTravel, moved, accuracy: 0.0001)
        }
    }

    /// Đạo hàm mép trên theo `progress` là hằng số, nên một điểm ngón tay đi
    /// là một điểm thẻ đi, ở mọi điểm của cú bung chứ không chỉ hai đầu.
    func testTheTopEdgeMovesLinearly() {
        let anchor = PlayerAnchor(frame: expanded, screen: screen)
        let quarter = anchor.cardFrame(progress: 0.25).minY
        let half = anchor.cardFrame(progress: 0.5).minY
        let start = anchor.cardFrame(progress: 0).minY
        XCTAssertEqual(start - quarter, (start - half) / 2, accuracy: 0.0001)
    }

    func testLandscapeKeepsBothUnequalMarginsAtRest() {
        let wide = CGSize(width: 874, height: 402)
        let frame = CGRect(x: 120, y: 330, width: 560, height: 48)
        let anchor = PlayerAnchor(frame: frame, screen: wide)
        XCTAssertEqual(anchor.leadingMargin, 120)
        XCTAssertEqual(anchor.trailingMargin, 194)
        XCTAssertEqual(anchor.cardFrame(progress: 0), frame)
        XCTAssertEqual(anchor.cardFrame(progress: 1), CGRect(origin: .zero, size: wide))
    }

    func testTheCornerIsAFullPill() {
        XCTAssertEqual(PlayerAnchor(frame: inline, screen: screen).collapsedCornerRadius, 24)
    }

    func testProgressOutsideTheRangeIsClamped() {
        let anchor = PlayerAnchor(frame: expanded, screen: screen)
        XCTAssertEqual(anchor.cardFrame(progress: -0.3), anchor.cardFrame(progress: 0))
        XCTAssertEqual(anchor.cardFrame(progress: 1.4), anchor.cardFrame(progress: 1))
    }

    // MARK: - Review Focus 1: chưa từng đo

    func testAnUnmeasuredFrameFallsBackToTheBottomOfTheScreen() {
        let resolved = PlayerAnchor.resolve(measured: .zero, screen: screen)
        XCTAssertEqual(resolved, PlayerAnchor.fallbackFrame(screen: screen))
        XCTAssertEqual(resolved.maxY, screen.height - 91, "đáy như số đo .expanded")
        XCTAssertEqual(resolved.height, 48)
        XCTAssertEqual(resolved.minX, 20)
    }

    func testAFrameOffTheScreenIsNotTrusted() {
        let offscreen = CGRect(x: 20, y: 900, width: 360, height: 48)
        XCTAssertEqual(PlayerAnchor.resolve(measured: offscreen, screen: screen),
                       PlayerAnchor.fallbackFrame(screen: screen))
    }

    func testAMeasuredFrameIsUsedAsIs() {
        XCTAssertEqual(PlayerAnchor.resolve(measured: inline, screen: screen), inline)
    }

    func testTravelIsNeverZero() {
        XCTAssertEqual(PlayerAnchor.dragTravel(for: .zero), 1)
    }
}
