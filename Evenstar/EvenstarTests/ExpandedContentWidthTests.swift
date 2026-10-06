import XCTest
import SwiftUI
@testable import Evenstar

/// **Khối nội dung mở rộng (`NowPlayingContent`) không được đổi bề rộng theo
/// `progress`.**
///
/// Cùng một lỗi với `MiniPlayerRowTitleWidthTests`, ở khối chữ lớn: video QA
/// iPhone 12 (2026-10-06), khung #45–#47 của cú bung, tên bài hai dòng
/// "…OST Part 3] 조정석" vẽ chồng chữ lên nhau. `expandedContent` từng lấy bề
/// rộng của thẻ, thẻ rộng dần ra khi bung, nên tên bài xuống dòng ở hai chỗ
/// khác nhau ở hai đầu cú morph và SwiftUI nội suy giữa hai bố cục chữ ấy.
///
/// Đo ở hai `progress` đứng yên: **bề ngang của phần nội dung sáng** — từ mép
/// trái tới mép phải của những thứ bám hai lề nội dung (nhãn thời gian, hai
/// biểu tượng loa, hẹn giờ ngủ và danh sách) — phải như nhau ở 0,9 và ở 1.
/// Trước bản sửa, ở 0,9 thẻ hẹp hơn 4pt và khối nội dung hẹp theo.
@MainActor
final class ExpandedContentWidthTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private static let screen = CGSize(width: 390, height: 844)
    private static let scale: CGFloat = 2

    func testTheExpandedContentKeepsItsWidthWhileTheCardNarrows() throws {
        let library = try InMemoryLibrary.make()
        let track = InMemoryLibrary.makeTrack(title: "Expanded width probe")
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

        func contentExtent(at progress: Double) throws -> (left: CGFloat, right: CGFloat) {
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

            // Nửa dưới của thẻ, chỗ khối nội dung nằm, cách xa bốn góc bo
            // (ngoài góc bo là nền trắng của cửa sổ) và xa tấm bìa ở trên.
            let firstRow = Int((card.minY + card.height * 0.6) * Self.scale)
            let lastRow = Int((card.maxY - 50) * Self.scale)
            let firstColumn = Int((card.minX + 6) * Self.scale)
            let lastColumn = Int((card.maxX - 6) * Self.scale)
            var left: Int?
            var right: Int?
            for row in firstRow..<lastRow {
                for column in firstColumn..<lastColumn {
                    let p = (row * width + column) * 4
                    let sum = Int(data[p]) + Int(data[p + 1]) + Int(data[p + 2])
                    // Nội dung sáng trên mặt thẻ tối.
                    if sum > 300 {
                        left = min(left ?? column, column)
                        right = max(right ?? column, column)
                    }
                }
            }
            let l = try XCTUnwrap(left, "no expanded content at progress \(progress)")
            let r = try XCTUnwrap(right, "no expanded content at progress \(progress)")
            return (CGFloat(l) / Self.scale, CGFloat(r + 1) / Self.scale)
        }

        let open = try contentExtent(at: 1)
        let narrower = try contentExtent(at: 0.9)
        XCTAssertEqual(
            narrower.right - narrower.left, open.right - open.left, accuracy: 1,
            """
            Khối nội dung mở rộng hẹp lại theo thẻ (\(open.right - open.left)pt ở progress 1, \
            \(narrower.right - narrower.left)pt ở 0,9). Bề rộng của NowPlayingContent đang đi \
            theo progress, và trong cú morph có animation tên bài sẽ xuống dòng ở hai chỗ \
            khác nhau — SwiftUI vẽ chồng hai bố cục chữ.
            """
        )
    }
}
