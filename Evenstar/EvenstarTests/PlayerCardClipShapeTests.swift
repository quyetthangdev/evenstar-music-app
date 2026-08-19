import XCTest
@testable import Evenstar

/// Hình dùng để cắt tấm thẻ, và vì sao nó phải rẽ nhánh theo máy.
///
/// Viết từ một số đo chứ không từ một lỗi báo về: Color Offscreen-Rendered
/// Yellow trên Release, iPhone 12, ngày 2026-08-18, cho thấy cú
/// `.clipShape(UnevenRoundedRectangle(...))` của thẻ làm **cả màn hình** bị
/// rasterize ngoài màn hình — ở mọi màn hình của app, kể cả khi player đóng,
/// vì thẻ luôn nằm trong cây. Bốn bán kính khác nhau không ánh xạ xuống
/// `layer.cornerRadius` được; một bán kính đều thì có.
///
/// Cái giá của nhánh nhanh là hai góc dưới cũng bo khi mở hết, và điều đó chỉ
/// vô hình trên máy có màn hình bo góc. Toàn bộ lý lẽ nằm ở doc của
/// `PlayerCard.cardCornerRadiiMayBeUniform(bottomSafeAreaInset:)`; ở đây chỉ
/// ghim những chỗ mà sai thì không ai nhìn ra cho tới khi cầm đúng cái máy.
///
/// `@MainActor` vì các hàm dưới đây là `static` trên một `View`, mà
/// `InferIsolatedConformances` làm chúng main-actor isolated.
@MainActor
final class PlayerCardClipShapeTests: XCTestCase {

    // MARK: - Máy nào được đi nhánh nhanh

    /// Máy có thanh Home ảo — tức có inset dưới — là máy có màn hình bo góc.
    func testADisplayWithAHomeIndicatorTakesTheUniformCorner() {
        // 34pt dọc, 21pt ngang: hai giá trị thật của lớp máy này.
        XCTAssertTrue(PlayerCard.cardCornerRadiiMayBeUniform(bottomSafeAreaInset: 34))
        XCTAssertTrue(PlayerCard.cardCornerRadiiMayBeUniform(bottomSafeAreaInset: 21))
    }

    /// iPhone SE 2/3 và iPad có nút Home: inset dưới bằng 0, màn hình góc
    /// vuông. Đi nhánh nhanh ở đây là hở hai lỗ tròn ở đáy player mở hết.
    func testASquareCorneredDisplayKeepsTheUnevenShape() {
        XCTAssertFalse(PlayerCard.cardCornerRadiiMayBeUniform(bottomSafeAreaInset: 0))
    }

    // MARK: - Biên an toàn của nhánh nhanh

    /// **Đây là test đáng giá nhất trong file.**
    ///
    /// Nhánh nhanh chỉ đúng chừng nào góc trên của thẻ khi mở hết còn *nhỏ hơn*
    /// bán kính bo màn hình của máy hẹp nhất còn chạy iOS 18 — iPhone XS /
    /// 11 Pro, ~39pt. Biên hiện tại là **1pt**. Ai nâng `expandedCornerRadius`
    /// lên 40 sẽ không thấy gì sai trên máy mình (iPhone 12 cắt 47pt, 14 Pro
    /// cắt 55pt) và làm hở góc trên đúng những máy không có trong tay.
    func testTheExpandedCornerStaysInsideTheNarrowestRoundedDisplay() {
        XCTAssertLessThanOrEqual(
            PlayerCard.cardTopCornerRadius(progress: 1),
            PlayerCard.narrowestRoundedDisplayCorner,
            """
            Góc thẻ khi mở hết đã vượt bán kính bo màn hình của iPhone XS/11 Pro. \
            Trên những máy ấy hai góc dưới sẽ hở ra thành hai lỗ tròn, và nhánh \
            bán kính đều không còn dùng được — xem cardCornerRadiiMayBeUniform.
            """
        )
    }

    // MARK: - Hai đầu của cú morph

    /// Thu gọn thì thẻ là một viên thuốc thật, nên bốn góc vốn đã bằng nhau —
    /// đó là lý do nhánh nhanh không đổi gì ở trạng thái người dùng nhìn thấy
    /// nhiều nhất.
    func testCollapsedTheTopAndBottomRadiiAgree() {
        XCTAssertEqual(
            PlayerCard.cardTopCornerRadius(progress: 0),
            PlayerCard.cardBottomCornerRadius(progress: 0),
            accuracy: 0.001
        )
    }

    /// Mở hết thì hai bên tách ra, và đó chính là chỗ hai nhánh khác nhau.
    func testExpandedTheBottomSquaresOffWhileTheTopDoesNot() {
        XCTAssertEqual(PlayerCard.cardBottomCornerRadius(progress: 1), 0, accuracy: 0.001)
        XCTAssertGreaterThan(PlayerCard.cardTopCornerRadius(progress: 1), 0)
    }

    /// Góc trên **không bao giờ** về 0 — thẻ mở hết vẫn là một tấm thẻ có vai
    /// bo, không phải một hình chữ nhật.
    func testTheTopCornerIsNeverSquareAtAnyPointOfTheMorph() {
        for step in 0...20 {
            let progress = Double(step) / 20
            XCTAssertGreaterThan(
                PlayerCard.cardTopCornerRadius(progress: progress), 0,
                "góc trên về 0 ở progress \(progress)"
            )
        }
    }

    /// Cả hai bán kính đi một chiều, không quay đầu giữa đường — một cú đảo
    /// chiều đọc ra như thẻ bị giật một nhịp giữa cú bung.
    func testBothRadiiMoveMonotonicallyAcrossTheMorph() {
        var previousTop = PlayerCard.cardTopCornerRadius(progress: 0)
        var previousBottom = PlayerCard.cardBottomCornerRadius(progress: 0)
        for step in 1...20 {
            let progress = Double(step) / 20
            let top = PlayerCard.cardTopCornerRadius(progress: progress)
            let bottom = PlayerCard.cardBottomCornerRadius(progress: progress)
            XCTAssertGreaterThanOrEqual(top, previousTop, "góc trên quay đầu ở \(progress)")
            XCTAssertLessThanOrEqual(bottom, previousBottom, "góc dưới quay đầu ở \(progress)")
            previousTop = top
            previousBottom = bottom
        }
    }
}
