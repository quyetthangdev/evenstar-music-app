import XCTest
import SwiftUI
@testable import Evenstar

/// Nốt nhạc trong ô bìa mặc định không được lấn ra ngoài ô.
///
/// **Lỗi mà file này canh biên dịch được, chạy được, và chỉ sai khi nhìn.**
/// `PlayerCard` vẽ nốt ở `font(size: 140)` rồi thu nhỏ bằng `scaleEffect` —
/// `scaleEffect` có hoạt hoá được, thứ `.font(size:)` không có, và đó là lý do
/// cả khối ấy viết như vậy.
///
/// Nhưng `scaleEffect` **không đổi kích thước layout**. Nốt luôn chiếm một hộp
/// 140pt dù được vẽ nhỏ tới đâu. Trong thẻ mở rộng thì vừa; trong player thu
/// nhỏ, ô bìa chỉ khoảng 40pt và hộp 140pt lấn ra, đẩy hàng chữ bên cạnh.
///
/// Không test nào trong repo bắt được nó — các test hiện có đo chuyển động, chi
/// phí commit, và nguồn ảnh, không cái nào đo *chỗ chiếm*. Nó tới từ mắt người
/// dùng.
@MainActor
final class PlaceholderGlyphLayoutTests: XCTestCase {
    /// Dựng đúng khối glyph mà `PlayerCard` dựng, ở một cạnh cho trước, rồi hỏi
    /// SwiftUI nó đòi bao nhiêu chỗ.
    ///
    /// Chép hình dạng chứ không gọi vào `PlayerCard`: khối ấy nằm sâu trong một
    /// `body` cần cả thẻ, cả `PlaybackService` và cả một cú morph đang chạy để
    /// tới được. Cái đang kiểm là quan hệ giữa `font(size:)`, `scaleEffect` và
    /// `frame` — chép ba dòng ấy là chép đúng thứ có thể sai.
    private func glyphSize(side: CGFloat, bounded: Bool) -> CGSize {
        let base: CGFloat = 280
        let glyph = Image(systemName: "music.note")
            .font(.system(size: base * 0.5))
            .scaleEffect(side / base)

        let view: AnyView = bounded
            ? AnyView(glyph.frame(width: side, height: side))
            : AnyView(glyph)

        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: .max, height: .max))
    }

    /// Cạnh ô bìa trong player thu nhỏ, xấp xỉ.
    private let miniSide: CGFloat = 40

    /// Bản đã sửa: chỗ chiếm bằng đúng cạnh ô bìa.
    func testTheGlyphAsksForNoMoreRoomThanTheArtworkSide() {
        let size = glyphSize(side: miniSide, bounded: true)
        XCTAssertEqual(size.width, miniSide, accuracy: 1,
                       "nốt nhạc phải chiếm đúng cạnh ô bìa")
        XCTAssertEqual(size.height, miniSide, accuracy: 1)
    }

    /// Và bản chưa sửa thì **không** — nếu không có khẳng định này thì test trên
    /// có thể xanh vì một lý do chẳng liên quan gì tới `frame`.
    ///
    /// Đây là thứ phân biệt "test bắt được lỗi" với "test tình cờ xanh": bỏ
    /// `.frame` ra thì chỗ chiếm phải phình lên nhiều lần cạnh ô bìa.
    func testWithoutTheFrameItAsksForFarMoreThanItDraws() {
        let unbounded = glyphSize(side: miniSide, bounded: false)
        XCTAssertGreaterThan(unbounded.width, miniSide * 2,
                             "không có frame thì nốt phải đòi chỗ gấp nhiều lần — "
                             + "đòi \(unbounded.width) cho ô \(miniSide)")
    }

    /// Thẻ mở rộng cũng phải đúng, không chỉ player thu nhỏ.
    ///
    /// Ở cạnh lớn, hộp 140pt vốn đã vừa, nên lỗi cũ không lộ ra ở đây — đó
    /// chính là lý do nó sống sót tới lúc có người nhìn thấy ở player thu nhỏ.
    func testTheExpandedCardIsBoundedToo() {
        let side: CGFloat = 320
        let size = glyphSize(side: side, bounded: true)
        XCTAssertEqual(size.width, side, accuracy: 1)
    }
}
