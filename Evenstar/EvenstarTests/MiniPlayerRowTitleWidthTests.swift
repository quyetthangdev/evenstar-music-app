import XCTest
import SwiftUI
@testable import Evenstar

/// **Tên bài trong hàng mini của thẻ không được đổi bề rộng theo `progress`.**
///
/// Lỗi quay được trên iPhone 12 (QA 2026-10-06): cuối cú thu, ▶ ⏭ đã nằm đúng
/// hàng trên cùng của thẻ nhưng tên bài trôi ở tận phần dưới tấm thẻ, rồi mới
/// leo lên khớp hàng khi thẻ về cỡ accessory; đầu cú bung thì tên bài biến mất
/// hẳn. Hai nút và tên bài nằm chung một `HStack`, nên chúng chỉ tách được nếu
/// SwiftUI vẽ tên bài theo một đường khác — và nó làm đúng thế: hàng từng lấy
/// bề rộng **của thẻ**, thẻ mở hết rộng hơn accessory, nên `Text` có hai bố cục
/// khác nhau ở hai đầu cú morph (cắt chữ ở hai chỗ khác nhau). Trong một
/// `withAnimation`, SwiftUI nội suy *giữa hai bố cục chữ* ấy thay vì dời một
/// khối chữ cố định, và đường nội suy ấy vẽ chữ ra khỏi hàng. Hai nút không đổi
/// cỡ nên không bị.
///
/// Test này ghim **nguyên nhân**, không ghim triệu chứng: triệu chứng chỉ có
/// trong cú animation và phụ thuộc đồng hồ, còn nguyên nhân thì đọc được ở hai
/// `progress` đứng yên — chỗ chữ bị cắt (mép phải dấu "…") tính từ mép trái thẻ
/// phải như nhau ở `progress` 0 và ở một `progress` mà thẻ đã rộng ra. Trước bản
/// sửa, ở 0,2 thẻ rộng hơn 8pt và tên bài dài ra theo.
@MainActor
final class MiniPlayerRowTitleWidthTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private static let screen = CGSize(width: 390, height: 844)
    private static let scale: CGFloat = 2

    func testTheTitleIsCutAtTheSamePlaceWhileTheCardWidens() throws {
        let library = try InMemoryLibrary.make()
        // Toàn chữ "l" hẹp: 8pt bề rộng thêm là hai, ba ký tự nữa lọt vào hàng,
        // nên khác biệt không thể trốn vào khoảng giữa hai ký tự rộng.
        let track = InMemoryLibrary.makeTrack(title: String(repeating: "l", count: 160))
        try library.insert(track)
        let playback = PlaybackService(player: MockAudioPlayer(),
                                       nowPlaying: MockNowPlayingPublisher(),
                                       library: library)
        let expansion = PlayerExpansion()
        playback.play(track, in: [track])

        let card = PlayerCard(playback: playback, expansion: expansion)
            .environment(library)
            .environment(playback)
        let host = UIHostingController(rootView: ZStack { Color.white.ignoresSafeArea(); card })
        host.view.frame = CGRect(origin: .zero, size: Self.screen)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        // Không có accessory trong test, nên thẻ bung từ khung dự phòng.
        let anchor = PlayerAnchor(frame: PlayerAnchor.fallbackFrame(screen: Self.screen),
                                  screen: Self.screen)
        expansion.leaveRest()

        func titleEnd(at progress: Double) throws -> CGFloat {
            expansion.setAccessoryDragDelta(progress)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let view = try XCTUnwrap(host.view)
            view.setNeedsLayout()
            view.layoutIfNeeded()

            let card = anchor.cardFrame(progress: progress)
            let width = Int(Self.screen.width * Self.scale)
            let height = Int(Self.screen.height * Self.scale)
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &data, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: Self.scale, y: -Self.scale)
            view.layer.render(in: context)

            // Dải hàng mini: 48pt trên cùng của thẻ. Cột: từ quá tấm bìa đang
            // lớn (ở 0,2 nó đã rộng ~100pt) tới trước ▶ ⏭ và khe hở.
            let rowTop = Int(card.minY * Self.scale)
            let rowBottom = Int((card.minY + MiniPlayerMetrics.artworkSide + 18) * Self.scale)
            let firstColumn = Int((card.minX + 130) * Self.scale)
            let lastColumn = Int((card.maxX - MiniPlayerMetrics.trailingInset
                                  - 2 * MiniPlayerMetrics.buttonSize - MiniPlayerMetrics.buttonGap
                                  - MiniPlayerMetrics.artworkTitleGap) * Self.scale)
            var rightmost: Int?
            for row in rowTop..<min(rowBottom, height) {
                for column in firstColumn..<lastColumn {
                    let p = (row * width + column) * 4
                    let sum = Int(data[p]) + Int(data[p + 1]) + Int(data[p + 2])
                    // Mặt thẻ ở đây xám rất nhạt (~650); chữ đen ở độ mờ 0,4
                    // còn dưới ~420. 520 tách hai thứ với biên rộng hai phía.
                    if sum < 520 { rightmost = max(rightmost ?? column, column) }
                }
            }
            let end = try XCTUnwrap(rightmost, "no title ink in the mini row at progress \(progress)")
            return CGFloat(end) / Self.scale - card.minX
        }

        let atRest = try titleEnd(at: 0)
        let widened = try titleEnd(at: 0.2)
        XCTAssertEqual(
            widened, atRest, accuracy: 1,
            """
            Tên bài trong hàng mini bị cắt ở chỗ khác khi thẻ rộng ra \
            (\(atRest)pt ở progress 0, \(widened)pt ở 0,2, tính từ mép trái thẻ). \
            Bề rộng của Text đang đi theo progress, và trong cú morph có animation \
            SwiftUI sẽ nội suy giữa hai bố cục chữ — tên bài trôi khỏi hàng ▶ ⏭.
            """
        )
    }
}
